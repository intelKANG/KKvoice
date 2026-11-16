import Foundation

/// Implementations must output 48 kHz interleaved stereo floats to the explicitly selected
/// output device. They must never substitute the system default if the device is unavailable.
public protocol RemoteAudioOutput: AnyObject {
    func start(deviceUID: String, sampleRate: Int, channels: Int,
               render: @escaping (Int) -> [Float]) throws
    /// Must stop callbacks and release the output device before returning.
    func stop()
}

public enum RemoteAudioBridgeError: Error {
    case missingDeviceUID
    case alreadyRunning
}

/// Routes only the remote's PCM. This object never captures a Mac microphone.
public final class RemoteAudioBridge {
    private let lifecycleLock = NSLock()
    private let buffer: RemotePCMBuffer
    private let output: RemoteAudioOutput
    private var session: UUID?

    public init(output: RemoteAudioOutput, capacityFrames: Int = 48_000) {
        self.output = output
        self.buffer = RemotePCMBuffer(capacityFrames: capacityFrames)
    }

    /// The UUID must accompany each packet and stop to guard against late device events.
    @discardableResult public func start(deviceUID: String) throws -> UUID {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard !deviceUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteAudioBridgeError.missingDeviceUID
        }
        guard session == nil else { throw RemoteAudioBridgeError.alreadyRunning }
        let id = UUID()
        buffer.start(session: id)
        session = id
        do {
            try output.start(deviceUID: deviceUID, sampleRate: RemotePCMBuffer.outputRate,
                             channels: RemotePCMBuffer.channels) { [weak buffer] frames in
                buffer?.render(frameCount: frames, session: id) ?? Array(repeating: 0, count: max(0, frames) * 2)
            }
            return id
        } catch {
            // The output may have partially started before throwing.
            output.stop()
            _ = buffer.stop(session: id)
            session = nil
            throw error
        }
    }

    @discardableResult public func receive(_ pcm16LE: Data, session id: UUID) -> Bool {
        buffer.appendPCM16LE(pcm16LE, session: id)
    }

    /// An obsolete stop cannot close an active later session.
    @discardableResult public func stop(session id: UUID) -> Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard session == id else { return false }
        // Invalidate and silence first, including while output is shutting down.
        _ = buffer.stop(session: id)
        session = nil
        output.stop()
        return true
    }
}
