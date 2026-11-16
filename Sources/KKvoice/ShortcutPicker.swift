import AppKit
import CoreGraphics
import SwiftUI
import VoiceSessions

extension ShortcutDefinition {
    static func localizedKeyLabel(for keyName: String) -> String {
        switch keyName {
        case "Space": return "空格"
        case "Return": return "回车 ↩"
        case "Escape": return "Esc ⎋"
        case "Tab": return "Tab ⇥"
        case "Backspace": return "退格 ⌫"
        case "ForwardDelete": return "删除 ⌦"
        case "Home": return "Home ↖"
        case "End": return "End ↘"
        case "PageUp": return "Page Up ⇞"
        case "PageDown": return "Page Down ⇟"
        case "ArrowUp": return "↑ 方向上"
        case "ArrowDown": return "↓ 方向下"
        case "ArrowLeft": return "← 方向左"
        case "ArrowRight": return "→ 方向右"
        case "LeftCommand": return "左 ⌘ Command"
        case "RightCommand": return "右 ⌘ Command"
        case "LeftOption": return "左 ⌥ Option"
        case "RightOption": return "右 ⌥ Option"
        case "LeftControl": return "左 ⌃ Control"
        case "RightControl": return "右 ⌃ Control"
        case "LeftShift": return "左 ⇧ Shift"
        case "RightShift": return "右 ⇧ Shift"
        case "Fn": return "Fn"
        default: return keyName
        }
    }

    static func compactKeySymbol(for keyName: String) -> String {
        switch keyName {
        case "Space": return "空格"
        case "Return": return "↩"
        case "Escape": return "Esc"
        case "Tab": return "⇥"
        case "Backspace": return "⌫"
        case "ForwardDelete": return "⌦"
        case "Home": return "↖"
        case "End": return "↘"
        case "PageUp": return "⇞"
        case "PageDown": return "⇟"
        case "ArrowUp": return "↑"
        case "ArrowDown": return "↓"
        case "ArrowLeft": return "←"
        case "ArrowRight": return "→"
        case "LeftCommand": return "左 ⌘"
        case "RightCommand": return "右 ⌘"
        case "LeftOption": return "左 ⌥"
        case "RightOption": return "右 ⌥"
        case "LeftControl": return "左 Control"
        case "RightControl": return "右 Control"
        case "LeftShift": return "左 Shift"
        case "RightShift": return "右 Shift"
        case "Fn": return "Fn"
        default: return keyName
        }
    }

    var displayString: String {
        var prefix = ""
        let lowerMods = Set(modifiers.map { $0.lowercased() })
        if lowerMods.contains("fn") { prefix += "Fn " }
        if lowerMods.contains("control") || lowerMods.contains("leftcontrol") { prefix += "⌃" }
        if lowerMods.contains("rightcontrol") { prefix += "右⌃" }
        if lowerMods.contains("option") || lowerMods.contains("leftoption") { prefix += "⌥" }
        if lowerMods.contains("rightoption") { prefix += "右⌥" }
        if lowerMods.contains("shift") || lowerMods.contains("leftshift") { prefix += "⇧" }
        if lowerMods.contains("rightshift") { prefix += "右⇧" }
        if lowerMods.contains("command") || lowerMods.contains("leftcommand") { prefix += "⌘" }
        if lowerMods.contains("rightcommand") { prefix += "右⌘" }
        return prefix + Self.compactKeySymbol(for: keyName)
    }

    static func displayString(forEncoded raw: String) -> String {
        if let decoded = ShortcutDefinition(encoded: raw) ?? ShortcutDefinition(keyName: raw) {
            return decoded.displayString
        }
        return raw
    }
}

@MainActor
private final class ShortcutCaptureState: ObservableObject {
    @Published var selectedKey: String
    @Published var selectedModifiers: Set<String>
    @Published var errorMessage: String? = nil

    static let modifierOptions: [(id: String, symbol: String, title: String)] = [
        ("command", "⌘", "⌘ Command"),
        ("option", "⌥", "⌥ Option"),
        ("control", "⌃", "⌃ Control"),
        ("shift", "⇧", "⇧ Shift"),
        ("fn", "Fn", "Fn")
    ]

    static let standaloneModifiers: Set<String> = [
        "LeftCommand", "RightCommand",
        "LeftOption", "RightOption",
        "LeftControl", "RightControl",
        "LeftShift", "RightShift",
        "Fn"
    ]

    init(previous: ShortcutDefinition?) {
        self.selectedKey = previous?.keyName ?? "N"
        self.selectedModifiers = Set(previous?.modifiers ?? ["command", "option"])
    }

    var orderedModifiers: [String] {
        Self.modifierOptions.map(\.id).filter { selectedModifiers.contains($0) }
    }

    var previewText: String {
        if let def = ShortcutDefinition(keyName: selectedKey, modifiers: orderedModifiers) {
            return def.displayString
        }
        let symbols = Self.modifierOptions
            .filter { selectedModifiers.contains($0.id) }
            .map(\.symbol)
            .joined()
        return symbols + ShortcutDefinition.compactKeySymbol(for: selectedKey)
    }

    func toggleModifier(_ id: String) {
        errorMessage = nil
        if Self.standaloneModifiers.contains(selectedKey) {
            selectedKey = "Space"
        }
        if selectedModifiers.contains(id) {
            selectedModifiers.remove(id)
        } else {
            selectedModifiers.insert(id)
        }
    }

    func chooseKey(_ key: String) {
        errorMessage = nil
        selectedKey = key
        if Self.standaloneModifiers.contains(key) {
            selectedModifiers.removeAll()
        }
    }
}

private struct ShortcutRecorderPanelView: View {
    @ObservedObject var state: ShortcutCaptureState
    let globalWake: Bool
    let onConfirm: (ShortcutDefinition) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s16) {
            HStack(spacing: DS.s8) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text("录制快捷键")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            VStack(spacing: DS.s8) {
                Text("请按下快捷键")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(state.previewText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, DS.s16)
                    .padding(.vertical, 6)

                Text("直接按键自动识别 · 按 Esc 取消")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.s12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("手动选择")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: DS.s12) {
                    Text("主键")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)

                    Menu {
                        ForEach(ShortcutDefinition.supportedKeyNames, id: \.self) { name in
                            Button {
                                state.chooseKey(name)
                            } label: {
                                if name == state.selectedKey {
                                    Label(ShortcutDefinition.localizedKeyLabel(for: name), systemImage: "checkmark")
                                } else {
                                    Text(ShortcutDefinition.localizedKeyLabel(for: name))
                                }
                            }
                        }
                    } label: {
                        Text(ShortcutDefinition.localizedKeyLabel(for: state.selectedKey))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderedButton)
                }

                HStack(alignment: .top, spacing: DS.s12) {
                    Text("修饰键")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(ShortcutCaptureState.modifierOptions.prefix(3), id: \.id) { item in
                                modifierChip(item)
                            }
                        }
                        HStack(spacing: 6) {
                            ForEach(ShortcutCaptureState.modifierOptions.suffix(2), id: \.id) { item in
                                modifierChip(item)
                            }
                        }
                    }
                }
            }

            if let errorMessage = state.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CardDivider()

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("确定") {
                    validateAndSubmit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.s20)
        .frame(width: 360)
        .background(DS.windowBackground)
    }

    private func modifierChip(_ item: (id: String, symbol: String, title: String)) -> some View {
        let isOn = state.selectedModifiers.contains(item.id)
        return Button {
            state.toggleModifier(item.id)
        } label: {
            Text(item.title)
                .font(.caption.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.15) : DS.subtleFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isOn ? Color.accentColor.opacity(0.45) : DS.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func validateAndSubmit() {
        guard let value = ShortcutDefinition(keyName: state.selectedKey, modifiers: state.orderedModifiers) else {
            state.errorMessage = "单独修饰键不能再叠加其他修饰键"
            return
        }
        if globalWake && !value.supportedByLegacyKeyboardTrigger {
            state.errorMessage = "唤醒键使用字母或数字时需搭配修饰键"
            return
        }
        onConfirm(value)
    }
}

/// Capture in the foreground with a SwiftUI recording panel and localized manual fallback.
enum ShortcutPicker {
    @MainActor
    static func prompt(previous: ShortcutDefinition?, globalWake: Bool) -> ShortcutDefinition? {
        let state = ShortcutCaptureState(previous: previous)
        var confirmedResult: ShortcutDefinition? = nil

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "录制快捷键"
        panel.isReleasedWhenClosed = false
        panel.appearance = AppModel.currentWindowAppearance

        let rootView = ShortcutRecorderPanelView(
            state: state,
            globalWake: globalWake,
            onConfirm: { result in
                confirmedResult = result
                NSApp.stopModal(withCode: .OK)
            },
            onCancel: {
                NSApp.stopModal(withCode: .cancel)
            }
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.center()

        var ordinaryKeyCaptured = false
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let matched = ShortcutDefinition.supportedKeyNames.first { name in
                guard let definition = ShortcutDefinition(keyName: name),
                      let first = definition.systemShortcut.events.first else { return false }
                return first.keyCode == event.keyCode
            }
            if event.type == .keyDown {
                if event.keyCode == 0x35 {
                    NSApp.stopModal(withCode: .cancel)
                    return nil
                }
                guard let matched else { return nil }
                ordinaryKeyCaptured = true
                state.selectedKey = matched
                state.errorMessage = nil
                let flags = event.modifierFlags
                var mods = Set<String>()
                if flags.contains(.command) { mods.insert("command") }
                if flags.contains(.option) { mods.insert("option") }
                if flags.contains(.control) { mods.insert("control") }
                if flags.contains(.shift) { mods.insert("shift") }
                if flags.contains(.function) { mods.insert("fn") }
                state.selectedModifiers = mods
                return nil
            }
            if let matched, ShortcutCaptureState.standaloneModifiers.contains(matched) {
                let down = CGEventSource.keyState(.combinedSessionState, key: event.keyCode)
                if down {
                    ordinaryKeyCaptured = false
                } else if !ordinaryKeyCaptured {
                    state.selectedKey = matched
                    state.selectedModifiers.removeAll()
                    state.errorMessage = nil
                }
            }
            return event
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            panel.orderOut(nil)
        }

        let response = NSApp.runModal(for: panel)
        return response == .OK ? confirmedResult : nil
    }
}
