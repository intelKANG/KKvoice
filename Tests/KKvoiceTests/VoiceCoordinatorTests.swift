import XCTest
import VoiceSessions
@testable import KKvoice

final class VoiceCoordinatorTests: XCTestCase {
    func testCancelDoesNotSubmitAndIdleCancelDoesNothing() {
        var events: [String] = []
        let coordinator = VoiceCoordinator(beginOutput: { _ in events.append("start") }, endOutput: { _ in events.append("stop"); return nil }, command: { events.append($0["type"] as? String ?? "?") }, shortcut: { events.append("shortcut") }, report: { _ in })
        coordinator.setReady(true)
        coordinator.cancelWithoutSubmitting()
        XCTAssertTrue(events.isEmpty)
        coordinator.press(.remote); coordinator.audioStarted(); coordinator.release(.remote)
        coordinator.cancelWithoutSubmitting()
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "start", "shortcut", "stop_capture", "set_escape_cancel", "stop"])
        coordinator.press(.remote)
        if case .starting = coordinator.phase {} else { XCTFail("cancellation must allow a new session") }
    }
    func testRemoteToggleStartsOnlyAfterAudioReadyAndStopsOnSecondRelease() {
        var events: [String] = []
        let coordinator = VoiceCoordinator(
            beginOutput: { _ in events.append("output-start") },
            endOutput: { _ in events.append("output-stop"); return nil },
            command: { events.append($0["type"] as? String ?? "?") },
            shortcut: { events.append("shortcut") }, report: { _ in })
        coordinator.setReady(true)
        coordinator.press(.remote)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "output-start"])
        coordinator.audioStarted()
        coordinator.release(.remote)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "output-start", "shortcut"])
        coordinator.press(.remote)
        XCTAssertEqual(events.count, 4)
        coordinator.release(.remote)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "output-start", "shortcut", "stop_capture", "set_escape_cancel", "output-stop", "shortcut"])
        XCTAssertEqual(coordinator.phase, .idle)
    }
    func testKeyboardDefersBothSyntheticTogglesUntilPhysicalRelease() {
        var events: [String] = []
        let coordinator = VoiceCoordinator(
            beginOutput: { _ in events.append("start") },
            endOutput: { _ in events.append("stop"); return nil },
            command: { events.append($0["type"] as? String ?? "?") },
            shortcut: { events.append("shortcut") }, report: { _ in })
        coordinator.setReady(true)
        coordinator.press(.keyboard)
        coordinator.audioStarted()
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "start"])
        coordinator.release(.keyboard)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "start", "shortcut"])
        coordinator.press(.keyboard)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "start", "shortcut", "stop_capture", "set_escape_cancel", "stop"])
        coordinator.release(.keyboard)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "start", "shortcut", "stop_capture", "set_escape_cancel", "stop", "shortcut"])
    }
    func testFailedOutputNeverSendsTriggerAndAttemptsCleanup() {
        var commands: [String] = []; var toggleCount = 0
        let coordinator = VoiceCoordinator(
            beginOutput: { _ in throw NSError(domain: "fake", code: 1) },
            endOutput: { _ in nil },
            command: { commands.append($0["type"] as? String ?? "?") },
            shortcut: { toggleCount += 1 }, report: { _ in })
        coordinator.setReady(true); coordinator.press(.remote); coordinator.audioStarted()
        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(commands, ["ensure_capture", "set_escape_cancel", "stop_capture", "set_escape_cancel"])
        XCTAssertEqual(coordinator.phase, .idle)
    }
}

extension VoiceCoordinatorTests {
    func testPhysicalPassthroughNeverInjectsOnTwoShortToggles() {
        var events: [String] = []
        let c = VoiceCoordinator(beginOutput: { _ in events.append("start") }, endOutput: { _ in events.append("stop"); return nil }, command: { events.append($0["type"] as? String ?? "?") }, shortcut: { events.append("shortcut") }, report: { _ in })
        XCTAssertTrue(c.setKeyboardPassThrough(true)); c.setReady(true)
        c.press(.keyboard); c.press(.keyboard); c.audioStarted(); c.release(.keyboard)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "start"])
        XCTAssertEqual(c.phase, .recording({ if case .recording(let id) = c.phase { return id }; return UUID() }()))
        c.press(.keyboard); c.release(.keyboard)
        XCTAssertEqual(events, ["ensure_capture", "set_escape_cancel", "start", "stop_capture", "set_escape_cancel", "stop"])
        XCTAssertEqual(c.phase, .idle)
    }
    func testPassthroughCrossSourceAndCancel() {
        var events: [String] = []
        let c = VoiceCoordinator(beginOutput: { _ in events.append("start") }, endOutput: { _ in events.append("stop"); return nil }, command: { events.append($0["type"] as? String ?? "?") }, shortcut: { events.append("shortcut") }, report: { _ in })
        XCTAssertTrue(c.setKeyboardPassThrough(true)); c.setReady(true)
        // Physical starts; remote stops and must send exactly one target toggle.
        c.press(.keyboard); c.audioStarted(); c.release(.keyboard)
        c.press(.remote); c.release(.remote)
        XCTAssertEqual(events.filter { $0 == "shortcut" }.count, 1)
        // Remote starts and sends target toggle after capture ready; physical stops without another.
        c.press(.remote); c.audioStarted(); c.release(.remote)
        c.press(.keyboard); c.release(.keyboard)
        XCTAssertEqual(events.filter { $0 == "shortcut" }.count, 2)
        // Physical start, then explicit cancel: exactly one closing toggle.
        c.press(.keyboard); c.audioStarted(); c.release(.keyboard); c.cancel()
        XCTAssertEqual(events.filter { $0 == "shortcut" }.count, 3)
    }
    func testPassthroughStartFailureAndUnavailableNeverSynthesizesToggle() {
        var events: [String] = []; var reports: [String] = []
        let c = VoiceCoordinator(beginOutput: { _ in throw NSError(domain: "fake", code: 1) }, endOutput: { _ in nil }, command: { events.append($0["type"] as? String ?? "?") }, shortcut: { events.append("shortcut") }, report: { reports.append($0) })
        XCTAssertTrue(c.setKeyboardPassThrough(true)); c.setReady(true)
        c.press(.keyboard); c.release(.keyboard); c.audioStarted()
        XCTAssertFalse(events.contains("shortcut")); XCTAssertEqual(c.phase, .idle)
        XCTAssertTrue(reports.contains { $0.contains("输入软件状态") })
        c.setReady(false)
        c.press(.keyboard); c.release(.keyboard)
        c.setReady(true); c.press(.remote)
        XCTAssertEqual(c.phase, .idle, "a passed-through event while unavailable requires acknowledgement")
        XCTAssertTrue(c.acknowledgeInputSoftwareStopped())
    }
    func testInterruptedPhysicalReleaseDoesNotFlushPendingToggle() {
        var events: [String] = []
        let c = VoiceCoordinator(beginOutput: { _ in events.append("start") }, endOutput: { _ in events.append("stop"); return nil }, command: { events.append($0["type"] as? String ?? "?") }, shortcut: { events.append("shortcut") }, report: { _ in })
        c.setReady(true); c.press(.keyboard); c.audioStarted()
        c.keyboardInterrupted()
        XCTAssertFalse(events.contains("shortcut"), "interrupted is not a real release")
        XCTAssertEqual(c.phase, .idle)
        XCTAssertTrue(c.acknowledgeInputSoftwareStopped())
    }
    func testKeyboardModeCannotChangeWhilePressedOrRecording() {
        let c = VoiceCoordinator(beginOutput: { _ in }, endOutput: { _ in nil }, command: { _ in }, shortcut: {}, report: { _ in })
        c.setReady(true); c.press(.keyboard)
        XCTAssertFalse(c.setKeyboardPassThrough(true))
        c.audioStarted(); c.release(.keyboard)
        XCTAssertFalse(c.setKeyboardPassThrough(true))
        c.press(.keyboard); c.release(.keyboard)
        XCTAssertTrue(c.setKeyboardPassThrough(true))
    }
}
