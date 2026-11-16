import XCTest
import VoiceSessions
@testable import KKvoice

final class KeyboardSettingsTests: XCTestCase {
    func testShortcutsPersistByIdentifierAndDisabledRemainsDisabled() throws {
        let suite = "local.kkvoice.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = KeyboardSettings(defaults: defaults)
        let choices = InputShortcut.choices
        XCTAssertEqual(first.wakeSelection(choices: choices), 1)
        XCTAssertEqual(first.inputSelection(choices: choices), 0)
        XCTAssertEqual(first.wakeDefinition()?.keyName, "Fn")
        XCTAssertEqual(first.inputDefinition().keyName, "Fn")
        first.saveWake(selection: 1, choices: choices)
        first.saveInput(selection: 2, choices: choices)
        let restored = KeyboardSettings(defaults: defaults)
        XCTAssertEqual(restored.wakeSelection(choices: choices), 1)
        XCTAssertEqual(restored.inputSelection(choices: choices), 2)
        let reordered = Array(choices.reversed())
        XCTAssertEqual(reordered[restored.wakeSelection(choices: reordered) - 1].helperKey, choices[0].helperKey)
        XCTAssertEqual(reordered[restored.inputSelection(choices: reordered)].helperKey, choices[2].helperKey)
        restored.saveWake(selection: 0, choices: choices)
        XCTAssertEqual(restored.wakeSelection(choices: choices), 0)
        XCTAssertNil(restored.wakeDefinition())
    }

    func testKeyboardStatusIsIndependentOfDeviceStatus() {
        var status = KeyboardListenerStatus()
        status.connecting(key: "LeftControl")
        XCTAssertEqual(status.state, .starting)
        status.receive(["type": "keyboard_trigger_ready", "key": "LeftControl", "captureCancelOnly": false])
        XCTAssertEqual(status.state, .ready("LeftControl"))
        status.receive(["type": "device_ready"])
        status.receive(["type": "audio_start"])
        XCTAssertEqual(status.state, .ready("LeftControl"))
        status.receive(["type": "permission_required", "permission": "accessibility", "source": "keyboard-trigger"])
        XCTAssertEqual(status.state, .permissionRequired)
        status.receive(["type": "device_ready"])
        XCTAssertEqual(status.state, .permissionRequired)
        status.receive(["type": "helper_process_exited"])
        XCTAssertEqual(status.state, .stopped)
        status.connecting(key: nil)
        XCTAssertEqual(status.state, .disabled)
    }
}

extension KeyboardSettingsTests {
    func testCustomChordPersistenceAndLegacyWakeValidation() throws {
        let suite = "local.kkvoice.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KeyboardSettings(defaults: defaults)
        let chord = try XCTUnwrap(ShortcutDefinition(keyName: "K", modifiers: ["command", "shift"]))
        settings.saveWakeDefinition(chord); settings.saveInputDefinition(chord)
        XCTAssertEqual(settings.wakeDefinition(), chord)
        XCTAssertEqual(settings.inputDefinition(), chord)
        XCTAssertEqual(settings.wakeSelection(choices: InputShortcut.choices), InputShortcut.choices.count + 1)
        XCTAssertEqual(settings.inputSelection(choices: InputShortcut.choices), InputShortcut.choices.count)
        let invalid = try XCTUnwrap(ShortcutDefinition(keyName: "K"))
        settings.saveWakeDefinition(invalid)
        XCTAssertEqual(settings.wakeDefinition(), chord)
        defaults.set("shortcut:none:K", forKey: "keyboardWakeKey")
        XCTAssertNil(settings.wakeDefinition())
        XCTAssertEqual(settings.wakeSelection(choices: InputShortcut.choices), 0)
    }
}
