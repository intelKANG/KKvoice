import Foundation
import CoreFoundation

/// MCP Streamable HTTP client. No credentials or note contents are written to logs.
public actor SnapNoteMCPClient: SnapNoteService {
    private let token: String
    private let transport: SnapNoteHTTPTransport
    private let timeout: TimeInterval
    private var protocolVersion = "2025-06-18"
    private var sessionID: String?
    private var initialized = false
    private var initializing: Task<Void, Error>?

    public init(token raw: String, transport: SnapNoteHTTPTransport = SnapNoteLocalTransport(), timeout: TimeInterval = 1.8) throws {
        let normalized = try SnapNoteToken.normalize(raw)
        self.token = normalized; self.transport = transport; self.timeout = timeout
    }

    public init(token raw: String, endpoint: URL, timeout: TimeInterval = 1.8) throws {
        let normalized = try SnapNoteToken.normalize(raw)
        self.token = normalized
        self.transport = SnapNoteLocalTransport(endpoint: endpoint)
        self.timeout = timeout
    }

    public init(token raw: String, endpointString: String, timeout: TimeInterval = 1.8) throws {
        let normalized = try SnapNoteToken.normalize(raw)
        let url = try SnapNoteLocalTransport.normalizeEndpoint(endpointString)
        self.token = normalized
        self.transport = SnapNoteLocalTransport(endpoint: url)
        self.timeout = timeout
    }

    public func verifyService() async throws {
        let result = try await tool("snapnote.service_profile", arguments: [:], readOnly: true)
        guard result["service_key"] as? String == "snapnote.data_source" else { throw SnapNoteError.protocolError }
    }

    public func recent() async throws -> [UUID: SnapNoteRecord] {
        let result = try await tool("snapnote.memo_recent", arguments: ["limit":100, "response_mode":"standard", "include_archived":false], readOnly: true)
        return try Self.parseRecent(result)
    }

    public func addFlashTag(noteID: UUID, tagName: String = "闪念") async throws {
        // Never retry a write: transport failure or HTTP/session failure may occur after a side effect.
        _ = try await tool("snapnote.memo_add_tags", arguments: ["note_uuids":[noteID.uuidString.lowercased()], "tag_path":tagName], readOnly: false)
    }

    private func initializeIfNeeded() async throws {
        if initialized { return }
        if let task = initializing { return try await task.value }
        let task = Task { try await self.performInitialization() }
        initializing = task
        do { try await task.value; initializing = nil }
        catch { initializing = nil; throw error }
    }

    private func performInitialization() async throws {
        let response = try await request(method: "initialize", params: ["protocolVersion":"2025-06-18", "capabilities":[:], "clientInfo":["name":"KKvoice", "version":"0.1"]], isInitialization: true, notification: false)
        guard let result = response?["result"] as? [String: Any], let version = result["protocolVersion"] as? String, !version.isEmpty else {
            throw SnapNoteError.protocolError
        }
        protocolVersion = version
        _ = try await request(method: "notifications/initialized", params: nil, isInitialization: false, notification: true)
        initialized = true
    }

    private func tool(_ name: String, arguments: [String: Any], readOnly: Bool) async throws -> [String: Any] {
        try await initializeIfNeeded()
        func invoke() async throws -> [String: Any] {
            let message = try await request(method: "tools/call", params: ["name":name, "arguments":arguments], isInitialization: false, notification: false)
            guard let result = message?["result"] as? [String: Any], result["isError"] as? Bool != true else { throw SnapNoteError.operationFailed }
            if let structured = result["structuredContent"] as? [String: Any] { return structured }
            if let content = result["content"] as? [[String: Any]] {
                let text = content.compactMap { item -> String? in
                    guard item["type"] as? String == "text" else { return nil }; return item["text"] as? String
                }.joined(separator: "\n")
                if let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return object }
            }
            throw SnapNoteError.protocolError
        }
        do { return try await invoke() }
        catch SnapNoteError.sessionExpired where readOnly {
            try await initializeIfNeeded()
            return try await invoke()
        }
    }

    private func request(method: String, params: [String: Any]?, isInitialization: Bool, notification: Bool) async throws -> [String: Any]? {
        try Task.checkCancellation()
        let requestID = notification ? nil : UUID().uuidString
        var request: [String: Any] = ["jsonrpc":"2.0", "method":method]
        if let params { request["params"] = params }
        if let requestID { request["id"] = requestID }
        let body = try JSONSerialization.data(withJSONObject: request)
        var headers = ["Authorization":"Bearer \(token)", "Content-Type":"application/json", "Accept":"application/json, text/event-stream"]
        let hadSession = !isInitialization && sessionID != nil
        if let sessionID, !isInitialization { headers["Mcp-Session-Id"] = sessionID }
        if !isInitialization { headers["MCP-Protocol-Version"] = protocolVersion }
        let response: SnapNoteHTTPResponse
        do { response = try await transport.post(body: body, headers: headers, timeout: timeout) }
        catch let error as SnapNoteError { throw error }
        catch is CancellationError { throw SnapNoteError.cancelled }
        catch { throw SnapNoteError.unavailable }
        if let newSession = response.header("Mcp-Session-Id"), !newSession.isEmpty { sessionID = newSession }
        if notification && (response.statusCode == 202 || response.statusCode == 204) { return nil }
        if response.statusCode == 401 || response.statusCode == 403 { throw SnapNoteError.unauthorized }
        if response.statusCode == 404 && hadSession {
            sessionID = nil; initialized = false; throw SnapNoteError.sessionExpired
        }
        guard (200..<300).contains(response.statusCode) else { throw SnapNoteError.unavailable }
        if notification && response.data.isEmpty { return nil }
        let message = try Self.parseRPC(response.data, contentType: response.header("Content-Type") ?? "application/json", expectedID: requestID)
        guard message["error"] == nil else { throw SnapNoteError.operationFailed }
        return message
    }

    static func parseRPC(_ data: Data, contentType: String, expectedID: String?) throws -> [String: Any] {
        guard data.count <= 5_000_000 else { throw SnapNoteError.protocolError }
        var payloads: [Data] = []
        if contentType.lowercased().contains("text/event-stream") {
            guard let string = String(data: data, encoding: .utf8) else { throw SnapNoteError.protocolError }
            var eventLines: [String] = []
            for raw in string.components(separatedBy: .newlines) {
                let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
                if line.hasPrefix("data:") { eventLines.append(String(line.dropFirst(5)).replacingOccurrences(of: "^ ", with: "", options: .regularExpression)) }
                else if line.isEmpty && !eventLines.isEmpty {
                    if let bytes = eventLines.joined(separator: "\n").data(using: .utf8) { payloads.append(bytes) }
                    eventLines = []
                }
            }
            if !eventLines.isEmpty, let bytes = eventLines.joined(separator: "\n").data(using: .utf8) { payloads.append(bytes) }
        } else { payloads = [data] }
        for payload in payloads {
            guard let value = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], value["jsonrpc"] as? String == "2.0" else { continue }
            if let expectedID, value["id"] as? String != expectedID { continue }
            return value
        }
        throw SnapNoteError.protocolError
    }

    static func parseRecent(_ payload: [String: Any]) throws -> [UUID: SnapNoteRecord] {
        guard let items = payload["items"] as? [[String: Any]], items.count <= 100 else { throw SnapNoteError.protocolError }
        var records: [UUID: SnapNoteRecord] = [:]
        for item in items {
            guard let rawID = item["uuid"] as? String, let id = UUID(uuidString: rawID), records[id] == nil,
                  let created = item["created_at_ms"] as? NSNumber,
                  CFGetTypeID(created) != CFBooleanGetTypeID(), created.doubleValue.isFinite,
                  created.doubleValue > 0, created.doubleValue < Double(Int64.max),
                  created.doubleValue.rounded() == created.doubleValue,
                  let body = item["body_preview_text"] as? String, let preview = item["preview_text"] as? String,
                  let facts = item["facts"] as? [String: Any], let chars = facts["plain_text_char_count"] as? NSNumber,
                  CFGetTypeID(chars) != CFBooleanGetTypeID(), chars.doubleValue.isFinite,
                  chars.doubleValue.rounded() == chars.doubleValue,
                  chars.doubleValue >= 0, chars.doubleValue < Double(Int.max) else { throw SnapNoteError.protocolError }
            var names = (item["tag_names"] as? [String]) ?? []
            // A root tag may be reported only in the detailed tag array.
            if let tags = item["tags"] as? [[String: Any]] {
                for tag in tags {
                    if let path = tag["path"] as? String { names.append(path) }
                    else if let name = tag["name"] as? String, tag["parent_uuid"] == nil || tag["parent_uuid"] is NSNull {
                        if tag["parent_name"] == nil || tag["parent_name"] is NSNull { names.append(name) }
                    }
                }
            }
            records[id] = SnapNoteRecord(id:id, createdAtMs:created.int64Value, title:item["title"] as? String ?? "",
                bodyPreview:body, preview:preview, plainTextCount:chars.intValue, tagNames:names,
                isArchived:item["is_archived"] as? Bool == true, isDeleted:item["is_deleted"] as? Bool == true)
        }
        return records
    }
}
