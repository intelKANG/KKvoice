import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func beginID(_ effects: [VoiceSession.Effect]) -> UUID {
    guard effects.count == 1, case .begin(let id) = effects[0] else { fatalError("expected begin") }
    return id
}
func endMatches(_ effects: [VoiceSession.Effect], _ id: UUID) -> Bool { effects == [.end(id)] }

// Remote short press toggles on; one long release stays active, second press-release ends.
do {
    var s = VoiceSession(); let id = beginID(s.press(.remote, at: 0))
    expect(s.press(.remote, at: 0.01).isEmpty, "duplicate press")
    expect(s.didStart(id).isEmpty, "start")
    expect(s.release(.remote, at: 0.2).isEmpty, "short release keeps running")
    expect(s.phase == .recording(id), "short press must remain recording")
    expect(s.press(.remote, at: 0.3).isEmpty, "second remote down is pending stop")
    expect(endMatches(s.release(.remote, at: 0.4), id), "second release stops")
    expect(s.phase == .stopping(id), "stopping pending cleanup")
    s.didStop(id); expect(s.phase == .idle, "completed cleanup")
}
do {
    var s = VoiceSession(); let id = beginID(s.press(.remote, at: 0))
    _ = s.didStart(id)
    _ = s.release(.remote, at: 0.1)
    expect(s.press(.remote, at: 1).isEmpty, "second remote down does not stop before up")
    expect(s.phase == .recording(id), "second gesture remains recording while held")
    expect(endMatches(s.release(.remote, at: 2), id), "second remote up ends toggle session")
}
// In default toggle mode, a delayed release must not end the session.
do {
    var s = VoiceSession(); let id = beginID(s.press(.remote, at: 1))
    expect(s.release(.remote, at: 3).isEmpty, "delayed release preserves toggle session")
    _ = s.didStart(id)
    expect(s.phase == .recording(id), "delayed device stop does not end recording")
    expect(s.press(.remote, at: 4).isEmpty, "second press waits for release")
    expect(endMatches(s.release(.remote, at: 4.1), id), "second press stops")
    s.didStop(id)
}
// Explicit hybrid mode preserves the legacy hold-to-talk gesture.
do {
    var s = VoiceSession(remoteGesture: .hybrid); let id = beginID(s.press(.remote, at: 1))
    expect(endMatches(s.release(.remote, at: 1.5), id), "hybrid long press stops pending start")
    expect(endMatches(s.didStart(id), id), "late start must be stopped")
    s.didStop(id); expect(s.phase == .idle, "pending start cleanup")
}
// Keyboard toggles on press regardless of duration; autorepeat is suppressed.
do {
    var s = VoiceSession(); let id = beginID(s.press(.keyboard, at: 0))
    expect(s.press(.keyboard, at: 5).isEmpty, "autorepeat")
    _ = s.didStart(id); expect(s.release(.keyboard, at: 6).isEmpty, "keyboard release")
    expect(endMatches(s.press(.keyboard, at: 7), id), "keyboard second press")
    expect(s.release(.keyboard, at: 7.1).isEmpty, "keyboard release cleanup")
    s.didStop(id)
}
// Cross-source start/stop and stale release cannot stop newer session.
do {
    var s = VoiceSession(); let a = beginID(s.press(.remote, at: 0))
    _ = s.didStart(a)
    expect(endMatches(s.press(.keyboard, at: 0.1), a), "remote to keyboard")
    s.didStop(a); _ = s.release(.keyboard, at: 0.2)
    let b = beginID(s.press(.keyboard, at: 0.3)); _ = s.didStart(b)
    expect(s.release(.remote, at: 2).isEmpty, "old release must not stop new session")
    _ = s.release(.keyboard, at: 2)
    expect(s.press(.remote, at: 2.1).isEmpty, "cross-source remote press")
    expect(endMatches(s.release(.remote, at: 2.2), b), "keyboard to remote")
    s.didStop(b)
}
// Errors/disconnect close capture; old callbacks cannot alter new session.
do {
    var s = VoiceSession(); let a = beginID(s.press(.keyboard, at: 0))
    expect(endMatches(s.cancel(), a), "cancel")
    s.didStop(a)
    let b = beginID(s.press(.remote, at: 1))
    s.didStop(a); expect(s.phase == .starting(b), "old stop")
    expect(endMatches(s.didStart(a), a), "old late start")
    expect(s.phase == .starting(b), "old start preserves current state")
    _ = s.didStart(b); expect(endMatches(s.cancel(), b), "disconnect while running")
    expect(s.cancel().isEmpty, "duplicate cancellation")
    s.didStop(b); expect(s.phase == .idle, "disconnect cleanup")
}
print("PASS: KKvoice session state machine")

// Left Control uses explicit left keycode and correctly releases modifier.
do {
    let shortcut = SystemShortcut(modifiers: [.leftControl], key: nil)!
    expect(shortcut.events.count == 2, "left control pair")
    expect(shortcut.events[0].keyCode == 0x3B && shortcut.events[0].isDown && shortcut.events[0].flags.contains(.maskControl), "left control down")
    expect(shortcut.events[1].keyCode == 0x3B && !shortcut.events[1].isDown && !shortcut.events[1].flags.contains(.maskControl), "left control up")
    expect(SystemShortcut(modifiers: [], key: nil) == nil, "empty shortcut invalid")
    expect(SystemShortcut(modifiers: [.leftControl, .leftControl], key: nil) == nil, "duplicate modifiers invalid")
    expect(SystemShortcut(modifiers: [.leftControl], key: 0x3B) == nil, "modifier as main key invalid")
}
// Synthetic and repeat events cannot recursively trigger a physical shortcut.
do {
    var gate = PhysicalTriggerGate()
    expect(gate.receive(keyCode: 0x3B, configuredKey: 0x3B, isDown: true, isSynthetic: true, isRepeat: false) == nil, "synthetic ignored")
    expect(gate.receive(keyCode: 0x3E, configuredKey: 0x3B, isDown: true, isSynthetic: false, isRepeat: false) == nil, "right control ignored")
    expect(gate.receive(keyCode: 0x3B, configuredKey: 0x3B, isDown: true, isSynthetic: false, isRepeat: false) == .down, "physical down")
    expect(gate.receive(keyCode: 0x3B, configuredKey: 0x3B, isDown: true, isSynthetic: false, isRepeat: true) == nil, "autorepeat ignored")
    expect(gate.receive(keyCode: 0x3B, configuredKey: 0x3B, isDown: false, isSynthetic: false, isRepeat: false) == .up, "physical up")
}
// Relay: remote starts only after audio ready; physical passthrough never doubles.
do {
    var voice = VoiceSession(); var relay = ShortcutRelay()
    let first = voice.press(.remote, at: 0); let id = beginID(first)
    expect(relay.handle(first, origin: .remote) == [.capture(.begin(id))], "no premature shortcut")
    _ = voice.didStart(id)
    expect(relay.audioReady(id) == [.sendToggle(id)], "ready starts target")
    expect(relay.audioReady(id).isEmpty, "duplicate ready ignored")
    _ = voice.release(.remote, at: 0.1)
    let physicalStop = voice.press(.keyboard, at: 1)
    expect(relay.handle(physicalStop, origin: .keyboardDelivered) == [.capture(.end(id))], "physical stop is never duplicated")
    voice.didStop(id); _ = voice.release(.keyboard, at: 1.1)
    let physicalStart = voice.press(.keyboard, at: 2); let id2 = beginID(physicalStart)
    expect(relay.handle(physicalStart, origin: .keyboardDelivered) == [.capture(.begin(id2))], "physical start is never duplicated")
    _ = voice.didStart(id2); expect(relay.audioReady(id2).isEmpty, "physical start already delivered")
    _ = voice.release(.keyboard, at: 2.1)
    _ = voice.press(.remote, at: 2.2)
    expect(relay.handle(voice.release(.remote, at: 2.3), origin: .remote) == [.capture(.end(id2)), .sendToggle(id2)], "remote stops physical start")
}
// Cancel before capture ready must not turn on target afterwards.
do {
    var voice = VoiceSession(remoteGesture: .hybrid); var relay = ShortcutRelay()
    let start = voice.press(.remote, at: 0); let id = beginID(start)
    _ = relay.handle(start, origin: .remote)
    let stop = voice.release(.remote, at: 1)
    expect(relay.handle(stop, origin: .remote) == [.capture(.end(id))], "no stop toggle before start")
    expect(relay.audioReady(id).isEmpty, "late readiness cannot start target")
    expect(voice.didStart(id) == [.end(id)], "late physical capture is stopped")
}
print("PASS: shortcut relay and left Control")
// A failed stop shortcut is still surfaced even after the relay forgot its session.
do {
    var relay = ShortcutRelay(); let id = UUID()
    _ = relay.handle([.begin(id)], origin: .keyboardDelivered)
    _ = relay.handle([.end(id)], origin: .remote)
    expect(relay.failed(id) == [.synchronizationUncertain(id)], "failed stop surfaced")
}

// All upstream key names resolve and produce complete balanced event pairs.
do {
    expect(Set(ShortcutDefinition.supportedKeyNames).count == ShortcutDefinition.supportedKeyNames.count, "keys unique")
    for key in ShortcutDefinition.supportedKeyNames {
        guard let definition = ShortcutDefinition(keyName: key) else { fatalError("missing key \(key)") }
        let events = definition.systemShortcut.events
        expect(events.count == 2 && events.first!.isDown && !events.last!.isDown, "balanced \(key)")
        expect(events.first!.keyCode == events.last!.keyCode, "same key on up \(key)")
        expect(ShortcutDefinition(encoded: definition.encoded) == definition, "round trip \(key)")
    }
    expect(ShortcutDefinition(encoded: "key:a")?.keyName == "A", "legacy key")
    expect(ShortcutDefinition(encoded: "shortcut:none:LeftControl")?.systemShortcut.events.first?.keyCode == 0x3B, "left control")
    expect(ShortcutDefinition(encoded: "shortcut:none:RightControl")?.systemShortcut.events.first?.keyCode == 0x3E, "right control")
    let chord = ShortcutDefinition(encoded: "shortcut:command+shift:K")!
    let events = chord.systemShortcut.events
    expect(events.map(\.keyCode) == [0x37,0x38,0x28,0x28,0x38,0x37], "full modifier order")
    expect(events.map(\.isDown) == [true,true,true,false,false,false], "modifier release order")
    expect(events[2].flags.contains(.maskCommand) && events[2].flags.contains(.maskShift), "chord flags")
    expect(events.last!.flags.isEmpty, "release clears flags")
    let sided = ShortcutDefinition(encoded: "shortcut:rightControl+leftShift:F12")!
    expect(sided.systemShortcut.events.map(\.keyCode) == [0x3E,0x38,0x6F,0x6F,0x38,0x3E], "sided chord")
    expect(ShortcutDefinition(encoded: "shortcut:ctrl:K") == nil, "unknown modifier")
    expect(ShortcutDefinition(encoded: "shortcut:control+leftControl:K") == nil, "duplicate modifier flags")
    expect(ShortcutDefinition(encoded: "shortcut:control++shift:K") == nil, "empty modifier")
    expect(ShortcutDefinition(encoded: "shortcut:command:LeftControl") == nil, "modifier as main in chord")
    expect(ShortcutDefinition(encoded: "shortcut:none:NoSuchKey") == nil, "unknown key")
    expect(!ShortcutDefinition(keyName: "A")!.suitableForGlobalTrigger, "unsafe global letter")
    expect(ShortcutDefinition(keyName: "A", modifiers: ["control"])!.suitableForGlobalTrigger, "modified global letter")
    let saved = try! JSONEncoder().encode(sided)
    expect(try! JSONDecoder().decode(ShortcutDefinition.self, from: saved) == sided, "codable roundtrip")
    let invalid = Data(#"{"keyName":"Bad","modifiers":[]}"#.utf8)
    expect((try? JSONDecoder().decode(ShortcutDefinition.self, from: invalid)) == nil, "invalid saved config rejected")
}
print("PASS: complete shortcut catalog and serialization")
do {
    expect(ShortcutDefinition(encoded: "shortcut:command+shift:K")!.legacyHelperEncoding == "shortcut:command+shift:K", "generic helper encoding")
    expect(ShortcutDefinition(encoded: "shortcut:rightControl+shift:K")!.legacyHelperEncoding == nil, "cannot silently lose modifier side")
    expect(ShortcutDefinition(encoded: "shortcut:none:RightControl")!.supportedByLegacyKeyboardTrigger, "standalone right control wake supported")
    expect(!ShortcutDefinition(encoded: "shortcut:none:ArrowLeft")!.supportedByLegacyKeyboardTrigger, "helper trigger has narrower key set")
    expect(!ShortcutDefinition(encoded: "shortcut:none:K")!.supportedByLegacyKeyboardTrigger, "plain global letter rejected")
}
