import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceSessions

struct ButtonMappingsView: View {
    private enum EditingGesture: String, CaseIterable, Identifiable {
        case singleTap = "单击"
        case doubleTap = "双击"
        case longPress = "长按"
        var id: String { rawValue }
    }

    @ObservedObject var model: AppModel
    @State private var draft: ButtonMappings
    @State private var selectedButtonID: String
    @State private var editingGesture: EditingGesture = .singleTap
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

    private static func normalizeButtonID(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.lowercased() == "voice" ? "voice" : raw.uppercased()
    }

    init(model: AppModel) {
        self.model = model
        self._draft = State(initialValue: model.mappings)
        self._selectedButtonID = State(initialValue: Self.normalizeButtonID(model.lastPressedButtonID) ?? "07")
    }

    private var hasUnsavedChanges: Bool {
        draft != model.mappings
    }

    var body: some View {
        VStack(spacing: 0) {
            PageScaffold(
                title: "按键",
                subtitle: "每个按键可同时配置单击、双击和长按动作，互不冲突",
                scrollable: false,
                headerAccessory: {
                    Picker("", selection: $editingGesture) {
                        ForEach(EditingGesture.allCases) { gesture in
                            Text(gestureTabTitle(for: gesture)).tag(gesture)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 246)
                    .help("点击切换正在编辑的手势层；单击、双击、长按可同时生效")
                }
            ) {
                VStack(alignment: .leading, spacing: DS.s12) {
                    switcherBannerCard
                    mappingWorkbench
                }
            }

            stickyBottomBar
        }
        .background(DS.windowBackground)
        .onAppear {
            if let id = Self.normalizeButtonID(model.lastPressedButtonID) {
                selectedButtonID = id
            }
            syncUnsavedRegistration()
        }
        .onChange(of: draft) { _ in
            syncUnsavedRegistration()
        }
        .onChange(of: model.mappings) { newValue in
            draft = newValue
            syncUnsavedRegistration()
        }
        .onChange(of: model.lastPressedButtonID) { newValue in
            if let id = Self.normalizeButtonID(newValue) {
                withAnimation(DS.stateAnimation) {
                    selectedButtonID = id
                }
            }
        }
    }

    private func syncUnsavedRegistration() {
        model.registerUnsavedChanges(
            for: .mappings,
            hasChanges: draft != model.mappings,
            onSave: { saveMappings() },
            onDiscard: {
                draft = model.mappings
                saveFeedback = nil
            }
        )
    }

    // MARK: - Top Switcher Banner

    private var switcherBannerCard: some View {
        Card(padding: 10) {
            HStack(alignment: .center, spacing: DS.s12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.subtleFill)
                        .frame(width: 30, height: 30)
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("左右键切换应用")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("方向左/右直接切换应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.s12)

                Toggle("", isOn: $draft.appSwitcherNavigation)
                    .labelsHidden()
                    .toggleStyle(.kkSwitch)
                    .accessibilityLabel("左右键切换应用")
                    .onChange(of: draft.appSwitcherNavigation) { _ in
                        saveFeedback = nil
                    }
            }
        }
    }

    // MARK: - Standard Three-Column Workbench

    private var mappingWorkbench: some View {
        HStack(alignment: .top, spacing: DS.s16) {
            // Left column (7 buttons, top-aligned with remote and right column)
            VStack(spacing: 14) {
                ForEach(Self.leftColumnItems) { item in
                    buttonRowCard(for: item, side: .left)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            // Center remote stage (top-aligned with both card columns)
            centerRemoteStage
                .frame(width: 168, alignment: .top)

            // Right column (8 items including fixed voice card, top-aligned)
            VStack(spacing: 6) {
                ForEach(Self.rightColumnItems) { item in
                    buttonRowCard(for: item, side: .right)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .overlayPreferenceValue(MappingAnchorPrefKey.self) { prefs in
            GeometryReader { geo in
                connectorLinesCanvas(prefs: prefs, in: geo)
            }
            .allowsHitTesting(false)
        }
    }

    private var centerRemoteStage: some View {
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
                .frame(width: 160, height: 392)
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

        return Card(padding: 8, isHighlighted: isSelected) {
            HStack(spacing: 8) {
                iconBadge(symbol: item.symbol, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                        Text("固定")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.14) : DS.subtleFill)
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Text("短按切换收音，或长按说话松开结束")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
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

    private func gestureTabTitle(for gesture: EditingGesture) -> String {
        switch gesture {
        case .singleTap:
            return "单击"
        case .doubleTap:
            let count = draft.doubleTapButtons.values.filter { $0.target != "none" }.count
            return count > 0 ? "双击 · \(count)" : "双击"
        case .longPress:
            let count = draft.longPressButtons.values.filter { $0.target != "none" }.count
            return count > 0 ? "长按 · \(count)" : "长按"
        }
    }

    private func currentAction(for id: String) -> ButtonAction {
        switch editingGesture {
        case .singleTap:
            return draft.buttons[id] ?? .none
        case .doubleTap:
            return draft.doubleTapButtons[id] ?? .none
        case .longPress:
            return draft.longPressButtons[id] ?? .none
        }
    }

    private func setAction(_ action: ButtonAction, for id: String) {
        switch editingGesture {
        case .singleTap:
            draft.buttons[id] = action
        case .doubleTap:
            if action.target == "none" {
                draft.doubleTapButtons.removeValue(forKey: id)
            } else {
                draft.doubleTapButtons[id] = action
            }
        case .longPress:
            if action.target == "none" {
                draft.longPressButtons.removeValue(forKey: id)
            } else {
                draft.longPressButtons[id] = action
            }
        }
    }

    private func otherConfiguredGestureBadges(for id: String) -> [(short: String, full: String)] {
        var badges: [(String, String)] = []
        if editingGesture != .singleTap, let act = draft.buttons[id], act.target != "none" {
            badges.append(("单", "已配置单击"))
        }
        if editingGesture != .doubleTap, let act = draft.doubleTapButtons[id], act.target != "none" {
            badges.append(("双", "已配置双击"))
        }
        if editingGesture != .longPress, let act = draft.longPressButtons[id], act.target != "none" {
            badges.append(("长", "已配置长按"))
        }
        return badges
    }

    private func configurableButtonCard(for item: ButtonMeta, side: ColumnSide) -> some View {
        let isSelected = (selectedButtonID == item.id)
        let lockedBySwitcher = isSwitcherLocked(item.id)
        let currentAction = currentAction(for: item.id)
        let appInfo = lockedBySwitcher ? nil : resolvedApplication(for: currentAction)
        let otherBadges = lockedBySwitcher ? [] : otherConfiguredGestureBadges(for: item.id)

        return Card(
            padding: 8,
            isHighlighted: isSelected,
            isDisabled: lockedBySwitcher
        ) {
            HStack(spacing: 6) {
                iconBadge(
                    symbol: item.symbol,
                    isSelected: isSelected
                )

                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                if !otherBadges.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(otherBadges, id: \.short) { badge in
                            Text(badge.short)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.13))
                                )
                                .help(badge.full)
                        }
                    }
                }

                Spacer(minLength: 4)

                if let icon = appInfo?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 15, height: 15)
                }

                actionMenu(for: item.id, lockedBySwitcher: lockedBySwitcher)
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(DS.stateAnimation) {
                    selectedButtonID = item.id
                }
            }
        }
        .help(lockedBySwitcher ? "已用于切换应用" : "\(item.name)：\(actionSummary(for: item.id))")
        .anchorPreference(key: MappingAnchorPrefKey.self, value: .bounds) { bounds in
            [.init(kind: .cardBounds, id: item.id, side: side, bounds: bounds)]
        }
    }

    private func iconBadge(symbol: String, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : DS.subtleFill)
                .frame(width: 26, height: 26)

            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        }
    }

    @ViewBuilder
    private func actionMenu(for id: String, lockedBySwitcher: Bool) -> some View {
        let action = currentAction(for: id)
        let desired = desiredMenuChoice(for: action)
        let summary = lockedBySwitcher ? "切换应用" : actionSummary(for: id)
        let appInfo = resolvedApplication(for: action)

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
                let title = desired == customShortcutChoice
                    ? "快捷键：\(ShortcutDefinition.displayString(forEncoded: action.target))"
                    : "自定义快捷键…"
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
                    ? "应用：\(appInfo?.displayName ?? (action.target.components(separatedBy: ":").last ?? ""))"
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
                let title = desired == typeTextChoice ? "输入文字" : "输入文字…"
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
                    Label("新建快速笔记", systemImage: "checkmark")
                } else {
                    Text("新建快速笔记")
                }
            }
        } label: {
            Text(summary)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .frame(width: 130)
        .disabled(lockedBySwitcher)
        .simultaneousGesture(
            TapGesture().onEnded {
                withAnimation(DS.stateAnimation) {
                    selectedButtonID = id
                }
            }
        )
    }

    // MARK: - Sticky Bottom Bar

    private var stickyBottomBar: some View {
        VStack(spacing: 0) {
            CardDivider()

            HStack(alignment: .center, spacing: DS.s12) {
                HStack(spacing: DS.s8) {
                    StatusDot(tone: hasUnsavedChanges ? .warning : .connected, size: 7)
                    Text(
                        hasUnsavedChanges
                            ? "有未保存更改"
                            : (saveFeedback ?? "已保存")
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: DS.s8)

                Button("恢复默认") {
                    withAnimation(DS.stateAnimation) {
                        draft = .defaults
                        saveFeedback = "已恢复默认，点击保存生效"
                    }
                }
                .controlSize(.regular)
                .fixedSize(horizontal: true, vertical: false)
                .help("恢复默认")

                Button("保存") {
                    saveMappings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize(horizontal: true, vertical: false)
                .keyboardShortcut(.defaultAction)
                .help("保存")
            }
            .padding(.horizontal, DS.s24)
            .padding(.vertical, 10)
            .background(DS.cardBackground)
        }
    }

    // MARK: - Connector Lines Canvas

    @ViewBuilder
    private func connectorLinesCanvas(prefs: [MappingAnchorItem], in geo: GeometryProxy) -> some View {
        if let remoteItem = prefs.first(where: { $0.kind == .remoteBounds }) {
            let remoteRect = geo[remoteItem.bounds]
            let cardItems = prefs.filter { $0.kind == .cardBounds }

            Canvas { context, _ in
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

    private func resolvedApplication(for action: ButtonAction) -> (displayName: String, icon: NSImage?)? {
        let target = action.target
        let isFocus = target.hasPrefix("openAppFocus:")
        let isOpen = target.hasPrefix("openApp:")
        guard isFocus || isOpen else { return nil }
        let prefix = isFocus ? "openAppFocus:" : "openApp:"
        let bundleID = String(target.dropFirst(prefix.count))
        guard !bundleID.isEmpty else { return nil }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            var name = FileManager.default.displayName(atPath: url.path)
            if name.lowercased().hasSuffix(".app") {
                name = String(name.dropLast(4))
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            return (name.isEmpty ? bundleID : name, icon)
        }
        return (bundleID, nil)
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
        let action = currentAction(for: id)
        let desired = desiredMenuChoice(for: action)
        switch desired {
        case customShortcutChoice:
            return "快捷键：\(ShortcutDefinition.displayString(forEncoded: action.target))"
        case chooseAppChoice:
            let appName = resolvedApplication(for: action)?.displayName
                ?? (action.target.components(separatedBy: ":").last ?? "")
            return "应用：\(appName)"
        case chooseFileChoice:
            return "文件：\(URL(fileURLWithPath: String(action.target.dropFirst("openFile:".count))).lastPathComponent)"
        case typeTextChoice:
            return "输入文字"
        case snapnoteChoice:
            return "新建快速笔记"
        default:
            return ActionCatalog.fixed.first(where: { $0.target == action.target })?.label ?? action.target
        }
    }

    private func selectMenuOption(choice: String, for id: String) {
        selectedButtonID = id
        let existing = currentAction(for: id)
        var replacement: ButtonAction?
        switch choice {
        case customShortcutChoice:
            replacement = promptShortcut(previous: existing)
        case chooseAppChoice:
            replacement = promptApplication()
        case chooseFileChoice:
            replacement = promptFile()
        case typeTextChoice:
            replacement = promptText(previous: existing.text)
        case snapnoteChoice:
            replacement = ButtonAction(target: "snapnoteNewNote")
        default:
            replacement = ButtonAction(target: choice)
        }
        if let replacement, ActionCatalog.isValid(replacement) {
            setAction(replacement, for: id)
            saveFeedback = nil
        }
    }

    @discardableResult
    func saveMappings() -> Bool {
        do {
            try model.applyMappings(draft)
            saveFeedback = "已保存"
            model.clearUnsavedChanges(for: .mappings)
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func promptShortcut(previous: ButtonAction?) -> ButtonAction? {
        guard model.canCaptureShortcut else {
            showError("断开遥控器后可录制快捷键")
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
        panel.message = "选择应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.appearance = AppModel.currentWindowAppearance
        guard panel.runModal() == .OK,
              let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        var focus = false
        if ["com.openai.codex", "com.openai.chatgpt"].contains(id) {
            let alert = NSAlert()
            alert.messageText = "打开后自动聚焦输入框？"
            alert.addButton(withTitle: "聚焦")
            alert.addButton(withTitle: "仅打开")
            alert.window.appearance = AppModel.currentWindowAppearance
            focus = alert.runModal() == .alertFirstButtonReturn
        }
        return ButtonAction(target: "\(focus ? "openAppFocus:" : "openApp:")\(id)")
    }

    private func promptFile() -> ButtonAction? {
        let panel = NSOpenPanel()
        panel.message = "选择文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.appearance = AppModel.currentWindowAppearance
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return ButtonAction(target: "openFile:\(url.path)")
    }

    private func promptText(previous: String?) -> ButtonAction? {
        let alert = NSAlert()
        alert.messageText = "输入文字并发送 Enter"
        alert.informativeText = ""
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: previous ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.window.appearance = AppModel.currentWindowAppearance
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let action = ButtonAction(target: "typeText", text: field.stringValue)
        guard ActionCatalog.isValid(action) else {
            showError("限 128 字内单行文字")
            return nil
        }
        return action
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.window.appearance = AppModel.currentWindowAppearance
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
