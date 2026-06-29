import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case usage = "Usage"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
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
        case .usage:
            UsageSettingsView()
        // Billing removed in 11x local cockpit
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

struct SettingsUsageDetail: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

enum SettingsRecentUsageAmountStyle {
    case usage(BillingPlan?)
    case signedUsage(BillingPlan?)

    var detailLabel: String {
        switch self {
        case .usage:
            "Cost"
        case .signedUsage:
            "Spend"
        }
    }

    func text(for charge: BillingMessageCharge) -> String {
        guard charge.totalCredits != 0 else { return "Free" }
        switch self {
        case .usage(let plan):
            return BillingDisplay.usageAmount(for: charge.totalCredits, using: plan)
        case .signedUsage(let plan):
            return BillingDisplay.signedUsageAmount(for: charge.totalCredits, using: plan)
        }
    }
}

struct SettingsRecentUsageSection: View {
    let title: String
    let charges: [BillingMessageCharge]
    let limit: Int?
    let emptyMessage: String
    let amountStyle: SettingsRecentUsageAmountStyle

    @State private var expandedChargeIDs: Set<String> = []

    init(
        title: String = "Recent Usage",
        charges: [BillingMessageCharge],
        limit: Int? = 12,
        emptyMessage: String = "No usage yet.",
        amountStyle: SettingsRecentUsageAmountStyle
    ) {
        self.title = title
        self.charges = charges
        self.limit = limit
        self.emptyMessage = emptyMessage
        self.amountStyle = amountStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingMD) {
                Text(title)
                    .font(Theme.geist(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: Theme.spacingMD)

                if let summaryText {
                    Text(summaryText)
                        .font(Theme.geistMono(11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if charges.isEmpty {
                Text(emptyMessage)
                    .font(Theme.geist(13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedCharges.enumerated()), id: \.element.id) { index, charge in
                        recentUsageRow(charge)

                        if index < displayedCharges.count - 1 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                                .padding(.leading, Theme.spacingLG)
                        }
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingLG)
        .settingsPanelCard()
    }

    private func fallbackTitle(for charge: BillingMessageCharge) -> String {
        if charge.isImageGeneration {
            return "Image Generation"
        }
        return charge.taskType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var displayedCharges: [BillingMessageCharge] {
        guard let limit else { return charges }
        return Array(charges.prefix(limit))
    }

    private var summaryText: String? {
        guard !charges.isEmpty else { return nil }
        if let limit, charges.count > limit {
            return "\(displayedCharges.count) of \(charges.count) shown"
        }
        return "\(charges.count) recent"
    }

    private func recentUsageRow(_ charge: BillingMessageCharge) -> some View {
        let isExpanded = expandedChargeIDs.contains(charge.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    toggleExpansion(for: charge.id)
                }
            } label: {
                HStack(alignment: .top, spacing: Theme.spacingMD) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(charge.messagePreview ?? fallbackTitle(for: charge))
                            .font(Theme.geist(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(summaryText(for: charge))
                            .font(Theme.geist(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.spacingMD)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(amountStyle.text(for: charge))
                            .font(Theme.geistMono(12, weight: .semibold))
                            .foregroundStyle(charge.totalCredits == 0 ? Theme.accent : Theme.textPrimary)

                        HStack(spacing: 8) {
                            if showsCollapsedStatus(for: charge.primaryStatus) {
                                collapsedStatusLabel(for: charge.primaryStatus)
                            }

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, 10)

            if isExpanded {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .padding(.leading, Theme.spacingLG)

                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    ForEach(detailRows(for: charge)) { detail in
                        usageDetailRow(detail)
                    }
                }
                .padding(.horizontal, Theme.spacingLG)
                .padding(.vertical, Theme.spacingMD)
                .background(Theme.surfaceInset.opacity(0.35))
            }
        }
    }

    private func toggleExpansion(for id: String) {
        if expandedChargeIDs.contains(id) {
            expandedChargeIDs.remove(id)
        } else {
            expandedChargeIDs.insert(id)
        }
    }

    private func showsCollapsedStatus(for status: String) -> Bool {
        let normalized = status.lowercased()
        return !normalized.isEmpty && !["completed", "paid", "success", "succeeded"].contains(normalized)
    }

    private func collapsedStatusLabel(for status: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.billingStatusTint(status))
                .frame(width: 6, height: 6)

            Text(BillingDisplay.statusLabel(status))
                .font(Theme.geistMono(10, weight: .semibold))
                .foregroundStyle(Theme.billingStatusTint(status))
        }
    }

    private func usageDetailRow(_ detail: SettingsUsageDetail) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingLG) {
            Text(detail.label)
                .font(Theme.geistMono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            Spacer(minLength: Theme.spacingLG)

            Text(detail.value)
                .font(Theme.geist(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func summaryText(for charge: BillingMessageCharge) -> String {
        "\(BillingDisplay.dateTime(charge.createdAt)) • \(charge.summaryLabel)"
    }

    private func detailRows(for charge: BillingMessageCharge) -> [SettingsUsageDetail] {
        var details = [
            SettingsUsageDetail(label: "When", value: BillingDisplay.dateTime(charge.createdAt)),
            SettingsUsageDetail(label: "Task", value: charge.taskLabel),
            SettingsUsageDetail(label: "Status", value: charge.statusLabel),
            SettingsUsageDetail(label: amountStyle.detailLabel, value: amountStyle.text(for: charge))
        ]

        if let model = charge.model, !model.isEmpty {
            details.insert(SettingsUsageDetail(label: "Model", value: model), at: 2)
        }

        if charge.isImageGeneration {
            let count = charge.displayedImageCount
            details.append(
                SettingsUsageDetail(
                    label: "Images",
                    value: "\(BillingDisplay.integer(count)) image\(count == 1 ? "" : "s")"
                )
            )
        } else {
            details.append(SettingsUsageDetail(label: "Input", value: BillingDisplay.integer(charge.inputTokens)))
            details.append(SettingsUsageDetail(label: "Output", value: BillingDisplay.integer(charge.outputTokens)))
        }

        if charge.callCount > 1 {
            details.append(SettingsUsageDetail(label: "Calls", value: BillingDisplay.integer(charge.callCount)))
        }

        return details
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
