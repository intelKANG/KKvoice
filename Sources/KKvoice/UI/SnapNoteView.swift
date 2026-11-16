import SwiftUI
import VoiceSessions

struct SnapNoteView: View {
    @ObservedObject var model: AppModel
    @State private var tokenInput: String
    @State private var draftShortcut: String?
    @State private var draftTag: String
    @State private var draftEndpoint: String
    @State private var draftPort: String

    private static let controlColumnWidth: CGFloat = 240
    private static let wideControlColumnWidth: CGFloat = 310

    init(model: AppModel) {
        self.model = model
        _tokenInput = State(initialValue: "")
        _draftShortcut = State(initialValue: model.snapNoteShortcut)
        _draftTag = State(initialValue: model.snapNoteTagName)
        _draftEndpoint = State(initialValue: model.snapNoteMCPEndpoint)
        _draftPort = State(initialValue: model.snapNoteMCPPort)
    }

    private var providerBinding: Binding<QuickNoteProvider> {
        Binding(
            get: { model.quickNoteProvider },
            set: { newValue in
                model.selectQuickNoteProvider(newValue)
                syncUnsavedState()
            }
        )
    }

    private var effectiveShortcutText: String {
        guard let raw = draftShortcut ?? model.snapNoteShortcut else {
            return "未设置"
        }
        return ShortcutDefinition.displayString(forEncoded: raw)
    }

    private var hasUnsavedChanges: Bool {
        if draftTag.trimmingCharacters(in: .whitespaces) != model.snapNoteTagName {
            return true
        }
        if model.quickNoteProvider == .snapNote {
            let tokenDirty = !tokenInput.isEmpty
            let shortcutDirty = (draftShortcut != model.snapNoteShortcut)
            let endpointDirty = (draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) != model.snapNoteMCPEndpoint)
            let portDirty = (draftPort.trimmingCharacters(in: .whitespacesAndNewlines) != model.snapNoteMCPPort)
            return tokenDirty || shortcutDirty || endpointDirty || portDirty
        }
        return false
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { draftEndpoint },
            set: { newValue in
                draftEndpoint = newValue
                if let extracted = AppModel.extractPortString(from: newValue) {
                    draftPort = extracted
                }
            }
        )
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { draftPort },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                draftPort = filtered
                if let updatedEndpoint = AppModel.applyingPort(filtered, to: draftEndpoint) {
                    draftEndpoint = updatedEndpoint
                }
            }
        )
    }

    var body: some View {
        PageScaffold(title: "快速笔记") {
            if model.isControlsLocked {
                StatusPill(
                    title: "收音中不可修改",
                    tone: .warning,
                    systemImage: "lock.fill"
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: DS.s12) {
                configurationCard
                howItWorksCard
            }
        }
        .onAppear {
            loadFromModel()
            syncUnsavedState()
        }
        .onChange(of: model.quickNoteProvider) { _ in
            syncUnsavedState()
        }
        .onChange(of: model.snapNoteShortcut) { newValue in
            draftShortcut = newValue
            syncUnsavedState()
        }
        .onChange(of: model.snapNoteTagName) { newValue in
            draftTag = newValue
            syncUnsavedState()
        }
        .onChange(of: model.snapNoteMCPEndpoint) { newValue in
            draftEndpoint = newValue
            syncUnsavedState()
        }
        .onChange(of: model.snapNoteMCPPort) { newValue in
            draftPort = newValue
            syncUnsavedState()
        }
        .onChange(of: tokenInput) { _ in
            syncUnsavedState()
        }
        .onChange(of: draftShortcut) { _ in
            syncUnsavedState()
        }
        .onChange(of: draftTag) { _ in
            syncUnsavedState()
        }
        .onChange(of: draftEndpoint) { _ in
            syncUnsavedState()
        }
        .onChange(of: draftPort) { _ in
            syncUnsavedState()
        }
    }

    private func loadFromModel() {
        draftShortcut = model.snapNoteShortcut
        draftTag = model.snapNoteTagName
        draftEndpoint = model.snapNoteMCPEndpoint
        draftPort = model.snapNoteMCPPort
    }

    @discardableResult
    private func performSave() -> Bool {
        let ok = model.saveQuickNoteConfiguration(
            provider: model.quickNoteProvider,
            tagName: draftTag,
            token: tokenInput,
            shortcutEncoded: draftShortcut ?? model.snapNoteShortcut,
            mcpEndpoint: draftEndpoint,
            mcpPort: draftPort
        )
        if ok {
            tokenInput = ""
            draftEndpoint = model.snapNoteMCPEndpoint
            draftPort = model.snapNoteMCPPort
            model.clearUnsavedChanges(for: .snapNote)
        }
        return ok
    }

    private func syncUnsavedState() {
        model.registerUnsavedChanges(
            for: .snapNote,
            hasChanges: hasUnsavedChanges,
            onSave: {
                performSave()
            },
            onDiscard: {
                tokenInput = ""
                loadFromModel()
            }
        )
    }

    private var configurationCard: some View {
        Card(padding: DS.s16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("设置", systemImage: "note.text.badge.plus") {
                    HStack(spacing: DS.s8) {
                        if model.quickNoteProvider == .snapNote {
                            Button {
                                model.openSnapNoteWebsite()
                            } label: {
                                Label("闪念笔记官网", systemImage: "arrow.up.right.square")
                            }
                            .controlSize(.small)
                            .help("打开闪念笔记官方网站")

                            StatusPill(
                                title: model.hasSnapNoteToken ? "已配置" : "未配置",
                                tone: model.hasSnapNoteToken ? .connected : .disconnected
                            )
                        } else {
                            StatusPill(
                                title: "系统内置",
                                tone: .connected
                            )
                        }
                    }
                }

                CardDivider()

                LabeledRow("笔记软件", systemImage: "app.badge.checkmark") {
                    Picker("", selection: providerBinding) {
                        ForEach(QuickNoteProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: Self.controlColumnWidth)
                    .disabled(model.isControlsLocked)
                }

                if model.quickNoteProvider == .snapNote {
                    CardDivider()

                    LabeledRow(
                        "MCP 地址",
                        subtitle: "本机或局域网数据接口 URL",
                        systemImage: "network"
                    ) {
                        TextField(AppModel.defaultSnapNoteEndpoint, text: endpointBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .frame(width: Self.wideControlColumnWidth)
                            .disabled(model.isControlsLocked)
                    }

                    CardDivider()

                    LabeledRow(
                        "端口",
                        subtitle: "默认 31090，与上方地址自动同步",
                        systemImage: "number.square"
                    ) {
                        TextField("31090", text: portBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospacedDigit())
                            .frame(width: Self.controlColumnWidth)
                            .disabled(model.isControlsLocked)
                    }

                    CardDivider()

                    LabeledRow("Token", systemImage: "lock.rectangle") {
                        SecureField(
                            model.hasSnapNoteToken ? "已保存，留空不修改" : "输入 Token",
                            text: $tokenInput
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Self.controlColumnWidth)
                        .disabled(model.isControlsLocked)
                    }

                    CardDivider()

                    LabeledRow(
                        "新建快捷键",
                        subtitle: "需与闪念笔记内一致",
                        systemImage: "keyboard.badge.ellipsis"
                    ) {
                        HStack(spacing: DS.s8) {
                            Text(effectiveShortcutText)
                                .font(.callout.weight(.medium))
                                .foregroundStyle((draftShortcut ?? model.snapNoteShortcut) == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(DS.subtleFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(DS.border, lineWidth: 1)
                                )

                            Button("录制…") {
                                if let picked = model.pickSnapNoteShortcut(currentEncoded: draftShortcut) {
                                    draftShortcut = picked
                                }
                            }
                            .disabled(model.isControlsLocked)
                            .help("录制快捷键")
                        }
                        .frame(width: Self.controlColumnWidth, alignment: .trailing)
                    }
                }

                CardDivider()

                LabeledRow(
                    "标签",
                    subtitle: model.quickNoteProvider == .appleNotes ? "新建备忘录后自动写入 #标签（1–20 字）" : "新建笔记后自动添加（1–20 字）",
                    systemImage: "tag"
                ) {
                    TextField("闪念", text: $draftTag)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Self.controlColumnWidth)
                        .disabled(model.isControlsLocked)
                }

                CardDivider()

                HStack(alignment: .center, spacing: DS.s12) {
                    if hasUnsavedChanges {
                        HStack(spacing: 6) {
                            StatusDot(tone: .warning, size: 7)
                            Text("有未保存修改")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("保存") {
                        performSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isControlsLocked)
                    .help("保存设置")
                }
            }
        }
    }

    private var howItWorksCard: some View {
        Card(padding: DS.s16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("工作原理", systemImage: "sparkles")

                CardDivider()

                if model.quickNoteProvider == .appleNotes {
                    VStack(alignment: .leading, spacing: 6) {
                        stepRow(number: "1", text: "按下映射为「新建快速笔记」的遥控器按键")
                        stepRow(number: "2", text: "自动唤醒系统「备忘录」并发送 ⌘N 新建空白笔记")
                        stepRow(number: "3", text: "自动写入 #标签 并换行聚焦正文，按语音键即可直接说话")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        stepRow(number: "1", text: "按下映射为「新建快速笔记」的遥控器按键")
                        stepRow(number: "2", text: "发送新建快捷键，闪念笔记新建一条笔记")
                        stepRow(number: "3", text: "通过 MCP 接口自动为新笔记添加上方设置的标签")
                    }
                }
            }
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(DS.subtleFill)
                )
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
