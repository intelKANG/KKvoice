import Foundation

/// Relay for a single configured toggle shortcut. Mutate on the same serial
/// queue as VoiceSession. `physicalDelivered` is true ONLY when the exact
/// original keyboard event was allowed through to the target input app.
public struct ShortcutRelay {
    public enum Origin { case remote, keyboardConsumed, keyboardDelivered }
    public enum Action: Equatable {
        case capture(VoiceSession.Effect)
        case sendToggle(UUID)
        /// A physical shortcut reached the input app while a start was still
        /// pending, or capture failed. Input-app state must be checked manually.
        case synchronizationUncertain(UUID)
    }
    private enum TargetState { case waiting, assumedActive }
    private var sessions: [UUID: TargetState] = [:]
    public init() {}

    /// Supply only effects from a user press/release or explicit cancel.
    /// Do not pass effects generated for a stale didStart to this method.
    public mutating func handle(_ effects: [VoiceSession.Effect], origin: Origin) -> [Action] {
        var result: [Action] = []
        for effect in effects {
            switch effect {
            case .begin(let id):
                // Physical key already passed through; never duplicate it.
                sessions[id] = origin == .keyboardDelivered ? .assumedActive : .waiting
                result.append(.capture(effect))
            case .end(let id):
                result.append(.capture(effect))
                guard let state = sessions.removeValue(forKey: id) else { continue }
                if origin == .keyboardDelivered {
                    if case .waiting = state { result.append(.synchronizationUncertain(id)) }
                } else if case .assumedActive = state {
                    result.append(.sendToggle(id))
                }
            }
        }
        return result
    }

    /// Call after VoiceSession.didStart succeeds for the *current* session.
    /// The send is queued only after audio capture is ready; a cancellation
    /// during startup therefore cannot turn on the target input app late.
    public mutating func audioReady(_ id: UUID) -> [Action] {
        guard case .waiting? = sessions[id] else { return [] }
        sessions[id] = .assumedActive
        return [.sendToggle(id)]
    }

    /// An injected shortcut has no delivery acknowledgement. On a failed send,
    /// capture failure, device loss or target-app termination, never guess or
    /// send a second toggle: surface the uncertain state for user recovery.
    public mutating func failed(_ id: UUID) -> [Action] {
        sessions.removeValue(forKey: id)
        return [.synchronizationUncertain(id)]
    }

    /// The target has already been cancelled; close capture without another toggle.
    public mutating func cancelled(_ id: UUID) {
        sessions.removeValue(forKey: id)
    }
}

/// `isDown` must be a reliable per-key physical state from the adapter; do not
/// infer it solely from aggregate modifier flags when both Control keys are held.
/// When the trigger and injected shortcut use the same physical key (e.g.
/// left Control), wait until `pressed` is false before posting synthetic events;
/// otherwise the injected key-up can interfere with the physical key hold.
public struct PhysicalTriggerGate {
    public enum Edge { case down, up }
    public private(set) var pressed = false
    public init() {}
    public mutating func receive(keyCode: UInt16, configuredKey: UInt16, isDown: Bool,
                                 isSynthetic: Bool, isRepeat: Bool) -> Edge? {
        guard !isSynthetic, !isRepeat, keyCode == configuredKey, pressed != isDown else { return nil }
        pressed = isDown
        return isDown ? .down : .up
    }
    public mutating func reset() { pressed = false }
}
