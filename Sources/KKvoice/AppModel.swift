import AppKit
import Combine
import CoreAudio
import Foundation
import RemoteAudio
import ServiceManagement
import SnapNote
import VoiceSessions

enum SidebarTab: String, CaseIterable, Identifiable {
    case connection
    case mappings
    case snapNote
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: return "连接"
        case .mappings: return "按键"
        case .snapNote: return "闪念笔记"
        case .general: return "通用"
        case .about: return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: return "link"
        case .mappings: return "keyboard"
        case .snapNote: return "note.text"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case keysConnected
    case voiceReady
    case recording
    case error(String)
    case permissionRequired(String)

    var tone: StatusTone {
        switch self {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .keysConnected, .voiceReady:
            return .connected
        case .recording:
            return .recording
        case .permissionRequired:
            return .warning
        case .error:
            return .error
        }
    }

    var badgeTitle: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "正在查找"
        case .keysConnected:
            return "按键已连"
        case .voiceReady:
            return "已连接"
        case .recording:
            return "录音中"
        case .permissionRequired:
            return "需要权限"
        case .error:
            return "连接异常"
        }
    }

    var headlineTitle: String {
        switch self {
        case .disconnected:
            return "未连接遥控器"
        case .connecting:
            return "正在查找遥控器…"
        case .keysConnected:
            return "按键通道已就绪"
        case .voiceReady:
            return "遥控器已连接"
        case .recording:
            return "正在收音…"
        case .permissionRequired:
            return "需要系统权限"
        case .error:
            return "遥控器暂不可用"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: SidebarTab = .connection
    @Published var connectionPhase: ConnectionPhase = .disconnected
    @Published var statusText: String = "尚未连接"
    @Published var keyboardStatusText: String = "键盘监听：未连接"
    @Published var keyboardState: KeyboardListenerStatus.State = .stopped

    @Published var isSessionActive: Bool = false
    @Published var hidConnected: Bool = false
    @Published var voiceChannelReady: Bool = false
    @Published var isRecording: Bool = false
    @Published var recordingFrames: Int = 0
    @Published var requiredPermission: String? = nil
    @Published var lastPressedButtonID: String? = nil

    @Published var availableDevices: [KKAudioOutputDevice] = []
    @Published var selectedDeviceIndex: Int = 0
    @Published var deviceLoadFailed: Bool = false

    @Published var wakeSelectionIndex: Int = 0
    @Published var inputSelectionIndex: Int = 0
    @Published var voiceModeIndex: Int = 0
    @Published var customWakeTitle: String = "自定义快捷键…"
    @Published var customInputTitle: String = "自定义快捷键…"

    @Published var launchAtLogin: Bool = false
    @Published var loginItemRequiresApproval: Bool = false

    @Published var mappings: ButtonMappings
    @Published var snapNoteShortcut: String? = nil
    @Published var hasSnapNoteToken: Bool = false
    @Published var isSnapNoteBusy: Bool = false

    private let bridge = RemoteBridge()
    private let snapTokenStore = SnapNoteTokenStore()
    private var snapAdapter: SnapNoteHelperActionAdapter?
    private var snapTask: Task<Void, Never>? {
        didSet { isSnapNoteBusy = (snapTask != nil) }
    }
    let snapShortcutKey = "snapNoteNewShortcut"
    private let mappingStore = ButtonMappingStore()
    private lazy var buttonDispatcher = ButtonActionDispatcher(
        mappings: mappings,
        send: { [weak self] message in
            guard let self else { throw NSError(domain: "KKvoice", code: 21) }
            try self.bridge.send(message)
        },
        cancelVoice: { [weak self] in self?.voice.cancelWithoutSubmitting() },
        status: { [weak self] text in self?.statusText = text }
    )
    private let output = KKCoreAudioOutput()
    private lazy var audio = RemoteAudioBridge(output: output)
    private var outputSessions: [UUID: UUID] = [:]
    private var inputAppWatchdog: Timer?
    private var inputAppObservedActive = false
    private var inputAppInactiveSamples = 0
    private let keyboardSettings = KeyboardSettings()
    private var keyboardStatus = KeyboardListenerStatus()
    private var selectedDeviceUID: String?
    private var chosenInputShortcut = ShortcutDefinition(keyName: "LeftControl")!.systemShortcut

    private lazy var voice: VoiceCoordinator = VoiceCoordinator(
        beginOutput: { [weak self] session in
            guard let self, let uid = self.selectedDeviceUID else {
                throw NSError(domain: "KKvoice", code: 10, userInfo: [NSLocalizedDescriptionKey: "请选择已安装的虚拟音频设备。"])
            }
            let audioID = try self.audio.start(deviceUID: uid)
            self.outputSessions[session] = audioID
        },
        endOutput: { [weak self] session in
            guard let self, let id = self.outputSessions.removeValue(forKey: session) else { return nil }
            _ = self.audio.stop(session: id)
            return self.output.lastStopError
        },
        command: { [weak self] message in
            guard let self else { throw NSError(domain: "KKvoice", code: 11) }
            try self.bridge.send(message)
        },
        shortcut: { [weak self] in
            guard let self else { throw NSError(domain: "KKvoice", code: 12) }
            try SystemShortcutSender.send(self.chosenInputShortcut)
        },
        report: { [weak self] text in
            guard let self else { return }
            self.statusText = text
            self.syncVoicePhase()
        }
    )

    var canConnect: Bool { !isSessionActive }
    var canDisconnect: Bool { isSessionActive }
    var canCaptureShortcut: Bool { !isSessionActive }
    var isControlsLocked: Bool { isSessionActive }

    var wakeKeyTitles: [String] {
        ["不启用"] + InputShortcut.choices.map(\.name) + [customWakeTitle]
    }

    var inputKeyTitles: [String] {
        InputShortcut.choices.map(\.name) + [customInputTitle]
    }

    static let voiceModeTitles = [
        "按一次开始，再按一次结束",
        "短按切换，长按松开结束"
    ]

    init(autoRefreshDevices: Bool = true) {
        let initialMappings = mappingStore.load()
        self.mappings = initialMappings
        self.voiceModeIndex = UserDefaults.standard.bool(forKey: "remoteHybridGesture") ? 1 : 0
        self.wakeSelectionIndex = keyboardSettings.wakeSelection(choices: InputShortcut.choices)
        self.inputSelectionIndex = keyboardSettings.inputSelection(choices: InputShortcut.choices)
        self.snapNoteShortcut = UserDefaults.standard.string(forKey: snapShortcutKey)
        self.hasSnapNoteToken = ((try? snapTokenStore.load()) ?? nil) != nil

        let serviceStatus = SMAppService.mainApp.status
        self.launchAtLogin = (serviceStatus == .enabled)
        self.loginItemRequiresApproval = (serviceStatus == .requiresApproval)

        bridge.onStatus = { [weak self] text in
            self?.statusText = text
        }
        bridge.onMessage = { [weak self] message in
            self?.handleHelperMessage(message)
        }
        buttonDispatcher.createSnapNote = { [weak self] in
            self?.createSnapNote()
        }

        updateCustomShortcutTitles()
        if autoRefreshDevices {
            refreshDevices()
        }
    }

    func refreshDevices() {
        do {
            // Restrict UI to known loopback devices, never speakers or the Mac mic.
            availableDevices = try KKAudioOutputDevices.list().filter {
                $0.uid == "KKvoiceMi2ch_UID" || $0.uid == "vRemoteDr2ch_UID" || $0.name.localizedCaseInsensitiveContains("BlackHole")
            }
            deviceLoadFailed = false
            if let index = availableDevices.firstIndex(where: { $0.uid == "KKvoiceMi2ch_UID" }) {
                selectedDeviceIndex = index
            } else if let index = availableDevices.firstIndex(where: { $0.uid == "vRemoteDr2ch_UID" }) {
                selectedDeviceIndex = index
            } else {
                selectedDeviceIndex = 0
            }
        } catch {
            availableDevices = []
            selectedDeviceIndex = 0
            deviceLoadFailed = true
            statusText = "读取音频设备失败：\(error)"
        }
    }

    func deviceDisplayTitle(_ device: KKAudioOutputDevice) -> String {
        "\(device.name.trimmingCharacters(in: .whitespacesAndNewlines)) (\(device.uid))"
    }

    var emptyDevicePlaceholderTitle: String {
        deviceLoadFailed ? "无法读取音频设备" : "未找到虚拟音频设备"
    }

    func selectWakeKey(at index: Int) {
        let choices = InputShortcut.choices
        if index == choices.count + 1 {
            if let value = ShortcutPicker.prompt(previous: keyboardSettings.wakeDefinition(), globalWake: true) {
                keyboardSettings.saveWakeDefinition(value)
            }
        } else {
            keyboardSettings.saveWake(selection: index, choices: choices)
        }
        wakeSelectionIndex = keyboardSettings.wakeSelection(choices: choices)
        updateCustomShortcutTitles()
    }

    func promptCustomWakeShortcut() {
        guard canCaptureShortcut else { return }
        if let value = ShortcutPicker.prompt(previous: keyboardSettings.wakeDefinition(), globalWake: true) {
            keyboardSettings.saveWakeDefinition(value)
        }
        wakeSelectionIndex = keyboardSettings.wakeSelection(choices: InputShortcut.choices)
        updateCustomShortcutTitles()
    }

    func selectInputKey(at index: Int) {
        let choices = InputShortcut.choices
        if index == choices.count {
            if let value = ShortcutPicker.prompt(previous: keyboardSettings.inputDefinition(), globalWake: false) {
                keyboardSettings.saveInputDefinition(value)
            }
        } else {
            keyboardSettings.saveInput(selection: index, choices: choices)
        }
        inputSelectionIndex = keyboardSettings.inputSelection(choices: choices)
        updateCustomShortcutTitles()
    }

    func promptCustomInputShortcut() {
        guard canCaptureShortcut else { return }
        if let value = ShortcutPicker.prompt(previous: keyboardSettings.inputDefinition(), globalWake: false) {
            keyboardSettings.saveInputDefinition(value)
        }
        inputSelectionIndex = keyboardSettings.inputSelection(choices: InputShortcut.choices)
        updateCustomShortcutTitles()
    }

    func selectVoiceMode(at index: Int) {
        voiceModeIndex = index
        UserDefaults.standard.set(index == 1, forKey: "remoteHybridGesture")
    }

    func updateCustomShortcutTitles() {
        let choices = InputShortcut.choices
        if keyboardSettings.wakeSelection(choices: choices) == choices.count + 1,
           let definition = keyboardSettings.wakeDefinition() {
            customWakeTitle = "自定义：\(definition.encoded)"
        } else {
            customWakeTitle = "自定义快捷键…"
        }
        if keyboardSettings.inputSelection(choices: choices) == choices.count {
            customInputTitle = "自定义：\(keyboardSettings.inputDefinition().encoded)"
        } else {
            customInputTitle = "自定义快捷键…"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            let current = SMAppService.mainApp.status
            launchAtLogin = current == .enabled
            loginItemRequiresApproval = current == .requiresApproval
            if current == .requiresApproval {
                statusText = "请在系统设置的登录项中允许 KKvoice 开机启动。"
            }
        } catch {
            let current = SMAppService.mainApp.status
            launchAtLogin = current == .enabled
            loginItemRequiresApproval = current == .requiresApproval
            statusText = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    func connect() {
        guard canConnect else { return }
        guard let resourceURL = Bundle.main.resourceURL else {
            statusText = "找不到应用资源。"
            return
        }
        let index = selectedDeviceIndex
        selectedDeviceUID = availableDevices.indices.contains(index) ? availableDevices[index].uid : nil
        chosenInputShortcut = keyboardSettings.inputDefinition().systemShortcut
        let wakeDefinition = keyboardSettings.wakeDefinition()
        guard voice.setRemoteGesture(voiceModeIndex == 1 ? .hybrid : .toggle) else {
            statusText = "请先结束当前收音。"
            return
        }
        // Start the remote audio route before Vokie receives its toggle. Passing
        // through the physical key can make Vokie open the input before CoreAudio
        // has attached to the virtual microphone, which yields an empty recording.
        let passThrough = false
        guard voice.setKeyboardPassThrough(passThrough) else {
            statusText = "请先结束当前收音。"
            return
        }
        let selectedWake = wakeDefinition?.keyName
        let helper = resourceURL.appendingPathComponent("KKvoiceRemoteHelper.app/Contents/MacOS/KKvoiceRemoteHelper")
        do {
            requiredPermission = nil
            keyboardStatus.connecting(key: selectedWake)
            keyboardState = keyboardStatus.state
            keyboardStatusText = keyboardStatus.text
            connectionPhase = .connecting
            try bridge.start(
                helperURL: helper,
                keyboardKey: selectedWake,
                keyboardModifiers: wakeDefinition?.modifiers ?? [],
                keyboardPassThrough: passThrough
            )
            snapAdapter = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported: true) { [weak self] message in
                DispatchQueue.main.async { [weak self] in
                    do { try self?.bridge.send(message.wireFields) }
                    catch { Task { await self?.snapAdapter?.helperDisconnected() } }
                }
            }
            isSessionActive = true
        } catch {
            keyboardStatus.receive(["type": "helper_process_exited"])
            keyboardState = keyboardStatus.state
            keyboardStatusText = keyboardStatus.text
            isSessionActive = false
            connectionPhase = .error(error.localizedDescription)
            bridge.stop()
            statusText = error.localizedDescription
        }
    }

    func disconnect() {
        stopInputAppWatchdog()
        snapTask?.cancel()
        if let adapter = snapAdapter { Task { await adapter.helperDisconnected() } }
        snapAdapter = nil
        voice.setReady(false)
        bridge.stop()
    }

    func applyMappings(_ newMappings: ButtonMappings) throws {
        try mappingStore.save(newMappings)
        mappings = newMappings
        buttonDispatcher.mappings = newMappings
    }

    func pickSnapNoteShortcut(currentEncoded: String? = nil) -> String? {
        guard canCaptureShortcut else {
            statusText = "请先断开遥控器，再修改闪念设置。"
            return nil
        }
        let source = currentEncoded ?? UserDefaults.standard.string(forKey: snapShortcutKey)
        let previous = source.flatMap(ShortcutDefinition.init(encoded:))
        guard let selected = ShortcutPicker.prompt(previous: previous, globalWake: false),
              SnapNoteCoordinator.validShortcut(selected.encoded) else {
            statusText = "请设置带修饰键的闪念新建快捷键。"
            return nil
        }
        return selected.encoded
    }

    @discardableResult
    func saveSnapNoteConfiguration(token: String, shortcutEncoded: String?) -> Bool {
        guard canCaptureShortcut else {
            statusText = "请先断开遥控器，再修改闪念设置。"
            return false
        }
        do {
            if !token.isEmpty {
                try snapTokenStore.save(token)
                hasSnapNoteToken = true
            }
            guard let encoded = shortcutEncoded,
                  SnapNoteCoordinator.validShortcut(encoded) else {
                statusText = "请设置带修饰键的闪念新建快捷键。"
                return false
            }
            UserDefaults.standard.set(encoded, forKey: snapShortcutKey)
            snapNoteShortcut = encoded
            statusText = "闪念快捷键已保存；请确认与闪念笔记设置一致。"
            return true
        } catch {
            statusText = "无法保存闪念令牌：\(error.localizedDescription)"
            return false
        }
    }

    func configureSnapNoteModal() {
        guard canCaptureShortcut else {
            statusText = "请先断开遥控器，再修改闪念设置。"
            return
        }
        let alert = NSAlert()
        alert.messageText = "闪念笔记设置"
        alert.informativeText = "输入本机接口 Token；留空表示保留已有 Token。"
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Token"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if !field.stringValue.isEmpty {
                try snapTokenStore.save(field.stringValue)
                hasSnapNoteToken = true
            }
            let previous = UserDefaults.standard.string(forKey: snapShortcutKey).flatMap(ShortcutDefinition.init(encoded:))
            guard let selected = ShortcutPicker.prompt(previous: previous, globalWake: false),
                  SnapNoteCoordinator.validShortcut(selected.encoded) else {
                statusText = "请设置带修饰键的闪念新建快捷键。"
                return
            }
            UserDefaults.standard.set(selected.encoded, forKey: snapShortcutKey)
            snapNoteShortcut = selected.encoded
            statusText = "闪念快捷键已保存；请确认与闪念笔记设置一致。"
        } catch {
            statusText = "无法保存闪念令牌：\(error.localizedDescription)"
        }
    }

    func createSnapNote() {
        guard snapTask == nil else { statusText = "闪念笔记操作进行中。"; return }
        guard let adapter = snapAdapter else { statusText = "请先连接遥控器。"; return }
        guard case .idle = voice.phase else { statusText = "请先结束语音输入。"; return }
        guard let shortcut = UserDefaults.standard.string(forKey: snapShortcutKey) else {
            statusText = "请先配置闪念笔记快捷键。"
            return
        }
        do {
            guard let token = try snapTokenStore.load() else {
                statusText = "请先配置闪念笔记 Token。"
                return
            }
            let client = try SnapNoteMCPClient(token: token)
            let coordinator = SnapNoteCoordinator(client: client, native: adapter, isRecording: { [weak self] in
                await self?.isVoiceActive() ?? true
            })
            statusText = "正在新建闪念笔记…"
            snapTask = Task { @MainActor [weak self] in
                let result = await coordinator.createAndTag(shortcut: shortcut)
                guard let self else { return }
                self.snapTask = nil
                if result.succeeded {
                    self.statusText = "闪念笔记已创建并添加标签。"
                } else if result.noteMayExist {
                    self.statusText = "闪念操作未完成，笔记可能已创建，请检查后再试。"
                } else {
                    self.statusText = "闪念操作未完成：\(String(describing: result.error))"
                }
            }
        } catch {
            statusText = "闪念笔记配置不可用。"
        }
    }

    private func isVoiceActive() -> Bool {
        if case .idle = voice.phase { return false }
        return true
    }

    func handleHelperMessage(_ message: [String: Any]) {
        if let type = message["type"] as? String,
           let raw = message["actionId"] as? String,
           let id = UUID(uuidString: raw),
           let adapter = snapAdapter {
            let prevented = message["prevented"] as? Bool
            Task { await adapter.handleHelperEvent(type: type, actionID: id, prevented: prevented) }
        }
        keyboardStatus.receive(message)
        keyboardState = keyboardStatus.state
        keyboardStatusText = keyboardStatus.text
        switch message["type"] as? String {
        case "device_ready":
            voice.setReady(true)
            voiceChannelReady = true
            requiredPermission = nil
            statusText = "遥控器语音通道已连接"
            syncVoicePhase()
        case "hid_connected":
            hidConnected = true
            statusText = "已检测到遥控器按键"
            syncVoicePhase()
        case "scanning":
            statusText = "正在查找遥控器…"
            if !voiceChannelReady && !hidConnected {
                connectionPhase = .connecting
            }
        case "ble_disconnected", "bluetooth_off":
            voice.setReady(false)
            voiceChannelReady = false
            statusText = "遥控器蓝牙已断开"
            syncVoicePhase()
        case "hid_disconnected":
            buttonDispatcher.deviceDisconnected()
            hidConnected = false
            lastPressedButtonID = nil
            statusText = "遥控器按键已断开"
            syncVoicePhase()
        case "button_down":
            if let id = message["buttonId"] as? String {
                let upper = id.uppercased()
                lastPressedButtonID = upper
                buttonDispatcher.down(upper)
            }
        case "button_up":
            if let id = message["buttonId"] as? String {
                let upper = id.uppercased()
                if lastPressedButtonID == upper { lastPressedButtonID = nil }
                buttonDispatcher.up(upper)
            }
        case "app_switcher_state":
            buttonDispatcher.switcherActive = message["active"] as? Bool == true
        case "action_error":
            statusText = message["message"] as? String ?? "按键动作失败。"
        case "voice_press":
            guard snapTask == nil else {
                statusText = "闪念操作进行中，请稍候再录音。"
                return
            }
            voice.press(.remote)
            syncVoicePhase()
        case "voice_release":
            voice.release(.remote)
            syncVoicePhase()
        case "keyboard_trigger_down":
            guard snapTask == nil else {
                statusText = "闪念操作进行中，请稍候再录音。"
                return
            }
            voice.press(.keyboard)
            syncVoicePhase()
        case "keyboard_trigger_up":
            if message["interrupted"] as? Bool == true {
                voice.keyboardInterrupted()
            } else {
                voice.release(.keyboard)
            }
            syncVoicePhase()
        case "keyboard_cancel_session":
            voice.cancelWithoutSubmitting()
            syncVoicePhase()
        case "capture_probe_started":
            statusText = "正在确认遥控器语音请求…"
        case "capture_probe_timeout":
            statusText = "未建立语音会话，已停止遥控器收音。"
            syncVoicePhase()
        case "audio_start":
            voice.audioStarted()
            recordingFrames = 0
            syncVoicePhase()
        case "audio_reopen_requested":
            statusText = "正在恢复遥控器收音…"
        case "audio_stream_progress":
            if case .recording = voice.phase, let frames = message["frames"] as? Int {
                recordingFrames = frames
                statusText = "遥控器收音中，已接收 \(frames) 帧。"
                startInputAppWatchdog()
            }
            syncVoicePhase()
        case "audio_frame":
            guard message["sampleRate"] as? Int == 16_000,
                  let encoded = message["pcmBase64"] as? String,
                  let pcm = Data(base64Encoded: encoded),
                  let session = outputSessions.values.first else { return }
            _ = audio.receive(pcm, session: session)
        case "mic_open_error":
            if let code = message["code"] as? NSNumber {
                voice.audioFailed("遥控器麦克风未能开启（错误码 \(code.uint64Value)）。")
            } else {
                voice.audioFailed("遥控器麦克风未能开启。")
            }
            syncVoicePhase()
        case "permission_required":
            voice.setReady(false)
            voiceChannelReady = false
            let perm = message["permission"] as? String ?? "unknown"
            requiredPermission = perm
            switch perm {
            case "accessibility":
                statusText = "请在系统设置中允许 KKvoice Remote Helper 使用辅助功能。"
            case "input-monitoring":
                statusText = "请在系统设置中允许 KKvoice Remote Helper 进行输入监控。"
            case "bluetooth":
                statusText = "请在系统设置中允许 KKvoice Remote Helper 使用蓝牙。"
            default:
                statusText = "请检查系统权限设置。"
            }
            connectionPhase = .permissionRequired(perm)
        case "device_error", "device_not_found":
            voice.setReady(false)
            voiceChannelReady = false
            let errMsg = message["message"] as? String ?? "遥控器暂不可用"
            statusText = errMsg
            connectionPhase = .error(errMsg)
        case "helper_process_exited":
            stopInputAppWatchdog()
            snapTask?.cancel()
            if let adapter = snapAdapter { Task { await adapter.helperDisconnected() } }
            snapAdapter = nil
            buttonDispatcher.reset()
            voice.setReady(false)
            isSessionActive = false
            hidConnected = false
            voiceChannelReady = false
            isRecording = false
            recordingFrames = 0
            lastPressedButtonID = nil
            if requiredPermission == nil {
                connectionPhase = .disconnected
            }
        default:
            break
        }
    }

    private func syncVoicePhase() {
        switch voice.phase {
        case .recording:
            isRecording = true
            connectionPhase = .recording
        case .starting, .stopping:
            isRecording = false
            if voiceChannelReady {
                connectionPhase = .voiceReady
            }
        case .idle:
            isRecording = false
            recordingFrames = 0
            if let perm = requiredPermission {
                connectionPhase = .permissionRequired(perm)
            } else if voiceChannelReady {
                connectionPhase = .voiceReady
            } else if hidConnected {
                connectionPhase = .keysConnected
            } else if isSessionActive {
                connectionPhase = .connecting
            } else {
                connectionPhase = .disconnected
            }
        }
    }

    private func startInputAppWatchdog() {
        guard inputAppWatchdog == nil else { return }
        inputAppObservedActive = false
        inputAppInactiveSamples = 0
        inputAppWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                guard case .recording = self.voice.phase else {
                    self.stopInputAppWatchdog()
                    return
                }
                guard let uid = self.selectedDeviceUID else { return }
                guard let active = InputApplicationAudioMonitor.isVokieCapturing(deviceUID: uid) else {
                    self.inputAppInactiveSamples = 0
                    return
                }
                if active {
                    self.inputAppObservedActive = true
                    self.inputAppInactiveSamples = 0
                    return
                }
                if self.inputAppObservedActive {
                    self.inputAppInactiveSamples += 1
                    guard self.inputAppInactiveSamples >= 3 else { return }
                    self.voice.cancelWithoutSubmitting()
                    self.stopInputAppWatchdog()
                    self.statusText = "Vokie 已结束或取消录音，遥控器收音已关闭。"
                    self.syncVoicePhase()
                }
            }
        }
    }

    private func stopInputAppWatchdog() {
        inputAppWatchdog?.invalidate()
        inputAppWatchdog = nil
        inputAppObservedActive = false
        inputAppInactiveSamples = 0
    }

    var activePermissionIssue: String? {
        if let requiredPermission {
            return requiredPermission
        }
        if keyboardState == .permissionRequired {
            return "accessibility"
        }
        return nil
    }

    func permissionTitle(for permission: String) -> String {
        switch permission {
        case "accessibility":
            return "需要辅助功能权限"
        case "input-monitoring":
            return "需要输入监控权限"
        case "bluetooth":
            return "需要蓝牙权限"
        default:
            return "需要系统权限"
        }
    }

    func permissionDescription(for permission: String) -> String {
        switch permission {
        case "accessibility":
            return "请在系统设置 › 隐私与安全性 › 辅助功能中允许 KKvoice Remote Helper，以启用按键动作与唤醒键监听。"
        case "input-monitoring":
            return "请在系统设置 › 隐私与安全性 › 输入监控中允许 KKvoice Remote Helper，以读取遥控器按键事件。"
        case "bluetooth":
            return "请在系统设置 › 隐私与安全性 › 蓝牙中允许 KKvoice Remote Helper，以连接 Chromecast 遥控器语音通道。"
        default:
            return "请检查系统设置 › 隐私与安全性中的权限配置。"
        }
    }

    func openPermissionSettings(for permission: String? = nil) {
        let target = permission ?? activePermissionIssue ?? ""
        let urlString: String
        switch target {
        case "accessibility":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case "input-monitoring":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case "bluetooth":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        case "login-items":
            urlString = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        default:
            urlString = "x-apple.systempreferences:com.apple.preference.security"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openExternalURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
        return short
    }

    var appBuildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
