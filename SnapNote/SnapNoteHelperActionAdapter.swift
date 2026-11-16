import Foundation

/// A sanitized local helper command; it never contains the SnapNote token or note content.
public struct SnapNoteHelperMessage: Equatable, Sendable {
    public let type: String
    public let actionID: UUID
    public let target: String?
    public let shortcut: String?
    public init(type: String, actionID: UUID, target: String? = nil, shortcut: String? = nil) {
        self.type = type; self.actionID = actionID; self.target = target; self.shortcut = shortcut
    }
    /// Wire keys expected by the helper's JSON protocol. No token belongs in this dictionary.
    public var wireFields: [String: String] {
        var fields = ["type":type, "actionId":actionID.uuidString.lowercased()]
        if let target { fields["target"] = target }
        if let shortcut { fields["shortcut"] = shortcut }
        return fields
    }
}

/// Async request correlation around a nonblocking, serialized helper pipe.
///
/// IMPORTANT: The existing helper does NOT implement cancellation acknowledgements. Therefore
/// `cancellationAcknowledgementSupported` defaults to false and requests fail before dispatch.
/// Only set it true after verifying the actual running helper implements this wire contract:
/// - receive {type:"cancel_snapnote_action", actionId:...}; atomically invalidate its delayed
///   action on the helper's main queue before acknowledging;
/// - reply {type:"snapnote_action_cancelled", actionId:..., prevented:true} ONLY if the
///   pending shortcut/period cannot run after that reply; reply prevented:false if completion
///   might already have occurred. Old/unknown action IDs must never cancel a different action.
/// A caller must restart/replace the helper after an unconfirmed cancellation. Construct a new
/// adapter only after that restart has completed; the old adapter deliberately stays quarantined.
public actor SnapNoteHelperActionAdapter: SnapNoteNativeAction {
    private final class Pending {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
        var timeout: Task<Void, Never>?
        var grace: Task<Void, Never>?
        var cancelling: SnapNoteError?
        init(id: UUID, continuation: CheckedContinuation<Void, Error>) {
            self.id = id; self.continuation = continuation
        }
    }

    private let cancellationAcknowledgementSupported: Bool
    /// Must be nonblocking and serialize writes; a thrown error means delivery is unknown.
    private let send: @Sendable (SnapNoteHelperMessage) throws -> Void
    private let timeoutNanoseconds: UInt64
    private let cancellationGraceNanoseconds: UInt64
    private var pending: Pending?
    private var quarantined = false

    public init(cancellationAcknowledgementSupported: Bool = false,
                timeoutNanoseconds: UInt64 = 8_000_000_000,
                cancellationGraceNanoseconds: UInt64 = 1_000_000_000,
                send: @escaping @Sendable (SnapNoteHelperMessage) throws -> Void) {
        self.cancellationAcknowledgementSupported = cancellationAcknowledgementSupported
        self.timeoutNanoseconds = timeoutNanoseconds
        self.cancellationGraceNanoseconds = cancellationGraceNanoseconds
        self.send = send
    }

    public var isQuarantined: Bool { quarantined }

    public func performNewNote(shortcut: String, actionID: UUID) async throws {
        guard cancellationAcknowledgementSupported else { throw SnapNoteError.nativeCancellationUnsupported }
        guard !quarantined else { throw SnapNoteError.nativeCancellationUnconfirmed }
        guard pending == nil else { throw SnapNoteError.busy }
        guard SnapNoteCoordinator.validShortcut(shortcut) else { throw SnapNoteError.invalidShortcut }
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: SnapNoteError.cancelled); return }
                let entry = Pending(id: actionID, continuation: continuation)
                pending = entry
                entry.timeout = Task { [timeoutNanoseconds] in
                    do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
                    self.beginCancellation(actionID: actionID, reason: .timeout)
                }
                do {
                    try send(SnapNoteHelperMessage(type: "post_key", actionID: actionID,
                                                   target: "snapnoteNewNote", shortcut: shortcut))
                } catch {
                    // The write might have reached the pipe even if reporting failure.
                    beginCancellation(actionID: actionID, reason: .nativeActionFailed)
                }
            }
        } onCancel: {
            Task { await self.beginCancellation(actionID: actionID, reason: .cancelled) }
        }
    }

    /// Feed only events from the current, authenticated helper connection.
    /// The new cancellation acknowledgement is NOT implemented by the current helper.
    public func handleHelperEvent(type: String, actionID: UUID, prevented: Bool? = nil) {
        guard let entry = pending, entry.id == actionID else { return }
        if type == "snapnote_action_cancelled", let reason = entry.cancelling {
            if prevented == true { finish(entry, error: reason) }
            else { quarantined = true; finish(entry, error: .nativeCancellationUnconfirmed) }
        } else if type == "action_done" {
            if entry.cancelling != nil {
                quarantined = true; finish(entry, error: .nativeCancellationUnconfirmed)
            } else { finish(entry, error: nil) }
        } else if type == "action_error" {
            if entry.cancelling == nil { finish(entry, error: .nativeActionFailed) }
            // While cancelling, wait for the explicit acknowledgement or grace deadline.
        }
    }

    /// Invoke on helper shutdown or exit, even when idle. An action may already have inserted
    /// its marker; no more work may be dispatched until a fresh helper and adapter are created.
    public func helperDisconnected() {
        quarantined = true
        guard let entry = pending else { return }
        finish(entry, error: .nativeCancellationUnconfirmed)
    }

    private func beginCancellation(actionID: UUID, reason: SnapNoteError) {
        guard let entry = pending, entry.id == actionID, entry.cancelling == nil else { return }
        entry.cancelling = reason
        entry.timeout?.cancel(); entry.timeout = nil
        do { try send(SnapNoteHelperMessage(type: "cancel_snapnote_action", actionID: actionID)) }
        catch {
            quarantined = true; finish(entry, error: .nativeCancellationUnconfirmed); return
        }
        entry.grace = Task { [cancellationGraceNanoseconds] in
            do { try await Task.sleep(nanoseconds: cancellationGraceNanoseconds) } catch { return }
            self.cancellationDeadline(actionID: actionID)
        }
    }

    private func cancellationDeadline(actionID: UUID) {
        guard let entry = pending, entry.id == actionID, entry.cancelling != nil else { return }
        quarantined = true
        finish(entry, error: .nativeCancellationUnconfirmed)
    }

    private func finish(_ entry: Pending, error: SnapNoteError?) {
        guard pending === entry else { return }
        pending = nil
        entry.timeout?.cancel(); entry.grace?.cancel()
        if let error { entry.continuation.resume(throwing: error) }
        else { entry.continuation.resume() }
    }
}
