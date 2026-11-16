import SwiftUI

struct GeneralView: View {
    @ObservedObject var model: AppModel

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    var body: some View {
        PageScaffold(
            title: "通用",
            subtitle: "管理 KKvoice 的启动方式、窗口行为与 macOS 系统权限"
        ) {
            VStack(alignment: .leading, spacing: DS.s16) {
                startupCard
                permissionsCard
            }
        }
    }

    private var startupCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader(
                    "启动与常驻",
                    subtitle: "配置应用随系统登录启动与菜单栏运行方式",
                    systemImage: "power.circle"
                )

                CardDivider()

                LabeledRow(
                    "开机启动",
                    subtitle: "登录 macOS 时自动启动 KKvoice 并尝试连接遥控器",
                    systemImage: "sunrise"
                ) {
                    Toggle("", isOn: launchBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("开机启动")
                }

                if model.loginItemRequiresApproval {
                    HStack(spacing: DS.s12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("请在系统设置的「登录项」中允许 KKvoice 开机启动。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开登录项设置") {
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
                    "菜单栏常驻与关闭隐藏",
                    subtitle: "关闭主窗口时隐藏至右上角菜单栏（左键打开窗口，右键弹出菜单）",
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
                SectionHeader(
                    "系统隐私权限",
                    subtitle: "KKvoice Remote Helper 需要以下系统权限以完成蓝牙收音、按键监听与快捷键发送",
                    systemImage: "hand.raised.circle"
                )

                CardDivider()

                LabeledRow(
                    "辅助功能（Accessibility）",
                    subtitle: "用于向语音输入软件发送快捷键及监听电脑全局唤醒键",
                    systemImage: "figure.wave.circle"
                ) {
                    Button("打开设置") {
                        model.openPermissionSettings(for: "accessibility")
                    }
                    .controlSize(.small)
                }

                CardDivider()

                LabeledRow(
                    "输入监控（Input Monitoring）",
                    subtitle: "用于捕获 Chromecast 遥控器 HID 按键事件",
                    systemImage: "keyboard.badge.eye"
                ) {
                    Button("打开设置") {
                        model.openPermissionSettings(for: "input-monitoring")
                    }
                    .controlSize(.small)
                }

                CardDivider()

                LabeledRow(
                    "蓝牙（Bluetooth）",
                    subtitle: "用于连接遥控器 BLE 语音通道并接收 16 kHz 语音流",
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
