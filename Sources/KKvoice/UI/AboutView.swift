import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PageScaffold(title: "关于") {
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

                    Text("Google TV 遥控器语音输入与按键映射工具")
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
                    subtitle: "遥控器与音频驱动参考",
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
