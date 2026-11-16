import Foundation

/// A bounded 48 kHz stereo buffer fed with 16 kHz mono signed 16-bit samples.
/// No microphone or audio device is opened by this type.
public final class RemotePCMBuffer {
    public static let inputRate = 16_000
    public static let outputRate = 48_000
    public static let channels = 2

    private let lock = NSLock()
    private var samples: [Float]
    private var readIndex = 0
    private var count = 0
    private var previous: Float?
    private var activeSession: UUID?
    private var droppedFrameCount = 0
    public var droppedFrames: Int {
        lock.lock(); defer { lock.unlock() }
        return droppedFrameCount
    }

    /// Capacity is measured in output stereo frames; oldest frames are dropped on overflow.
    public init(capacityFrames: Int = 48_000) {
        precondition(capacityFrames > 0)
        samples = Array(repeating: 0, count: capacityFrames * Self.channels)
    }

    public func start(session: UUID) {
        lock.lock(); defer { lock.unlock() }
        clearLocked()
        activeSession = session
        droppedFrameCount = 0
    }

    /// Stale stop requests cannot cancel a newer recording.
    @discardableResult public func stop(session: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard activeSession == session else { return false }
        activeSession = nil
        clearLocked()
        return true
    }

    /// Converts PCM to interleaved float stereo, preserving interpolation across packets.
    /// Returns false for stale packets or non-whole little-endian samples.
    @discardableResult public func appendPCM16LE(_ data: Data, session: UUID) -> Bool {
        guard data.count.isMultiple(of: 2) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard activeSession == session else { return false }
        let bytes = [UInt8](data)
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            let current = Float(Int16(bitPattern: bits)) / 32768.0
            let prior = previous ?? current
            // Three 48 kHz frames for each 16 kHz sample. Resampling has one-sample latency.
            for phase in 1...3 {
                let value = prior + (current - prior) * (Float(phase) / 3.0)
                appendFrameLocked(value)
            }
            previous = current
        }
        return true
    }

    /// Always returns the requested number of interleaved samples; underruns are silent.
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

    private func appendFrameLocked(_ value: Float) {
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
    }
}
