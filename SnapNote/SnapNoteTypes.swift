import Foundation

public enum SnapNoteError: Error, Equatable, Sendable {
    case invalidToken, notConfigured, invalidShortcut, invalidTag, recording, busy
    case unavailable, unauthorized, timeout, protocolError, sessionExpired
    case operationFailed, unstableBaseline, multipleCandidates, candidateRejected
    case candidateNotFound, tagUnverified, cancelled
    case nativeCancellationUnsupported, nativeCancellationUnconfirmed, nativeActionFailed
}

/// Only data needed to correlate a newly created note. Never log these records.
public struct SnapNoteRecord: Equatable, Sendable {
    public let id: UUID
    public let createdAtMs: Int64
    public let title: String
    public let bodyPreview: String
    public let preview: String
    public let plainTextCount: Int
    public let tagNames: [String]
    public let isArchived: Bool
    public let isDeleted: Bool

    public init(id: UUID, createdAtMs: Int64, title: String, bodyPreview: String, preview: String,
                plainTextCount: Int, tagNames: [String], isArchived: Bool = false, isDeleted: Bool = false) {
        self.id = id; self.createdAtMs = createdAtMs; self.title = title
        self.bodyPreview = bodyPreview; self.preview = preview; self.plainTextCount = plainTextCount
        self.tagNames = tagNames; self.isArchived = isArchived; self.isDeleted = isDeleted
    }
}

public protocol SnapNoteService: Sendable {
    func verifyService() async throws
    func recent() async throws -> [UUID: SnapNoteRecord]
    /// A failed or timed-out write has an unknown outcome and MUST NOT be retried automatically.
    func addFlashTag(noteID: UUID, tagName: String) async throws
}

public extension SnapNoteService {
    func addFlashTag(noteID: UUID) async throws {
        try await addFlashTag(noteID: noteID, tagName: "闪念")
    }
}

public struct SnapNoteHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data
    public init(statusCode: Int, headers: [String: String] = [:], data: Data = Data()) {
        self.statusCode = statusCode; self.headers = headers; self.data = data
    }
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol SnapNoteHTTPTransport: Sendable {
    func post(body: Data, headers: [String: String], timeout: TimeInterval) async throws -> SnapNoteHTTPResponse
}
