import Foundation
import CoreAudio
import AudioToolbox

public struct KKAudioOutputDevice: Equatable {
    public let uid: String
    public let name: String
    public let transportType: UInt32
}

public enum KKCoreAudioError: Error, CustomStringConvertible {
    case system(operation: String, status: OSStatus)
    case missingDevice(String)
    case duplicateDeviceUID(String)
    case unsupportedFormat(String)
    case alreadyRunning

    public var description: String {
        switch self {
        case let .system(operation, status): return "\(operation) failed (OSStatus \(status))"
        case let .missingDevice(uid): return "Output device not found or has no output: \(uid)"
        case let .duplicateDeviceUID(uid): return "Output device UID is ambiguous: \(uid)"
        case let .unsupportedFormat(description): return "Unsupported output format: \(description)"
        case .alreadyRunning: return "Audio output is already running"
        }
    }
}

/// Read-only inventory. The UID is opaque and must be chosen by the user.
/// USB transport does NOT prove a device is physical: some virtual drivers report USB.
public enum KKAudioOutputDevices {
    public static func list() throws -> [KKAudioOutputDevice] {
        try allDevices().compactMap { id in
            guard (try? outputChannelCount(id)) ?? 0 > 0,
                  let uid = try? stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = try? stringProperty(id, kAudioObjectPropertyName) else { return nil }
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
            return KKAudioOutputDevice(uid: uid, name: name, transportType: transport)
        }
    }

    fileprivate static func resolve(_ uid: String) throws -> AudioDeviceID {
        let matches = try allDevices().filter { id in
            ((try? outputChannelCount(id)) ?? 0) > 0 &&
            (try? stringProperty(id, kAudioDevicePropertyDeviceUID)) == uid
        }
        guard !matches.isEmpty else { throw KKCoreAudioError.missingDevice(uid) }
        guard matches.count == 1, let first = matches.first else {
            throw KKCoreAudioError.duplicateDeviceUID(uid)
        }
        return first
    }

    private static func allDevices() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes)
        guard status == noErr else { throw KKCoreAudioError.system(operation: "list output devices", status: status) }
        guard bytes % UInt32(MemoryLayout<AudioDeviceID>.stride) == 0 else {
            throw KKCoreAudioError.unsupportedFormat("Invalid CoreAudio device inventory size")
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioDeviceID>.stride)
        if ids.isEmpty { return [] }
        status = ids.withUnsafeMutableBytes { raw in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes, raw.baseAddress!)
        }
        guard status == noErr else { throw KKCoreAudioError.system(operation: "read output devices", status: status) }
        return Array(ids.prefix(Int(bytes) / MemoryLayout<AudioDeviceID>.stride))
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else { throw KKCoreAudioError.system(operation: "read device property", status: status) }
        guard let text = value?.takeRetainedValue() as String? else {
            throw KKCoreAudioError.unsupportedFormat("Missing device identity")
        }
        return text
    }

    private static func outputChannelCount(_ id: AudioDeviceID) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard status == noErr else { throw KKCoreAudioError.system(operation: "read output channel size", status: status) }
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw)
        guard status == noErr else { throw KKCoreAudioError.system(operation: "read output channels", status: status) }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + $1.mNumberChannels }
    }
}

/// The sink opens an existing output only while a remote session is active. It never opens
/// a Mac microphone or modifies device formats, default devices, drivers or permissions.
public final class KKCoreAudioOutput: RemoteAudioOutput {
    private let lock = NSLock()
    private var activeDevice: AudioDeviceID?
    private var ioProc: AudioDeviceIOProcID?
    public private(set) var lastStopError: String?

    public init() {}

    /// Checks availability and format without starting the device or changing settings.
    public static func preflight(deviceUID: String) throws {
        let device = try KKAudioOutputDevices.resolve(deviceUID)
        try checkFormat(device: device, sampleRate: 48_000, channels: 2)
    }

    public func start(deviceUID: String, sampleRate: Int, channels: Int,
                      render: @escaping (Int) -> [Float]) throws {
        lock.lock(); defer { lock.unlock() }
        guard activeDevice == nil else { throw KKCoreAudioError.alreadyRunning }
        guard sampleRate == 48_000 && channels == 2 else {
            throw KKCoreAudioError.unsupportedFormat("Bridge must supply 48 kHz stereo")
        }
        let device = try KKAudioOutputDevices.resolve(deviceUID)
        try Self.checkFormat(device: device, sampleRate: sampleRate, channels: channels)
        Self.ensureUnmutedFullVolume(device: device)
        var proc: AudioDeviceIOProcID?
        let create = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, _, _, outputData, _ in
            KKCoreAudioOutput.write(outputData, render: render)
        }
        guard create == noErr, let proc else {
            // Defensively release any handle returned alongside an error.
            if let proc {
                let destroy = AudioDeviceDestroyIOProcID(device, proc)
                if destroy != noErr { lastStopError = "destroy after failed create: \(destroy)" }
            }
            throw KKCoreAudioError.system(operation: "create output callback", status: create)
        }
        let status = AudioDeviceStart(device, proc)
        guard status == noErr else {
            let destroy = AudioDeviceDestroyIOProcID(device, proc)
            if destroy != noErr { lastStopError = "destroy after failed start: \(destroy)" }
            throw KKCoreAudioError.system(operation: "start selected output", status: status)
        }
        lastStopError = nil
        activeDevice = device
        ioProc = proc
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let device = activeDevice, let proc = ioProc else { return }
        let stopped = AudioDeviceStop(device, proc)
        let destroyed = AudioDeviceDestroyIOProcID(device, proc)
        if stopped != noErr || destroyed != noErr {
            lastStopError = "stop=\(stopped), destroy=\(destroyed)"
        } else { lastStopError = nil }
        // A failed destruction retains the handle so callers can retry cleanup.
        if destroyed == noErr { activeDevice = nil; ioProc = nil }
    }

    private static func checkFormat(device: AudioDeviceID, sampleRate: Int, channels: Int) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var bytes = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, &format)
        guard status == noErr else { throw KKCoreAudioError.system(operation: "read output stream format", status: status) }
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate == Double(sampleRate),
              format.mChannelsPerFrame == UInt32(channels),
              format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              format.mFramesPerPacket == 1 else {
            throw KKCoreAudioError.unsupportedFormat("Requires 48 kHz, 2-channel packed Float32 PCM; device reports \(format)")
        }
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard format.mBytesPerFrame == (nonInterleaved ? 4 : 8),
              format.mBytesPerPacket == format.mBytesPerFrame else {
            throw KKCoreAudioError.unsupportedFormat("Invalid bytes per frame or packet")
        }
    }

    /// Ensures the selected virtual loopback device is unmuted and at full unity gain (1.0)
    /// across both Output and Input scopes and owned HAL volume/mute controls.
    private static func ensureUnmutedFullVolume(device: AudioDeviceID) {
        let scopes: [AudioObjectPropertyScope] = [
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyScopeInput,
            kAudioObjectPropertyScopeGlobal
        ]
        let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2
        ]

        for scope in scopes {
            for element in elements {
                var muteAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyMute,
                    mScope: scope,
                    mElement: element
                )
                if AudioObjectHasProperty(device, &muteAddr) {
                    var settable: DarwinBoolean = false
                    if AudioObjectIsPropertySettable(device, &muteAddr, &settable) == noErr, settable.boolValue {
                        var unmuted: UInt32 = 0
                        _ = AudioObjectSetPropertyData(
                            device,
                            &muteAddr,
                            0,
                            nil,
                            UInt32(MemoryLayout<UInt32>.size),
                            &unmuted
                        )
                    }
                }

                var volAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: scope,
                    mElement: element
                )
                if AudioObjectHasProperty(device, &volAddr) {
                    var settable: DarwinBoolean = false
                    if AudioObjectIsPropertySettable(device, &volAddr, &settable) == noErr, settable.boolValue {
                        var fullVolume: Float32 = 1.0
                        _ = AudioObjectSetPropertyData(
                            device,
                            &volAddr,
                            0,
                            nil,
                            UInt32(MemoryLayout<Float32>.size),
                            &fullVolume
                        )
                    }
                }
            }
        }

        var controlListAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyControlList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var listBytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &controlListAddr, 0, nil, &listBytes) == noErr,
              listBytes >= UInt32(MemoryLayout<AudioObjectID>.stride) else {
            return
        }
        let count = Int(listBytes) / MemoryLayout<AudioObjectID>.stride
        var controls = [AudioObjectID](repeating: 0, count: count)
        let status = controls.withUnsafeMutableBytes { raw in
            AudioObjectGetPropertyData(device, &controlListAddr, 0, nil, &listBytes, raw.baseAddress!)
        }
        guard status == noErr else { return }

        for controlID in controls {
            var muteCtrlAddr = AudioObjectPropertyAddress(
                mSelector: kAudioBooleanControlPropertyValue,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(controlID, &muteCtrlAddr) {
                var unmuted: UInt32 = 0
                _ = AudioObjectSetPropertyData(
                    controlID,
                    &muteCtrlAddr,
                    0,
                    nil,
                    UInt32(MemoryLayout<UInt32>.size),
                    &unmuted
                )
            }

            var levelCtrlAddr = AudioObjectPropertyAddress(
                mSelector: kAudioLevelControlPropertyScalarValue,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(controlID, &levelCtrlAddr) {
                var fullVolume: Float32 = 1.0
                _ = AudioObjectSetPropertyData(
                    controlID,
                    &levelCtrlAddr,
                    0,
                    nil,
                    UInt32(MemoryLayout<Float32>.size),
                    &fullVolume
                )
            }
        }
    }

    /// Internal so tests can verify planar/interleaved layouts without audio hardware.
    static func write(_ pointer: UnsafeMutablePointer<AudioBufferList>, render: (Int) -> [Float]) {
        let buffers = UnsafeMutableAudioBufferListPointer(pointer)
        // Never leak stale output if a device presents an unexpected layout.
        for buffer in buffers {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard buffers.count == 1 || buffers.count == 2 else { return }
        if buffers.count == 1 {
            let b = buffers[0]
            guard b.mNumberChannels == 2, let data = b.mData,
                  b.mDataByteSize % 8 == 0 else { return }
            let frames = Int(b.mDataByteSize) / 8
            let pcm = render(frames)
            guard pcm.count == frames * 2 else { return }
            pcm.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { data.copyMemory(from: base, byteCount: Int(b.mDataByteSize)) }
            }
        } else {
            let l = buffers[0], r = buffers[1]
            guard l.mNumberChannels == 1, r.mNumberChannels == 1,
                  l.mDataByteSize == r.mDataByteSize, l.mDataByteSize % 4 == 0,
                  let left = l.mData?.assumingMemoryBound(to: Float.self),
                  let right = r.mData?.assumingMemoryBound(to: Float.self) else { return }
            let frames = Int(l.mDataByteSize) / 4
            let pcm = render(frames)
            guard pcm.count == frames * 2 else { return }
            for frame in 0..<frames { left[frame] = pcm[frame * 2]; right[frame] = pcm[frame * 2 + 1] }
        }
    }
}
