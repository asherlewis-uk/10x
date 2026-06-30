import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case provider = "Provider"
    case usage = "Usage"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .provider: "network"
        case .usage: "chart.bar"
        }
    }
}

struct SettingsView: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)
            content
        }
        .background(Theme.surface)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            ForEach(SettingsSection.allCases) { section in
                sidebarItem(section)
            }
            Spacer()
        }
        .padding(.vertical, Theme.spacingXXL)
        .padding(.leading, Theme.spacingXL)
        .padding(.trailing, Theme.spacingMD)
        .frame(width: 244, alignment: .leading)
        .background(Theme.surface)
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        isSelected ? Theme.accent : Theme.textSecondary
                    )
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(Theme.geist(13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected ? Theme.textPrimary : Theme.textSecondary
                    )

                Spacer()
            }
            .padding(.horizontal, Theme.spacingSM)
            .padding(.vertical, Theme.spacingSM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .fill(
                        isSelected
                            ? Theme.surfaceElevated
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .stroke(isSelected ? Theme.separator : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView()
        case .provider:
            ProviderSettingsView()
        case .usage:
            UsageSettingsView()
        }
    }
}

struct SettingsPageContainer<Content: View>: View {
    private let maxWidth: CGFloat
    private let content: Content

    init(maxWidth: CGFloat = 760, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXXL) {
                content
            }
            .padding(.horizontal, Theme.spacingXXL)
            .padding(.top, Theme.spacingXXL + Theme.spacingSM)
            .padding(.bottom, Theme.spacingXXL)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.surface)
    }
}

struct SettingsPageHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacingLG) {
            Text(title)
                .font(Theme.geist(32, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: Theme.spacingLG)

            trailing
        }
    }
}

extension SettingsPageHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) {
            EmptyView()
        }
    }
}

struct SettingsPanel<HeaderTrailing: View, Content: View>: View {
    private let title: String
    private let headerTrailing: HeaderTrailing
    private let content: Content

    init(_ title: String, @ViewBuilder headerTrailing: () -> HeaderTrailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            HStack(alignment: .center, spacing: Theme.spacingMD) {
                Text(title)
                    .font(Theme.geist(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: Theme.spacingMD)

                headerTrailing
            }

            content
        }
        .padding(Theme.spacingXL)
        .settingsPanelCard()
    }
}

extension SettingsPanel where HeaderTrailing == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, headerTrailing: { EmptyView() }, content: content)
    }
}

struct SettingsInsetRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }
}

struct SettingsMetricTile: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        SettingsInsetRow {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(Theme.geistMono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)

                Text(value)
                    .font(Theme.geist(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(detail)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsMetaChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.geistMono(11, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }
}

extension View {
    func settingsPanelCard(background: Color = Theme.surfaceElevated, radius: CGFloat = Theme.radiusMD) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }
}
