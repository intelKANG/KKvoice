import SwiftUI

/// Pure-SwiftUI illustration of the Chromecast with Google TV voice remote,
/// modeled after the physical hardware layout:
/// - Top large circular D-pad ring (`03` up, `04` down, `05` left, `06` right) + center OK (`07`)
/// - 2×3 circular buttons: Back (`0B`), Google Assistant (`voice`),
///   Home (`0A`), Mute (`08`), YouTube (`0E`), NETFLIX (`0F`)
/// - Bottom recessed horizontal groove: Power (`01`), status LED, Input (`11`)
/// - Right-edge volume rocker (`0C` volume +, `0D` volume -)
struct RemoteIllustration: View {
    var highlighted: String? = nil
    var compact: Bool = false
    var onTap: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredID: String? = nil

    // Canonical design coordinate space (with generous margin so shadows never clip)
    private static let canvasWidth: CGFloat = 176
    private static let canvasHeight: CGFloat = 512
    private static let bodyWidth: CGFloat = 148
    private static let bodyHeight: CGFloat = 476
    private static let bodyCenterX: CGFloat = 86
    private static let bodyTopY: CGFloat = 16

    /// Normalized anchor points (in 0...1 unit coordinates of the RemoteIllustration view)
    /// for connector lines on the ButtonMappingsView page.
    static func anchorPoint(for id: String) -> UnitPoint {
        let w = canvasWidth
        let h = canvasHeight
        let cx = bodyCenterX
        let dpadY = bodyTopY + 76

        let pt: CGPoint
        switch id {
        case "03": pt = CGPoint(x: cx, y: dpadY - 45)
        case "04": pt = CGPoint(x: cx, y: dpadY + 45)
        case "05": pt = CGPoint(x: cx - 45, y: dpadY)
        case "06": pt = CGPoint(x: cx + 45, y: dpadY)
        case "07": pt = CGPoint(x: cx, y: dpadY)
        case "0B": pt = CGPoint(x: cx - 31.5, y: bodyTopY + 190)
        case "voice": pt = CGPoint(x: cx + 31.5, y: bodyTopY + 190)
        case "0A": pt = CGPoint(x: cx - 31.5, y: bodyTopY + 250)
        case "08": pt = CGPoint(x: cx + 31.5, y: bodyTopY + 250)
        case "0E": pt = CGPoint(x: cx - 31.5, y: bodyTopY + 310)
        case "0F": pt = CGPoint(x: cx + 31.5, y: bodyTopY + 310)
        case "01": pt = CGPoint(x: cx - 37.5, y: bodyTopY + 368)
        case "11": pt = CGPoint(x: cx + 37.5, y: bodyTopY + 368)
        case "0C": pt = CGPoint(x: cx + bodyWidth / 2 + 2.5, y: bodyTopY + 124)
        case "0D": pt = CGPoint(x: cx + bodyWidth / 2 + 2.5, y: bodyTopY + 162)
        default: pt = CGPoint(x: cx, y: h / 2)
        }
        return UnitPoint(x: pt.x / w, y: pt.y / h)
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / Self.canvasWidth,
                geo.size.height / Self.canvasHeight
            )
            let offsetX = (geo.size.width - Self.canvasWidth * scale) / 2
            let offsetY = (geo.size.height - Self.canvasHeight * scale) / 2

            ZStack(alignment: .topLeading) {
                remoteCanvas(scale: scale)
            }
            .frame(width: Self.canvasWidth * scale, height: Self.canvasHeight * scale)
            .offset(x: offsetX, y: offsetY)
        }
        .aspectRatio(Self.canvasWidth / Self.canvasHeight, contentMode: .fit)
        .frame(
            width: compact ? 104 : 176,
            height: compact ? 302 : 512
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Google TV 语音遥控器")
    }

    @ViewBuilder
    private func remoteCanvas(scale: CGFloat) -> some View {
        let cx = Self.bodyCenterX * scale
        let topY = Self.bodyTopY * scale
        let bodyW = Self.bodyWidth * scale
        let bodyH = Self.bodyHeight * scale
        let dpadCenterY = (Self.bodyTopY + 76) * scale
        let dpadOuterR: CGFloat = 63.5 * scale
        let dpadInnerR: CGFloat = 24.5 * scale

        ZStack {
            // 1. Side volume rockers (tucked cleanly along the right edge of the pill body)
            sideVolumeButton(
                id: "0C",
                label: "音量＋",
                symbol: "+",
                centerX: (Self.bodyCenterX + Self.bodyWidth / 2 + 0.5) * scale,
                centerY: (Self.bodyTopY + 124) * scale,
                width: 8.5 * scale,
                height: 34 * scale,
                scale: scale
            )
            sideVolumeButton(
                id: "0D",
                label: "音量－",
                symbol: "−",
                centerX: (Self.bodyCenterX + Self.bodyWidth / 2 + 0.5) * scale,
                centerY: (Self.bodyTopY + 162) * scale,
                width: 8.5 * scale,
                height: 34 * scale,
                scale: scale
            )

            // 2. Main Pill Body
            ZStack {
                Capsule(style: .circular)
                    .fill(bodyGradient)
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.09),
                        radius: 8 * scale,
                        x: 0,
                        y: 4 * scale
                    )
                Capsule(style: .circular)
                    .strokeBorder(bodyRimGradient, lineWidth: 1.2 * scale)
                Capsule(style: .circular)
                    .strokeBorder(bodyOuterBorder, lineWidth: 0.9 * scale)
            }
            .frame(width: bodyW, height: bodyH)
            .position(x: cx, y: topY + bodyH / 2)

            // 3. Top Circular D-Pad Ring + Center OK
            dpadView(
                cx: cx,
                cy: dpadCenterY,
                outerR: dpadOuterR,
                innerR: dpadInnerR,
                scale: scale
            )

            // 4. 2x3 Grid of Round Buttons
            let leftX = (Self.bodyCenterX - 31.5) * scale
            let rightX = (Self.bodyCenterX + 31.5) * scale
            let roundDiameter = 46.5 * scale

            // Row 1: Back (0B) & Google Assistant (voice)
            roundSurfaceButton(
                id: "0B",
                accessibilityTitle: "返回",
                centerX: leftX,
                centerY: (Self.bodyTopY + 190) * scale,
                diameter: roundDiameter,
                scale: scale
            ) { fg in
                Image(systemName: "arrow.left")
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(fg)
            }

            assistantButton(
                centerX: rightX,
                centerY: (Self.bodyTopY + 190) * scale,
                diameter: roundDiameter,
                scale: scale
            )

            // Row 2: Home (0A) & Mute (08)
            roundSurfaceButton(
                id: "0A",
                accessibilityTitle: "Home",
                centerX: leftX,
                centerY: (Self.bodyTopY + 250) * scale,
                diameter: roundDiameter,
                scale: scale
            ) { fg in
                HomeHouseGlyph(scale: scale, color: fg)
            }

            roundSurfaceButton(
                id: "08",
                accessibilityTitle: "静音",
                centerX: rightX,
                centerY: (Self.bodyTopY + 250) * scale,
                diameter: roundDiameter,
                scale: scale
            ) { fg in
                MuteSpeakerXGlyph(scale: scale, color: fg)
            }

            // Row 3: YouTube (0E) & NETFLIX (0F)
            roundSurfaceButton(
                id: "0E",
                accessibilityTitle: "YouTube",
                centerX: leftX,
                centerY: (Self.bodyTopY + 310) * scale,
                diameter: roundDiameter,
                scale: scale
            ) { fg in
                Text("YouTube")
                    .font(.system(size: 9.0 * scale, weight: .heavy, design: .rounded))
                    .tracking(-0.3 * scale)
                    .foregroundStyle(fg)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            roundSurfaceButton(
                id: "0F",
                accessibilityTitle: "Netflix",
                centerX: rightX,
                centerY: (Self.bodyTopY + 310) * scale,
                diameter: roundDiameter,
                scale: scale
            ) { fg in
                Text("NETFLIX")
                    .font(.system(size: 8.6 * scale, weight: .black, design: .default))
                    .tracking(-0.15 * scale)
                    .foregroundStyle(fg)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            // 5. Bottom Recessed Horizontal Groove (Power 01 + LED + Input 11)
            bottomRecessedGroove(cx: cx, cy: (Self.bodyTopY + 368) * scale, scale: scale)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func dpadView(
        cx: CGFloat,
        cy: CGFloat,
        outerR: CGFloat,
        innerR: CGFloat,
        scale: CGFloat
    ) -> some View {
        let diameter = outerR * 2

        ZStack {
            // Base D-pad ring surface
            Circle()
                .fill(dpadRingGradient)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .strokeBorder(buttonStrokeColor, lineWidth: 1.0 * scale)
                )

            // 4 Directional Sectors (03 Up, 06 Right, 04 Down, 05 Left)
            dpadSector(
                id: "03",
                label: "方向上",
                startDegrees: -135,
                endDegrees: -45,
                outerR: outerR,
                innerR: innerR,
                dotOffset: CGPoint(x: 0, y: -(outerR + innerR) / 2),
                scale: scale
            )
            dpadSector(
                id: "06",
                label: "方向右",
                startDegrees: -45,
                endDegrees: 45,
                outerR: outerR,
                innerR: innerR,
                dotOffset: CGPoint(x: (outerR + innerR) / 2, y: 0),
                scale: scale
            )
            dpadSector(
                id: "04",
                label: "方向下",
                startDegrees: 45,
                endDegrees: 135,
                outerR: outerR,
                innerR: innerR,
                dotOffset: CGPoint(x: 0, y: (outerR + innerR) / 2),
                scale: scale
            )
            dpadSector(
                id: "05",
                label: "方向左",
                startDegrees: 135,
                endDegrees: 225,
                outerR: outerR,
                innerR: innerR,
                dotOffset: CGPoint(x: -(outerR + innerR) / 2, y: 0),
                scale: scale
            )

            // Center OK button (07)
            let okActive = isActive("07")
            let okHovered = isHovered("07")
            Circle()
                .fill(okActive ? Color.accentColor.opacity(0.24) : dpadCenterFill(hovered: okHovered))
                .frame(width: innerR * 2, height: innerR * 2)
                .overlay(
                    Circle()
                        .strokeBorder(
                            okActive ? Color.accentColor : buttonStrokeColor,
                            lineWidth: (okActive ? 2.0 : 1.0) * scale
                        )
                )
                .shadow(
                    color: okActive ? Color.accentColor.opacity(0.35) : .clear,
                    radius: 5 * scale
                )
                .contentShape(Circle())
                .onTapGesture {
                    onTap?("07")
                }
                .onHover { hovering in
                    if onTap != nil {
                        hoveredID = hovering ? "07" : (hoveredID == "07" ? nil : hoveredID)
                    }
                }
                .help("确认")
                .accessibilityLabel("确认")
                .accessibilityAddTraits(.isButton)
        }
        .frame(width: diameter, height: diameter)
        .position(x: cx, y: cy)
    }

    @ViewBuilder
    private func dpadSector(
        id: String,
        label: String,
        startDegrees: Double,
        endDegrees: Double,
        outerR: CGFloat,
        innerR: CGFloat,
        dotOffset: CGPoint,
        scale: CGFloat
    ) -> some View {
        let active = isActive(id)
        let hovered = isHovered(id)
        let sectorShape = AnnularSectorShape(
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            innerRadiusRatio: innerR / outerR
        )

        ZStack {
            sectorShape
                .fill(
                    active
                        ? Color.accentColor.opacity(0.25)
                        : (hovered ? Color.accentColor.opacity(0.10) : Color.clear)
                )
            if active || hovered {
                sectorShape
                    .stroke(
                        active ? Color.accentColor : Color.accentColor.opacity(0.45),
                        lineWidth: (active ? 2.0 : 1.2) * scale
                    )
            }
            if active {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5.5 * scale, height: 5.5 * scale)
                    .offset(x: dotOffset.x, y: dotOffset.y)
            }
        }
        .frame(width: outerR * 2, height: outerR * 2)
        .contentShape(sectorShape)
        .onTapGesture {
            onTap?(id)
        }
        .onHover { hovering in
            if onTap != nil {
                hoveredID = hovering ? id : (hoveredID == id ? nil : hoveredID)
            }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func roundSurfaceButton<Label: View>(
        id: String,
        accessibilityTitle: String,
        centerX: CGFloat,
        centerY: CGFloat,
        diameter: CGFloat,
        scale: CGFloat,
        @ViewBuilder label: (Color) -> Label
    ) -> some View {
        let active = isActive(id)
        let hovered = isHovered(id)
        let fg = active ? Color.accentColor : buttonGlyphColor

        ZStack {
            Circle()
                .fill(
                    active
                        ? Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.16)
                        : surfaceButtonFill(hovered: hovered)
                )
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .strokeBorder(
                            active ? Color.accentColor : buttonStrokeColor,
                            lineWidth: (active ? 2.0 : 1.0) * scale
                        )
                )
                .shadow(
                    color: active ? Color.accentColor.opacity(0.30) : Color.black.opacity(0.03),
                    radius: (active ? 5 : 1.5) * scale,
                    x: 0,
                    y: 1 * scale
                )

            label(fg)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onTapGesture {
            onTap?(id)
        }
        .onHover { hovering in
            if onTap != nil {
                hoveredID = hovering ? id : (hoveredID == id ? nil : hoveredID)
            }
        }
        .help(accessibilityTitle)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(.isButton)
        .position(x: centerX, y: centerY)
    }

    @ViewBuilder
    private func assistantButton(
        centerX: CGFloat,
        centerY: CGFloat,
        diameter: CGFloat,
        scale: CGFloat
    ) -> some View {
        let active = isActive("voice")
        let hovered = isHovered("voice")

        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.12, blue: 0.14),
                            Color(red: 0.04, green: 0.05, blue: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .strokeBorder(
                            active
                                ? Color.accentColor
                                : (hovered ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.16)),
                            lineWidth: (active ? 2.2 : 1.0) * scale
                        )
                )
                .shadow(
                    color: active ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.18),
                    radius: (active ? 6 : 2.5) * scale,
                    x: 0,
                    y: 1.5 * scale
                )

            // Iconic 4-dot Google Assistant cluster
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 9.4 * scale, height: 9.4 * scale)
                    .offset(x: -5.2 * scale, y: -1.1 * scale)

                Circle()
                    .fill(Color.white)
                    .frame(width: 4.5 * scale, height: 4.5 * scale)
                    .offset(x: 3.3 * scale, y: -4.3 * scale)

                Circle()
                    .fill(Color.white)
                    .frame(width: 5.5 * scale, height: 5.5 * scale)
                    .offset(x: 3.3 * scale, y: 3.7 * scale)

                Circle()
                    .fill(Color.white)
                    .frame(width: 2.6 * scale, height: 2.6 * scale)
                    .offset(x: 8.2 * scale, y: -1.1 * scale)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onTapGesture {
            onTap?("voice")
        }
        .onHover { hovering in
            if onTap != nil {
                hoveredID = hovering ? "voice" : (hoveredID == "voice" ? nil : hoveredID)
            }
        }
        .help("Google 助理（语音键）")
        .accessibilityLabel("Google 助理语音键")
        .accessibilityAddTraits(.isButton)
        .position(x: centerX, y: centerY)
    }

    @ViewBuilder
    private func bottomRecessedGroove(cx: CGFloat, cy: CGFloat, scale: CGFloat) -> some View {
        let grooveW = 104 * scale
        let grooveH = 30 * scale
        let btnDiameter = 25 * scale
        let powerX = cx - 37.5 * scale
        let inputX = cx + 37.5 * scale

        ZStack {
            // Recessed horizontal capsule groove
            Capsule(style: .continuous)
                .fill(recessedGrooveGradient)
                .frame(width: grooveW, height: grooveH)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(buttonStrokeColor.opacity(0.65), lineWidth: 0.8 * scale)
                )
                .position(x: cx, y: cy)

            // Center tiny indicator pill
            Capsule(style: .continuous)
                .fill(buttonGlyphColor.opacity(0.75))
                .frame(width: 7.2 * scale, height: 3.0 * scale)
                .position(x: cx, y: cy)

            // Left: Power button (01)
            roundSurfaceButton(
                id: "01",
                accessibilityTitle: "电源",
                centerX: powerX,
                centerY: cy,
                diameter: btnDiameter,
                scale: scale
            ) { fg in
                Image(systemName: "power")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(fg)
            }

            // Right: Input button (11)
            roundSurfaceButton(
                id: "11",
                accessibilityTitle: "信源",
                centerX: inputX,
                centerY: cy,
                diameter: btnDiameter,
                scale: scale
            ) { fg in
                InputSourceGlyph(scale: scale, color: fg)
            }
        }
    }

    @ViewBuilder
    private func sideVolumeButton(
        id: String,
        label: String,
        symbol: String,
        centerX: CGFloat,
        centerY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) -> some View {
        let active = isActive(id)
        let hovered = isHovered(id)

        ZStack {
            RoundedRectangle(cornerRadius: 3.5 * scale, style: .continuous)
                .fill(
                    active
                        ? Color.accentColor
                        : (hovered ? Color.accentColor.opacity(0.55) : sideRockerFill)
                )
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5 * scale, style: .continuous)
                        .strokeBorder(
                            active ? Color.accentColor : buttonStrokeColor,
                            lineWidth: (active ? 1.5 : 0.85) * scale
                        )
                )
                .shadow(
                    color: active ? Color.accentColor.opacity(0.35) : .clear,
                    radius: 4 * scale
                )
        }
        .frame(width: max(width, 18 * scale), height: height + 4 * scale)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?(id)
        }
        .onHover { hovering in
            if onTap != nil {
                hoveredID = hovering ? id : (hoveredID == id ? nil : hoveredID)
            }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .position(x: centerX, y: centerY)
    }

    // MARK: - Helpers & Palette

    private func isActive(_ id: String) -> Bool {
        highlighted?.uppercased() == id.uppercased()
    }

    private func isHovered(_ id: String) -> Bool {
        hoveredID?.uppercased() == id.uppercased()
    }

    private var bodyGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.24, blue: 0.28),
                    Color(red: 0.16, green: 0.18, blue: 0.21),
                    Color(red: 0.13, green: 0.14, blue: 0.17)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.99, blue: 0.995),
                    Color(red: 0.955, green: 0.96, blue: 0.97),
                    Color(red: 0.915, green: 0.922, blue: 0.935)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var bodyRimGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.20 : 0.90),
                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.25),
                Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bodyOuterBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.13)
    }

    private var dpadRingGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.21, blue: 0.25),
                    Color(red: 0.24, green: 0.26, blue: 0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.955, blue: 0.965),
                    Color(red: 0.985, green: 0.985, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func dpadCenterFill(hovered: Bool) -> Color {
        if hovered {
            return Color.accentColor.opacity(0.12)
        }
        return colorScheme == .dark
            ? Color(red: 0.22, green: 0.24, blue: 0.28)
            : Color(red: 0.975, green: 0.98, blue: 0.985)
    }

    private func surfaceButtonFill(hovered: Bool) -> Color {
        if hovered {
            return Color.accentColor.opacity(0.10)
        }
        return colorScheme == .dark
            ? Color(red: 0.23, green: 0.25, blue: 0.29)
            : Color(red: 0.985, green: 0.987, blue: 0.992)
    }

    private var recessedGrooveGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                    Color(red: 0.16, green: 0.18, blue: 0.21)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.875, green: 0.882, blue: 0.90),
                    Color(red: 0.945, green: 0.95, blue: 0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var sideRockerFill: Color {
        colorScheme == .dark
            ? Color(red: 0.27, green: 0.29, blue: 0.34)
            : Color(red: 0.86, green: 0.87, blue: 0.89)
    }

    private var buttonStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.28)
    }

    private var buttonGlyphColor: Color {
        colorScheme == .dark
            ? Color(red: 0.93, green: 0.94, blue: 0.96)
            : Color(red: 0.10, green: 0.11, blue: 0.13)
    }
}

// MARK: - Custom Shapes & Hardware Glyphs

private struct AnnularSectorShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRadiusRatio

        var path = Path()
        path.addArc(
            center: center,
            radius: outerR,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerR,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

/// Minimalist Google TV Home icon (solid pentagon house with a doorway notch at bottom center).
private struct HomeHouseGlyph: View {
    let scale: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()
            // Roof peak
            path.move(to: CGPoint(x: w * 0.50, y: h * 0.08))
            // Right eave
            path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.44))
            // Bottom right wall
            path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.92))
            // Doorway right side
            path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.60))
            // Doorway top
            path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.60))
            // Doorway left side
            path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.92))
            // Bottom left wall
            path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.92))
            // Left eave
            path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.44))
            path.closeSubpath()

            context.fill(path, with: .color(color))
        }
        .frame(width: 15.5 * scale, height: 15.5 * scale)
    }
}

/// Google TV Mute glyph: solid speaker cone on the left + crisp '×' mark on the right.
private struct MuteSpeakerXGlyph: View {
    let scale: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Speaker body + cone on the left
            var speaker = Path()
            speaker.move(to: CGPoint(x: w * 0.05, y: h * 0.36))
            speaker.addLine(to: CGPoint(x: w * 0.22, y: h * 0.36))
            speaker.addLine(to: CGPoint(x: w * 0.46, y: h * 0.14))
            speaker.addLine(to: CGPoint(x: w * 0.46, y: h * 0.86))
            speaker.addLine(to: CGPoint(x: w * 0.22, y: h * 0.64))
            speaker.addLine(to: CGPoint(x: w * 0.05, y: h * 0.64))
            speaker.closeSubpath()
            context.fill(speaker, with: .color(color))

            // '×' mark on the right
            var xmark = Path()
            let x1 = w * 0.58
            let x2 = w * 0.92
            let y1 = h * 0.31
            let y2 = h * 0.69
            xmark.move(to: CGPoint(x: x1, y: y1))
            xmark.addLine(to: CGPoint(x: x2, y: y2))
            xmark.move(to: CGPoint(x: x2, y: y1))
            xmark.addLine(to: CGPoint(x: x1, y: y2))

            context.stroke(
                xmark,
                with: .color(color),
                style: StrokeStyle(lineWidth: max(1.7 * scale, 1.1), lineCap: .round)
            )
        }
        .frame(width: 18.5 * scale, height: 15 * scale)
    }
}

/// Custom TV-input glyph matching the Chromecast remote's bottom-right Input button
/// (rounded screen box with an arrow entering from the left).
private struct InputSourceGlyph: View {
    let scale: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let strokeW = max(1.1 * scale, 1.0)

            let boxRect = CGRect(
                x: w * 0.18,
                y: h * 0.16,
                width: w * 0.68,
                height: h * 0.68
            )
            let boxPath = Path(roundedRect: boxRect, cornerRadius: 2.2 * scale)
            context.stroke(boxPath, with: .color(color), lineWidth: strokeW)

            var arrow = Path()
            let midY = h * 0.50
            arrow.move(to: CGPoint(x: w * 0.08, y: midY))
            arrow.addLine(to: CGPoint(x: w * 0.56, y: midY))
            arrow.move(to: CGPoint(x: w * 0.42, y: midY - h * 0.17))
            arrow.addLine(to: CGPoint(x: w * 0.57, y: midY))
            arrow.addLine(to: CGPoint(x: w * 0.42, y: midY + h * 0.17))

            context.stroke(
                arrow,
                with: .color(color),
                style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 12 * scale, height: 10 * scale)
    }
}
