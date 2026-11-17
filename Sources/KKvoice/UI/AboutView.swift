import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PageScaffold(title: "关于") {
            VStack(alignment: .leading, spacing: DS.s16) {
                brandHeroCard
                projectSupportCard
                acknowledgementsCard
            }
        }
    }

    private var brandHeroCard: some View {
        Card(padding: DS.s20) {
            HStack(alignment: .center, spacing: DS.s20) {
                AppLogoImage(size: 68)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("KKvoice")
                            .font(.title.bold())
                            .foregroundStyle(.primary)

                        Text("v\(model.appVersionString) (\(model.appBuildString))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DS.subtleFill)
                            )
                    }

                    Text("Google TV 遥控器语音输入与按键映射工具")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if model.updater.isBusy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.updater.statusSummaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let info = model.updater.availableRelease {
                        Button("一键更新 v\(info.version)") {
                            model.updater.installUpdate(info)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("检查更新") {
                            model.updater.checkForUpdates(userInitiated: true, showUpToDateAlert: true)
                        }
                    }

                    if !model.updater.isBusy, case .idle = model.updater.state {
                        EmptyView()
                    } else if !model.updater.isBusy {
                        Text(model.updater.statusSummaryText)
                            .font(.caption2)
                            .foregroundStyle(model.updater.hasUpdateAvailable ? Color.accentColor : .secondary)
                    }
                }
            }
        }
    }

    private var projectSupportCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader("项目与反馈", systemImage: "bubble.left.and.exclamationmark.bubble.right")

                CardDivider()

                LabeledRow(
                    "KKvoice 开源仓库",
                    subtitle: "查看项目源码、版本说明与使用指南",
                    systemImage: "chevron.left.forwardslash.chevron.right"
                ) {
                    Button {
                        model.openExternalURL("https://github.com/intelKANG/KKvoice")
                    } label: {
                        Label("GitHub 主页", systemImage: "arrow.up.right.square")
                    }
                    .help("打开 KKvoice GitHub 主页")
                }

                CardDivider()

                LabeledRow(
                    "问题与建议反馈",
                    subtitle: "遇到 Bug 或有功能建议？欢迎提交 Issue",
                    systemImage: "exclamationmark.bubble"
                ) {
                    Button {
                        model.openExternalURL("https://github.com/intelKANG/KKvoice/issues")
                    } label: {
                        Label("反馈问题 / 建议", systemImage: "arrow.up.right.square")
                    }
                    .help("在 GitHub Issues 提交问题或建议")
                }
            }
        }
    }

    private var acknowledgementsCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader("开源鸣谢", systemImage: "heart.text.square")

                CardDivider()

                LabeledRow(
                    "BlackHole",
                    subtitle: "虚拟音频驱动",
                    systemImage: "waveform.circle"
                ) {
                    Button {
                        model.openExternalURL("https://github.com/ExistentialAudio/BlackHole")
                    } label: {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                    .help("打开 GitHub")
                }

                CardDivider()

                LabeledRow(
                    "vRemoter",
                    subtitle: "遥控器协议参考",
                    systemImage: "appletvremote.gen4"
                ) {
                    Button {
                        model.openExternalURL("https://github.com/VincentKingHsu/vRemoter")
                    } label: {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                    .help("打开 GitHub")
                }
            }
        }
    }
}

struct AppLogoImage: View {
    var size: CGFloat = 36

    private static func loadLogo() -> NSImage? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("KKvoice-logo.png")
            if let img = NSImage(contentsOf: bundled) {
                return img
            }
        }
        let repoAsset = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Native/Assets/KKvoice-logo.png")
        if let img = NSImage(contentsOf: repoAsset) {
            return img
        }
        return nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.98, blue: 0.99),
                            Color(red: 0.92, green: 0.93, blue: 0.96)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

            if let image = Self.loadLogo() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.14)
            } else {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Color(red: 0.11, green: 0.13, blue: 0.16))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("KKvoice 图标")
    }
}
