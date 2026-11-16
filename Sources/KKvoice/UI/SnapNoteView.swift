import SwiftUI

struct SnapNoteView: View {
    @ObservedObject var model: AppModel
    @State private var tokenInput: String = ""
    @State private var draftShortcut: String? = nil

    private var effectiveShortcutText: String {
        draftShortcut ?? model.snapNoteShortcut ?? "未设置"
    }

    var body: some View {
        PageScaffold(title: "闪念笔记") {
            if model.isControlsLocked {
                StatusPill(
                    title: "断开后可修改",
                    tone: .warning,
                    systemImage: "lock.fill"
                )
            }
        } content: {
            configurationCard
        }
        .onAppear {
            draftShortcut = model.snapNoteShortcut
        }
        .onChange(of: model.snapNoteShortcut) { newValue in
            draftShortcut = newValue
        }
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
                    .frame(width: 260)
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
                            .font(.callout.monospaced())
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
                    .frame(width: 260, alignment: .trailing)
                }

                CardDivider()

                HStack(alignment: .center, spacing: DS.s12) {
                    Spacer()

                    Button("保存") {
                        if model.saveSnapNoteConfiguration(
                            token: tokenInput,
                            shortcutEncoded: draftShortcut ?? model.snapNoteShortcut
                        ) {
                            tokenInput = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isControlsLocked)
                    .help("保存设置")
                }
            }
        }
    }
}
