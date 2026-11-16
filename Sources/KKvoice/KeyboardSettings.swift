import Foundation
import VoiceSessions

/// Persist stable helper key identifiers rather than menu indexes or titles.
struct KeyboardSettings {
    private static let defaultKeyName = "Fn"
    private static let disabledValue = "disabled"
    private let defaults: UserDefaults
    private let wakeKey = "keyboardWakeKey"
    private let inputKey = "inputShortcutKey"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func wakeSelection(choices: [InputShortcut]) -> Int {
        guard let definition = wakeDefinition() else { return 0 }
        guard definition.modifiers.isEmpty,
              let index = choices.firstIndex(where: { $0.helperKey == definition.keyName }) else { return choices.count + 1 }
        return index + 1 // Menu index zero means disabled.
    }

    func inputSelection(choices: [InputShortcut]) -> Int {
        let definition = inputDefinition()
        guard definition.modifiers.isEmpty,
              let index = choices.firstIndex(where: { $0.helperKey == definition.keyName }) else { return choices.count }
        return index
    }

    func wakeDefinition() -> ShortcutDefinition? {
        guard let raw = defaults.string(forKey: wakeKey) else {
            return ShortcutDefinition(keyName: Self.defaultKeyName)
        }
        if raw == Self.disabledValue { return nil }
        guard let result = ShortcutDefinition(encoded: raw) ?? ShortcutDefinition(keyName: raw),
              result.supportedByLegacyKeyboardTrigger else { return nil }
        return result
    }
    func inputDefinition() -> ShortcutDefinition {
        if let raw = defaults.string(forKey: inputKey),
           let value = ShortcutDefinition(encoded: raw) ?? ShortcutDefinition(keyName: raw) { return value }
        return ShortcutDefinition(keyName: Self.defaultKeyName)!
    }
    func saveWakeDefinition(_ value: ShortcutDefinition) {
        guard value.supportedByLegacyKeyboardTrigger else { return }
        defaults.set(value.encoded, forKey: wakeKey)
    }
    func saveInputDefinition(_ value: ShortcutDefinition) { defaults.set(value.encoded, forKey: inputKey) }

    func saveWake(selection: Int, choices: [InputShortcut]) {
        let index = selection - 1
        if choices.indices.contains(index) { defaults.set(choices[index].helperKey, forKey: wakeKey) }
        else { defaults.set(Self.disabledValue, forKey: wakeKey) }
    }

    func saveInput(selection: Int, choices: [InputShortcut]) {
        guard choices.indices.contains(selection) else { return }
        defaults.set(choices[selection].helperKey, forKey: inputKey)
    }
}

/// Independent of Bluetooth and audio status, which can change concurrently.
struct KeyboardListenerStatus {
    enum State: Equatable { case disabled, stopped, starting, ready(String), permissionRequired, failed }
    private(set) var state: State = .stopped

    mutating func connecting(key: String?) { state = key == nil ? .disabled : .starting }
    mutating func receive(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "keyboard_trigger_ready":
            guard message["captureCancelOnly"] as? Bool != true else { return }
            state = .ready(message["key"] as? String ?? "")
        case "keyboard_trigger_error": state = .failed
        case "permission_required":
            if message["permission"] as? String == "accessibility",
               message["source"] as? String == "keyboard-trigger" { state = .permissionRequired }
        case "helper_process_exited": state = .stopped
        default: break
        }
    }

    var text: String {
        switch state {
        case .disabled: return "未启用"
        case .stopped: return "未连接"
        case .starting: return "启动中"
        case .ready: return "已启用"
        case .permissionRequired: return "需要辅助功能权限"
        case .failed: return "启动失败"
        }
    }
}
