import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

public enum MacMicrophonePermissionStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

public enum MacMicrophoneError: Error, LocalizedError, Equatable, CustomStringConvertible {
    case permissionDenied
    case noInputDeviceAvailable
    case missingOutputDeviceUID
    case alreadyRunning
    case deviceNotFound(String)
    case unsupportedInputFormat(String)
    case system(operation: String, status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要麦克风权限"
        case .noInputDeviceAvailable:
            return "未找到可用的 Mac 麦克风"
        case .missingOutputDeviceUID:
            return "未选择虚拟麦克风"
        case .alreadyRunning:
            return "麦克风已在收音中"
        case let .deviceNotFound(uid):
            return "找不到 Mac 麦克风：\(uid)"
        case let .unsupportedInputFormat(detail):
            return "不支持的麦克风格式：\(detail)"
        case let .system(operation, status):
            return "Mac 麦克风启动失败（\(operation): \(status)）"
        }
    }

    public var description: String {
        errorDescription ?? "Mac 麦克风错误"
    }

    public var isPermissionDenied: Bool {
        if case .permissionDenied = self { return true }
        return false
    }
}

/// Bounded 48 kHz stereo Float32 circular buffer fed by a Mac physical microphone
/// at any input sample rate (e.g. 48 kHz, 44.1 kHz, 24 kHz, 16 kHz) and channel count.
/// Uses an exact integer phase accumulator for drift-free linear resampling.
public final class MacMicrophonePCMBuffer {
    public static let outputRate = 48_000
    public static let channels = 2

    private let lock = NSLock()
    private var samples: [Float]
    private var readIndex = 0
    private var count = 0
    private var previous: Float?
    private var inputRate: Int = 48_000
    private var phaseUnits: Int = 48_000
    private var activeSession: UUID?
    private var droppedFrameCount = 0
    private var receivedInputFrameCount = 0

    public var droppedFrames: Int {
        lock.lock(); defer { lock.unlock() }
        return droppedFrameCount
    }

    public var receivedInputFrames: Int {
        lock.lock(); defer { lock.unlock() }
        return receivedInputFrameCount
    }

    public init(capacityFrames: Int = 48_000) {
        precondition(capacityFrames > 0)
        self.samples = Array(repeating: 0, count: capacityFrames * Self.channels)
    }

    public func start(session: UUID, inputSampleRate: Int = 48_000) {
        lock.lock(); defer { lock.unlock() }
        clearLocked()
        let rate = max(1, inputSampleRate)
        self.inputRate = rate
        self.phaseUnits = min(rate, Self.outputRate)
        self.activeSession = session
        self.droppedFrameCount = 0
        self.receivedInputFrameCount = 0
    }

    @discardableResult
    public func stop(session: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard activeSession == session else { return false }
        activeSession = nil
        clearLocked()
        return true
    }

    /// Appends mono Float32 samples at `sampleRate` (defaults to the rate configured at `start`).
    @discardableResult
    public func appendMonoFloats(_ mono: [Float], sampleRate: Int? = nil, session: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard activeSession == session else { return false }
        if let sampleRate, sampleRate > 0, sampleRate != inputRate {
            inputRate = sampleRate
            phaseUnits = min(sampleRate, Self.outputRate)
            previous = nil
        }
        appendMonoLocked(mono)
        return true
    }

    /// Extracts mono samples from a CoreAudio `AudioBufferList` (interleaved or planar, Float32 or Int16)
    /// and resamples them into 48 kHz stereo frames.
    @discardableResult
    public func appendAudioBufferList(
        _ pointer: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription,
        session: UUID
    ) -> Bool {
        guard let mono = Self.extractMonoFloats(from: pointer, format: format), !mono.isEmpty else {
            return false
        }
        let rate = max(1, Int(format.mSampleRate.rounded()))
        return appendMonoFloats(mono, sampleRate: rate, session: session)
    }

    /// Renders `frameCount` stereo frames (2 floats per frame). Underruns or stale sessions produce silence.
    public func render(frameCount: Int, session: UUID) -> [Float] {
        precondition(frameCount >= 0)
        lock.lock(); defer { lock.unlock() }
        var output = Array(repeating: Float.zero, count: frameCount * Self.channels)
        guard activeSession == session else { return output }
        let take = min(output.count, count)
        for index in 0..<take {
            output[index] = samples[readIndex]
            samples[readIndex] = 0
            readIndex = (readIndex + 1) % samples.count
        }
        count -= take
        return output
    }

    internal static func extractMonoFloats(
        from pointer: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription
    ) -> [Float]? {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate > 0,
              format.mChannelsPerFrame >= 1 else {
            return nil
        }
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32
        let isInt16 = (format.mFormatFlags & kAudioFormatFlagIsFloat) == 0 && format.mBitsPerChannel == 16
        guard isFloat || isInt16 else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: pointer))
        guard !buffers.isEmpty else { return nil }

        if buffers.count == 1 {
            let b = buffers[0]
            let channels = Int(b.mNumberChannels)
            guard channels >= 1, let data = b.mData, b.mDataByteSize > 0 else { return nil }
            if isFloat {
                let bytesPerFrame = channels * 4
                guard Int(b.mDataByteSize) >= bytesPerFrame else { return nil }
                let frames = Int(b.mDataByteSize) / bytesPerFrame
                let src = data.assumingMemoryBound(to: Float.self)
                if channels == 1 {
                    return Array(UnsafeBufferPointer(start: src, count: frames))
                }
                var result = [Float](repeating: 0, count: frames)
                let scale = 1.0 / Float(channels)
                for f in 0..<frames {
                    var sum: Float = 0
                    let base = f * channels
                    for c in 0..<channels {
                        sum += src[base + c]
                    }
                    result[f] = sum * scale
                }
                return result
            } else {
                let bytesPerFrame = channels * 2
                guard Int(b.mDataByteSize) >= bytesPerFrame else { return nil }
                let frames = Int(b.mDataByteSize) / bytesPerFrame
                let src = data.assumingMemoryBound(to: Int16.self)
                var result = [Float](repeating: 0, count: frames)
                let scale = 1.0 / (32768.0 * Float(channels))
                for f in 0..<frames {
                    var sum: Float = 0
                    let base = f * channels
                    for c in 0..<channels {
                        sum += Float(Int16(littleEndian: src[base + c]))
                    }
                    result[f] = sum * scale
                }
                return result
            }
        } else {
            let validBuffers = buffers.filter { $0.mNumberChannels >= 1 && $0.mData != nil && $0.mDataByteSize > 0 }
            guard let first = validBuffers.first else { return nil }
            let sampleSize = isFloat ? 4 : 2
            let frames = Int(first.mDataByteSize) / sampleSize
            guard frames > 0 else { return nil }
            var result = [Float](repeating: 0, count: frames)
            var channelCount = 0
            for buf in validBuffers {
                guard Int(buf.mDataByteSize) / sampleSize >= frames, let data = buf.mData else { continue }
                channelCount += 1
                if isFloat {
                    let src = data.assumingMemoryBound(to: Float.self)
                    for f in 0..<frames { result[f] += src[f] }
                } else {
                    let src = data.assumingMemoryBound(to: Int16.self)
                    for f in 0..<frames { result[f] += Float(Int16(littleEndian: src[f])) / 32768.0 }
                }
            }
            guard channelCount > 0 else { return nil }
            if channelCount > 1 {
                let scale = 1.0 / Float(channelCount)
                for f in 0..<frames { result[f] *= scale }
            }
            return result
        }
    }

    private func appendMonoLocked(_ mono: [Float]) {
        let outRate = Self.outputRate
        let inRate = max(1, inputRate)
        receivedInputFrameCount += mono.count
        for current in mono {
            let prior = previous ?? current
            while phaseUnits <= outRate {
                let frac = Float(phaseUnits) / Float(outRate)
                let value = prior + (current - prior) * frac
                appendStereoFrameLocked(value)
                phaseUnits += inRate
            }
            phaseUnits -= outRate
            previous = current
        }
    }

    private func appendStereoFrameLocked(_ value: Float) {
        if count + Self.channels > samples.count {
            for _ in 0..<Self.channels {
                samples[readIndex] = 0
                readIndex = (readIndex + 1) % samples.count
                count -= 1
            }
            droppedFrameCount += 1
        }
        for _ in 0..<Self.channels {
            samples[(readIndex + count) % samples.count] = value
            count += 1
        }
    }

    private func clearLocked() {
        for index in samples.indices { samples[index] = 0 }
        readIndex = 0
        count = 0
        previous = nil
        phaseUnits = min(inputRate, Self.outputRate)
        receivedInputFrameCount = 0
    }
}

public protocol MacMicrophoneInputDriver: AnyObject {
    func start(
        deviceUID: String,
        onInput: @escaping (UnsafePointer<AudioBufferList>, AudioStreamBasicDescription) -> Void
    ) throws
    func stop()
    var lastStopError: String? { get }
}

/// Captures from a specific physical input device only while a session is active.
/// Never touches the system default device or creates aggregate devices.
public final class KKCoreAudioInputDriver: MacMicrophoneInputDriver {
    private let lock = NSLock()
    private var activeDevice: AudioDeviceID?
    private var ioProc: AudioDeviceIOProcID?
    public private(set) var lastStopError: String?

    public init() {}

    public func start(
        deviceUID: String,
        onInput: @escaping (UnsafePointer<AudioBufferList>, AudioStreamBasicDescription) -> Void
    ) throws {
        lock.lock(); defer { lock.unlock() }
        guard activeDevice == nil else { throw MacMicrophoneError.alreadyRunning }
        let device: AudioDeviceID
        do {
            device = try KKInputDeviceCatalog.resolveAudioDeviceID(forUID: deviceUID)
        } catch {
            throw MacMicrophoneError.deviceNotFound(deviceUID)
        }
        let format = try Self.readInputFormat(device: device)
        var proc: AudioDeviceIOProcID?
        let create = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, inInputData, _, _, _ in
            onInput(inInputData, format)
        }
        guard create == noErr, let proc else {
            if let proc {
                let destroy = AudioDeviceDestroyIOProcID(device, proc)
                if destroy != noErr { lastStopError = "destroy input after failed create: \(destroy)" }
            }
            throw MacMicrophoneError.system(operation: "create input callback", status: create)
        }
        let status = AudioDeviceStart(device, proc)
        guard status == noErr else {
            let destroy = AudioDeviceDestroyIOProcID(device, proc)
            if destroy != noErr { lastStopError = "destroy input after failed start: \(destroy)" }
            throw MacMicrophoneError.system(operation: "start input device", status: status)
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
            lastStopError = "input stop=\(stopped), destroy=\(destroyed)"
        } else {
            lastStopError = nil
        }
        if destroyed == noErr {
            activeDevice = nil
            ioProc = nil
        }
    }

    private static func readInputFormat(device: AudioDeviceID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var bytes = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, &format)
        guard status == noErr else {
            throw MacMicrophoneError.system(operation: "read input stream format", status: status)
        }
        let isFloat32 = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32
        let isInt16 = (format.mFormatFlags & kAudioFormatFlagIsFloat) == 0 && format.mBitsPerChannel == 16
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate > 0,
              format.mChannelsPerFrame >= 1,
              isFloat32 || isInt16 else {
            throw MacMicrophoneError.unsupportedInputFormat("\(format)")
        }
        return format
    }
}

/// Bridges a physical Mac microphone to the selected virtual output device (`KKvoice Mic`)
/// strictly for the duration of a single voice session.
public final class MacMicrophoneSource {
    public typealias PermissionChecker = () -> MacMicrophonePermissionStatus
    public typealias PermissionRequester = (@escaping (Bool) -> Void) -> Void

    private let lifecycleLock = NSLock()
    private let input: MacMicrophoneInputDriver
    private let output: RemoteAudioOutput
    private let buffer: MacMicrophonePCMBuffer
    private let permissionCheck: PermissionChecker
    private let permissionRequest: PermissionRequester
    private var session: UUID?

    public var lastStopError: String? {
        input.lastStopError
    }

    public init(
        input: MacMicrophoneInputDriver = KKCoreAudioInputDriver(),
        output: RemoteAudioOutput,
        capacityFrames: Int = 48_000,
        permissionCheck: @escaping PermissionChecker = MacMicrophoneSource.systemPermissionStatus,
        permissionRequest: @escaping PermissionRequester = MacMicrophoneSource.requestSystemPermission
    ) {
        self.input = input
        self.output = output
        self.buffer = MacMicrophonePCMBuffer(capacityFrames: capacityFrames)
        self.permissionCheck = permissionCheck
        self.permissionRequest = permissionRequest
    }

    public static func systemPermissionStatus() -> MacMicrophonePermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public static func requestSystemPermission(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    @discardableResult
    public func start(
        inputDeviceUID: String,
        outputDeviceUID: String,
        onPermissionDenied: (() -> Void)? = nil
    ) throws -> UUID {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        let trimmedInput = inputDeviceUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = outputDeviceUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw MacMicrophoneError.missingOutputDeviceUID
        }
        guard !trimmedInput.isEmpty else {
            throw MacMicrophoneError.noInputDeviceAvailable
        }
        guard session == nil else {
            throw MacMicrophoneError.alreadyRunning
        }

        let authStatus = permissionCheck()
        switch authStatus {
        case .denied, .restricted:
            throw MacMicrophoneError.permissionDenied
        case .notDetermined:
            let pendingID = UUID()
            return try startCaptureLocked(
                id: pendingID,
                inputDeviceUID: trimmedInput,
                outputDeviceUID: trimmedOutput,
                requestingPermission: true,
                onPermissionDenied: onPermissionDenied
            )
        case .authorized:
            let id = UUID()
            return try startCaptureLocked(
                id: id,
                inputDeviceUID: trimmedInput,
                outputDeviceUID: trimmedOutput,
                requestingPermission: false,
                onPermissionDenied: nil
            )
        }
    }

    /// Injects synthetic mono float frames into the active session (for hardware-free testing).
    @discardableResult
    public func receiveMonoFloats(_ mono: [Float], sampleRate: Int = 48_000, session id: UUID) -> Bool {
        buffer.appendMonoFloats(mono, sampleRate: sampleRate, session: id)
    }

    @discardableResult
    public func stop(session id: UUID) -> Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard session == id else { return false }
        _ = buffer.stop(session: id)
        session = nil
        input.stop()
        output.stop()
        return true
    }

    private func startCaptureLocked(
        id: UUID,
        inputDeviceUID: String,
        outputDeviceUID: String,
        requestingPermission: Bool,
        onPermissionDenied: (() -> Void)?
    ) throws -> UUID {
        buffer.start(session: id, inputSampleRate: 48_000)
        session = id
        do {
            try output.start(
                deviceUID: outputDeviceUID,
                sampleRate: MacMicrophonePCMBuffer.outputRate,
                channels: MacMicrophonePCMBuffer.channels
            ) { [weak buffer] frames in
                buffer?.render(frameCount: frames, session: id) ?? Array(repeating: 0, count: max(0, frames) * 2)
            }
            try input.start(deviceUID: inputDeviceUID) { [weak buffer] bufferList, format in
                _ = buffer?.appendAudioBufferList(bufferList, format: format, session: id)
            }
            if requestingPermission {
                permissionRequest { [weak self] granted in
                    guard let self else { return }
                    if !granted {
                        if self.stop(session: id) {
                            onPermissionDenied?()
                        }
                    }
                }
            }
            return id
        } catch {
            input.stop()
            output.stop()
            _ = buffer.stop(session: id)
            session = nil
            throw error
        }
    }
}
