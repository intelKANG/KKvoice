import Combine
import Foundation

public enum AudioSource: Equatable, Sendable {
    case remote
    case mac(uid: String, name: String)

    /// Display text for status cards: e.g. `"遥控器"` or `"Mac 麦克风（MacBook Pro麦克风）"`.
    public var displayTitle: String {
        switch self {
        case .remote:
            return "遥控器"
        case let .mac(_, name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Mac 麦克风" : "Mac 麦克风（\(trimmed)）"
        }
    }

    /// Compact source label: `"遥控器"` or `"Mac 麦克风"`.
    public var shortTitle: String {
        switch self {
        case .remote:
            return "遥控器"
        case .mac:
            return "Mac 麦克风"
        }
    }

    public var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }
}

/// Per-session audio source router for "自动切换音源".
/// - Decides the audio source at `beginSession` time based on `remoteReady`:
///   - `remoteReady == true` → routes remote 16 kHz PCM into the virtual output device (`KKvoice Mic`).
///   - `remoteReady == false` → captures the selected Mac physical microphone into the virtual output device.
/// - Never hot-swaps mid-session: if the remote connects or disconnects during a session,
///   the current session finishes on its locked-in source and the next session re-decides.
/// - Never captures the Mac microphone while idle; opens only during a session and releases on `endSession`.
public final class AudioSourceRouter: ObservableObject {
    public typealias PhysicalDeviceLister = () throws -> [KKAudioInputDevice]
    public typealias DefaultUIDProvider = () -> String?

    @Published public private(set) var availableMacMics: [KKAudioInputDevice] = []
    @Published public var selectedMacMicUID: String {
        didSet {
            let trimmed = selectedMacMicUID.trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedMacMicUID != trimmed {
                selectedMacMicUID = trimmed
                return
            }
            userDefaults.set(trimmed, forKey: KKInputDeviceCatalog.userDefaultsKey)
        }
    }
    /// Non-nil while a voice session is active; `nil` when idle.
    @Published public private(set) var currentSource: AudioSource? = nil
    /// Target virtual output device UID (e.g. `"KKvoiceMi2ch_UID"`). Can be set ahead of time or passed to `beginSession`.
    public var virtualDeviceUID: String?

    /// Invoked if microphone permission is asynchronously denied after a `.notDetermined` prompt.
    public var onPermissionDenied: (() -> Void)?

    private struct ActiveSession {
        let voiceSessionID: UUID
        let backendID: UUID
        let source: AudioSource
    }

    private let output: RemoteAudioOutput
    private let remoteBridge: RemoteAudioBridge
    private let macSource: MacMicrophoneSource
    private let userDefaults: UserDefaults
    private let listDevices: PhysicalDeviceLister
    private let defaultUIDProvider: DefaultUIDProvider
    private let outputErrorProvider: () -> String?
    private var activeSession: ActiveSession?

    public convenience init(
        output: KKCoreAudioOutput = KKCoreAudioOutput(),
        userDefaults: UserDefaults = .standard,
        autoRefreshDevices: Bool = true
    ) {
        self.init(
            output: output,
            remoteBridge: RemoteAudioBridge(output: output),
            macSource: MacMicrophoneSource(output: output),
            userDefaults: userDefaults,
            listDevices: KKInputDeviceCatalog.listPhysicalDevices,
            defaultUIDProvider: KKInputDeviceCatalog.systemDefaultInputDeviceUID,
            outputErrorProvider: { output.lastStopError },
            autoRefreshDevices: autoRefreshDevices
        )
    }

    public init(
        output: RemoteAudioOutput,
        remoteBridge: RemoteAudioBridge? = nil,
        macSource: MacMicrophoneSource? = nil,
        userDefaults: UserDefaults = .standard,
        listDevices: @escaping PhysicalDeviceLister = KKInputDeviceCatalog.listPhysicalDevices,
        defaultUIDProvider: @escaping DefaultUIDProvider = KKInputDeviceCatalog.systemDefaultInputDeviceUID,
        outputErrorProvider: @escaping () -> String? = { nil },
        autoRefreshDevices: Bool = false
    ) {
        self.output = output
        self.remoteBridge = remoteBridge ?? RemoteAudioBridge(output: output)
        self.macSource = macSource ?? MacMicrophoneSource(output: output)
        self.userDefaults = userDefaults
        self.listDevices = listDevices
        self.defaultUIDProvider = defaultUIDProvider
        self.outputErrorProvider = outputErrorProvider
        let saved = userDefaults.string(forKey: KKInputDeviceCatalog.userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.selectedMacMicUID = saved
        if autoRefreshDevices {
            refreshMacMics()
        }
    }

    /// Reloads the list of physical Mac microphones.
    public func refreshMacMics() {
        do {
            availableMacMics = try listDevices()
        } catch {
            availableMacMics = []
        }
    }

    /// Selects "系统默认" (`selectedMacMicUID = ""`).
    public func selectSystemDefaultMacMic() {
        selectedMacMicUID = KKInputDeviceCatalog.systemDefaultUID
    }

    /// Selects a specific physical microphone by UID.
    public func selectMacMic(uid: String) {
        selectedMacMicUID = uid
    }

    /// Summary title for the "Mac 麦克风" Picker button on the 连接 page.
    public var selectedMacMicTitle: String {
        if selectedMacMicUID.isEmpty {
            return KKInputDeviceCatalog.systemDefaultTitle
        }
        if let match = availableMacMics.first(where: { $0.uid == selectedMacMicUID }) {
            return match.displayName
        }
        return KKInputDeviceCatalog.systemDefaultTitle
    }

    /// Returns the locked-in source during an active session, or the source that would be used
    /// if a session started right now given `remoteReady`.
    public func activeOrStandbySource(remoteReady: Bool) -> AudioSource {
        if let currentSource {
            return currentSource
        }
        if remoteReady {
            return .remote
        }
        let devices = availableMacMics.isEmpty ? ((try? listDevices()) ?? []) : availableMacMics
        if let resolved = KKInputDeviceCatalog.resolve(
            selectedUID: selectedMacMicUID,
            available: devices,
            systemDefaultUID: defaultUIDProvider()
        ) {
            return .mac(uid: resolved.uid, name: resolved.displayName)
        }
        return .mac(uid: "", name: "")
    }

    /// Starts a voice session on either the remote microphone or the Mac microphone,
    /// decided once at session start.
    @discardableResult
    public func beginSession(
        session: UUID = UUID(),
        virtualDeviceUID: String? = nil,
        remoteReady: Bool
    ) throws -> AudioSource {
        let targetOutputUID = (virtualDeviceUID ?? self.virtualDeviceUID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !targetOutputUID.isEmpty else {
            throw NSError(
                domain: "KKvoice",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "未选择虚拟麦克风"]
            )
        }
        if activeSession != nil {
            _ = endSession()
        }

        if remoteReady {
            let backendID = try remoteBridge.start(deviceUID: targetOutputUID)
            let source: AudioSource = .remote
            activeSession = ActiveSession(voiceSessionID: session, backendID: backendID, source: source)
            currentSource = source
            return source
        } else {
            let devices = (try? listDevices()) ?? availableMacMics
            if !devices.isEmpty {
                availableMacMics = devices
            }
            guard let resolvedMic = KKInputDeviceCatalog.resolve(
                selectedUID: selectedMacMicUID,
                available: devices,
                systemDefaultUID: defaultUIDProvider()
            ) else {
                throw MacMicrophoneError.noInputDeviceAvailable
            }
            let backendID = try macSource.start(
                inputDeviceUID: resolvedMic.uid,
                outputDeviceUID: targetOutputUID,
                onPermissionDenied: { [weak self] in
                    guard let self else { return }
                    self.activeSession = nil
                    self.currentSource = nil
                    self.onPermissionDenied?()
                }
            )
            let source: AudioSource = .mac(uid: resolvedMic.uid, name: resolvedMic.displayName)
            activeSession = ActiveSession(voiceSessionID: session, backendID: backendID, source: source)
            currentSource = source
            return source
        }
    }

    /// Feeds 16 kHz mono Int16 PCM from the remote helper into the active session.
    /// Ignored when the active session is using the Mac microphone or when idle.
    @discardableResult
    public func receiveRemotePCM(_ pcm16LE: Data) -> Bool {
        guard let active = activeSession, active.source == .remote else { return false }
        return remoteBridge.receive(pcm16LE, session: active.backendID)
    }

    /// Ends the active session, stops and releases the active input/output devices, and clears buffers.
    /// If `session` is provided, only closes if it matches the active session ID.
    @discardableResult
    public func endSession(session: UUID? = nil) -> String? {
        guard let active = activeSession else { return nil }
        if let session, active.voiceSessionID != session {
            return nil
        }
        activeSession = nil
        currentSource = nil
        switch active.source {
        case .remote:
            _ = remoteBridge.stop(session: active.backendID)
            return outputErrorProvider()
        case .mac:
            _ = macSource.stop(session: active.backendID)
            return macSource.lastStopError ?? outputErrorProvider()
        }
    }
}
