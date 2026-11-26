import XCTest
@testable import KKvoice

final class ButtonMappingsTests: XCTestCase {
    func testDefaultsCoverAllButtonsAndSwitcherOverride() {
        XCTAssertEqual(Set(ButtonMappings.defaults.buttons.keys), Set(RemoteButton.all.map(\.id)))
        var sent: [[String: Any]] = []
        let dispatcher = ButtonActionDispatcher(mappings: .defaults, send: { sent.append($0) }, cancelVoice: {}, status: { _ in })
        dispatcher.down("05"); dispatcher.down("05")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["target"] as? String, "appSwitcherLeft")
        dispatcher.up("05"); dispatcher.down("07")
        XCTAssertEqual(sent.last?["type"] as? String, "app_switcher_commit")
        dispatcher.up("07")
        dispatcher.mappings.appSwitcherNavigation = false
        dispatcher.down("05")
        XCTAssertEqual(sent.last?["target"] as? String, "arrowLeft")
    }

    func testBuiltInAndCustomRoutingAndHoldDebounce() {
        var sent: [[String: Any]] = []; var shortcuts: [String] = []; var cancels = 0; var messages: [String] = []
        var mappings = ButtonMappings.defaults
        mappings.appSwitcherNavigation = false
        mappings.buttons["0E"] = .init(target: "typeText", text: "测试文字")
        mappings.buttons["0F"] = .init(target: "shortcut:command+shift:K")
        mappings.buttons["11"] = .init(target: "openApp:com.example.app")
        mappings.buttons["01"] = .init(target: "openFile:/tmp/test file")
        let dispatcher = ButtonActionDispatcher(mappings: mappings, send: { sent.append($0) }, sendShortcut: { shortcuts.append($0.encoded) }, cancelVoice: { cancels += 1 }, status: { messages.append($0) })
        dispatcher.down("0E"); dispatcher.down("0E")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["target"] as? String, "typeTextAndEnter")
        XCTAssertEqual(sent[0]["text"] as? String, "测试文字")
        dispatcher.up("0E"); dispatcher.down("0E")
        dispatcher.down("0F"); dispatcher.down("11"); dispatcher.down("01")
        XCTAssertEqual(shortcuts, ["shortcut:command+shift:K"])
        XCTAssertEqual(sent.suffix(2).compactMap { $0["target"] as? String }, ["openApp:com.example.app", "openFile:/tmp/test file"])
        dispatcher.down("0B"); XCTAssertEqual(cancels, 1)
        dispatcher.down("FF"); XCTAssertTrue(messages.isEmpty)
    }

    func testInvalidTargetsAndSnapshotsCannotExecute() {
        XCTAssertFalse(ActionCatalog.isValid(.init(target: "openApp:bad;command")))
        XCTAssertFalse(ActionCatalog.isValid(.init(target: "shortcut:control:LeftControl")))
        XCTAssertFalse(ActionCatalog.isValid(.init(target: "typeText", text: "one\ntwo")))
        XCTAssertFalse(ActionCatalog.isValid(.init(target: "openFile:relative")))
        XCTAssertEqual(ActionCatalog.shortcut(key: "K", modifiers: ["shift", "command"]), "shortcut:command+shift:K")
        var mappings = ButtonMappings.defaults; mappings.buttons["0E"] = .init(target: "snapnoteNewNote")
        var calls = 0; var messages: [String] = []
        let dispatcher = ButtonActionDispatcher(mappings: mappings, send: { _ in calls += 1 }, cancelVoice: {}, status: { messages.append($0) })
        dispatcher.down("0E"); XCTAssertEqual(calls, 0); XCTAssertFalse(messages.isEmpty)
    }

    func testPersistenceAndCorruptionFallback() throws {
        let suite = "local.kkvoice.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ButtonMappingStore(defaults: defaults)
        XCTAssertEqual(store.load(), .defaults)
        var mappings = ButtonMappings.defaults
        mappings.appSwitcherNavigation = false
        mappings.buttons["0E"] = .init(target: "shortcut:none:LeftControl")
        try store.save(mappings)
        XCTAssertEqual(store.load(), mappings)
        mappings.buttons["0E"] = .init(target: "openFile:relative")
        XCTAssertThrowsError(try store.save(mappings))
        defaults.set(Data("{not-json".utf8), forKey: "remoteButtonMappings.v1")
        XCTAssertEqual(store.load(), .defaults)
    }
    func testHIDDisconnectCancelsSwitcherBeforeClearingState() {
        var sent: [String] = []
        let dispatcher = ButtonActionDispatcher(mappings: .defaults,
            send: { sent.append($0["type"] as? String ?? "") }, cancelVoice: {}, status: { _ in })
        dispatcher.down("05")
        XCTAssertTrue(dispatcher.switcherActive)
        dispatcher.deviceDisconnected()
        XCTAssertEqual(sent, ["post_key", "app_switcher_cancel"])
        XCTAssertFalse(dispatcher.switcherActive)
    }

    func testLongPressAndShortPressRoutingAndPersistence() throws {
        let suite = "local.kkvoice.longpress.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ButtonMappingStore(defaults: defaults)

        var mappings = ButtonMappings.defaults
        mappings.buttons["08"] = .init(target: "mute")
        mappings.doubleTapButtons["08"] = .init(target: "showDesktop")
        mappings.longPressButtons["08"] = .init(target: "lockScreen")
        try store.save(mappings)
        let loaded = store.load()
        XCTAssertEqual(loaded.doubleTapButtons["08"], .init(target: "showDesktop"))
        XCTAssertEqual(loaded.longPressButtons["08"], .init(target: "lockScreen"))

        var sentTargets: [String] = []
        let dispatcher = ButtonActionDispatcher(
            mappings: loaded,
            send: { sentTargets.append($0["target"] as? String ?? "") },
            cancelVoice: {},
            status: { _ in },
            longPressThreshold: 0.08,
            doubleTapWindow: 0.06
        )

        // 1) Single tap (release quickly and wait past doubleTapWindow) -> fires "mute".
        let singleExp = expectation(description: "single tap fired")
        dispatcher.down("08")
        dispatcher.up("08")
        XCTAssertTrue(sentTargets.isEmpty)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            singleExp.fulfill()
        }
        wait(for: [singleExp], timeout: 1.0)
        XCTAssertEqual(sentTargets, ["mute"])

        // 2) Double tap (two quick presses within doubleTapWindow) -> fires "showDesktop" immediately on 2nd down.
        dispatcher.down("08")
        dispatcher.up("08")
        dispatcher.down("08")
        dispatcher.up("08")
        XCTAssertEqual(sentTargets, ["mute", "showDesktop"])

        // 3) Long press (hold past longPressThreshold) -> fires "lockScreen", release does not double-fire.
        let longExp = expectation(description: "long press fired")
        dispatcher.down("08")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            dispatcher.up("08")
            longExp.fulfill()
        }
        wait(for: [longExp], timeout: 1.0)
        XCTAssertEqual(sentTargets, ["mute", "showDesktop", "lockScreen"])
    }

}
