import Foundation
import VoiceSessions

struct RemoteButton: Equatable {
    let id: String
    let name: String
    static let all: [RemoteButton] = [
        .init(id: "03", name: "方向上"), .init(id: "04", name: "方向下"),
        .init(id: "05", name: "方向左"), .init(id: "06", name: "方向右"),
        .init(id: "07", name: "确认"), .init(id: "0B", name: "返回"),
        .init(id: "0A", name: "Home"), .init(id: "0E", name: "YouTube"),
        .init(id: "08", name: "静音"), .init(id: "0F", name: "Netflix"),
        .init(id: "01", name: "电源"), .init(id: "11", name: "信源"),
        .init(id: "0C", name: "音量＋"), .init(id: "0D", name: "音量－")
    ]
}

struct ButtonAction: Codable, Equatable {
    var target: String
    var text: String? = nil
    static let none = ButtonAction(target: "none")
}

struct ButtonMappings: Codable, Equatable {
    var appSwitcherNavigation: Bool
    var buttons: [String: ButtonAction]
    static let defaults = ButtonMappings(appSwitcherNavigation: true, buttons: [
        "03": .init(target: "arrowUp"), "04": .init(target: "arrowDown"),
        "05": .init(target: "arrowLeft"), "06": .init(target: "arrowRight"),
        "07": .init(target: "sendEnter"), "0B": .init(target: "cancelRecording"),
        "0A": .init(target: "showDesktop"), "0E": .none,
        "08": .init(target: "mute"), "0F": .none,
        "01": .init(target: "lockScreen"), "11": .none,
        "0C": .init(target: "volumeUp"), "0D": .init(target: "volumeDown")
    ])
}

struct ButtonMappingStore {
    private let defaults: UserDefaults
    private let key = "remoteButtonMappings.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> ButtonMappings {
        guard let data = defaults.data(forKey: key), data.count <= 100_000,
              let saved = try? JSONDecoder().decode(ButtonMappings.self, from: data) else { return .defaults }
        var result = ButtonMappings.defaults
        result.appSwitcherNavigation = saved.appSwitcherNavigation
        for button in RemoteButton.all {
            if let action = saved.buttons[button.id], ActionCatalog.isValid(action) { result.buttons[button.id] = action }
        }
        return result
    }
    func save(_ mappings: ButtonMappings) throws {
        guard Set(mappings.buttons.keys).isSubset(of: Set(RemoteButton.all.map(\.id))),
              mappings.buttons.values.allSatisfy(ActionCatalog.isValid) else { throw MappingError.invalid }
        defaults.set(try JSONEncoder().encode(mappings), forKey: key)
    }
}

enum MappingError: LocalizedError {
    case invalid
    var errorDescription: String? { "按键设置无效" }
}

struct ActionOption {
    let target: String
    let label: String
}

enum ActionCatalog {
    static let fixed: [ActionOption] = [
        .init(target: "none", label: "不操作"),
        .init(target: "arrowUp", label: "方向上"), .init(target: "arrowDown", label: "方向下"),
        .init(target: "arrowLeft", label: "方向左"), .init(target: "arrowRight", label: "方向右"),
        .init(target: "return", label: "Enter"), .init(target: "escape", label: "Escape"),
        .init(target: "delete", label: "Delete"), .init(target: "tab", label: "Tab"), .init(target: "space", label: "空格"),
        .init(target: "home", label: "Home"), .init(target: "end", label: "End"),
        .init(target: "pageUp", label: "Page Up"), .init(target: "pageDown", label: "Page Down"),
        .init(target: "lockScreen", label: "锁定屏幕（⌃⌘Q）"), .init(target: "commandSpace", label: "Spotlight（⌘Space）"),
        .init(target: "commandA", label: "全选（⌘A）"), .init(target: "commandC", label: "复制（⌘C）"),
        .init(target: "commandV", label: "粘贴（⌘V）"), .init(target: "commandZ", label: "撤销（⌘Z）"),
        .init(target: "commandS", label: "保存（⌘S）"), .init(target: "commandW", label: "关闭窗口（⌘W）"),
        .init(target: "commandQ", label: "退出应用（⌘Q）"), .init(target: "sendEnter", label: "发送 Enter"),
        .init(target: "cancelRecording", label: "取消收音"), .init(target: "showDesktop", label: "显示桌面（Fn+F11）"),
        .init(target: "appSwitcher", label: "切换应用"), .init(target: "volumeUp", label: "系统音量＋"),
        .init(target: "volumeDown", label: "系统音量－"), .init(target: "mute", label: "系统静音")
    ]
    static let modifiers = ["command", "option", "control", "shift", "fn"]
    static let standaloneModifiers = ["LeftCommand", "RightCommand", "LeftOption", "RightOption", "LeftControl", "RightControl", "LeftShift", "RightShift", "Fn"]
    static let keys: [String] = (1...12).map { "F\($0)" } + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init) + ["Space", "Return", "Escape", "Tab", "Backspace", "ForwardDelete", "Home", "End", "PageUp", "PageDown", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"] + standaloneModifiers
    static func shortcut(key: String, modifiers requested: [String]) -> String? {
        guard keys.contains(key), Set(requested).count == requested.count,
              requested.allSatisfy({ modifiers.contains($0) }),
              !(standaloneModifiers.contains(key) && !requested.isEmpty) else { return nil }
        let order = modifiers.filter { requested.contains($0) }
        return ShortcutDefinition(keyName: key, modifiers: order)?.encoded
    }
    static func isValid(_ action: ButtonAction) -> Bool {
        let target = action.target
        if fixed.contains(where: { $0.target == target }) { return action.text == nil }
        if (1...12).contains(where: { target == "F\($0)" }) { return action.text == nil && ShortcutDefinition(keyName: target) != nil }
        if target.hasPrefix("key:") { return action.text == nil && ShortcutDefinition(encoded: target) != nil }
        if target == "typeText" {
            guard let text = action.text, !text.isEmpty, text.utf16.count <= 128 else { return false }
            return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }
        if target.hasPrefix("shortcut:") {
            return action.text == nil && ShortcutDefinition(encoded: target) != nil
        }
        if target.hasPrefix("openApp:") || target.hasPrefix("openAppFocus:") {
            let focus = target.hasPrefix("openAppFocus:")
            let bundleID = String(target.dropFirst(focus ? "openAppFocus:".count : "openApp:".count))
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
            guard !bundleID.isEmpty, bundleID.count <= 255, action.text == nil,
                  bundleID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
            return !focus || ["com.openai.codex", "com.openai.chatgpt"].contains(bundleID)
        }
        if target.hasPrefix("openFile:") {
            let path = String(target.dropFirst("openFile:".count))
            return path.hasPrefix("/") && !path.contains("\n") && path.utf8.count <= 4096 && action.text == nil
        }
        // Preserve the target in persisted configurations, but do not execute
        // until the safety-checked SnapNote flow has been migrated.
        return target == "snapnoteNewNote" && action.text == nil
    }
}

final class ButtonActionDispatcher {
    var mappings: ButtonMappings
    var switcherActive = false
    private var pressed: Set<String> = []
    private let send: ([String: Any]) throws -> Void
    private let sendShortcut: (ShortcutDefinition) throws -> Void
    private let cancelVoice: () -> Void
    var createSnapNote: () -> Void
    private let status: (String) -> Void

    init(mappings: ButtonMappings, send: @escaping ([String: Any]) throws -> Void,
         sendShortcut: @escaping (ShortcutDefinition) throws -> Void = { try SystemShortcutSender.send($0.systemShortcut) },
         cancelVoice: @escaping () -> Void, status: @escaping (String) -> Void) {
        self.mappings = mappings; self.send = send; self.sendShortcut = sendShortcut; self.cancelVoice = cancelVoice; self.status = status
        self.createSnapNote = { status("未配置快速笔记") }
    }
    func reset() { pressed.removeAll(); switcherActive = false }
    func deviceDisconnected() {
        if switcherActive {
            do { try send(["type": "app_switcher_cancel"]) }
            catch { status("切换应用失败：\(error.localizedDescription)") }
        }
        reset()
    }
    func up(_ button: String) { pressed.remove(button) }
    func down(_ button: String) {
        guard RemoteButton.all.contains(where: { $0.id == button }), pressed.insert(button).inserted else { return }
        let action = mappings.buttons[button] ?? .none
        guard ActionCatalog.isValid(action) else { status("按键设置无效") ; return }
        do {
            if mappings.appSwitcherNavigation && (button == "05" || button == "06") {
                try send(["type": "post_key", "target": button == "05" ? "appSwitcherLeft" : "appSwitcherRight"])
                switcherActive = true
                return
            }
            if switcherActive && action.target != "none" && !["sendEnter", "cancelRecording", "appSwitcher", "arrowLeft", "arrowRight"].contains(action.target) {
                try send(["type": "app_switcher_cancel"])
                switcherActive = false
            }
            switch action.target {
            case "none": break
            case "snapnoteNewNote": createSnapNote()
            case "sendEnter":
                if switcherActive { try send(["type": "app_switcher_commit"]); switcherActive = false }
                else { try send(["type": "post_key", "target": "return"]) }
            case "cancelRecording":
                if switcherActive { try send(["type": "app_switcher_cancel"]); switcherActive = false }
                else { cancelVoice() }
            case "appSwitcher": try send(["type": "post_key", "target": "appSwitcher"]); switcherActive = true
            case "typeText": try send(["type": "post_key", "target": "typeTextAndEnter", "text": action.text ?? ""])
            default:
                let shortcut: ShortcutDefinition?
                if action.target.hasPrefix("shortcut:") || action.target.hasPrefix("key:") { shortcut = ShortcutDefinition(encoded: action.target) }
                else if (1...12).contains(where: { action.target == "F\($0)" }) { shortcut = ShortcutDefinition(keyName: action.target) }
                else { shortcut = nil }
                if let shortcut { try sendShortcut(shortcut) }
                else { try send(["type": "post_key", "target": action.target]) }
            }
        } catch { status("按键发送失败：\(error.localizedDescription)") }
    }
}
