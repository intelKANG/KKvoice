import SwiftUI

struct GeneralView: View {
    @ObservedObject var model: AppModel

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { model.appearanceMode },
            set: { model.setAppearanceMode($0) }
        )
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { model.showMenuBarIcon },
            set: { model.setShowMenuBarIcon($0) }
        )
    }

    var body: some View {
        PageScaffold(title: "通用") {
            VStack(alignment: .leading, spacing: DS.s16) {
                startupCard
                permissionsCard
            }
        }
    }

    private var startupCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader("启动与运行", systemImage: "power.circle")

                CardDivider()

                LabeledRow("外观", systemImage: model.appearanceMode.systemImage) {
                    Picker("", selection: appearanceBinding) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }

                CardDivider()

                LabeledRow("开机启动", systemImage: "sunrise") {
                    Toggle("", isOn: launchBinding)
                        .labelsHidden()
                        .toggleStyle(.kkSwitch)
                        .accessibilityLabel("开机启动")
                }

                if model.loginItemRequiresApproval {
                    HStack(spacing: DS.s12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("需在系统设置「登录项」中允许")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开设置") {
                            model.openPermissionSettings(for: "login-items")
                        }
                        .controlSize(.small)
                    }
                    .padding(DS.s12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.controlRadius, style: .continuous)
                            .fill(Color.orange.opacity(0.10))
                    )
                }

                CardDivider()

                LabeledRow(
                    "菜单栏图标",
                    subtitle: model.showMenuBarIcon ? "关闭窗口时隐藏至菜单栏" : "已关闭，关闭窗口时保留在程序坞",
                    systemImage: "menubar.rectangle"
                ) {
                    Toggle("", isOn: menuBarIconBinding)
                        .labelsHidden()
                        .toggleStyle(.kkSwitch)
                        .accessibilityLabel("菜单栏图标")
                }

                CardDivider()

                LabeledRow(
                    "虚拟麦克风驱动",
                    subtitle: driverRowSubtitle,
                    systemImage: "waveform.badge.mic"
                ) {
                    if model.isDriverInstalling {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("安装中…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(model.isKKvoiceMicAvailable ? "重新安装驱动" : "安装 KKvoice Mic") {
                            model.installDriver(reinstall: true)
                        }
                        .controlSize(.small)
                        .disabled(model.isControlsLocked)
                    }
                }
            }
        }
    }

    private var driverRowSubtitle: String {
        if let err = model.driverInstallError {
            return err
        }
        if let msg = model.driverInstallMessage {
            return msg
        }
        return model.isKKvoiceMicAvailable ? "KKvoice Mic 已安装" : "尚未安装 KKvoice Mic"
    }

    private var permissionsCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader("系统权限", systemImage: "hand.raised.circle")

                CardDivider()

                LabeledRow(
                    "辅助功能",
                    subtitle: "发送快捷键与监听唤醒键",
                    systemImage: "figure.wave.circle"
                ) {
                    Button("打开设置") {
                        model.openPermissionSettings(for: "accessibility")
                    }
                    .controlSize(.small)
                }

                CardDivider()

                LabeledRow(
                    "输入监控",
                    subtitle: "响应遥控器按键",
                    systemImage: "keyboard.badge.eye"
                ) {
                    Button("打开设置") {
                        model.openPermissionSettings(for: "input-monitoring")
                    }
                    .controlSize(.small)
                }

                CardDivider()

                LabeledRow(
                    "蓝牙",
                    subtitle: "连接遥控器语音",
                    systemImage: "dot.radiowaves.left.and.right"
                ) {
                    Button("打开设置") {
                        model.openPermissionSettings(for: "bluetooth")
                    }
                    .controlSize(.small)
                }

                CardDivider()

                LabeledRow(
                    "麦克风",
                    subtitle: "遥控器未就绪时使用 Mac 麦克风",
                    systemImage: "mic.circle"
                ) {
                    Button("打开设置") {
                        model.openPermissionSettings(for: "microphone")
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
