import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var hoveredTab: SidebarTab? = nil

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 208)

            Rectangle()
                .fill(DS.divider)
                .frame(width: 1)

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, idealWidth: 960, maxWidth: .infinity, minHeight: 600, idealHeight: 680, maxHeight: .infinity)
        .background(DS.windowBackground)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Leave room for window traffic-light buttons in fullSizeContentView
            Spacer()
                .frame(height: 32)

            brandHeader
                .padding(.horizontal, DS.s16)
                .padding(.bottom, DS.s20)

            VStack(spacing: 6) {
                ForEach(SidebarTab.allCases) { tab in
                    sidebarRow(for: tab)
                }
            }
            .padding(.horizontal, DS.s12)

            Spacer()

            sidebarFooter
                .padding(DS.s12)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .opacity(0.65)
        )
    }

    private var brandHeader: some View {
        HStack(spacing: DS.s12) {
            AppLogoImage(size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("KKvoice")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
                Text("v\(model.appVersionString)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func sidebarRow(for tab: SidebarTab) -> some View {
        let isSelected = (model.selectedTab == tab)
        let isHovered = (hoveredTab == tab)

        return Button {
            withAnimation(DS.stateAnimation) {
                model.selectedTab = tab
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 20)

                Text(tab.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                Spacer()

                if tab == .connection && model.activePermissionIssue != nil {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.14)
                            : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.28) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
        }
        .help(tab.title)
        .accessibilityLabel(tab.title)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: DS.s8) {
            CardDivider()
                .padding(.bottom, 4)

            HStack(spacing: 6) {
                StatusPill(
                    title: model.connectionPhase.badgeTitle,
                    tone: model.connectionPhase.tone
                )
                Spacer(minLength: 0)
            }

            Text(model.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.selectedTab {
        case .connection:
            ConnectionView(model: model)
        case .mappings:
            ButtonMappingsView(model: model)
        case .snapNote:
            SnapNoteView(model: model)
        case .general:
            GeneralView(model: model)
        case .about:
            AboutView(model: model)
        }
    }
}
