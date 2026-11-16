import AppKit
import SwiftUI

enum DS {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8

    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let subtleFill = Color.primary.opacity(0.05)
    static let border = Color.primary.opacity(0.08)
    static let divider = Color.primary.opacity(0.08)

    static let stateAnimation = Animation.easeInOut(duration: 0.2)
}

enum StatusTone: Equatable, Sendable {
    case connected
    case recording
    case connecting
    case warning
    case error
    case disconnected

    var color: Color {
        switch self {
        case .connected:
            return .green
        case .recording:
            return .blue
        case .connecting, .warning:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .secondary
        }
    }

    var isPulsing: Bool {
        self == .recording
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = DS.s16
    var isHighlighted: Bool = false
    var isDisabled: Bool = false
    @ViewBuilder var content: () -> Content

    init(
        padding: CGFloat = DS.s16,
        isHighlighted: Bool = false,
        isDisabled: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.isHighlighted = isHighlighted
        self.isDisabled = isDisabled
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.10) : DS.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Color.accentColor : DS.border,
                        lineWidth: isHighlighted ? 1.5 : 1
                    )
            )
            .opacity(isDisabled ? 0.55 : 1.0)
            .animation(DS.stateAnimation, value: isHighlighted)
            .animation(DS.stateAnimation, value: isDisabled)
    }
}

typealias KKCard = Card

struct CardDivider: View {
    init() {}

    var body: some View {
        Rectangle()
            .fill(DS.divider)
            .frame(height: 1)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.s8) {
            VStack(alignment: .leading, spacing: DS.s4) {
                HStack(spacing: DS.s8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DS.s8)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.init(title, subtitle: subtitle, systemImage: systemImage) {
            EmptyView()
        }
    }
}

struct StatusDot: View {
    let tone: StatusTone
    var size: CGFloat = 8
    var pulse: Bool? = nil
    @State private var animatePulse = false

    private var shouldPulse: Bool {
        pulse ?? tone.isPulsing
    }

    var body: some View {
        ZStack {
            if shouldPulse {
                Circle()
                    .fill(tone.color.opacity(0.32))
                    .frame(width: size * 2.1, height: size * 2.1)
                    .scaleEffect(animatePulse ? 1.15 : 0.75)
                    .opacity(animatePulse ? 0.15 : 0.65)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: animatePulse
                    )
            }
            Circle()
                .fill(tone.color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.1, height: size * 2.1)
        .onAppear {
            animatePulse = shouldPulse
        }
        .onChange(of: shouldPulse) { newValue in
            animatePulse = newValue
        }
    }
}

struct StatusPill: View {
    let title: String
    let tone: StatusTone
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(tone: tone, size: 7)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(tone.color)
            }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(tone.color.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tone.color.opacity(0.28), lineWidth: 1)
        )
        .animation(DS.stateAnimation, value: tone)
        .animation(DS.stateAnimation, value: title)
    }
}

struct LabeledRow<Content: View>: View {
    let label: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    init(
        _ label: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.s12) {
            HStack(spacing: DS.s8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: DS.s12)
            content()
        }
    }
}

struct PageScaffold<HeaderAccessory: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var scrollable: Bool = true
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        scrollable: Bool = true,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.scrollable = scrollable
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        Group {
            if scrollable {
                ScrollView {
                    innerBody
                }
            } else {
                innerBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.windowBackground)
    }

    private var innerBody: some View {
        VStack(alignment: .leading, spacing: DS.s20) {
            HStack(alignment: .center, spacing: DS.s16) {
                VStack(alignment: .leading, spacing: DS.s4) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: DS.s12)
                headerAccessory()
            }
            content()
        }
        .padding(DS.s24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension PageScaffold where HeaderAccessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        scrollable: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            scrollable: scrollable,
            headerAccessory: { EmptyView() },
            content: content
        )
    }
}
