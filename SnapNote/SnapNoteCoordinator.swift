import Foundation

/// App implementation must correlate completion using actionID and implement its own bounded
/// timeout/cancellation. It must send the native helper `post_key` action snapnoteNewNote, whose
/// completion is after the configured shortcut and insertion of the single "." marker.
public protocol SnapNoteNativeAction: Sendable {
    func performNewNote(shortcut: String, actionID: UUID) async throws
}

public enum SnapNotePhase: Equatable, Sendable { case preflight, creating, identifying, tagging, verifying }

public struct SnapNoteOutcome: Equatable, Sendable {
    public let noteID: UUID?
    public let error: SnapNoteError?
    public let phase: SnapNotePhase
    /// True once the native action has been sent; do not automatically retry creation.
    public let noteMayExist: Bool
    /// True once the tag request has been sent, regardless of the response.
    public let tagMayHaveBeenWritten: Bool
    public var succeeded: Bool { error == nil && noteID != nil }
}

public actor SnapNoteCoordinator {
    private let client: SnapNoteService
    private let native: SnapNoteNativeAction
    private let isRecording: @Sendable () async -> Bool
    private let nowMs: @Sendable () -> Int64
    private let delay: @Sendable (UInt64) async throws -> Void
    private let overallTimeoutNanoseconds: UInt64
    private var inFlight = false
    private var lastCompletedMs: Int64?

    public init(client: SnapNoteService, native: SnapNoteNativeAction,
                isRecording: @escaping @Sendable () async -> Bool,
                nowMs: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
                delay: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
                overallTimeoutNanoseconds: UInt64 = 22_000_000_000) {
        self.client = client; self.native = native; self.isRecording = isRecording
        self.nowMs = nowMs; self.delay = delay; self.overallTimeoutNanoseconds = overallTimeoutNanoseconds
    }

    /// Run on a single coordinator instance. Do not clear/replace its configuration while running;
    /// cancellation must also cancel the native helper's pending delayed "." action.
    public func createAndTag(shortcut: String) async -> SnapNoteOutcome {
        func outcome(_ id: UUID? = nil, _ error: SnapNoteError? = nil, _ phase: SnapNotePhase = .preflight,
                     _ note: Bool = false, _ tag: Bool = false) -> SnapNoteOutcome {
            SnapNoteOutcome(noteID: id, error: error, phase: phase, noteMayExist: note, tagMayHaveBeenWritten: tag)
        }
        guard !inFlight else { return outcome(nil, .busy) }
        guard Self.validShortcut(shortcut) else { return outcome(nil, .invalidShortcut) }
        let started = nowMs()
        if let last = lastCompletedMs, started >= last && started - last < 2500 { return outcome(nil, .busy) }
        inFlight = true
        defer { inFlight = false; lastCompletedMs = nowMs() }
        let currentUptime = DispatchTime.now().uptimeNanoseconds
        let (sum, overflow) = currentUptime.addingReportingOverflow(overallTimeoutNanoseconds)
        let deadline = overflow ? UInt64.max : sum
        let client = self.client, native = self.native, isRecording = self.isRecording, delay = self.delay
        var phase: SnapNotePhase = .preflight
        var noteMayExist = false, tagMayHaveBeenWritten = false
        var candidateID: UUID?
        do {
            guard !(try await Self.before(deadline) { await isRecording() }) else { throw SnapNoteError.recording }
            try Task.checkCancellation()
            try await Self.before(deadline) { try await client.verifyService() }
            let baselineA = try await Self.before(deadline) { try await client.recent() }
            let baselineB = try await Self.before(deadline) { try await client.recent() }
            guard Set(baselineA.keys) == Set(baselineB.keys) else { throw SnapNoteError.unstableBaseline }
            try Task.checkCancellation()
            guard !(try await Self.before(deadline) { await isRecording() }) else { throw SnapNoteError.recording }
            let triggerAt = nowMs()
            phase = .creating
            // Even a reported failure can arrive after the native side effect.
            noteMayExist = true
            let actionID = UUID()
            try await Self.before(deadline) { try await native.performNewNote(shortcut: shortcut, actionID: actionID) }
            try Task.checkCancellation()
            phase = .identifying
            var previous: (UUID, Int64)?
            var stable = 0
            var candidate: SnapNoteRecord?
            for attempt in 0..<20 {
                if attempt > 0 { try await Self.before(deadline) { try await delay(250_000_000) } }
                try Task.checkCancellation()
                let current = try await Self.before(deadline) { try await client.recent() }
                let additions = current.values.filter { baselineB[$0.id] == nil }
                guard additions.count <= 1 else { throw SnapNoteError.multipleCandidates }
                guard let record = additions.first else { previous = nil; stable = 0; continue }
                guard !record.isArchived, !record.isDeleted,
                      record.createdAtMs >= triggerAt, record.createdAtMs <= nowMs() + 2500 else { throw SnapNoteError.candidateRejected }
                let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard record.plainTextCount == 1, trimmed(record.title) == ".",
                      trimmed(record.bodyPreview).isEmpty || trimmed(record.bodyPreview) == ".",
                      trimmed(record.preview).isEmpty || trimmed(record.preview) == "." else { throw SnapNoteError.candidateRejected }
                if let last = previous, last.0 == record.id && last.1 == record.createdAtMs { stable += 1 }
                else { previous = (record.id, record.createdAtMs); stable = 1 }
                if stable >= 2 { candidate = record; break }
            }
            guard let record = candidate else { throw SnapNoteError.candidateNotFound }
            candidateID = record.id
            try Task.checkCancellation()
            if !record.tagNames.contains("闪念") {
                phase = .tagging
                tagMayHaveBeenWritten = true
                try await Self.before(deadline) { try await client.addFlashTag(noteID: record.id) }
            }
            phase = .verifying
            let verification = try await Self.before(deadline) { try await client.recent() }
            guard let confirmed = verification[record.id], confirmed.tagNames.contains("闪念") else { throw SnapNoteError.tagUnverified }
            return outcome(record.id, nil, phase, true, tagMayHaveBeenWritten)
        } catch is CancellationError {
            return outcome(candidateID, .cancelled, phase, noteMayExist, tagMayHaveBeenWritten)
        } catch let error as SnapNoteError {
            return outcome(candidateID, error, phase, noteMayExist, tagMayHaveBeenWritten)
        } catch {
            return outcome(candidateID, .operationFailed, phase, noteMayExist, tagMayHaveBeenWritten)
        }
    }

    /// Dependencies must cooperate with cancellation; the helper adapter additionally waits for
    /// a cancellation acknowledgement (or quarantines itself after its grace deadline).
    private static func before<T: Sendable>(_ deadline: UInt64,
        _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { throw SnapNoteError.timeout }
        let remaining = deadline - now
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: remaining)
                throw SnapNoteError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw SnapNoteError.operationFailed }
            return result
        }
    }

    public static func validShortcut(_ shortcut: String) -> Bool {
        let parts = shortcut.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "shortcut" else { return false }
        let modifiers = parts[1].split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let allowed = Set(["command", "option", "control", "shift", "fn"])
        guard !modifiers.isEmpty, modifiers.allSatisfy({ allowed.contains($0) }), Set(modifiers).count == modifiers.count else { return false }
        let keys = Set((1...12).map { "F\($0)" } + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)
            + ["Space", "Return", "Escape", "Tab", "Backspace", "ForwardDelete", "Home", "End", "PageUp", "PageDown", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"])
        return keys.contains(parts[2])
    }
}
