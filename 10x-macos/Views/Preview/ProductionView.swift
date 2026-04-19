import SwiftUI

struct ProductionView: View {
    @Environment(BuilderViewModel.self) private var viewModel

    @State private var selectedTab: PublishingTab = .docs
    @State private var checklistState: ProductionChecklistState = .empty
    @State private var checklistStatusMessage: String?
    @State private var latestChecklistSaveID = UUID()
    private var publishingModeOptions: [PreviewModeSwitcherOption<PublishingTab>] {
        PublishingTab.allCases.map { tab in
            PreviewModeSwitcherOption(
                value: tab,
                title: tab.title,
                iconName: tab.iconName
            )
        }
    }

    private enum PublishingTab: String, CaseIterable {
        case docs
        case checklist

        var title: String {
            switch self {
            case .docs:
                return "Docs"
            case .checklist:
                return "Checklist"
            }
        }

        var iconName: String {
            switch self {
            case .docs:
                return "doc.text"
            case .checklist:
                return "checkmark.circle"
            }
        }
    }

    var body: some View {
        let guide = viewModel.productionGuide

        VStack(spacing: 0) {
            fixedTabBar

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingXXL) {
                    switch selectedTab {
                    case .docs:
                        docsContent(guide)
                    case .checklist:
                        checklistContent
                    }
                }
                .padding(.horizontal, Theme.spacingXXL)
                .padding(.top, Theme.spacingXL)
                .padding(.bottom, Theme.spacingXXL)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(Theme.surfaceInset)
        .onAppear {
            syncChecklistState(clearStatus: true)
        }
        .onChange(of: viewModel.activeProject?.id) { _, _ in
            syncChecklistState(clearStatus: true)
        }
        .onChange(of: viewModel.productionChecklistState) { _, _ in
            syncChecklistState(clearStatus: false)
        }
    }

    private var checklistProgress: (completed: Int, total: Int, ratio: Double) {
        let sections = viewModel.productionChecklistSections
        let total = sections.reduce(0) { partial, section in
            partial + section.items.count
        }
        let completed = sections.reduce(0) { partial, section in
            partial + section.items.filter { checklistState.isChecked($0.id) }.count
        }
        let ratio = total > 0 ? Double(completed) / Double(total) : 0
        return (completed, total, ratio)
    }

    private var fixedTabBar: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                publishingModePicker
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.spacingXL)
            .padding(.top, Theme.spacingLG)
            .padding(.bottom, Theme.spacingMD)

            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
        }
        .background(Theme.surfaceInset)
    }

    private var publishingModePicker: some View {
        PreviewModeSwitcher(
            selection: Binding(
                get: { selectedTab },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = newValue
                    }
                }
            ),
            options: publishingModeOptions
        )
    }

    private func docsContent(_ guide: ProductionGuide) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingXXL) {
            minimalIntro(guide)
            productionFlowSection

            ForEach(Array(guide.sections.enumerated()), id: \.element.id) { index, section in
                if section.id == "stack" {
                    providerComparisonSection(section)
                } else {
                    guideSection(section)
                }

                if index < guide.sections.count - 1 {
                    contentDivider
                }
            }

            productionDocNote
        }
    }

    private func minimalIntro(_ guide: ProductionGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guide.title)
                .font(Theme.geist(28, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(guide.summary)
                .font(Theme.geist(15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var productionFlowSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            sectionLabel(title: "Suggested Production Flow", icon: "point.3.connected.trianglepath.dotted")

            Text("Keep the app thin. Let the backend own secrets and business rules. Let your data layer own auth, storage, and durable state.")
                .font(Theme.geist(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                flowLine(title: "Primary path", steps: ["iOS app", "backend", "providers"])
                flowLine(title: "Data path", steps: ["iOS app", "Supabase", "auth + data + storage"])
            }
        }
    }

    private func flowLine(title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.geistMono(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            HStack(alignment: .center, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Text(step)
                        .font(Theme.geist(13, weight: .medium))
                        .foregroundStyle(index == steps.count - 1 ? Theme.textPrimary : Theme.textSecondary)
                }
            }
        }
    }

    private func providerComparisonSection(_ section: ProductionGuideSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingMD) {
                sectionLabel(title: section.title, icon: section.icon)
                Spacer(minLength: 0)
                Text("Pick the smallest backend surface")
                    .font(Theme.geist(11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(section.summary)
                .font(Theme.geist(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230, maximum: 280), alignment: .top)],
                alignment: .leading,
                spacing: Theme.spacingXL
            ) {
                ForEach(section.modules) { module in
                    providerColumn(module)
                }
            }
        }
    }

    private func providerColumn(_ module: ProductionGuideModule) -> some View {
        let accent = providerAccent(for: module.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)

                Text(module.title)
                    .font(Theme.geist(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            if let tag = providerTag(for: module.id) {
                Text(tag)
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(module.summary)
                .font(Theme.geist(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(module.bullets.enumerated()), id: \.offset) { bullet in
                    bulletRow(text: bullet.element)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerAccent(for moduleID: String) -> Color {
        switch moduleID {
        case "vercel":
            return Color(hex: "4D8DFF")
        case "supabase":
            return Theme.accent
        case "managed-backend":
            return Color(hex: "2DBA7F")
        case "both":
            return Theme.warning
        default:
            return Theme.textSecondary
        }
    }

    private func providerTag(for moduleID: String) -> String? {
        switch moduleID {
        case "managed-backend":
            return "10x-managed path"
        case "both":
            return "Add only if needed"
        default:
            return nil
        }
    }

    private func guideSection(_ section: ProductionGuideSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            sectionLabel(title: section.title, icon: section.icon)

            Text(section.summary)
                .font(Theme.geist(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(section.modules.enumerated()), id: \.element.id) { index, module in
                moduleBlock(module)

                if index < section.modules.count - 1 {
                    contentDivider
                }
            }
        }
    }

    private func moduleBlock(_ module: ProductionGuideModule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(module.title)
                .font(Theme.geist(17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(module.summary)
                .font(Theme.geist(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !module.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(module.bullets.enumerated()), id: \.offset) { bullet in
                        bulletRow(text: bullet.element)
                    }
                }
            }

            if let codeBlock = module.codeBlock, !codeBlock.isEmpty {
                Text(codeBlock)
                    .font(Theme.geistMono(12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .textSelection(.enabled)
            }
        }
    }

    private func bulletRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.accent.opacity(0.85))
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            Text(text)
                .font(Theme.geist(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(Theme.geist(18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var checklistContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXXL) {
            checklistSummary

            ForEach(Array(viewModel.productionChecklistSections.enumerated()), id: \.element.id) { index, section in
                checklistSection(section)

                if index < viewModel.productionChecklistSections.count - 1 {
                    contentDivider
                }
            }
        }
    }

    private var checklistSummary: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingMD) {
                Text("Launch Readiness Checklist")
                    .font(Theme.geist(28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                Text("\(checklistProgress.completed)/\(checklistProgress.total)")
                    .font(Theme.geistMono(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text("Check off what is actually ready. Progress saves automatically for this project.")
                .font(Theme.geist(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 2)

                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * checklistProgress.ratio, height: 2)
                }
            }
            .frame(height: 2)

            if let checklistStatusMessage {
                Text(checklistStatusMessage)
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func checklistSection(_ section: ProductionChecklistSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            Text(section.title)
                .font(Theme.geist(18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(section.summary)
                .font(Theme.geist(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.spacingMD) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    checklistItemRow(item)

                    if index < section.items.count - 1 {
                        contentDivider
                    }
                }
            }
        }
    }

    private func checklistItemRow(_ item: ProductionChecklistItem) -> some View {
        let isChecked = checklistState.isChecked(item.id)

        return Button {
            updateChecklist(itemID: item.id, isChecked: !isChecked)
        } label: {
            HStack(alignment: .top, spacing: Theme.spacingMD) {
                ZStack {
                    Circle()
                        .fill(isChecked ? Theme.accent : Color.clear)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(isChecked ? Theme.accent : Theme.textTertiary.opacity(0.45), lineWidth: 1.2)
                        )

                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.86))
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(item.detail)
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .opacity(isChecked ? 0.92 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var productionDocNote: some View {
        Text("This documentation is also written to `PRODUCTION.md` in the project root.")
            .font(Theme.geistMono(10, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var contentDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
    }

    private func syncChecklistState(clearStatus: Bool) {
        checklistState = viewModel.productionChecklistState
        if clearStatus {
            checklistStatusMessage = nil
        }
    }

    private func updateChecklist(itemID: String, isChecked: Bool) {
        var nextState = checklistState
        nextState.setChecked(isChecked, for: itemID)
        checklistState = nextState
        checklistStatusMessage = "Saving..."

        let saveID = UUID()
        latestChecklistSaveID = saveID
        let snapshot = nextState

        Task {
            await viewModel.saveProductionChecklistState(snapshot)
            await MainActor.run {
                guard latestChecklistSaveID == saveID else { return }
                checklistStatusMessage = "Saved to this project"
            }
        }
    }
}
