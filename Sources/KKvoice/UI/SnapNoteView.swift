import SwiftUI

struct SnapNoteView: View {
    @ObservedObject var model: AppModel
    @State private var tokenInput: String = ""
    @State private var draftShortcut: String? = nil

    private var effectiveShortcutText: String {
        draftShortcut ?? model.snapNoteShortcut ?? "尚未设置"
    }

    var body: some View {
        PageScaffold(
            title: "闪念笔记",
            subtitle: "配置本机闪念笔记接口与快捷键，支持通过遥控器一键新建闪念并自动添加标签"
        ) {
            if model.isControlsLocked {
                StatusPill(
                    title: "断开连接后可修改",
                    tone: .warning,
                    systemImage: "lock.fill"
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: DS.s16) {
                if model.isControlsLocked {
                    lockedNoticeCard
                }

                configurationCard
                workflowGuideCard
            }
        }
        .onAppear {
            draftShortcut = model.snapNoteShortcut
        }
        .onChange(of: model.snapNoteShortcut) { newValue in
            draftShortcut = newValue
        }
    }

    private var lockedNoticeCard: some View {
        HStack(spacing: DS.s12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("遥控器当前处于连接状态")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("为避免快捷键录制与遥控器监听冲突，请先在「连接」页断开遥控器后再修改闪念设置。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DS.s12)
        .background(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
        )
    }

    private var configurationCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader(
                    "接口与快捷键设置",
                    subtitle: "输入本机接口 Token（留空表示保留已有 Token）并录入带修饰键的新建快捷键",
                    systemImage: "key.radiowaves.forward"
                ) {
                    StatusPill(
                        title: model.hasSnapNoteToken ? "Token 已配置" : "未配置 Token",
                        tone: model.hasSnapNoteToken ? .connected : .disconnected
                    )
                }

                CardDivider()

                LabeledRow(
                    "本机接口 Token",
                    subtitle: model.hasSnapNoteToken ? "安全存储于钥匙串，留空保存将保留现有 Token" : "请输入闪念笔记本机 MCP 接口 Token",
                    systemImage: "lock.rectangle"
                ) {
                    SecureField(
                        model.hasSnapNoteToken ? "留空表示保留已有 Token" : "输入本机接口 Token",
                        text: $tokenInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .disabled(model.isControlsLocked)
                }

                CardDivider()

                LabeledRow(
                    "新建闪念快捷键",
                    subtitle: "必须包含修饰键（⌘ / ⌥ / ⌃ / ⇧），需与闪念笔记应用内快捷键一致",
                    systemImage: "keyboard.badge.ellipsis"
                ) {
                    HStack(spacing: DS.s8) {
                        Text(effectiveShortcutText)
                            .font(.callout.monospaced())
                            .foregroundStyle((draftShortcut ?? model.snapNoteShortcut) == nil ? .secondary : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(DS.subtleFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(DS.border, lineWidth: 1)
                            )

                        Button("录入快捷键…") {
                            if let picked = model.pickSnapNoteShortcut(currentEncoded: draftShortcut) {
                                draftShortcut = picked
                            }
                        }
                        .disabled(model.isControlsLocked)
                        .help("打开快捷键录制窗口")
                    }
                }

                CardDivider()

                HStack(alignment: .center, spacing: DS.s12) {
                    HStack(spacing: 6) {
                        StatusDot(tone: model.connectionPhase.tone, size: 7)
                        Text(model.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("弹窗向导设置…") {
                        model.configureSnapNoteModal()
                        draftShortcut = model.snapNoteShortcut
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isControlsLocked)
                    .help("使用经典弹窗方式设置 Token 与快捷键")

                    Button("保存闪念设置") {
                        if model.saveSnapNoteConfiguration(
                            token: tokenInput,
                            shortcutEncoded: draftShortcut ?? model.snapNoteShortcut
                        ) {
                            tokenInput = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isControlsLocked)
                    .help("保存 Token 与闪念新建快捷键")
                }
            }
        }
    }

    private var workflowGuideCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s12) {
                SectionHeader(
                    "联动说明",
                    subtitle: "如何在遥控器上使用闪念笔记",
                    systemImage: "sparkles.rectangle.stack"
                )

                CardDivider()

                VStack(alignment: .leading, spacing: DS.s8) {
                    guideStepRow(number: "1", text: "在闪念笔记客户端开启本机服务，将 Token 粘贴到上方并保存。")
                    guideStepRow(number: "2", text: "录入与闪念笔记「新建闪念」一致的带修饰键全局快捷键。")
                    guideStepRow(number: "3", text: "前往「按键」页，将任意遥控器按键动作设为「新建闪念笔记（测试）」。")
                }
            }
        }
    }

    private func guideStepRow(number: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                )
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
