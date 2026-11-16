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
                    "菜单栏常驻",
                    subtitle: "关闭窗口时隐藏至菜单栏",
                    systemImage: "menubar.rectangle"
                ) {
                    StatusPill(title: "已启用", tone: .connected)
                }
            }
        }
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
            }
        }
    }
}
