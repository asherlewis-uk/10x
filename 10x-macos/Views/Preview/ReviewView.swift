import AppKit
import SwiftUI

struct ReviewView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @State private var editableDraft: AppStoreSubmissionDraft = .empty
    @State private var selectedLegalDocument: LegalDocumentTab = .privacy
    @State private var isDescriptionCopied = false

    fileprivate enum LegalDocumentTab: String, CaseIterable, Identifiable {
        case privacy
        case terms
        case support

        var id: Self { self }

        var title: String {
            switch self {
            case .privacy:
                return "Privacy"
            case .terms:
                return "Terms"
            case .support:
                return "Support"
            }
        }

        var pathComponent: String {
            switch self {
            case .privacy:
                return "privacy"
            case .terms:
                return "terms"
            case .support:
                return "support"
            }
        }
    }

    private var projectName: String {
        viewModel.activeProject?.name ?? "Untitled"
    }

    private var displayedIcon: NSImage? {
        if let path = viewModel.appStoreReviewState.icon?.relativeImagePath {
            return viewModel.appStoreReviewImage(for: path) ?? viewModel.projectIcon
        }
        return viewModel.projectIcon
    }

    private var descriptionText: String {
        for value in [
            viewModel.appStoreReviewState.description?.spec.fullDescription,
            viewModel.activeProject?.description,
        ] {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private var appStoreDescriptionPreviewText: String {
        descriptionText
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { return line }
                let normalized = trimmed
                    .drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reviewStatusMessage: String? {
        viewModel.appStoreReviewError ?? viewModel.appStoreReviewStatus
    }

    private var submissionStatusMessage: String? {
        viewModel.appStoreSubmissionError ?? viewModel.appStoreSubmissionStatus
    }

    private var reviewStatusColor: Color {
        viewModel.appStoreReviewError == nil ? Theme.textSecondary : Theme.error
    }

    private var submissionStatusColor: Color {
        viewModel.appStoreSubmissionError == nil ? Theme.textSecondary : Theme.error
    }

    private var publishBlockers: [String] {
        let normalized = editableDraft.normalized(projectName: projectName)
        return normalized.publishBlockers()
    }

    private var isSlugLocked: Bool {
        !(viewModel.appStoreSubmissionDraft.publish.lastPublishedSlug ?? "").isEmpty
    }

    private var publishPaths: [(label: String, url: URL?)] {
        [
            ("Privacy", editableHostedURL(kind: "privacy")),
            ("Terms", editableHostedURL(kind: "terms")),
            ("Support", editableHostedURL(kind: "support")),
        ]
    }

    private var hasGeneratedReviewAssets: Bool {
        viewModel.appStoreReviewState.icon != nil
            || viewModel.appStoreReviewState.description != nil
            || !viewModel.appStoreReviewState.screenshots.isEmpty
    }

    private var hasGeneratedLegalDrafts: Bool {
        editableDraft.generated.privacy.hasContent
            || editableDraft.generated.terms.hasContent
            || editableDraft.generated.support.hasContent
    }

    private var screenshotCount: Int {
        viewModel.appStoreReviewState.screenshots.count
    }

    private var selectedLegalDocumentBinding: Binding<AppStoreGeneratedDocument> {
        switch selectedLegalDocument {
        case .privacy:
            binding(for: \.generated.privacy)
        case .terms:
            binding(for: \.generated.terms)
        case .support:
            binding(for: \.generated.support)
        }
    }

    private var selectedHostedURL: URL? {
        editableHostedURL(kind: selectedLegalDocument.pathComponent)
    }

    private var descriptionCharacterCount: Int {
        editableDraft.generated.metadata.appStoreDescription.count
    }

    private var promotionalCharacterCount: Int {
        editableDraft.generated.metadata.promotionalText.count
    }

    private var keywordCharacterCount: Int {
        editableDraft.generated.metadata.keywordString.count
    }

    private var reviewNotesCount: Int {
        editableDraft.generated.metadata.reviewNotes.count
    }

    private var confirmedFieldCount: Int {
        editableDraft.confirmations.confirmedFields.values.filter { $0 }.count
    }

    private var generatedDocumentCount: Int {
        [
            editableDraft.generated.privacy.hasContent,
            editableDraft.generated.terms.hasContent,
            editableDraft.generated.support.hasContent,
        ]
        .filter { $0 }
        .count
    }

    private var submissionLimitWarnings: [String] {
        var warnings: [String] = []
        if promotionalCharacterCount > 170 {
            warnings.append("Promotional text is over Apple’s 170 character limit.")
        }
        if keywordCharacterCount > 100 {
            warnings.append("Keywords are over Apple’s 100 character limit.")
        }
        if descriptionCharacterCount > 4000 {
            warnings.append("Description is unusually long and may be hard to review quickly.")
        }
        return warnings
    }

    private var generatedWarnings: [String] {
        editableDraft.generated.warnings
    }

    private var publishStatusTitle: String {
        editableDraft.publish.isPublished ? "Published" : "Draft"
    }

    private var publishStatusTint: Color {
        editableDraft.publish.isPublished ? Theme.accent : Theme.textSecondary
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.spacingXL) {
                    assetsContent
                }
                .padding(.horizontal, Theme.spacingXXL)
                .padding(.top, Theme.spacingXL)
                .padding(.bottom, Theme.spacingXL)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(minHeight: max(proxy.size.height, 520), alignment: .top)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(Theme.surfaceInset)
        .task(id: viewModel.activeProject?.id) {
            syncEditableDraftFromViewModel()
        }
        .onChange(of: viewModel.appStoreSubmissionDraft) { _, _ in
            syncEditableDraftFromViewModel()
        }
    }

    private var assetsContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            if hasGeneratedReviewAssets {
                assetsSection
            } else {
                CenteredGenerationState(
                    title: "No App Store assets yet",
                    detail: "Generate the icon, description, and screenshots when you’re ready.",
                    primaryTitle: viewModel.isGeneratingAppStoreReviewAssets ? "Generating…" : "Auto-Generate",
                    secondaryTitle: "Update",
                    primaryAction: triggerAssetGeneration,
                    secondaryAction: triggerAssetGeneration,
                    statusMessage: reviewStatusMessage,
                    statusColor: reviewStatusColor,
                    isRunning: viewModel.isGeneratingAppStoreReviewAssets
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 520, alignment: .top)
    }

    private var legalContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            if hasGeneratedLegalDrafts {
                legalSection
            } else {
                CenteredGenerationState(
                    title: "No legal drafts yet",
                    detail: "Generate privacy, terms, and support pages from the project automatically.",
                    primaryTitle: viewModel.isGeneratingAppStoreSubmission ? "Generating…" : "Auto-Generate",
                    secondaryTitle: "Update",
                    primaryAction: triggerLegalGeneration,
                    secondaryAction: triggerLegalGeneration,
                    statusMessage: submissionStatusMessage,
                    statusColor: submissionStatusColor,
                    isRunning: viewModel.isGeneratingAppStoreSubmission
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 520, alignment: .top)
    }

    private var assetsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                compactAssetsSummary
                    .frame(width: 520)
                compactAssetsPreview
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                compactAssetsSummary
                compactAssetsPreview
            }
        }
    }

    private var legalSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                compactLegalSidebar
                    .frame(width: 360)
                compactLegalWorkspace
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                compactLegalSidebar
                compactLegalWorkspace
            }
        }
    }

    private var compactAssetsSummary: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.spacingLG) {
                    compactAssetsIdentity
                    Spacer(minLength: Theme.spacingSM)
                    compactAssetsActionGroup
                }

                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    compactAssetsIdentity

                    HStack {
                        Spacer(minLength: 0)
                        compactAssetsActionGroup
                    }
                }
            }

            if let reviewStatusMessage, !reviewStatusMessage.isEmpty {
                HStack(spacing: Theme.spacingXS) {
                    if viewModel.isGeneratingAppStoreReviewAssets {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(reviewStatusMessage)
                        .font(Theme.geist(12))
                        .foregroundStyle(reviewStatusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .appStorePanel()
    }

    private var compactAssetsIdentity: some View {
        HStack(alignment: .center, spacing: Theme.spacingMD) {
            Group {
                if let displayedIcon {
                    Image(nsImage: displayedIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.surface)
                        Image(systemName: "app.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(projectName)
                    .font(Theme.geist(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text("Icon, description, and screenshots in one place.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var compactAssetsActionGroup: some View {
        VStack(alignment: .trailing, spacing: Theme.spacingSM) {
            Button {
                triggerAssetGeneration()
            } label: {
                Label(
                    viewModel.isGeneratingAppStoreReviewAssets
                        ? "Generating…"
                        : (hasGeneratedReviewAssets ? "Update Assets" : "Auto-Generate"),
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isGeneratingAppStoreReviewAssets)

            HStack(spacing: Theme.spacingSM) {
                Button {
                    viewModel.revealAppStoreReviewAssetsInFinder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasExportedAppStoreReviewAssets)

                Button {
                    Task { await viewModel.exportAppStoreReviewAssetsZip() }
                } label: {
                    Label("Export ZIP", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.hasExportedAppStoreReviewAssets || viewModel.isGeneratingAppStoreReviewAssets)
            }
            .controlSize(.small)
        }
    }

    private var compactAssetsPreview: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .top, spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview")
                        .font(Theme.geist(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Quick visual QA with screenshots first, then the full App Store description.")
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                HStack {
                    Text("Screenshots")
                        .font(Theme.geist(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(screenshotCount)")
                        .font(Theme.geistMono(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                if viewModel.appStoreReviewState.screenshots.isEmpty {
                    Text("No screenshots yet.")
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Theme.spacingMD) {
                            ForEach(viewModel.appStoreReviewState.screenshots) { screenshot in
                                ReviewScreenshotCarouselCard(
                                    image: viewModel.appStoreReviewImage(for: screenshot.relativeImagePath)
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 320, maxHeight: 360)
                }
            }

            Divider()
                .overlay(Theme.separator)

            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                HStack(alignment: .top, spacing: Theme.spacingSM) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Full Description")
                            .font(Theme.geist(11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text("App Store-style markdown preview with short paragraphs and compact lists.")
                            .font(Theme.geist(11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !appStoreDescriptionPreviewText.isEmpty {
                        Button {
                            copyDescriptionToPasteboard()
                        } label: {
                            Label(
                                isDescriptionCopied ? "Copied" : "Copy Description",
                                systemImage: isDescriptionCopied ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(isDescriptionCopied ? Theme.success : Theme.accent)
                    }
                }

                if appStoreDescriptionPreviewText.isEmpty {
                    Text("No App Store description yet.")
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    MarkdownTextView(text: appStoreDescriptionPreviewText, animateTransitions: false)
                }
            }
        }
        .appStorePanel()
        .frame(minHeight: 500, alignment: .top)
    }

    private var compactLegalSidebar: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            compactLegalActionsPanel
            compactLegalFactsPanel
            compactLegalChecksPanel

            if editableDraft.publish.isPublished || !editableDraft.publish.publicSlug.isEmpty {
                compactHostedPagesPanel
            }
        }
    }

    private var compactLegalActionsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .center, spacing: Theme.spacingSM) {
                statusPill(title: publishStatusTitle, tint: publishStatusTint)
                Spacer()
                CompactMetricBadge(
                    title: "Blockers",
                    value: "\(publishBlockers.count)",
                    tint: publishBlockers.isEmpty ? Theme.accent : Theme.error
                )
            }

            HStack(spacing: Theme.spacingSM) {
                CompactMetricBadge(title: "Docs", value: "\(generatedDocumentCount)/3", tint: generatedDocumentCount == 3 ? Theme.accent : Theme.warning)
                CompactMetricBadge(title: "Checks", value: "\(confirmedFieldCount)", tint: Theme.textPrimary)
            }

            if let submissionStatusMessage, !submissionStatusMessage.isEmpty {
                HStack(spacing: Theme.spacingXS) {
                    if viewModel.isGeneratingAppStoreSubmission || viewModel.isPublishingAppStoreSubmission {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(submissionStatusMessage)
                        .font(Theme.geist(12))
                        .foregroundStyle(submissionStatusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !publishBlockers.isEmpty || !generatedWarnings.isEmpty {
                CompactIssueSummary(
                    blockers: publishBlockers,
                    warnings: generatedWarnings
                )
            }

            Button {
                triggerLegalGeneration()
            } label: {
                Label(
                    viewModel.isGeneratingAppStoreSubmission
                        ? "Generating…"
                        : (hasGeneratedLegalDrafts ? "Update Drafts" : "Auto-Generate"),
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isGeneratingAppStoreSubmission)

            HStack(spacing: Theme.spacingSM) {
                Menu {
                    Button("Refresh Facts") {
                        editableDraft.facts = viewModel.collectAppStoreSubmissionFacts()
                    }
                    Button("Save Draft") {
                        Task { await persistEditableDraft() }
                    }
                    Button("Export Packet") {
                        exportSubmissionPacket()
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Text("Hosted publishing is not available in 11x. Use local export instead.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .controlSize(.small)
        }
        .appStorePanel()
    }

    private var compactLegalFactsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            panelHeading("Public Facts", detail: "Optional metadata for local App Store submission notes.")

            LabeledField("Company Name", text: $editableDraft.facts.companyName)
            LabeledField("Support Email", text: $editableDraft.facts.supportEmail)
            LabeledField("Website URL", text: $editableDraft.facts.websiteURL)
            LabeledField(
                "Public Slug",
                text: $editableDraft.publish.publicSlug,
                helper: isSlugLocked ? "Locked after first publish." : "Not used for hosted pages in 11x local cockpit.",
                disabled: isSlugLocked
            )
        }
        .appStorePanel()
    }

    private var compactLegalChecksPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            panelHeading("Checks", detail: "Minimal inputs that affect policy accuracy and publish readiness.")

            CompactToggleRow(title: "Accounts", detail: "Users sign in or keep an account.", isOn: $editableDraft.facts.usesAccounts)
            CompactToggleRow(title: "Subscriptions", detail: "The app sells paid access.", isOn: $editableDraft.facts.usesSubscriptions)
            CompactToggleRow(title: "Tracking", detail: "ATT-relevant tracking or ad tech.", isOn: $editableDraft.facts.usesTracking)

            Divider()
                .overlay(Theme.separator)

            CompactConfirmationRow(title: "Support", detail: "Support contact is correct.", key: "support_contact", confirmations: $editableDraft.confirmations)
            CompactConfirmationRow(title: "Privacy", detail: "Privacy claims are accurate.", key: "privacy_claims", confirmations: $editableDraft.confirmations)
            CompactConfirmationRow(title: "Tracking", detail: "Tracking disclosures are accurate.", key: "tracking_claims", confirmations: $editableDraft.confirmations)
            CompactConfirmationRow(title: "Age Rating", detail: "Age-rating guidance is ready.", key: "age_rating", confirmations: $editableDraft.confirmations)
        }
        .appStorePanel()
    }

    private var compactHostedPagesPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            panelHeading("Hosted Pages", detail: "Not available in 11x local cockpit.")

            Text("Hosted publishing is not available in 11x. Use local export instead.")
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appStorePanel()
    }

    private var compactLegalWorkspace: some View {
        FocusedLegalDocumentWorkspace(
            selection: $selectedLegalDocument,
            document: selectedLegalDocumentBinding,
            liveURL: selectedHostedURL,
            onCopy: copyToPasteboard
        )
        .frame(minHeight: 620, alignment: .top)
    }

    private var hostedPagesSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            panelHeading("Hosted Pages", detail: "Not available in 11x local cockpit.")

            Text("Hosted publishing is not available in 11x. Use local export instead.")
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appStorePanel()
    }

    private var assetHeader: some View {
        HStack(alignment: .center, spacing: Theme.spacingLG) {
            Group {
                if let displayedIcon {
                    Image(nsImage: displayedIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Theme.surface)
                        Image(systemName: "app.fill")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                Text(projectName)
                    .font(Theme.geist(28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.spacingSM) {
                    Button {
                        triggerAssetGeneration()
                    } label: {
                        Label(hasGeneratedReviewAssets ? "Update Assets" : "Auto-Generate", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isGeneratingAppStoreReviewAssets)
                    .help("Send a generation request to the agent. If another task is in progress, it will be queued.")

                    Button {
                        viewModel.revealAppStoreReviewAssetsInFinder()
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasExportedAppStoreReviewAssets)

                    Button {
                        Task { await viewModel.exportAppStoreReviewAssetsZip() }
                    } label: {
                        Label("Export ZIP", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasExportedAppStoreReviewAssets || viewModel.isGeneratingAppStoreReviewAssets)
                }
                .controlSize(.small)

                if let reviewStatusMessage, !reviewStatusMessage.isEmpty {
                    Text(reviewStatusMessage)
                        .font(Theme.geist(12))
                        .foregroundStyle(reviewStatusColor)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Description")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            Group {
                if descriptionText.isEmpty {
                    Text("No App Store description yet.")
                        .font(Theme.geist(14))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    MarkdownTextView(text: descriptionText, animateTransitions: false)
                }
            }
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }

    private var screenshotsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Screenshots")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            Group {
                if viewModel.appStoreReviewState.screenshots.isEmpty {
                    Text("No App Store screenshots yet.")
                        .font(Theme.geist(14))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Theme.spacingMD) {
                            ForEach(viewModel.appStoreReviewState.screenshots) { screenshot in
                                ReviewScreenshotCarouselCard(
                                    image: viewModel.appStoreReviewImage(for: screenshot.relativeImagePath)
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }

    private var inferredSignalsSection: some View {
        let facts = editableDraft.facts.normalized
        return VStack(alignment: .leading, spacing: Theme.spacingSM) {
            panelHeading("Inferred Signals", detail: "Pulled from the project so you don’t have to re-enter obvious facts.")

            SignalRow(label: "Bundle ID", value: facts.bundleIdentifier)
            SignalRow(label: "Backend", value: facts.backendProvider)
            SignalRow(label: "Auth", value: facts.authProvider)
            SignalRow(label: "Integrated Services", value: facts.integratedServices.joined(separator: ", "))
            SignalRow(
                label: "Permissions",
                value: facts.permissionUsageDescriptions.keys.sorted().joined(separator: ", ")
            )
            SignalRow(label: "Entitlements", value: facts.entitlementKeys.joined(separator: ", "))
            SignalRow(label: "Required Reason APIs", value: facts.requiredReasonAPIs.joined(separator: ", "))

            if !facts.inferenceNotes.isEmpty {
                Divider()
                    .overlay(Theme.separator)
                    .padding(.vertical, Theme.spacingSM)

                ForEach(facts.inferenceNotes, id: \.self) { note in
                    Text(note)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .appStorePanel()
    }

    private var detailsToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.spacingMD) {
                statusPill(
                    title: publishStatusTitle,
                    tint: publishStatusTint
                )

                if let submissionStatusMessage, !submissionStatusMessage.isEmpty {
                    Text(submissionStatusMessage)
                        .font(Theme.geist(12))
                        .foregroundStyle(submissionStatusColor)
                        .lineLimit(2)
                }

                Spacer()

                Button("Save Draft") {
                    Task { await persistEditableDraft() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task {
                        await persistEditableDraft()
                        await viewModel.exportAppStoreSubmissionPacket()
                    }
                } label: {
                    Label("Export Packet", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                statusPill(
                    title: publishStatusTitle,
                    tint: publishStatusTint
                )
                if let submissionStatusMessage, !submissionStatusMessage.isEmpty {
                    Text(submissionStatusMessage)
                        .font(Theme.geist(12))
                        .foregroundStyle(submissionStatusColor)
                }
                HStack(spacing: Theme.spacingSM) {
                    Button("Save Draft") {
                        Task { await persistEditableDraft() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await persistEditableDraft()
                            await viewModel.exportAppStoreSubmissionPacket()
                        }
                    } label: {
                        Label("Export Packet", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private var legalToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.spacingMD) {
                statusPill(
                    title: publishStatusTitle,
                    tint: publishStatusTint
                )

                if let submissionStatusMessage, !submissionStatusMessage.isEmpty {
                    Text(submissionStatusMessage)
                        .font(Theme.geist(12))
                        .foregroundStyle(submissionStatusColor)
                        .lineLimit(2)
                }

                Spacer()

                Button("Refresh Facts") {
                    editableDraft.facts = viewModel.collectAppStoreSubmissionFacts()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save Draft") {
                    Task { await persistEditableDraft() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task {
                        await persistEditableDraft()
                        await viewModel.exportAppStoreSubmissionPacket()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task {
                        await persistEditableDraft()
                        await viewModel.generateAppStoreSubmissionDrafts()
                        syncEditableDraftFromViewModel()
                    }
                } label: {
                    Label(hasGeneratedLegalDrafts ? "Update Drafts" : "Auto-Generate", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isGeneratingAppStoreSubmission)

                Text("Hosted publishing is not available in 11x. Use local export instead.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                statusPill(
                    title: publishStatusTitle,
                    tint: publishStatusTint
                )

                if let submissionStatusMessage, !submissionStatusMessage.isEmpty {
                    Text(submissionStatusMessage)
                        .font(Theme.geist(12))
                        .foregroundStyle(submissionStatusColor)
                }

                HStack(spacing: Theme.spacingSM) {
                    Button("Refresh Facts") {
                        editableDraft.facts = viewModel.collectAppStoreSubmissionFacts()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Save Draft") {
                        Task { await persistEditableDraft() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await persistEditableDraft()
                            await viewModel.exportAppStoreSubmissionPacket()
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: Theme.spacingSM) {
                    Button {
                        Task {
                            await persistEditableDraft()
                            await viewModel.generateAppStoreSubmissionDrafts()
                            syncEditableDraftFromViewModel()
                        }
                    } label: {
                        Label(hasGeneratedLegalDrafts ? "Update Drafts" : "Auto-Generate", systemImage: "doc.badge.gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isGeneratingAppStoreSubmission)

                    Text("Hosted publishing is not available in 11x. Use local export instead.")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var minimalLegalStatusPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            if !publishBlockers.isEmpty {
                Text("Needs review before publish")
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.error)

                ForEach(publishBlockers, id: \.self) { blocker in
                    Text(blocker)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.error)
                }
            }

            if !generatedWarnings.isEmpty {
                if !publishBlockers.isEmpty {
                    Divider()
                        .overlay(Theme.separator)
                }
                ForEach(generatedWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .appStorePanel(fill: !publishBlockers.isEmpty ? Theme.error.opacity(0.08) : Theme.warning.opacity(0.08))
    }

    private var detailsMetricsStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.spacingMD)],
            alignment: .leading,
            spacing: Theme.spacingMD
        ) {
            MetricTile(title: "Description", value: "\(descriptionCharacterCount)", detail: "chars", tint: descriptionCharacterCount > 4000 ? Theme.warning : Theme.textPrimary)
            MetricTile(title: "Promo", value: "\(promotionalCharacterCount)", detail: "/ 170", tint: promotionalCharacterCount > 170 ? Theme.error : Theme.textPrimary)
            MetricTile(title: "Keywords", value: "\(keywordCharacterCount)", detail: "/ 100", tint: keywordCharacterCount > 100 ? Theme.error : Theme.textPrimary)
            MetricTile(title: "Review Notes", value: "\(reviewNotesCount)", detail: "items", tint: Theme.textPrimary)
        }
    }

    private var legalMetricsStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.spacingMD)],
            alignment: .leading,
            spacing: Theme.spacingMD
        ) {
            MetricTile(title: "Docs Ready", value: "\(generatedDocumentCount)", detail: "/ 3", tint: generatedDocumentCount == 3 ? Theme.accent : Theme.warning)
            MetricTile(title: "Confirmed", value: "\(confirmedFieldCount)", detail: "checks", tint: Theme.textPrimary)
            MetricTile(title: "Blockers", value: "\(publishBlockers.count)", detail: publishBlockers.isEmpty ? "clear" : "open", tint: publishBlockers.isEmpty ? Theme.accent : Theme.error)
            MetricTile(title: "Slug", value: editableDraft.publish.publicSlug.isEmpty ? "unset" : editableDraft.publish.publicSlug, detail: editableDraft.publish.isPublished ? "live" : "draft", tint: Theme.textPrimary)
        }
    }

    private var legalReadinessPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            panelHeading(
                "Publish Readiness",
                detail: publishBlockers.isEmpty
                    ? "Drafts look complete for local export."
                    : "These items still need confirmation before the drafts are ready for local export."
            )

            if publishBlockers.isEmpty {
                Text("No publish blockers.")
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else {
                ForEach(publishBlockers, id: \.self) { blocker in
                    Text(blocker)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.error)
                }
            }

            if !generatedWarnings.isEmpty {
                Divider()
                    .overlay(Theme.separator)
                ForEach(generatedWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .appStorePanel(fill: publishBlockers.isEmpty ? Theme.accent.opacity(0.06) : Theme.error.opacity(0.08))
    }

    private var detailsSidebar: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            linkReferencePanel

            GuidanceList(
                title: "Category Suggestions",
                items: editableDraft.generated.metadata.categorySuggestions,
                copyLabel: "Category suggestions",
                onCopy: copyToPasteboard
            )
            GuidanceList(
                title: "Reviewer Contact Checklist",
                items: editableDraft.generated.metadata.reviewerContactChecklist,
                copyLabel: "Reviewer contact checklist",
                onCopy: copyToPasteboard
            )
            GuidanceList(
                title: "Demo Account Checklist",
                items: editableDraft.generated.metadata.demoAccountChecklist,
                copyLabel: "Demo account checklist",
                onCopy: copyToPasteboard
            )
            GuidanceList(
                title: "App Privacy Guidance",
                items: editableDraft.generated.metadata.appPrivacyAnswers,
                copyLabel: "App privacy guidance",
                onCopy: copyToPasteboard
            )
            GuidanceList(
                title: "Age Rating Guidance",
                items: editableDraft.generated.metadata.ageRatingHints,
                copyLabel: "Age rating guidance",
                onCopy: copyToPasteboard
            )
            GuidanceList(
                title: "Accessibility Guidance",
                items: editableDraft.generated.metadata.accessibilityHints,
                copyLabel: "Accessibility guidance",
                onCopy: copyToPasteboard
            )

            if !generatedWarnings.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingXS) {
                    panelHeading("Generation Warnings", detail: "The model flagged these as needing manual review.")
                    ForEach(generatedWarnings, id: \.self) { warning in
                        Text(warning)
                            .font(Theme.geist(12))
                            .foregroundStyle(Theme.warning)
                    }
                }
                .appStorePanel(fill: Theme.warning.opacity(0.08))
            }
        }
    }

    private var linkReferencePanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            panelHeading("Reference Links", detail: "Copy the exact values you’ll need in App Store Connect.")

            referenceRow(title: "Support Email", value: editableDraft.facts.supportEmail)
            referenceRow(title: "Website URL", value: editableDraft.facts.websiteURL)
            referenceRow(title: "Marketing URL", value: editableDraft.facts.marketingURL)
            referenceRow(title: "Accessibility URL", value: editableDraft.facts.accessibilityURL)
            Text("Hosted legal page URLs are not available in 11x local cockpit. Export drafts locally instead.")
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appStorePanel()
    }

    @ViewBuilder
    private func referenceRow(title: String, value: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.geist(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(value.isEmpty ? "Not available yet" : value)
                    .font(Theme.geistMono(11))
                    .foregroundStyle(value.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            if !value.isEmpty {
                Button {
                    copyToPasteboard(value, title)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func statusPill(title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func panelHeading(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func editableHostedURL(kind: String) -> URL? {
        editableDraft
            .normalized(projectName: projectName)
            .hostedURL(baseURL: Config.hostedAppsBaseURL, kind: kind)
    }

    private func triggerAssetGeneration() {
        viewModel.requestAppStoreReviewGeneration()
    }

    private func triggerLegalGeneration() {
        Task {
            await persistEditableDraft()
            await viewModel.generateAppStoreSubmissionDrafts()
            syncEditableDraftFromViewModel()
        }
    }

    private func publishCurrentDraft() {
        viewModel.appStoreSubmissionError = "Hosted publishing is not available in 11x. Use local export instead."
    }

    private func unpublishCurrentDraft() {
        viewModel.appStoreSubmissionError = "Hosted publishing is not available in 11x. Use local export instead."
    }

    private func exportSubmissionPacket() {
        Task {
            await persistEditableDraft()
            await viewModel.exportAppStoreSubmissionPacket()
        }
    }

    private func copyDescriptionToPasteboard() {
        let trimmed = appStoreDescriptionPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        isDescriptionCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isDescriptionCopied = false
        }
    }

    private func copyToPasteboard(_ text: String, _ label: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        viewModel.appStoreSubmissionError = nil
        viewModel.appStoreSubmissionStatus = "Copied \(label)."
    }

    private func syncEditableDraftFromViewModel() {
        var draft = viewModel.appStoreSubmissionDraft.normalized(projectName: projectName)
        draft.facts = viewModel.collectAppStoreSubmissionFacts()
        editableDraft = draft
    }

    private func persistEditableDraft() async {
        await viewModel.saveAppStoreSubmissionDraft(editableDraft)
        editableDraft = viewModel.appStoreSubmissionDraft.normalized(projectName: projectName)
    }

    private func binding<Value>(for keyPath: WritableKeyPath<AppStoreSubmissionDraft, Value>) -> Binding<Value> {
        Binding(
            get: { editableDraft[keyPath: keyPath] },
            set: { editableDraft[keyPath: keyPath] = $0 }
        )
    }

}

private struct FocusedLegalDocumentWorkspace: View {
    @Binding var selection: ReviewView.LegalDocumentTab
    @Binding var document: AppStoreGeneratedDocument
    let liveURL: URL?
    let onCopy: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .center, spacing: Theme.spacingMD) {
                Picker("", selection: $selection) {
                    ForEach(ReviewView.LegalDocumentTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                if document.hasContent {
                    Button {
                        onCopy(document.markdown(), "\(selection.title) markdown")
                    } label: {
                        Label("Copy Markdown", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let liveURL {
                    Link(destination: liveURL) {
                        Label("Open Live", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selection.title)
                        .font(Theme.geist(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Focus on one hosted page at a time instead of scrolling through all three.")
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("\(document.sections.count) sections")
                    .font(Theme.geistMono(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            MultiLineField(
                title: "Intro",
                text: Binding(
                    get: { document.intro.joined(separator: "\n\n") },
                    set: { document.intro = splitParagraphs($0) }
                ),
                minHeight: 82
            )

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    ForEach(document.sections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: Theme.spacingSM) {
                            Text(document.sections[index].title)
                                .font(Theme.geist(12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)

                            MultiLineField(
                                title: "Paragraphs",
                                text: Binding(
                                    get: { document.sections[index].paragraphs.joined(separator: "\n\n") },
                                    set: { document.sections[index].paragraphs = splitParagraphs($0) }
                                ),
                                minHeight: 72
                            )

                            MultiLineField(
                                title: "Bullets",
                                text: Binding(
                                    get: { document.sections[index].bullets.joined(separator: "\n") },
                                    set: { document.sections[index].bullets = splitLines($0) }
                                ),
                                minHeight: 60
                            )
                        }
                        .padding(Theme.spacingMD)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                                .fill(Theme.surfaceInset)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                    }

                    if document.sections.isEmpty {
                        Text("No sections yet.")
                            .font(Theme.geist(12))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(minHeight: 360, maxHeight: 430)
        }
        .appStorePanel()
    }

    private func splitParagraphs(_ value: String) -> [String] {
        value
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct AppStoreFactsForm: View {
    @Binding var draft: AppStoreSubmissionDraft
    let isSlugLocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.spacingLG) {
                    minimalFactsPanel
                    minimalClaimsPanel
                }

                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    minimalFactsPanel
                    minimalClaimsPanel
                }
            }
        }
    }

    private var minimalFactsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            sectionHeader(
                "Public Facts",
                detail: "Only the essentials needed for hosted legal pages."
            )

            LabeledField("Company Name", text: $draft.facts.companyName)
            LabeledField("Support Email", text: $draft.facts.supportEmail)
            LabeledField("Website URL", text: $draft.facts.websiteURL)
            LabeledField(
                "Public Slug",
                text: $draft.publish.publicSlug,
                helper: isSlugLocked ? "Locked after first publish." : "Not used for hosted pages in 11x local cockpit.",
                disabled: isSlugLocked
            )
        }
        .appStorePanel()
    }

    private var minimalClaimsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            sectionHeader(
                "Claims To Check",
                detail: "Keep only the switches and confirmations that affect policy accuracy."
            )

            ToggleCard(title: "Accounts", detail: "Users can sign in or keep an account.", isOn: $draft.facts.usesAccounts)
            ToggleCard(title: "Subscriptions", detail: "The app has paid access or renewable purchases.", isOn: $draft.facts.usesSubscriptions)
            ToggleCard(title: "Tracking", detail: "The app uses ATT-relevant tracking or ad tech.", isOn: $draft.facts.usesTracking)

            Divider()
                .overlay(Theme.separator)
                .padding(.vertical, 2)

            ConfirmationCard(
                title: "Support",
                detail: "Support contact and public support flow are correct.",
                key: "support_contact",
                confirmations: $draft.confirmations
            )
            ConfirmationCard(
                title: "Privacy",
                detail: "Privacy claims match what the app actually does.",
                key: "privacy_claims",
                confirmations: $draft.confirmations
            )
            ConfirmationCard(
                title: "Tracking",
                detail: "Tracking and ad disclosures are accurate.",
                key: "tracking_claims",
                confirmations: $draft.confirmations
            )
            ConfirmationCard(
                title: "Age Rating",
                detail: "Age-rating guidance is ready to mirror in App Store Connect.",
                key: "age_rating",
                confirmations: $draft.confirmations
            )
        }
        .appStorePanel()
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(Theme.geist(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct AppStoreMetadataEditor: View {
    @Binding var draft: AppStoreSubmissionDraft
    let onCopy: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                fieldHeader(
                    title: "Description",
                    detail: "Main App Store description. Keep the opening lines immediately useful.",
                    metric: "\(draft.generated.metadata.appStoreDescription.count) chars",
                    metricTint: Theme.textSecondary,
                    copyText: draft.generated.metadata.appStoreDescription,
                    copyLabel: "description"
                )
                MultiLineField(
                    title: "App Store Description",
                    text: $draft.generated.metadata.appStoreDescription,
                    minHeight: 180
                )
            }
            .appStorePanel()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.spacingLG) {
                    promoPanel
                    keywordPanel
                }

                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    promoPanel
                    keywordPanel
                }
            }

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                fieldHeader(
                    title: "Review Notes",
                    detail: "Paste this into App Review notes. Include demo credentials or reviewer steps when needed.",
                    metric: "\(draft.generated.metadata.reviewNotes.count) items",
                    metricTint: Theme.textSecondary,
                    copyText: draft.generated.metadata.reviewNotes.joined(separator: "\n"),
                    copyLabel: "review notes"
                )
                MultiLineField(
                    title: "Review Notes",
                    text: Binding(
                        get: { draft.generated.metadata.reviewNotes.joined(separator: "\n") },
                        set: {
                            draft.generated.metadata.reviewNotes = $0
                                .split(whereSeparator: \.isNewline)
                                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                    ),
                    minHeight: 120
                )
            }
            .appStorePanel()
        }
    }

    private var promoPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            fieldHeader(
                title: "Promotional Text",
                detail: "Short marketing line shown above the description.",
                metric: "\(draft.generated.metadata.promotionalText.count) / 170",
                metricTint: draft.generated.metadata.promotionalText.count > 170 ? Theme.error : Theme.textSecondary,
                copyText: draft.generated.metadata.promotionalText,
                copyLabel: "promotional text"
            )
            LabeledField(
                "Promotional Text",
                text: $draft.generated.metadata.promotionalText
            )
        }
        .appStorePanel()
    }

    private var keywordPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            fieldHeader(
                title: "Keywords",
                detail: "Comma-separated. Keep it tight and literal.",
                metric: "\(draft.generated.metadata.keywordString.count) / 100",
                metricTint: draft.generated.metadata.keywordString.count > 100 ? Theme.error : Theme.textSecondary,
                copyText: draft.generated.metadata.keywordString,
                copyLabel: "keywords"
            )
            MultiLineField(
                title: "Keywords",
                text: Binding(
                    get: { draft.generated.metadata.keywords.joined(separator: ",") },
                    set: {
                        draft.generated.metadata.keywords = $0
                            .split(separator: ",")
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                ),
                minHeight: 90
            )
        }
        .appStorePanel()
    }

    private func fieldHeader(
        title: String,
        detail: String,
        metric: String,
        metricTint: Color,
        copyText: String,
        copyLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.geist(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(metric)
                    .font(Theme.geistMono(11, weight: .medium))
                    .foregroundStyle(metricTint)
                if !copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        onCopy(copyText, copyLabel)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

private struct AppStoreDocumentEditor: View {
    let title: String
    @Binding var document: AppStoreGeneratedDocument
    let onCopy: (String, String) -> Void
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                MultiLineField(
                    title: "Intro",
                    text: Binding(
                        get: { document.intro.joined(separator: "\n\n") },
                        set: { document.intro = splitParagraphs($0) }
                    ),
                    minHeight: 88
                )

                ForEach(document.sections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        Text(document.sections[index].title)
                            .font(Theme.geist(12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)

                        MultiLineField(
                            title: "Paragraphs",
                            text: Binding(
                                get: { document.sections[index].paragraphs.joined(separator: "\n\n") },
                                set: { document.sections[index].paragraphs = splitParagraphs($0) }
                            ),
                            minHeight: 88
                        )

                        MultiLineField(
                            title: "Bullets",
                            text: Binding(
                                get: { document.sections[index].bullets.joined(separator: "\n") },
                                set: { document.sections[index].bullets = splitLines($0) }
                            ),
                            minHeight: 72
                        )
                    }
                    .padding(Theme.spacingMD)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                            .fill(Theme.surfaceInset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                            .stroke(Theme.separator, lineWidth: 1)
                    )
                }
            }
            .padding(.top, Theme.spacingMD)
        } label: {
            HStack(spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(document.sections.count) sections")
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if document.hasContent {
                    Button {
                        onCopy(document.markdown(), "\(title) markdown")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .appStorePanel()
    }

    private func splitParagraphs(_ value: String) -> [String] {
        value
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ReviewScreenshotCarouselCard: View {
    let image: NSImage?

    private let cardWidth: CGFloat = 198

    private var screenshotAspectRatio: CGFloat {
        AppStoreReviewRenderer.screenshotSize.height / AppStoreReviewRenderer.screenshotSize.width
    }

    private var cardHeight: CGFloat {
        cardWidth * screenshotAspectRatio
    }

    private var cornerRadius: CGFloat {
        max(18, min(26, cardWidth * 0.085))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(
                        CGSize(
                            width: AppStoreReviewRenderer.screenshotSize.width,
                            height: AppStoreReviewRenderer.screenshotSize.height
                        ),
                        contentMode: .fit
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.surface)
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }
}

private struct CenteredGenerationState: View {
    let title: String
    let detail: String
    let primaryTitle: String
    let secondaryTitle: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
    var statusMessage: String? = nil
    var statusColor: Color = Theme.textSecondary
    var isRunning = false

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: Theme.spacingMD) {
                Text(title)
                    .font(Theme.geist(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(detail)
                    .font(Theme.geist(13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                if let statusMessage, !statusMessage.isEmpty {
                    HStack(spacing: Theme.spacingXS) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(statusMessage)
                            .font(Theme.geist(12))
                            .foregroundStyle(statusColor)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 420)
                }

                HStack(spacing: Theme.spacingSM) {
                    Button {
                        primaryAction()
                    } label: {
                        Label(primaryTitle, systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(secondaryTitle) {
                        secondaryAction()
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .disabled(isRunning)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }
}

private struct CompactMetricBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.geist(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .fill(Theme.surface.opacity(0.38))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }
}

private struct CompactIssueSummary: View {
    let blockers: [String]
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            if let blocker = blockers.first {
                Label(blocker, systemImage: "exclamationmark.circle.fill")
                    .font(Theme.geist(11, weight: .medium))
                    .foregroundStyle(Theme.error)
                    .lineLimit(3)
            }

            if blockers.count > 1 {
                Text("+\(blockers.count - 1) more blockers")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.error)
            } else if let warning = warnings.first {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.warning)
                    .lineLimit(3)
            }
        }
        .padding(Theme.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .fill(blockers.isEmpty ? Theme.warning.opacity(0.08) : Theme.error.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }
}

private struct CompactToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

private struct CompactConfirmationRow: View {
    let title: String
    let detail: String
    let key: String
    @Binding var confirmations: AppStoreSubmissionConfirmations

    private var isConfirmed: Binding<Bool> {
        Binding(
            get: { confirmations.isConfirmed(key) },
            set: { confirmations.setConfirmed(key, $0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isConfirmed)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

private struct CompactHostedLinkRow: View {
    let label: String
    let url: URL?
    let onCopy: (String, String) -> Void

    var body: some View {
        HStack(spacing: Theme.spacingSM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.geist(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(url?.absoluteString ?? "Not live yet")
                    .font(Theme.geistMono(11))
                    .foregroundStyle(url == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if let url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)

                Button {
                    onCopy(url.absoluteString, "\(label) URL")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LabeledField: View {
    let title: String
    @Binding var text: String
    var helper: String?
    var disabled = false

    init(
        _ title: String,
        text: Binding<String>,
        helper: String? = nil,
        disabled: Bool = false
    ) {
        self.title = title
        _text = text
        self.helper = helper
        self.disabled = disabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            Text(title)
                .font(Theme.geist(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.geist(13))
                .disabled(disabled)

            if let helper, !helper.isEmpty {
                Text(helper)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct MultiLineField: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat
    var helper: String?

    init(
        title: String,
        text: Binding<String>,
        minHeight: CGFloat,
        helper: String? = nil
    ) {
        self.title = title
        _text = text
        self.minHeight = minHeight
        self.helper = helper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            Text(title)
                .font(Theme.geist(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            TextEditor(text: $text)
                .font(Theme.geist(13))
                .frame(minHeight: minHeight)
                .padding(Theme.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                        .fill(Theme.surfaceInset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )

            if let helper, !helper.isEmpty {
                Text(helper)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct GuidanceList: View {
    let title: String
    let items: [String]
    var copyLabel: String?
    var onCopy: ((String, String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                Text(title)
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(Theme.geistMono(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if let copyLabel, let onCopy, !items.isEmpty {
                    Button {
                        onCopy(items.joined(separator: "\n"), copyLabel)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            if items.isEmpty {
                Text("No generated guidance yet.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("- \(item)")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .appStorePanel(padding: Theme.spacingMD, fill: Theme.surface.opacity(0.35))
    }
}

private struct SignalRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Text(label)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text(value.isEmpty ? "Not detected" : value)
                .font(Theme.geistMono(12))
                .foregroundStyle(value.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .textSelection(.enabled)
        }
    }
}

private struct ToggleCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(alignment: .top, spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.geist(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
        }
        .appStorePanel(padding: Theme.spacingMD, fill: isOn ? Theme.accent.opacity(0.08) : Theme.surface.opacity(0.32))
    }
}

private struct ConfirmationCard: View {
    let title: String
    let detail: String
    let key: String
    @Binding var confirmations: AppStoreSubmissionConfirmations

    private var isConfirmed: Binding<Bool> {
        Binding(
            get: { confirmations.isConfirmed(key) },
            set: { confirmations.setConfirmed(key, $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            HStack(alignment: .top, spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.geist(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: isConfirmed)
                    .labelsHidden()
            }
        }
        .appStorePanel(
            padding: Theme.spacingMD,
            fill: isConfirmed.wrappedValue ? Theme.accent.opacity(0.08) : Theme.surface.opacity(0.32)
        )
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.geist(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.geist(value.count > 16 ? 14 : 18, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(Theme.geist(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .appStorePanel(padding: Theme.spacingMD, fill: Theme.surface.opacity(0.3))
    }
}

private extension View {
    func appStorePanel(
        padding: CGFloat = Theme.spacingLG,
        fill: Color = Theme.surface.opacity(0.48)
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }
}
