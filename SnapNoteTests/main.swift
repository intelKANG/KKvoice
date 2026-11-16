import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let noteID = UUID(uuidString: "FCAE13AD-EA86-4C32-8CEF-0C8747A6FD48")!
let otherID = UUID(uuidString: "451128C2-18CF-472A-8D97-B005BE9C4BC1")!
let marker = SnapNoteRecord(id:noteID, createdAtMs:1000, title:".", bodyPreview:".", preview:".", plainTextCount:1, tagNames:[])
let tagged = SnapNoteRecord(id:noteID, createdAtMs:1000, title:".", bodyPreview:".", preview:".", plainTextCount:1, tagNames:["闪念"])

actor MockService: SnapNoteService {
    var snapshots: [[UUID: SnapNoteRecord]]
    var taggedIDs: [UUID] = []
    var taggedNames: [String] = []
    var failWrite = false
    var verificationFails = false
    init(_ snapshots: [[UUID: SnapNoteRecord]]) { self.snapshots = snapshots }
    func verifyService() async throws { if verificationFails { throw SnapNoteError.unauthorized } }
    func recent() async throws -> [UUID: SnapNoteRecord] {
        if snapshots.count > 1 { return snapshots.removeFirst() }
        guard let result = snapshots.first else { throw SnapNoteError.protocolError }
        return result
    }
    func addFlashTag(noteID: UUID, tagName: String) async throws {
        taggedIDs.append(noteID)
        taggedNames.append(tagName)
        if failWrite { throw SnapNoteError.timeout }
    }
    func writes() -> [UUID] { taggedIDs }
    func writeTagNames() -> [String] { taggedNames }
    func setFailWrite() { failWrite = true }
}

actor MockNative: SnapNoteNativeAction {
    var calls = 0
    func performNewNote(shortcut: String, actionID: UUID) async throws { calls += 1 }
    func count() -> Int { calls }
}

actor MockHTTP: SnapNoteHTTPTransport {
    var methods: [String] = []
    var writes = 0
    var forceWrite404 = false
    var sawCredential = false
    func post(body: Data, headers: [String: String], timeout: TimeInterval) async throws -> SnapNoteHTTPResponse {
        guard let request = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = request["method"] as? String else { throw SnapNoteError.protocolError }
        methods.append(method)
        sawCredential = headers["Authorization"] == "Bearer mock-secret"
        if method == "notifications/initialized" { return SnapNoteHTTPResponse(statusCode: 202) }
        let id = request["id"] as? String ?? ""
        var result: [String: Any]
        if method == "initialize" { result = ["protocolVersion":"2025-06-18"] }
        else {
            let p = request["params"] as? [String: Any] ?? [:]
            let name = p["name"] as? String ?? ""
            if name == "snapnote.memo_add_tags" {
                writes += 1
                if forceWrite404 { return SnapNoteHTTPResponse(statusCode:404) }
            }
            if name == "snapnote.memo_recent" {
                result = ["structuredContent":["items":[["uuid":noteID.uuidString,"created_at_ms":1000,"title":".","preview_text":".","body_preview_text":".","facts":["plain_text_char_count":1],"tag_names":["闪念"]]]]]
            } else { result = ["structuredContent":["service_key":"snapnote.data_source"]] }
        }
        let data = try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":id,"result":result])
        return SnapNoteHTTPResponse(statusCode:200, headers:["Content-Type":"application/json", "Mcp-Session-Id":"mock-session"], data:data)
    }
    func setWrite404() { forceWrite404 = true }
    func counts() -> (Int, Bool) { (writes, sawCredential) }
}

final class MockKeychain: SnapNoteKeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?
    func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; return value
    }
    func write(service: String, account: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }; self.value = value
    }
    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; value = nil
    }
}

final class MockWire: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [SnapNoteHelperMessage] = []
    func send(_ message: SnapNoteHelperMessage) throws {
        lock.lock(); defer { lock.unlock() }; sent.append(message)
    }
    func messages() -> [SnapNoteHelperMessage] {
        lock.lock(); defer { lock.unlock() }; return sent
    }
}

actor SlowService: SnapNoteService {
    func verifyService() async throws { try await Task.sleep(nanoseconds: 1_000_000_000) }
    func recent() async throws -> [UUID: SnapNoteRecord] { [:] }
    func addFlashTag(noteID: UUID, tagName: String) async throws {}
}

func waitFor(_ test: @Sendable () -> Bool) async throws {
    for _ in 0..<500 {
        if test() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    fatalError("timed out waiting for mock event")
}

@main struct SnapNoteTests {
    static func main() async throws {
        expect(SnapNoteCoordinator.validShortcut("shortcut:command+shift:Y"), "valid shortcut")
        expect(!SnapNoteCoordinator.validShortcut("shortcut:none:Y"), "no-modifier shortcut rejected")
        expect(!SnapNoteCoordinator.validShortcut("shortcut:command+command:Y"), "duplicate modifier rejected")
        expect(!SnapNoteCoordinator.validShortcut("shortcut:command:LeftShift"), "modifier as main key rejected")
        expect(SnapNoteCoordinator.validTagName("闪念"), "default tag valid")
        expect(SnapNoteCoordinator.validTagName("语音笔记"), "custom tag valid")
        expect(!SnapNoteCoordinator.validTagName(""), "empty tag rejected")
        expect(!SnapNoteCoordinator.validTagName("   "), "whitespace tag rejected")
        expect(!SnapNoteCoordinator.validTagName("换行\n标签"), "multiline tag rejected")
        expect(!SnapNoteCoordinator.validTagName(String(repeating: "字", count: 21)), "overlong tag rejected")

        // Custom MCP endpoint & port normalization tests
        let defaultEndpoint = try SnapNoteLocalTransport.normalizeEndpoint(SnapNoteLocalTransport.defaultEndpointString)
        expect(defaultEndpoint.absoluteString == "http://127.0.0.1:31090/snapnote/data-source/mcp", "default MCP endpoint preserved")
        let hostPortOnly = try SnapNoteLocalTransport.normalizeEndpoint("http://10.10.10.22:31090")
        expect(hostPortOnly.absoluteString == "http://10.10.10.22:31090/snapnote/data-source/mcp", "host:port auto-completes MCP path")
        let trailingSlash = try SnapNoteLocalTransport.normalizeEndpoint("https://10.10.10.22:32000/snapnote/data-source/mcp/")
        expect(trailingSlash.absoluteString == "https://10.10.10.22:32000/snapnote/data-source/mcp", "trailing slash trimmed")
        expect(SnapNoteLocalTransport.extractPort(from: "http://10.10.10.22:31090/snapnote/data-source/mcp") == 31090, "extract port from endpoint")
        expect(SnapNoteLocalTransport.replacingPort(in: "http://10.10.10.22:31090/snapnote/data-source/mcp", with: 32100) == "http://10.10.10.22:32100/snapnote/data-source/mcp", "replace port in endpoint")
        expect(SnapNoteLocalTransport.replacingPort(in: "http://127.0.0.1:31090/snapnote/data-source/mcp", with: 0) == nil, "port 0 rejected")
        expect(SnapNoteLocalTransport.replacingPort(in: "http://127.0.0.1:31090/snapnote/data-source/mcp", with: 70000) == nil, "port >65535 rejected")
        expect(!SnapNoteLocalTransport.validEndpoint("ftp://127.0.0.1:31090/snapnote/data-source/mcp"), "non-http scheme rejected")
        expect(!SnapNoteLocalTransport.validEndpoint("http://127.0.0.1:99999/snapnote/data-source/mcp"), "out-of-range port rejected")
        expect(!SnapNoteLocalTransport.validEndpoint(""), "empty endpoint rejected")

        do { _ = try SnapNoteMCPClient(token:"bad\nsecret", transport:MockHTTP()); fatalError("invalid token accepted") }
        catch SnapNoteError.invalidToken {}

        let http = MockHTTP()
        let client = try SnapNoteMCPClient(token:"Bearer mock-secret", transport:http)
        try await client.verifyService()
        let records = try await client.recent()
        expect(records[noteID]?.tagNames == ["闪念"], "structured recent response parsed")
        await http.setWrite404()
        do { try await client.addFlashTag(noteID:noteID); fatalError("write error accepted") }
        catch SnapNoteError.sessionExpired {}
        let counts = await http.counts()
        expect(counts.0 == 1, "failed write must not be retried")
        expect(counts.1, "authorized request sent")
        let sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":\"123\",\"result\":{}}\n\n".data(using:.utf8)!
        let parsed = try SnapNoteMCPClient.parseRPC(sse, contentType:"text/event-stream", expectedID:"123")
        expect(parsed["id"] as? String == "123", "SSE response")
        do { _ = try SnapNoteMCPClient.parseRPC(sse, contentType:"text/event-stream", expectedID:"wrong"); fatalError("wrong id accepted") }
        catch SnapNoteError.protocolError {}
        do { _ = try SnapNoteMCPClient.parseRecent(["items":[["uuid":noteID.uuidString]]]); fatalError("incomplete record accepted") }
        catch SnapNoteError.protocolError {}
        do {
            _ = try SnapNoteMCPClient.parseRecent(["items":[["uuid":noteID.uuidString, "created_at_ms":1000, "body_preview_text":".", "preview_text":".", "facts":["plain_text_char_count":true]]]])
            fatalError("boolean count accepted")
        } catch SnapNoteError.protocolError {}

        let successService = MockService([[:], [:], [noteID:marker], [noteID:marker], [noteID:tagged]])
        let native = MockNative()
        let coordinator = SnapNoteCoordinator(client:successService, native:native, isRecording:{false}, nowMs:{1000}, delay:{_ in})
        let success = await coordinator.createAndTag(shortcut:"shortcut:command+option:N")
        expect(success.succeeded && success.noteID == noteID && success.tagMayHaveBeenWritten, "full create and tag")
        let writes = await successService.writes()
        expect(writes == [noteID], "only confirmed UUID tagged")
        let cooldown = await coordinator.createAndTag(shortcut:"shortcut:command+option:N")
        expect(cooldown.error == .busy, "cooldown prevents repeat")
        let callCount = await native.count()
        expect(callCount == 1, "only one native creation")

        let customTagged = SnapNoteRecord(id:noteID, createdAtMs:1000, title:".", bodyPreview:".", preview:".", plainTextCount:1, tagNames:["灵感笔记"])
        let customTagService = MockService([[:], [:], [noteID:marker], [noteID:marker], [noteID:customTagged]])
        let customCoordinator = SnapNoteCoordinator(client:customTagService, native:MockNative(), isRecording:{false}, nowMs:{1000}, delay:{_ in})
        let customOutcome = await customCoordinator.createAndTag(shortcut:"shortcut:command+option:N", tagName:"灵感笔记")
        expect(customOutcome.succeeded && customOutcome.noteID == noteID, "custom tag create and verify")
        let writtenTags = await customTagService.writeTagNames()
        expect(writtenTags == ["灵感笔记"], "custom tag name forwarded to service")

        let concurrent = SnapNoteRecord(id:otherID, createdAtMs:1000, title:".", bodyPreview:".", preview:".", plainTextCount:1, tagNames:[])
        let ambiguousService = MockService([[:], [:], [noteID:marker, otherID:concurrent]])
        let ambiguous = await SnapNoteCoordinator(client:ambiguousService, native:MockNative(), isRecording:{false}, nowMs:{1000}, delay:{_ in}).createAndTag(shortcut:"shortcut:command:N")
        expect(ambiguous.error == .multipleCandidates && ambiguous.noteMayExist && !ambiguous.tagMayHaveBeenWritten, "multiple candidates fail closed")
        let ambiguousWrites = await ambiguousService.writes()
        expect(ambiguousWrites.isEmpty, "multiple candidates not tagged")

        let modified = SnapNoteRecord(id:noteID, createdAtMs:1000, title:"已有内容", bodyPreview:"已有内容", preview:"已有内容", plainTextCount:4, tagNames:[])
        let rejectedService = MockService([[:], [:], [noteID:modified]])
        let rejected = await SnapNoteCoordinator(client:rejectedService, native:MockNative(), isRecording:{false}, nowMs:{1000}, delay:{_ in}).createAndTag(shortcut:"shortcut:command:N")
        expect(rejected.error == .candidateRejected, "non-marker note not tagged")

        let timeoutService = MockService([[:], [:], [noteID:marker], [noteID:marker]])
        await timeoutService.setFailWrite()
        let timeout = await SnapNoteCoordinator(client:timeoutService, native:MockNative(), isRecording:{false}, nowMs:{1000}, delay:{_ in}).createAndTag(shortcut:"shortcut:command:N")
        expect(timeout.error == .timeout && timeout.noteMayExist && timeout.tagMayHaveBeenWritten, "unknown write outcome reported")
        let timeoutWrites = await timeoutService.writes()
        expect(timeoutWrites.count == 1, "no write retry after timeout")

        let recordService = MockService([])
        let recordingNative = MockNative()
        let recording = await SnapNoteCoordinator(client:recordService, native:recordingNative, isRecording:{true}).createAndTag(shortcut:"shortcut:command:N")
        expect(recording.error == .recording && !recording.noteMayExist, "recording blocks creation")
        let recordingCalls = await recordingNative.count()
        expect(recordingCalls == 0, "recording blocks native action")
        let keychain = MockKeychain()
        let store = SnapNoteTokenStore(backend:keychain)
        let initialToken = try store.load()
        expect(initialToken == nil && !store.exists(), "empty keychain")
        try store.save("Bearer mock-secret")
        let savedToken = try store.load()
        expect(savedToken == "mock-secret" && store.exists(), "normalized keychain round trip")
        try store.delete()
        let deletedToken = try store.load()
        expect(deletedToken == nil && !store.exists(), "keychain deletion")
        do { try store.save("bad\nsecret"); fatalError("invalid keychain token accepted") }
        catch SnapNoteError.invalidToken {}

        let unsupportedWire = MockWire()
        let unsupported = SnapNoteHelperActionAdapter(send:{ try unsupportedWire.send($0) })
        do { try await unsupported.performNewNote(shortcut:"shortcut:command:N", actionID:UUID()); fatalError("unsupported helper accepted") }
        catch SnapNoteError.nativeCancellationUnsupported {}
        expect(unsupportedWire.messages().isEmpty, "unsupported helper is never sent an action")

        let wire = MockWire()
        let adapter = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported:true,
            timeoutNanoseconds:1_000_000_000, cancellationGraceNanoseconds:200_000_000, send:{ try wire.send($0) })
        let id = UUID()
        let action = Task { try await adapter.performNewNote(shortcut:"shortcut:command:N", actionID:id) }
        try await waitFor { wire.messages().count == 1 }
        await adapter.handleHelperEvent(type:"action_done", actionID:UUID())
        expect(wire.messages()[0].wireFields["actionId"] == id.uuidString.lowercased(), "action id in helper wire message")
        await adapter.handleHelperEvent(type:"action_done", actionID:id)
        try await action.value

        let cancelID = UUID()
        let cancelTask = Task { try await adapter.performNewNote(shortcut:"shortcut:command:N", actionID:cancelID) }
        try await waitFor { wire.messages().count == 2 }
        cancelTask.cancel()
        try await waitFor { wire.messages().count == 3 }
        expect(wire.messages()[2].type == "cancel_snapnote_action" && wire.messages()[2].actionID == cancelID, "cancel message matches action")
        await adapter.handleHelperEvent(type:"snapnote_action_cancelled", actionID:UUID(), prevented:true)
        await adapter.handleHelperEvent(type:"snapnote_action_cancelled", actionID:cancelID, prevented:true)
        do { try await cancelTask.value; fatalError("cancel returned success") }
        catch SnapNoteError.cancelled {}
        let stillOK = await adapter.isQuarantined
        expect(!stillOK, "confirmed cancellation does not quarantine")

        let timeoutWire = MockWire()
        let timeoutAdapter = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported:true,
            timeoutNanoseconds:5_000_000, cancellationGraceNanoseconds:10_000_000, send:{ try timeoutWire.send($0) })
        do { try await timeoutAdapter.performNewNote(shortcut:"shortcut:command:N", actionID:UUID()); fatalError("unconfirmed cancellation accepted") }
        catch SnapNoteError.nativeCancellationUnconfirmed {}
        let blocked = await timeoutAdapter.isQuarantined
        expect(blocked && timeoutWire.messages().count == 2 && timeoutWire.messages()[1].type == "cancel_snapnote_action", "unconfirmed cancellation quarantines")
        do { try await timeoutAdapter.performNewNote(shortcut:"shortcut:command:N", actionID:UUID()); fatalError("quarantined adapter accepted action") }
        catch SnapNoteError.nativeCancellationUnconfirmed {}

        let disconnectWire = MockWire()
        let disconnected = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported:true, send:{ try disconnectWire.send($0) })
        let disTask = Task { try await disconnected.performNewNote(shortcut:"shortcut:command:N", actionID:UUID()) }
        try await waitFor { disconnectWire.messages().count == 1 }
        await disconnected.helperDisconnected()
        do { try await disTask.value; fatalError("disconnect accepted") }
        catch SnapNoteError.nativeCancellationUnconfirmed {}
        let disconnectedBlocked = await disconnected.isQuarantined
        expect(disconnectedBlocked, "disconnect quarantines")

        let idleWire = MockWire()
        let stoppedAdapter = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported:true, send:{ try idleWire.send($0) })
        await stoppedAdapter.helperDisconnected()
        do { try await stoppedAdapter.performNewNote(shortcut:"shortcut:command:N", actionID:UUID()); fatalError("stopped helper accepted action") }
        catch SnapNoteError.nativeCancellationUnconfirmed {}
        expect(idleWire.messages().isEmpty, "no commands after idle helper shutdown")

        let deadlineWire = MockWire()
        let deadlineAdapter = SnapNoteHelperActionAdapter(cancellationAcknowledgementSupported:true,
            timeoutNanoseconds:1_000_000_000, cancellationGraceNanoseconds:200_000_000, send:{ try deadlineWire.send($0) })
        let deadlineService = MockService([[:], [:]])
        let deadlineCoordinator = SnapNoteCoordinator(client:deadlineService, native:deadlineAdapter,
            isRecording:{false}, nowMs:{1000}, delay:{_ in}, overallTimeoutNanoseconds:30_000_000)
        let deadlineTask = Task { await deadlineCoordinator.createAndTag(shortcut:"shortcut:command:N") }
        try await waitFor { deadlineWire.messages().count >= 2 }
        let deadlineMessages = deadlineWire.messages()
        expect(deadlineMessages[0].type == "post_key" && deadlineMessages[1].type == "cancel_snapnote_action", "overall deadline cancels pending helper action")
        expect(deadlineMessages[0].actionID == deadlineMessages[1].actionID, "overall deadline cancels matching helper action")
        await deadlineAdapter.handleHelperEvent(type:"snapnote_action_cancelled", actionID:deadlineMessages[0].actionID, prevented:true)
        let nativeDeadlineResult = await deadlineTask.value
        expect(nativeDeadlineResult.error == .timeout && nativeDeadlineResult.noteMayExist && !nativeDeadlineResult.tagMayHaveBeenWritten,
               "overall deadline reports possible creation and avoids tag write")
        let deadlineWrites = await deadlineService.writes()
        expect(deadlineWrites.isEmpty, "no tag write after native deadline")

        let overall = SnapNoteCoordinator(client:SlowService(), native:MockNative(), isRecording:{false}, overallTimeoutNanoseconds:10_000_000)
        let deadlineResult = await overall.createAndTag(shortcut:"shortcut:command:N")
        expect(deadlineResult.error == .timeout && !deadlineResult.noteMayExist, "overall preflight deadline")
        print("PASS: keychain mock, helper correlation, cancellation, disconnect and overall deadline")
        print("PASS: MCP authentication, parsing, correlation, tagging and fail-closed cases")
    }
}
