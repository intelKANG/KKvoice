import AppKit
import VoiceSessions

/// Capture in the foreground, with manual selection as a fallback.
enum ShortcutPicker {
    static func prompt(previous: ShortcutDefinition?, globalWake: Bool) -> ShortcutDefinition? {
        let alert = NSAlert(); alert.messageText = "录制快捷键"
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        let key = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        key.addItems(withTitles: ShortcutDefinition.supportedKeyNames)
        if let previous { key.selectItem(withTitle: previous.keyName) }
        let choices = [("command", "⌘ Command"), ("option", "⌥ Option"), ("control", "⌃ Control"), ("shift", "⇧ Shift"), ("fn", "Fn")]
        let boxes = choices.map { name, label -> NSButton in
            let box = NSButton(checkboxWithTitle: label, target: nil, action: nil)
            box.identifier = NSUserInterfaceItemIdentifier(name)
            box.state = previous?.modifiers.contains(name) == true ? .on : .off
            return box
        }
        let hint = NSTextField(labelWithString: "按下快捷键，或手动选择")
        let stack = NSStackView(views: [hint, key] + boxes); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        stack.frame = NSRect(x: 0, y: 0, width: 330, height: 215); alert.accessoryView = stack
        var ordinaryKeyCaptured = false
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let matched = ShortcutDefinition.supportedKeyNames.first { name in
                guard let definition = ShortcutDefinition(keyName: name), let first = definition.systemShortcut.events.first else { return false }
                return first.keyCode == event.keyCode
            }
            if event.type == .keyDown {
                if event.keyCode == 0x35 { NSApp.abortModal(); return nil }
                guard let matched else { return nil }
                ordinaryKeyCaptured = true
                key.selectItem(withTitle: matched)
                let flags = event.modifierFlags
                let selected = [flags.contains(.command), flags.contains(.option), flags.contains(.control), flags.contains(.shift), flags.contains(.function)]
                for (box, enabled) in zip(boxes, selected) { box.state = enabled ? .on : .off }
                return nil
            }
            if let matched, ["LeftCommand", "RightCommand", "LeftOption", "RightOption", "LeftControl", "RightControl", "LeftShift", "RightShift", "Fn"].contains(matched) {
                let down = CGEventSource.keyState(.combinedSessionState, key: event.keyCode)
                if down { ordinaryKeyCaptured = false }
                else if !ordinaryKeyCaptured {
                    key.selectItem(withTitle: matched)
                    boxes.forEach { $0.state = .off }
                }
            }
            return event
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        guard alert.runModal() == .alertFirstButtonReturn, let selected = key.titleOfSelectedItem else { return nil }
        let modifiers = boxes.filter { $0.state == .on }.compactMap { $0.identifier?.rawValue }
        guard let value = ShortcutDefinition(keyName: selected, modifiers: modifiers) else {
            showError("单独修饰键不能再添加其他修饰键。"); return nil
        }
        if globalWake && !value.supportedByLegacyKeyboardTrigger {
            showError("唤醒键处理字母/数字时需搭配修饰键")
            return nil
        }
        return value
    }
    private static func showError(_ message: String) { let alert = NSAlert(); alert.messageText = message; alert.runModal() }
}
