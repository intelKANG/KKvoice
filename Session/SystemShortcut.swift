import Foundation
import CoreGraphics
import ApplicationServices

/// Explicit sides matter: Vokie can distinguish left Control (0x3B).
public struct SystemShortcut {
    public struct Modifier: Equatable {
        public let keyCode: CGKeyCode
        public let flag: CGEventFlags
        public init(keyCode: CGKeyCode, flag: CGEventFlags) { self.keyCode = keyCode; self.flag = flag }
        public static let leftControl = Modifier(keyCode: 0x3B, flag: .maskControl)
        public static let rightControl = Modifier(keyCode: 0x3E, flag: .maskControl)
        public static let leftOption = Modifier(keyCode: 0x3A, flag: .maskAlternate)
        public static let leftCommand = Modifier(keyCode: 0x37, flag: .maskCommand)
        public static let leftShift = Modifier(keyCode: 0x38, flag: .maskShift)
    }
    public struct Event: Equatable {
        public let keyCode: CGKeyCode
        public let isDown: Bool
        public let flags: CGEventFlags
    }
    /// Nonempty modifiers and nil key represent a modifier-only shortcut.
    public let modifiers: [Modifier]
    public let key: CGKeyCode?
    public init?(modifiers: [Modifier], key: CGKeyCode?) {
        guard key != nil || !modifiers.isEmpty,
              Set(modifiers.map(\.keyCode)).count == modifiers.count,
              Set(modifiers.map { $0.flag.rawValue }).count == modifiers.count,
              !modifiers.contains(where: { $0.keyCode == key }) else { return nil }
        self.modifiers = modifiers; self.key = key
    }
    public var events: [Event] {
        var flags: CGEventFlags = []; var result: [Event] = []
        for modifier in modifiers {
            flags.insert(modifier.flag)
            result.append(Event(keyCode: modifier.keyCode, isDown: true, flags: flags))
        }
        if let key {
            result.append(Event(keyCode: key, isDown: true, flags: flags))
            result.append(Event(keyCode: key, isDown: false, flags: flags))
        }
        for modifier in modifiers.reversed() {
            flags.remove(modifier.flag)
            result.append(Event(keyCode: modifier.keyCode, isDown: false, flags: flags))
        }
        return result
    }
}

/// Post from a dedicated serial queue; blocks it for `holdDuration` seconds.
/// A successful post confirms only injection, not delivery or Vokie state.
public enum SystemShortcutSender {
    public static let syntheticMarker: Int64 = 0x4B4B564F494345 // KKVOICE
    public enum SendError: Error { case permissionDenied, eventCreationFailed, invalidDuration }
    public static func send(_ shortcut: SystemShortcut, holdDuration: TimeInterval = 0.06) throws {
        guard holdDuration >= 0 && holdDuration <= 1 else { throw SendError.invalidDuration }
        guard CGPreflightPostEventAccess() else { throw SendError.permissionDenied }
        let planned = shortcut.events
        let source = CGEventSource(stateID: .hidSystemState)
        // Create all events before posting any, so allocation failure cannot
        // leave a modifier physically stuck down.
        let events: [CGEvent] = try planned.map { spec in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: spec.keyCode, keyDown: spec.isDown)
            else { throw SendError.eventCreationFailed }
            event.flags = spec.flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            return event
        }
        for index in events.indices {
            // Hold the shortcut at its turning point. For a normal key, pause
            // before the main-key release; for modifier-only, before first up.
            if index > 0 && !planned[index].isDown && planned[index - 1].isDown {
                Thread.sleep(forTimeInterval: holdDuration)
            }
            events[index].post(tap: .cghidEventTap)
        }
    }
    public static func isOwnEvent(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
    }
}
