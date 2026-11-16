import AppKit
import UniformTypeIdentifiers
import VoiceSessions

final class ButtonMappingsWindowController: NSWindowController {
    private let store: ButtonMappingStore
    private var draft: ButtonMappings
    private let onApply: (ButtonMappings) -> Void
    private let canCaptureShortcut: () -> Bool
    private var controls: [String: NSPopUpButton] = [:]
    private let switcher = NSButton(checkboxWithTitle: "左右键切换应用", target: nil, action: nil)
    private let customShortcut = "__shortcut"
    private let chooseApp = "__app"
    private let chooseFile = "__file"
    private let typeText = "__text"
    private let snapnote = "__snapnote"

    init(store: ButtonMappingStore, mappings: ButtonMappings, canCaptureShortcut: @escaping () -> Bool = { true }, onApply: @escaping (ButtonMappings) -> Void) {
        self.store = store; self.draft = mappings; self.onApply = onApply; self.canCaptureShortcut = canCaptureShortcut
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "按键设置"; window.center()
        super.init(window: window)
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "按键设置"); title.font = .boldSystemFont(ofSize: 20)
        switcher.state = draft.appSwitcherNavigation ? .on : .off
        switcher.target = self; switcher.action = #selector(switcherChanged)
        let rowHeight: CGFloat = 38
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let height = CGFloat(RemoteButton.all.count) * rowHeight + 12
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: height))
        document.autoresizingMask = [.width]
        for (index, button) in RemoteButton.all.enumerated() {
            let y = height - CGFloat(index + 1) * rowHeight
            let label = NSTextField(labelWithString: button.name)
            label.frame = NSRect(x: 8, y: y + 7, width: 110, height: 22)
            label.autoresizingMask = [.maxXMargin]
            let popup = NSPopUpButton(frame: NSRect(x: 124, y: y + 3, width: 420, height: 28))
            popup.autoresizingMask = [.width]
            popup.tag = index; popup.target = self; popup.action = #selector(mappingChanged(_:))
            for option in ActionCatalog.fixed { popup.addItem(withTitle: option.label); popup.lastItem?.representedObject = option.target }
            popup.menu?.addItem(.separator())
            add(popup, title: "设置自定义快捷键…", value: customShortcut)
            add(popup, title: "选择应用…", value: chooseApp)
            add(popup, title: "选择文件…", value: chooseFile)
            add(popup, title: "输入文字并发送 Enter…", value: typeText)
            add(popup, title: "新建闪念笔记（测试）", value: snapnote)
            document.addSubview(label); document.addSubview(popup); controls[button.id] = popup
            refreshPopup(button.id)
        }
        scroll.documentView = document
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetDefaults))
        let save = NSButton(title: "保存", target: self, action: #selector(saveMappings)); save.keyEquivalent = "\r"
        updateSwitcherControls()
        let bottom = NSStackView(views: [reset, save]); bottom.orientation = .horizontal; bottom.spacing = 12
        let layout = NSStackView(views: [title, switcher, scroll, bottom])
        layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 12
        layout.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            layout.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            layout.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            layout.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: layout.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }

    private func add(_ popup: NSPopUpButton, title: String, value: String) {
        popup.addItem(withTitle: title); popup.lastItem?.representedObject = value
    }
    private func menuValue(_ popup: NSPopUpButton) -> String? { popup.selectedItem?.representedObject as? String }
    private func refreshPopup(_ id: String) {
        guard let popup = controls[id] else { return }
        let action = draft.buttons[id] ?? .none
        let desired: String
        if action.target.hasPrefix("shortcut:") || action.target.hasPrefix("key:") || (1...12).contains(where: { action.target == "F\($0)" }) { desired = customShortcut }
        else if action.target.hasPrefix("openApp:") || action.target.hasPrefix("openAppFocus:") { desired = chooseApp }
        else if action.target.hasPrefix("openFile:") { desired = chooseFile }
        else if action.target == "typeText" { desired = typeText }
        else if action.target == "snapnoteNewNote" { desired = snapnote }
        else { desired = action.target }
        if let item = popup.itemArray.first(where: { ($0.representedObject as? String) == desired }) { popup.select(item) }
        // The selected item shows the configured value so mappings are reviewable.
        for item in popup.itemArray {
            switch item.representedObject as? String {
            case customShortcut: item.title = desired == customShortcut ? "快捷键：\(action.target)" : "设置自定义快捷键…"
            case chooseApp: item.title = desired == chooseApp ? "应用：\(action.target.components(separatedBy: ":").last ?? "")" : "选择应用…"
            case chooseFile: item.title = desired == chooseFile ? "文件：\(URL(fileURLWithPath: String(action.target.dropFirst("openFile:".count))).lastPathComponent)" : "选择文件…"
            case typeText: item.title = desired == typeText ? "文字：\(String((action.text ?? "").prefix(24)))" : "输入文字并发送 Enter…"
            default: break
            }
        }
    }

    private func updateSwitcherControls() {
        for id in ["05", "06"] {
            controls[id]?.isEnabled = !draft.appSwitcherNavigation
            controls[id]?.toolTip = draft.appSwitcherNavigation ? "已启用左右键切换应用，关闭后可自定义。" : nil
        }
    }
    @objc private func switcherChanged() { draft.appSwitcherNavigation = switcher.state == .on; updateSwitcherControls() }
    @objc private func resetDefaults() {
        draft = .defaults; switcher.state = .on
        for button in RemoteButton.all { refreshPopup(button.id) }
        updateSwitcherControls()
    }
    @objc private func mappingChanged(_ sender: NSPopUpButton) {
        guard RemoteButton.all.indices.contains(sender.tag), let choice = menuValue(sender) else { return }
        let id = RemoteButton.all[sender.tag].id
        var replacement: ButtonAction?
        switch choice {
        case customShortcut: replacement = promptShortcut(previous: draft.buttons[id])
        case chooseApp: replacement = promptApplication()
        case chooseFile: replacement = promptFile()
        case typeText: replacement = promptText(previous: draft.buttons[id]?.text)
        case snapnote: replacement = ButtonAction(target: "snapnoteNewNote")
        default: replacement = ButtonAction(target: choice)
        }
        if let replacement, ActionCatalog.isValid(replacement) { draft.buttons[id] = replacement }
        refreshPopup(id)
    }
    @objc private func saveMappings() {
        do { try store.save(draft); onApply(draft); window?.close() }
        catch { showError(error.localizedDescription) }
    }

    private func promptShortcut(previous: ButtonAction?) -> ButtonAction? {
        guard canCaptureShortcut() else { showError("请先断开遥控器，再录入快捷键。完成后重新连接。") ; return nil }
        let definition = previous.flatMap { action -> ShortcutDefinition? in
            if let decoded = ShortcutDefinition(encoded: action.target) { return decoded }
            return ShortcutDefinition(keyName: action.target)
        }
        guard let value = ShortcutPicker.prompt(previous: definition, globalWake: false) else { return nil }
        return ButtonAction(target: value.encoded)
    }

    private func promptApplication() -> ButtonAction? {
        let panel = NSOpenPanel(); panel.message = "选择要打开的应用"; panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        var focus = false
        if ["com.openai.codex", "com.openai.chatgpt"].contains(id) {
            let alert = NSAlert(); alert.messageText = "打开后尝试聚焦聊天输入框？"
            alert.addButton(withTitle: "聚焦"); alert.addButton(withTitle: "仅打开")
            focus = alert.runModal() == .alertFirstButtonReturn
        }
        return ButtonAction(target: "\(focus ? "openAppFocus:" : "openApp:")\(id)")
    }
    private func promptFile() -> ButtonAction? {
        let panel = NSOpenPanel(); panel.message = "选择要打开的文件"; panel.canChooseFiles = true
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ButtonAction(target: "openFile:\(url.path)")
    }
    private func promptText(previous: String?) -> ButtonAction? {
        let alert = NSAlert(); alert.messageText = "输入文字并发送 Enter"
        alert.informativeText = "文字会以明文保存在本机设置中。"
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        let field = NSTextField(string: previous ?? ""); field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let action = ButtonAction(target: "typeText", text: field.stringValue)
        guard ActionCatalog.isValid(action) else { showError("请输入不超过 128 个字符的单行文字。"); return nil }
        return action
    }
    private func showError(_ text: String) { let alert = NSAlert(); alert.messageText = text; alert.runModal() }
}
