import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PageScaffold(
            title: "关于",
            subtitle: "版本信息与开源项目鸣谢"
        ) {
            VStack(alignment: .leading, spacing: DS.s16) {
                brandHeroCard
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

                    Text("将 Google Chromecast / Google TV 语音遥控器打造为 macOS 无线语音麦克风与自定义快捷控制器。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
    }

    private var acknowledgementsCard: some View {
        Card(padding: DS.s20) {
            VStack(alignment: .leading, spacing: DS.s16) {
                SectionHeader(
                    "鸣谢开源项目",
                    subtitle: "KKvoice 的实现参考并受益于以下开源项目",
                    systemImage: "heart.text.square"
                )

                CardDivider()

                LabeledRow(
                    "BlackHole",
                    subtitle: "ExistentialAudio · 虚拟音频驱动基础",
                    systemImage: "waveform.circle"
                ) {
                    Button {
                        model.openExternalURL("https://github.com/ExistentialAudio/BlackHole")
                    } label: {
                        Label("BlackHole GitHub", systemImage: "arrow.up.right.square")
                    }
                    .help("在浏览器中打开 BlackHole GitHub 仓库")
                }

                CardDivider()

                LabeledRow(
                    "vRemoter",
                    subtitle: "VincentKingHsu · 遥控器与音频驱动实现参考",
                    systemImage: "appletvremote.gen4"
                ) {
                    Button {
                        model.openExternalURL("https://github.com/VincentKingHsu/vRemoter")
                    } label: {
                        Label("vRemoter GitHub", systemImage: "arrow.up.right.square")
                    }
                    .help("在浏览器中打开 vRemoter GitHub 仓库")
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
