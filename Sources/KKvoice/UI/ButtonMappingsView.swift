import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceSessions

struct ButtonMappingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: ButtonMappings
    @State private var selectedButtonID: String = "07"
    @State private var saveFeedback: String? = nil

    private let customShortcutChoice = "__shortcut"
    private let chooseAppChoice = "__app"
    private let chooseFileChoice = "__file"
    private let typeTextChoice = "__text"
    private let snapnoteChoice = "__snapnote"

    private struct ButtonMeta: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let isFixedVoice: Bool
    }

    // Left column (top-to-bottom matching the physical Google TV remote left side)
    private static let leftColumnItems: [ButtonMeta] = [
        .init(id: "03", name: "方向上", symbol: "arrow.up", isFixedVoice: false),
        .init(id: "05", name: "方向左", symbol: "arrow.left", isFixedVoice: false),
        .init(id: "04", name: "方向下", symbol: "arrow.down", isFixedVoice: false),
        .init(id: "0B", name: "返回", symbol: "arrow.uturn.backward", isFixedVoice: false),
        .init(id: "0A", name: "Home", symbol: "house.fill", isFixedVoice: false),
        .init(id: "0E", name: "YouTube", symbol: "play.rectangle.fill", isFixedVoice: false),
        .init(id: "01", name: "电源", symbol: "power", isFixedVoice: false)
    ]

    // Right column (top-to-bottom matching the physical Google TV remote right side)
    private static let rightColumnItems: [ButtonMeta] = [
        .init(id: "07", name: "确认", symbol: "circle.inset.filled", isFixedVoice: false),
        .init(id: "06", name: "方向右", symbol: "arrow.right", isFixedVoice: false),
        .init(id: "voice", name: "语音键", symbol: "mic.fill", isFixedVoice: true),
        .init(id: "08", name: "静音", symbol: "speaker.slash.fill", isFixedVoice: false),
        .init(id: "0F", name: "Netflix", symbol: "film.fill", isFixedVoice: false),
        .init(id: "0C", name: "音量＋", symbol: "speaker.wave.3.fill", isFixedVoice: false),
        .init(id: "0D", name: "音量－", symbol: "speaker.wave.1.fill", isFixedVoice: false),
        .init(id: "11", name: "信源", symbol: "display", isFixedVoice: false)
    ]

    init(model: AppModel) {
        self.model = model
        self._draft = State(initialValue: model.mappings)
    }

    private var hasUnsavedChanges: Bool {
        draft != model.mappings
    }

    var body: some View {
        PageScaffold(
            title: "按键映射",
            subtitle: "点击中央遥控器按键或两侧卡片，自定义 Google TV 遥控器在 macOS 上的动作。",
            scrollable: true
        ) {
            statusBadge
        } content: {
            VStack(alignment: .leading, spacing: DS.s16) {
                switcherBannerCard
                mappingWorkbench
                bottomToolbarCard
            }
        }
        .onChange(of: model.mappings) { newValue in
            draft = newValue
        }
        .onChange(of: model.lastPressedButtonID) { newValue in
            if let id = newValue?.uppercased() {
                withAnimation(DS.stateAnimation) {
                    selectedButtonID = id
                }
            }
        }
    }

    // MARK: - Top Status Pill & Switcher Banner

    @ViewBuilder
    private var statusBadge: some View {
        if hasUnsavedChanges {
            StatusPill(title: "有未保存更改", tone: .warning, systemImage: "pencil.circle.fill")
        } else if let saveFeedback {
            StatusPill(title: saveFeedback, tone: .connected, systemImage: "checkmark.circle.fill")
        } else {
            StatusPill(title: "已生效", tone: .connected, systemImage: "checkmark.circle")
        }
    }

    private var switcherBannerCard: some View {
        Card(padding: DS.s12) {
            HStack(alignment: .center, spacing: DS.s12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("左右键切换应用")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(
                        draft.appSwitcherNavigation
                            ? "已启用：按方向左 / 方向右直接唤起并浏览 macOS 应用切换器；关闭后可单独设置左右键动作。"
                            : "已关闭：方向左与方向右可自由映射为方向键、快捷键或打开指定应用。"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                Spacer(minLength: DS.s12)

                Toggle("左右键切换应用", isOn: $draft.appSwitcherNavigation)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("左右键切换应用")
                    .onChange(of: draft.appSwitcherNavigation) { _ in
                        saveFeedback = nil
                    }
            }
        }
    }

    // MARK: - Center Remote + Two-Column Workbench

    private var mappingWorkbench: some View {
        HStack(alignment: .center, spacing: DS.s24) {
            // Left column (7 buttons)
            VStack(spacing: DS.s8) {
                ForEach(Self.leftColumnItems) { item in
                    buttonRowCard(for: item, side: .left)
                }
            }
            .frame(maxWidth: .infinity)

            // Center remote stage
            centerRemoteStage
                .frame(width: 204)

            // Right column (8 items including fixed voice card)
            VStack(spacing: DS.s8) {
                ForEach(Self.rightColumnItems) { item in
                    buttonRowCard(for: item, side: .right)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlayPreferenceValue(MappingAnchorPrefKey.self) { prefs in
            GeometryReader { geo in
                connectorLinesCanvas(prefs: prefs, in: geo)
            }
            .allowsHitTesting(false)
        }
    }

    private var centerRemoteStage: some View {
        VStack(spacing: DS.s12) {
            ZStack {
                // Soft Google-TV inspired stage aura behind the remote
                Capsule(style: .circular)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.07),
                                Color.primary.opacity(0.03),
                                Color.accentColor.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 192, height: 524)
                    .overlay(
                        Capsule(style: .circular)
                            .strokeBorder(DS.border, lineWidth: 1)
                    )

                RemoteIllustration(
                    highlighted: selectedButtonID,
                    compact: false
                ) { tappedID in
                    withAnimation(DS.stateAnimation) {
                        selectedButtonID = tappedID
                    }
                }
                .anchorPreference(key: MappingAnchorPrefKey.self, value: .bounds) { bounds in
                    [.init(kind: .remoteBounds, id: "remote", side: .left, bounds: bounds)]
                }
            }

            selectedKeyPill
        }
    }

    private var selectedKeyPill: some View {
        let meta = (Self.leftColumnItems + Self.rightColumnItems).first { $0.id == selectedButtonID }
        let title = meta?.name ?? "按键"
        let symbol = meta?.symbol ?? "keyboard"
        let summary: String = {
            if selectedButtonID == "voice" {
                return "按一次开始，再按一次结束"
            }
            if isSwitcherLocked(selectedButtonID) {
                return "左右键切换应用"
            }
            return actionSummary(for: selectedButtonID)
        }()

        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text("·")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(DS.cardBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(DS.border, lineWidth: 1)
        )
    }

    // MARK: - Cards

    fileprivate enum ColumnSide {
        case left
        case right
    }

    @ViewBuilder
    private func buttonRowCard(for item: ButtonMeta, side: ColumnSide) -> some View {
        if item.isFixedVoice {
            voiceFixedCard(for: item, side: side)
        } else {
            configurableButtonCard(for: item, side: side)
        }
    }

    private func voiceFixedCard(for item: ButtonMeta, side: ColumnSide) -> some View {
        let isSelected = (selectedButtonID == item.id)

        return Card(padding: 10, isHighlighted: isSelected) {
            HStack(spacing: 10) {
                iconBadge(symbol: item.symbol, isSelected: isSelected, isMuted: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("固定")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                            )
                    }
                    Text("按一次开始，再按一次结束（不可映射）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(DS.stateAnimation) {
                    selectedButtonID = item.id
                }
            }
        }
        .anchorPreference(key: MappingAnchorPrefKey.self, value: .bounds) { bounds in
            [.init(kind: .cardBounds, id: item.id, side: side, bounds: bounds)]
        }
    }

    private func configurableButtonCard(for item: ButtonMeta, side: ColumnSide) -> some View {
        let isSelected = (selectedButtonID == item.id)
        let lockedBySwitcher = isSwitcherLocked(item.id)
        let currentAction = draft.buttons[item.id] ?? .none
        let isNone = !lockedBySwitcher && currentAction.target == "none"

        return Card(
            padding: 10,
            isHighlighted: isSelected,
            isDisabled: lockedBySwitcher
        ) {
            HStack(spacing: 10) {
                iconBadge(
                    symbol: item.symbol,
                    isSelected: isSelected,
                    isMuted: isNone || lockedBySwitcher
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if lockedBySwitcher {
                            Text("应用切换")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(DS.subtleFill)
                                )
                        }
                    }

                    if lockedBySwitcher {
                        Text("已启用左右键切换应用，关闭后可自定义。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(actionCategorySubtitle(for: currentAction))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                actionMenu(for: item.id, lockedBySwitcher: lockedBySwitcher)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(DS.stateAnimation) {
                    selectedButtonID = item.id
                }
            }
        }
        .help(lockedBySwitcher ? "已启用左右键切换应用，关闭后可自定义。" : "\(item.name)：\(actionSummary(for: item.id))")
        .anchorPreference(key: MappingAnchorPrefKey.self, value: .bounds) { bounds in
            [.init(kind: .cardBounds, id: item.id, side: side, bounds: bounds)]
        }
    }

    private func iconBadge(symbol: String, isSelected: Bool, isMuted: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    isSelected
                        ? Color.accentColor
                        : (isMuted ? DS.subtleFill : Color.accentColor.opacity(0.12))
                )
                .frame(width: 30, height: 30)

            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : (isMuted ? Color.secondary : Color.accentColor)
                )
        }
    }

    @ViewBuilder
    private func actionMenu(for id: String, lockedBySwitcher: Bool) -> some View {
        let action = draft.buttons[id] ?? .none
        let desired = desiredMenuChoice(for: action)
        let summary = lockedBySwitcher ? "切换应用" : actionSummary(for: id)

        Menu {
            ForEach(ActionCatalog.fixed, id: \.target) { option in
                Button {
                    selectMenuOption(choice: option.target, for: id)
                } label: {
                    if desired == option.target {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }

            Divider()

            Button {
                selectMenuOption(choice: customShortcutChoice, for: id)
            } label: {
                let title = desired == customShortcutChoice ? "快捷键：\(action.target)" : "设置自定义快捷键…"
                if desired == customShortcutChoice {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }

            Button {
                selectMenuOption(choice: chooseAppChoice, for: id)
            } label: {
                let title = desired == chooseAppChoice
                    ? "应用：\(action.target.components(separatedBy: ":").last ?? "")"
                    : "选择应用…"
                if desired == chooseAppChoice {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }

            Button {
                selectMenuOption(choice: chooseFileChoice, for: id)
            } label: {
                let title = desired == chooseFileChoice
                    ? "文件：\(URL(fileURLWithPath: String(action.target.dropFirst("openFile:".count))).lastPathComponent)"
                    : "选择文件…"
                if desired == chooseFileChoice {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }

            Button {
                selectMenuOption(choice: typeTextChoice, for: id)
            } label: {
                let title = desired == typeTextChoice
                    ? "文字：\(String((action.text ?? "").prefix(24)))"
                    : "输入文字并发送 Enter…"
                if desired == typeTextChoice {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }

            Button {
                selectMenuOption(choice: snapnoteChoice, for: id)
            } label: {
                if desired == snapnoteChoice {
                    Label("新建闪念笔记（测试）", systemImage: "checkmark")
                } else {
                    Text("新建闪念笔记（测试）")
                }
            }
        } label: {
            Text(summary)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 128, alignment: .leading)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .frame(width: 146)
        .disabled(lockedBySwitcher)
        .simultaneousGesture(
            TapGesture().onEnded {
                withAnimation(DS.stateAnimation) {
                    selectedButtonID = id
                }
            }
        )
    }

    // MARK: - Bottom Bar

    private var bottomToolbarCard: some View {
        Card(padding: DS.s12) {
            HStack(alignment: .center, spacing: DS.s12) {
                HStack(spacing: DS.s8) {
                    StatusDot(tone: hasUnsavedChanges ? .warning : .connected, size: 7)
                    Text(
                        hasUnsavedChanges
                            ? "当前有未保存的按键修改，点击「保存」后立即生效。"
                            : (saveFeedback ?? "所有按键映射均已保存。")
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: DS.s12)

                Button("恢复默认") {
                    withAnimation(DS.stateAnimation) {
                        draft = .defaults
                        saveFeedback = "已恢复默认映射（请点击保存生效）"
                    }
                }
                .controlSize(.regular)
                .help("将所有按键恢复为出厂默认动作")

                Button("保存") {
                    saveMappings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .help("校验并保存当前按键映射")
            }
        }
    }

    // MARK: - Connector Lines Canvas

    @ViewBuilder
    private func connectorLinesCanvas(prefs: [MappingAnchorItem], in geo: GeometryProxy) -> some View {
        if let remoteItem = prefs.first(where: { $0.kind == .remoteBounds }) {
            let remoteRect = geo[remoteItem.bounds]
            let cardItems = prefs.filter { $0.kind == .cardBounds }

            Canvas { context, _ in
                // Draw subtle guide curves first, then selected curve on top
                for item in cardItems where item.id != selectedButtonID {
                    drawConnector(for: item, remoteRect: remoteRect, in: geo, isSelected: false, context: &context)
                }
                if let activeItem = cardItems.first(where: { $0.id == selectedButtonID }) {
                    drawConnector(for: activeItem, remoteRect: remoteRect, in: geo, isSelected: true, context: &context)
                }
            }
        }
    }

    private func drawConnector(
        for item: MappingAnchorItem,
        remoteRect: CGRect,
        in geo: GeometryProxy,
        isSelected: Bool,
        context: inout GraphicsContext
    ) {
        let cardRect = geo[item.bounds]
        let unitAnchor = RemoteIllustration.anchorPoint(for: item.id)
        let targetPoint = CGPoint(
            x: remoteRect.minX + remoteRect.width * unitAnchor.x,
            y: remoteRect.minY + remoteRect.height * unitAnchor.y
        )
        let startPoint = CGPoint(
            x: item.side == .left ? cardRect.maxX : cardRect.minX,
            y: cardRect.midY
        )

        let midX = (startPoint.x + targetPoint.x) / 2
        var path = Path()
        path.move(to: startPoint)
        path.addCurve(
            to: targetPoint,
            control1: CGPoint(x: midX, y: startPoint.y),
            control2: CGPoint(x: midX, y: targetPoint.y)
        )

        if isSelected {
            context.stroke(
                path,
                with: .color(Color.accentColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
            )
            let startDot = Path(ellipseIn: CGRect(x: startPoint.x - 3.5, y: startPoint.y - 3.5, width: 7, height: 7))
            let endDot = Path(ellipseIn: CGRect(x: targetPoint.x - 3.5, y: targetPoint.y - 3.5, width: 7, height: 7))
            context.fill(startDot, with: .color(Color.accentColor))
            context.fill(endDot, with: .color(Color.accentColor))
        } else {
            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.11)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [3, 3])
            )
        }
    }

    // MARK: - Action Selection & Prompts (Exact Parity with ButtonMappingsWindow.swift)

    private func isSwitcherLocked(_ id: String) -> Bool {
        draft.appSwitcherNavigation && (id == "05" || id == "06")
    }

    private func desiredMenuChoice(for action: ButtonAction) -> String {
        if action.target.hasPrefix("shortcut:")
            || action.target.hasPrefix("key:")
            || (1...12).contains(where: { action.target == "F\($0)" }) {
            return customShortcutChoice
        } else if action.target.hasPrefix("openApp:") || action.target.hasPrefix("openAppFocus:") {
            return chooseAppChoice
        } else if action.target.hasPrefix("openFile:") {
            return chooseFileChoice
        } else if action.target == "typeText" {
            return typeTextChoice
        } else if action.target == "snapnoteNewNote" {
            return snapnoteChoice
        } else {
            return action.target
        }
    }

    func actionSummary(for id: String) -> String {
        let action = draft.buttons[id] ?? .none
        let desired = desiredMenuChoice(for: action)
        switch desired {
        case customShortcutChoice:
            return "快捷键：\(action.target)"
        case chooseAppChoice:
            return "应用：\(action.target.components(separatedBy: ":").last ?? "")"
        case chooseFileChoice:
            return "文件：\(URL(fileURLWithPath: String(action.target.dropFirst("openFile:".count))).lastPathComponent)"
        case typeTextChoice:
            return "文字：\(String((action.text ?? "").prefix(24)))"
        case snapnoteChoice:
            return "新建闪念笔记（测试）"
        default:
            return ActionCatalog.fixed.first(where: { $0.target == action.target })?.label ?? action.target
        }
    }

    private func actionCategorySubtitle(for action: ButtonAction) -> String {
        let desired = desiredMenuChoice(for: action)
        switch desired {
        case "none":
            return "未绑定动作"
        case customShortcutChoice:
            return "自定义键盘快捷键"
        case chooseAppChoice:
            return action.target.hasPrefix("openAppFocus:") ? "打开应用并聚焦输入框" : "启动 macOS 应用"
        case chooseFileChoice:
            return "打开本机文件"
        case typeTextChoice:
            return "输入预设文字并发送 Enter"
        case snapnoteChoice:
            return "通过 MCP 新建闪念笔记"
        default:
            return "预设系统 / 键盘动作"
        }
    }

    private func selectMenuOption(choice: String, for id: String) {
        selectedButtonID = id
        var replacement: ButtonAction?
        switch choice {
        case customShortcutChoice:
            replacement = promptShortcut(previous: draft.buttons[id])
        case chooseAppChoice:
            replacement = promptApplication()
        case chooseFileChoice:
            replacement = promptFile()
        case typeTextChoice:
            replacement = promptText(previous: draft.buttons[id]?.text)
        case snapnoteChoice:
            replacement = ButtonAction(target: "snapnoteNewNote")
        default:
            replacement = ButtonAction(target: choice)
        }
        if let replacement, ActionCatalog.isValid(replacement) {
            draft.buttons[id] = replacement
            saveFeedback = nil
        }
    }

    private func saveMappings() {
        do {
            try model.applyMappings(draft)
            saveFeedback = "已保存"
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func promptShortcut(previous: ButtonAction?) -> ButtonAction? {
        guard model.canCaptureShortcut else {
            showError("请先断开遥控器，再录入快捷键。完成后重新连接。")
            return nil
        }
        let definition = previous.flatMap { action -> ShortcutDefinition? in
            if let decoded = ShortcutDefinition(encoded: action.target) { return decoded }
            return ShortcutDefinition(keyName: action.target)
        }
        guard let value = ShortcutPicker.prompt(previous: definition, globalWake: false) else { return nil }
        return ButtonAction(target: value.encoded)
    }

    private func promptApplication() -> ButtonAction? {
        let panel = NSOpenPanel()
        panel.message = "选择要打开的应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        var focus = false
        if ["com.openai.codex", "com.openai.chatgpt"].contains(id) {
            let alert = NSAlert()
            alert.messageText = "打开后尝试聚焦聊天输入框？"
            alert.addButton(withTitle: "聚焦")
            alert.addButton(withTitle: "仅打开")
            focus = alert.runModal() == .alertFirstButtonReturn
        }
        return ButtonAction(target: "\(focus ? "openAppFocus:" : "openApp:")\(id)")
    }

    private func promptFile() -> ButtonAction? {
        let panel = NSOpenPanel()
        panel.message = "选择要打开的文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ButtonAction(target: "openFile:\(url.path)")
    }

    private func promptText(previous: String?) -> ButtonAction? {
        let alert = NSAlert()
        alert.messageText = "输入文字并发送 Enter"
        alert.informativeText = "文字会以明文保存在本机设置中。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: previous ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let action = ButtonAction(target: "typeText", text: field.stringValue)
        guard ActionCatalog.isValid(action) else {
            showError("请输入不超过 128 个字符的单行文字。")
            return nil
        }
        return action
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }
}

// MARK: - Anchor Preferences for Connector Lines

private struct MappingAnchorItem {
    enum Kind {
        case remoteBounds
        case cardBounds
    }
    let kind: Kind
    let id: String
    let side: ButtonMappingsView.ColumnSide
    let bounds: Anchor<CGRect>
}

private struct MappingAnchorPrefKey: PreferenceKey {
    static var defaultValue: [MappingAnchorItem] = []
    static func reduce(value: inout [MappingAnchorItem], nextValue: () -> [MappingAnchorItem]) {
        value.append(contentsOf: nextValue())
    }
}
