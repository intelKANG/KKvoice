import Foundation
import CoreAudio
import AudioToolbox

public struct KKAudioInputDevice: Equatable, Identifiable, Sendable {
    public let deviceID: AudioDeviceID
    public let uid: String
    public let name: String
    public let transportType: UInt32
    public let inputChannels: Int

    public var id: String { uid }

    public var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn ||
        uid.localizedCaseInsensitiveContains("BuiltInMicrophone")
    }

    public init(
        deviceID: AudioDeviceID = 0,
        uid: String,
        name: String,
        transportType: UInt32 = 0,
        inputChannels: Int = 1
    ) {
        self.deviceID = deviceID
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.inputChannels = inputChannels
    }
}

/// Lists physical macOS input devices and resolves the active Mac microphone selection.
/// Excludes KKvoice, BlackHole, vRemote, and other virtual/aggregate loopback devices
/// so the app never creates an audio feedback loop into KKvoice Mic.
public enum KKInputDeviceCatalog {
    public static let userDefaultsKey = "macMicrophoneUID"
    public static let systemDefaultUID = ""
    public static let systemDefaultTitle = "系统默认"

    public static func isExcludedVirtualDevice(uid: String, name: String, transportType: UInt32 = 0) -> Bool {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUID.isEmpty || trimmedName.isEmpty { return true }
        if transportType == kAudioDeviceTransportTypeVirtual ||
           transportType == kAudioDeviceTransportTypeAggregate {
            return true
        }
        let excludedTokens = [
            "kkvoice",
            "vremote",
            "blackhole",
            "soundflower",
            "loopback",
            "cadefaultdeviceaggregate"
        ]
        for token in excludedTokens {
            if trimmedUID.localizedCaseInsensitiveContains(token) ||
               trimmedName.localizedCaseInsensitiveContains(token) {
                return true
            }
        }
        return false
    }

    /// Lists all currently connected physical input devices (excluding virtual/loopback devices).
    public static func listPhysicalDevices() throws -> [KKAudioInputDevice] {
        try allDeviceIDs().compactMap { id in
            let channels = (try? inputChannelCount(id)) ?? 0
            guard channels > 0,
                  let uid = try? stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = try? stringProperty(id, kAudioObjectPropertyName) else {
                return nil
            }
            let transport = transportType(id)
            guard !isExcludedVirtualDevice(uid: uid, name: name, transportType: transport) else {
                return nil
            }
            return KKAudioInputDevice(
                deviceID: id,
                uid: uid,
                name: name,
                transportType: transport,
                inputChannels: Int(channels)
            )
        }
    }

    /// Returns the UID of the current macOS system default input device, if any.
    public static func systemDefaultInputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return try? stringProperty(deviceID, kAudioDevicePropertyDeviceUID)
    }

    /// Resolves the Mac microphone to use for a session.
    /// - Parameters:
    ///   - selectedUID: User-selected UID (`""` = 系统默认).
    ///   - available: Physical input devices (virtual devices already filtered or filtered here).
    ///   - systemDefaultUID: Current macOS system default input UID.
    /// - Returns: The resolved physical input device, or `nil` if no physical input exists.
    public static func resolve(
        selectedUID: String,
        available: [KKAudioInputDevice],
        systemDefaultUID: String?
    ) -> KKAudioInputDevice? {
        let physical = available.filter {
            !isExcludedVirtualDevice(uid: $0.uid, name: $0.name, transportType: $0.transportType)
        }
        guard !physical.isEmpty else { return nil }

        let trimmedSelection = selectedUID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelection.isEmpty {
            if let explicit = physical.first(where: { $0.uid == trimmedSelection }) {
                return explicit
            }
        }

        // System default: use the system default input if it is a physical device in our catalog.
        if let rawDefault = systemDefaultUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawDefault.isEmpty,
           let defaultDevice = physical.first(where: { $0.uid == rawDefault }) {
            return defaultDevice
        }

        // If the system default IS a virtual device (e.g. KKvoice Mic / BlackHole) or unavailable,
        // fall back to the built-in microphone first, then the first physical input device.
        if let builtIn = physical.first(where: \.isBuiltIn) {
            return builtIn
        }
        return physical.first
    }

    /// Resolves against the live CoreAudio inventory.
    public static func resolveCurrent(selectedUID: String) throws -> KKAudioInputDevice? {
        let devices = try listPhysicalDevices()
        let defaultUID = systemDefaultInputDeviceUID()
        return resolve(selectedUID: selectedUID, available: devices, systemDefaultUID: defaultUID)
    }

    internal static func resolveAudioDeviceID(forUID uid: String) throws -> AudioDeviceID {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KKCoreAudioError.missingDevice(uid) }
        let matches = try allDeviceIDs().filter { id in
            let channels = (try? inputChannelCount(id)) ?? 0
            guard channels > 0,
                  let devUID = try? stringProperty(id, kAudioDevicePropertyDeviceUID),
                  devUID == trimmed else { return false }
            let name = (try? stringProperty(id, kAudioObjectPropertyName)) ?? ""
            let transport = transportType(id)
            return !isExcludedVirtualDevice(uid: devUID, name: name, transportType: transport)
        }
        guard !matches.isEmpty else { throw KKCoreAudioError.missingDevice(uid) }
        guard matches.count == 1, let first = matches.first else {
            throw KKCoreAudioError.duplicateDeviceUID(uid)
        }
        return first
    }

    private static func allDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bytes: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &bytes
        )
        guard status == noErr else {
            throw KKCoreAudioError.system(operation: "list input devices", status: status)
        }
        guard bytes % UInt32(MemoryLayout<AudioDeviceID>.stride) == 0 else {
            throw KKCoreAudioError.unsupportedFormat("Invalid CoreAudio device inventory size")
        }
        let count = Int(bytes) / MemoryLayout<AudioDeviceID>.stride
        if count == 0 { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = ids.withUnsafeMutableBytes { raw in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &bytes,
                raw.baseAddress!
            )
        }
        guard status == noErr else {
            throw KKCoreAudioError.system(operation: "read input devices", status: status)
        }
        return Array(ids.prefix(Int(bytes) / MemoryLayout<AudioDeviceID>.stride))
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw KKCoreAudioError.system(operation: "read input device property", status: status)
        }
        guard let text = value?.takeRetainedValue() as String? else {
            throw KKCoreAudioError.unsupportedFormat("Missing input device identity")
        }
        return text
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport
    }

    private static func inputChannelCount(_ id: AudioDeviceID) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard status == noErr else {
            throw KKCoreAudioError.system(operation: "read input channel size", status: status)
        }
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw)
        guard status == noErr else {
            throw KKCoreAudioError.system(operation: "read input channels", status: status)
        }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + $1.mNumberChannels }
    }
}
