import Foundation

/// A hardware-independent, single-threaded session state machine.
/// Callers serialize events and perform effects in order on their own queue.
public struct VoiceSession {
    public enum Source: Hashable { case remote, keyboard }
    public enum RemoteGesture: Equatable { case toggle, hybrid }
    public enum Phase: Equatable {
        case idle
        case starting(UUID)
        case recording(UUID)
        case stopping(UUID)
    }
    /// begin/end are scoped to an ID. Drivers MUST NOT close a different session.
    /// end is idempotent, cancels pending begin as well as active capture, and
    /// must cause didStop even if capture was never opened.
    public enum Effect: Equatable { case begin(UUID), end(UUID) }
    private struct Press {
        let id: UUID?
        let began: TimeInterval
        let wasActive: Bool
    }
    public private(set) var phase: Phase = .idle
    private var presses: [Source: Press] = [:]
    private let longPress: TimeInterval
    public private(set) var remoteGesture: RemoteGesture

    public init(longPress: TimeInterval = 0.5, remoteGesture: RemoteGesture = .toggle) {
        precondition(longPress > 0)
        self.longPress = longPress
        self.remoteGesture = remoteGesture
    }

    @discardableResult public mutating func setRemoteGesture(_ gesture: RemoteGesture) -> Bool {
        guard phase == .idle, presses.isEmpty else { return false }
        remoteGesture = gesture
        return true
    }

    /// Time is supplied by caller from a monotonic clock, in seconds.
    public mutating func press(_ source: Source, at time: TimeInterval) -> [Effect] {
        guard presses[source] == nil else { return [] }
        switch phase {
        case .idle:
            let id = UUID()
            presses[source] = Press(id: id, began: time, wasActive: false)
            phase = .starting(id)
            return [.begin(id)]
        case .starting(let id), .recording(let id):
            presses[source] = Press(id: id, began: time, wasActive: true)
            if source == .keyboard { return requestStop(id) }
            return [] // Remote stop is confirmed on the matching release edge.
        case .stopping:
            presses[source] = Press(id: nil, began: time, wasActive: true)
            return []
        }
    }

    public mutating func release(_ source: Source, at time: TimeInterval) -> [Effect] {
        guard let press = presses.removeValue(forKey: source) else { return [] }
        guard source == .remote, let id = press.id else { return [] }
        guard currentID == id else { return [] } // Late release from older gesture.
        if press.wasActive || (remoteGesture == .hybrid && max(0, time - press.began) >= longPress) {
            return requestStop(id)
        }
        return []
    }

    /// A successful late start must be actively stopped; ignoring it can leak audio.
    public mutating func didStart(_ id: UUID) -> [Effect] {
        switch phase {
        case .starting(id): phase = .recording(id); return []
        case .recording(id): return [] // duplicate acknowledgement
        default: return [.end(id)]
        }
    }

    /// Drivers call this on start failure, disconnection, and successful teardown.
    /// Stale notifications never change a newer session.
    public mutating func didStop(_ id: UUID) {
        guard currentID == id else { return }
        phase = .idle
    }

    /// Close the actual capture on cancellation, disconnect, or application shutdown.
    public mutating func cancel() -> [Effect] {
        guard let id = currentID else { presses.removeAll(); return [] }
        presses.removeAll()
        return requestStop(id)
    }

    private var currentID: UUID? {
        switch phase {
        case .idle: return nil
        case .starting(let id), .recording(let id), .stopping(let id): return id
        }
    }
    private mutating func requestStop(_ id: UUID) -> [Effect] {
        switch phase {
        case .starting(id), .recording(id):
            phase = .stopping(id)
            return [.end(id)]
        default: return []
        }
    }
}
