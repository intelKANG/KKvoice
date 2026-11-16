import XCTest
@testable import KKvoice

final class RemoteBridgeTests: XCTestCase {
    func testDecoderHandlesPartialMultipleAndMalformedLines() {
        var decoder = JSONLineDecoder()
        XCTAssertTrue(decoder.append(Data("{\"type\":\"rea".utf8)).isEmpty)
        let result = decoder.append(Data("dy\"}\nnot-json\n{\"type\":\"next\"}\n".utf8))
        XCTAssertEqual(result.compactMap { $0["type"] as? String }, ["ready", "next"])
    }

    func testHelperLifecycleWithFakeProcess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-helper")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *configure*) printf '{"type":"configured"}\\n' ;;
            *shutdown*) printf '{"type":"helper_stopped"}\\n'; exit 0 ;;
          esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configured = expectation(description: "helper configured")
        let exited = expectation(description: "helper stopped")
        let bridge = RemoteBridge()
        bridge.onMessage = { message in
            switch message["type"] as? String {
            case "configured": configured.fulfill(); bridge.stop()
            case "helper_process_exited": exited.fulfill()
            default: break
            }
        }
        try bridge.start(helperURL: executable)
        wait(for: [configured, exited], timeout: 4)
    }
    func testConfiguredKeyboardChordIsDeliveredToHelper() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-helper")
        let capture = directory.appendingPathComponent("config.json")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *configure*) printf '%s' "$line" > '\(capture.path)'; printf '{"type":"configured"}\\n' ;;
            *shutdown*) exit 0 ;;
          esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configured = expectation(description: "configured")
        let exited = expectation(description: "exited")
        let bridge = RemoteBridge()
        bridge.onMessage = { message in
            switch message["type"] as? String {
            case "configured": configured.fulfill(); bridge.stop()
            case "helper_process_exited": exited.fulfill()
            default: break
            }
        }
        try bridge.start(helperURL: executable, keyboardKey: "K", keyboardModifiers: ["command", "shift"])
        wait(for: [configured, exited], timeout: 4)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: capture)) as? [String: Any])
        let config = try XCTUnwrap(object["config"] as? [String: Any])
        let trigger = try XCTUnwrap(config["keyboardTrigger"] as? [String: Any])
        XCTAssertEqual(trigger["enabled"] as? Bool, true)
        XCTAssertEqual(trigger["key"] as? String, "K")
        XCTAssertEqual(trigger["modifiers"] as? [String], ["command", "shift"])
    }

}
