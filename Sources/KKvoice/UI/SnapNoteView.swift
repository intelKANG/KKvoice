import SwiftUI
import VoiceSessions

struct SnapNoteView: View {
    @ObservedObject var model: AppModel
    @State private var tokenInput: String = ""
    @State private var draftShortcut: String? = nil
    @State private var draftTag: String = ""

    private static let controlColumnWidth: CGFloat = 240

    private var effectiveShortcutText: String {
        guard let raw = draftShortcut ?? model.snapNoteShortcut else {
            return "未设置"
        }
        return ShortcutDefinition.displayString(forEncoded: raw)
    }

    private var hasUnsavedChanges: Bool {
        let tokenDirty = !tokenInput.isEmpty
        let shortcutDirty = (draftShortcut != model.snapNoteShortcut)
        let tagDirty = (draftTag.trimmingCharacters(in: .whitespaces) != model.snapNoteTagName)
        return tokenDirty || shortcutDirty || tagDirty
    }

    var body: some View {
        PageScaffold(title: "闪念笔记") {
            if model.isControlsLocked {
                StatusPill(
                    title: "收音中不可修改",
                    tone: .warning,
                    systemImage: "lock.fill"
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: DS.s16) {
                configurationCard
                howItWorksCard
            }
        }
        .onAppear {
            draftShortcut = model.snapNoteShortcut
            draftTag = model.snapNoteTagName
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
        .onChange(of: tokenInput) { _ in
            syncUnsavedState()
        }
        .onChange(of: draftShortcut) { _ in
            syncUnsavedState()
        }
        .onChange(of: draftTag) { _ in
            syncUnsavedState()
        }
    }

    private func syncUnsavedState() {
        model.registerUnsavedChanges(
            for: .snapNote,
            hasChanges: hasUnsavedChanges,
            onSave: {
                let ok = model.saveSnapNoteConfiguration(
                    token: tokenInput,
                    shortcutEncoded: draftShortcut ?? model.snapNoteShortcut,
                    tagName: draftTag
                )
                if ok {
                    tokenInput = ""
                }
                return ok
            },
            onDiscard: {
                tokenInput = ""
                draftShortcut = model.snapNoteShortcut
                draftTag = model.snapNoteTagName
            }
        )
    }

    private var configurationCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader("设置", systemImage: "key.radiowaves.forward") {
                    StatusPill(
                        title: model.hasSnapNoteToken ? "已配置" : "未配置",
                        tone: model.hasSnapNoteToken ? .connected : .disconnected
                    )
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

                CardDivider()

                LabeledRow(
                    "标签",
                    subtitle: "新建笔记后自动添加（1–20 字）",
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
                        if model.saveSnapNoteConfiguration(
                            token: tokenInput,
                            shortcutEncoded: draftShortcut ?? model.snapNoteShortcut,
                            tagName: draftTag
                        ) {
                            tokenInput = ""
                            model.clearUnsavedChanges(for: .snapNote)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isControlsLocked)
                    .help("保存设置")
                }
            }
        }
    }

    private var howItWorksCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s12) {
                SectionHeader("工作原理", systemImage: "sparkles")

                CardDivider()

                VStack(alignment: .leading, spacing: DS.s8) {
                    stepRow(number: "1", text: "按下映射为「新建闪念笔记」的遥控器按键")
                    stepRow(number: "2", text: "KKvoice 发送新建快捷键，闪念笔记新建一条")
                    stepRow(number: "3", text: "自动为该条新笔记添加上方设置的标签")
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
