import CoreAudio
import Foundation

/// Read-only check of voice input apps' CoreAudio capture state and selected input UID.
enum InputApplicationAudioMonitor {
    private static let monitoredBundlePrefixes = [
        "com.vokie.desktop",
        "com.bytedance.inputmethod.doubaoime",
        "com.tencent.inputmethod.wetype"
    ]

    static func isMonitoredInputAppBundle(_ bundle: String) -> Bool {
        let normalized = bundle.lowercased()
        return monitoredBundlePrefixes.contains { prefix in
            normalized == prefix || normalized.hasPrefix(prefix + ".")
        }
    }

    static func isVokieCapturing(deviceUID: String) -> Bool? {
        guard let processes = propertyData(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList,
            kAudioObjectPropertyScopeGlobal
        ) else { return nil }
        let ids: [AudioObjectID] = processes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count.isMultiple(of: MemoryLayout<AudioObjectID>.stride) else { return [] }
            return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: AudioObjectID.self), count: raw.count / MemoryLayout<AudioObjectID>.stride))
        }
        var uncertain = false
        for id in ids {
            guard let bundle = stringProperty(id, kAudioProcessPropertyBundleID),
                  isMonitoredInputAppBundle(bundle) else { continue }
            guard let runningInput = uint32Property(id, kAudioProcessPropertyIsRunningInput) else { uncertain = true; continue }
            guard runningInput == 1 else { continue }
            guard let devices = propertyData(id, kAudioProcessPropertyDevices, kAudioDevicePropertyScopeInput) else { uncertain = true; continue }
            let deviceIDs: [AudioDeviceID] = devices.withUnsafeBytes { raw in
                guard let base = raw.baseAddress, raw.count.isMultiple(of: MemoryLayout<AudioDeviceID>.stride) else { return [] }
                return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: AudioDeviceID.self), count: raw.count / MemoryLayout<AudioDeviceID>.stride))
            }
            for deviceID in deviceIDs {
                guard let uid = stringProperty(deviceID, kAudioDevicePropertyDeviceUID) else { uncertain = true; continue }
                if uid == deviceUID { return true }
            }
        }
        return uncertain ? nil : false
    }

    private static func propertyData(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                     _ scope: AudioObjectPropertyScope) -> Data? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var data = Data(count: Int(size))
        let status = data.withUnsafeMutableBytes { raw in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, raw.baseAddress!)
        }
        return status == noErr ? data.prefix(Int(size)) : nil
    }

    private static func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
