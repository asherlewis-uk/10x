import SwiftUI

struct BackendView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth

    @State private var statusMessage: String?
    @State private var expandedFunctionIDs: Set<String> = []
    @State private var showsWarnings = true
    @State private var showsAllActivity = false

    private var runtimeSupabaseURL: String? {
        let value = viewModel.environmentValuesByKey["SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private var runtimeSupabaseProjectRef: String? {
        SupabaseManagementService.projectRef(from: runtimeSupabaseURL)
    }

    private var backendState: ProjectBackendState {
        viewModel.projectBackendState
    }

    private var canUseConnectedSupabase: Bool {
        runtimeSupabaseProjectRef != nil
    }

    private var backendFunctions: [ProjectBackendFunctionRecord] {
        backendState.attentionSortedFunctions
    }

    private var backendFunctionIDs: Set<String> {
        Set(backendFunctions.map(\.id))
    }

    private var backendSecrets: [ProjectBackendSecretRecord] {
        backendState.secrets.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func integrationDefinition(for secret: ProjectBackendSecretRecord) -> ProjectIntegrationDefinition? {
        ProjectIntegrations.all.first { definition in
            definition.hostedFields.contains { field in
                field.envKey.caseInsensitiveCompare(secret.name) == .orderedSame
            }
        }
    }

    private var unresolvedBackendRequirements: [ProjectDependencyResolution] {
        viewModel.resolvedProjectDependencies.filter {
            $0.requirement.setupSurface == .backend && !$0.isResolved
        }
    }

    private var recentActivity: [ProjectBackendLogEntry] {
        backendState.recentLogs.sorted { $0.timestamp > $1.timestamp }
    }

    private var visibleActivity: [ProjectBackendLogEntry] {
        Array(recentActivity.prefix(showsAllActivity ? recentActivity.count : 6))
    }

    private var warningCount: Int {
        setupWarningItems.count + unresolvedBackendRequirements.count + backendState.openFailures.count
    }

    private var linkedProviderTitle: String {
        backendState.providerID?.title ?? "Not linked"
    }

    private var backendStatusTitle: String {
        if warningCount > 0 {
            return "Needs attention"
        }
        if backendState.isConfigured {
            return "Connected"
        }
        return "Ready to connect"
    }

    private var backendStatusTone: Color {
        if warningCount > 0 {
            return Theme.warning
        }
        if backendState.isConfigured {
            return Theme.accent
        }
        return Theme.textSecondary
    }

    private var backendStatusSummary: String {
        if backendState.isConfigured, let projectRef = backendState.linkedProjectRef {
            return "Supabase project `\(projectRef)` is linked and available for Backend work."
        }
        if canUseConnectedSupabase {
            return "A Supabase project is already connected in Integrations. Link it here to manage functions and secrets."
        }
        return "Connect Supabase in Integrations, then link Backend so functions, secrets, and logs stay in one place."
    }

    private var localModeBanner: some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hosted backend management is not available in 11x")
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("11x is a local cockpit. Backend deploy, hosted secrets, and vendor-managed functions are disabled. Use local export to move your project to your own infrastructure.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var pendingSecretCount: Int {
        backendSecrets.filter { $0.lastSyncedAt == nil }.count
    }

    private var warningSummary: String {
        warningCount == 1 ? "1 issue needs attention" : "\(warningCount) issues need attention"
    }

    private var setupWarningItems: [BackendSetupWarning] {
        var items: [BackendSetupWarning] = []

        if !backendState.isConfigured {
            items.append(
                BackendSetupWarning(
                    id: "backend-link",
                    title: "Backend isn’t linked",
                    detail: "Connect Supabase in Integrations, then link Backend to the current project.",
                    primaryActionTitle: canUseConnectedSupabase ? "Link Backend" : "Open Integrations"
                ) {
                    if canUseConnectedSupabase {
                        linkConnectedSupabaseProject()
                    } else {
                        viewModel.focusEnvironmentIntegration(.supabase)
                    }
                }
            )
        }

        if backendState.hasUnsyncedSecrets {
            items.append(
                BackendSetupWarning(
                    id: "secret-sync",
                    title: "Some secrets are pending sync",
                    detail: "Backend has hosted secrets that still need to sync to Supabase.",
                    primaryActionTitle: "Add Secret"
                ) {
                    prefillAddSecretPrompt()
                }
            )
        }

        return items
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                localModeBanner

                overviewCard

                if warningCount > 0 {
                    warningsDisclosure
                }

                if let statusMessage, !statusMessage.isEmpty {
                    statusBanner(statusMessage)
                }

                functionsContent

                secretsContent

                recentActivityContent
            }
            .padding(Theme.spacingXL)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.surfaceInset)
        .onAppear {
            if viewModel.pendingBackendFocus {
                viewModel.pendingBackendFocus = false
            }
            syncExpandedFunctions()
        }
        .onChange(of: backendFunctionIDs) { _, _ in
            syncExpandedFunctions()
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: Theme.spacingSM) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        Text("Backend")
                            .font(Theme.geist(20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Text(backendStatusSummary)
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    badge(backendStatusTitle, tone: backendStatusTone)

                    if let refreshedAt = backendState.lastStatusRefreshAt ?? backendState.lastUpdatedAt {
                        Text("Updated \(refreshedAt)")
                            .font(Theme.geistMono(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 176, maximum: 260), spacing: Theme.spacingMD, alignment: .top)],
                alignment: .leading,
                spacing: Theme.spacingMD
            ) {
                metricCard(
                    title: "Provider",
                    value: linkedProviderTitle,
                    detail: backendState.linkedProjectRef ?? "No project linked yet",
                    tone: backendState.isConfigured ? Theme.accent : Theme.textSecondary
                )
                metricCard(
                    title: "Functions",
                    value: "\(backendFunctions.count)",
                    detail: backendState.latestDeployAt.map { "Last deploy \($0)" } ?? "No deploys yet",
                    tone: backendFunctions.isEmpty ? Theme.textSecondary : Theme.textPrimary
                )
                metricCard(
                    title: "Secrets",
                    value: "\(backendSecrets.count)",
                    detail: pendingSecretCount == 0
                        ? "All hosted secrets synced"
                        : "\(pendingSecretCount) pending sync",
                    tone: pendingSecretCount == 0 ? Theme.accent : Theme.warning
                )
                metricCard(
                    title: "Open Issues",
                    value: "\(warningCount)",
                    detail: warningCount == 0 ? "No current blockers" : warningSummary,
                    tone: warningCount == 0 ? Theme.accent : Theme.warning
                )
            }

            if !backendState.isConfigured {
                HStack(spacing: Theme.spacingSM) {
                    Button(canUseConnectedSupabase ? "Link Backend" : "Open Integrations") {
                        if canUseConnectedSupabase {
                            linkConnectedSupabaseProject()
                        } else {
                            viewModel.focusEnvironmentIntegration(.supabase)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)

                    if let projectRef = runtimeSupabaseProjectRef {
                        Text("Connected project: \(projectRef)")
                            .font(Theme.geistMono(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(Theme.spacingLG)
    }

    private var warningsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsWarnings.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: Theme.spacingSM) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: Theme.spacingSM) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.warning)

                            Text("Warnings")
                                .font(Theme.geist(16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)

                            Text("\(warningCount)")
                                .font(Theme.geistMono(12, weight: .semibold))
                                .foregroundStyle(Theme.warning)
                        }

                        Text(warningSummary)
                            .font(Theme.geist(13))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: showsWarnings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, Theme.spacingMD)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsWarnings {
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    ForEach(Array(setupWarningItems.enumerated()), id: \.element.id) { index, item in
                        warningRow(
                            title: item.title,
                            detail: item.detail,
                            actionTitle: item.primaryActionTitle,
                            action: item.action
                        )

                        if index < setupWarningItems.count - 1 || !unresolvedBackendRequirements.isEmpty || !backendState.openFailures.isEmpty {
                            Divider()
                                .overlay(Theme.separator)
                        }
                    }

                    ForEach(Array(unresolvedBackendRequirements.enumerated()), id: \.element.requirement.id) { index, resolution in
                        warningRow(
                            title: resolution.requirement.title,
                            detail: resolution.detail,
                            actionTitle: canUseConnectedSupabase && !backendState.isConfigured ? "Link Backend" : "Open Integrations"
                        ) {
                            if canUseConnectedSupabase && !backendState.isConfigured {
                                linkConnectedSupabaseProject()
                            } else {
                                viewModel.focusEnvironmentIntegration(.supabase)
                            }
                        }

                        if index < unresolvedBackendRequirements.count - 1 || !backendState.openFailures.isEmpty {
                            Divider()
                                .overlay(Theme.separator)
                        }
                    }

                    ForEach(Array(backendState.openFailures.enumerated()), id: \.element.id) { index, failure in
                        warningRow(
                            title: failure.functionName,
                            detail: failure.errorSummary,
                            actionTitle: viewModel.isGenerating ? "Working..." : "Fix with AI",
                            actionDisabled: viewModel.isGenerating
                        ) {
                            triggerFix(for: failure)
                        }

                        if index < backendState.openFailures.count - 1 {
                            Divider()
                                .overlay(Theme.separator)
                        }
                    }
                }
                .padding(.top, Theme.spacingMD)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.bottom, Theme.spacingMD)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.warning.opacity(0.18), lineWidth: 1)
        )
    }

    private var functionsContent: some View {
        sectionContainer(
            title: "Functions",
            count: backendFunctions.count,
            detail: "Named edge functions, deploy status, and the latest failure context."
        ) {
            if backendFunctions.isEmpty {
                emptySectionState(
                    title: "No backend functions yet.",
                    detail: "Functions you add through chat will appear here once Backend is linked."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(backendFunctions.enumerated()), id: \.element.id) { index, function in
                        functionRow(function, showsDivider: index < backendFunctions.count - 1)
                    }
                }
            }
        }
    }

    private var secretsContent: some View {
        sectionContainer(
            title: "Secrets",
            count: backendSecrets.count,
            detail: "Hosted keys that should stay out of the client runtime.",
            actionTitle: "Add"
        ) {
            prefillAddSecretPrompt()
        } content: {
            if backendSecrets.isEmpty {
                emptySectionState(
                    title: "No backend secrets yet.",
                    detail: "Add hosted secrets here when provider credentials should stay server-side."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(backendSecrets.enumerated()), id: \.element.id) { index, secret in
                        secretRow(secret, showsDivider: index < backendSecrets.count - 1)
                    }
                }
            }
        }
    }

    private var recentActivityContent: some View {
        sectionContainer(
            title: "Activity",
            count: recentActivity.count,
            detail: "Recent backend logs, failures, and deployment-related activity.",
            actionTitle: recentActivity.count > 6 ? (showsAllActivity ? "Less" : "More") : nil
        ) {
            showsAllActivity.toggle()
        } content: {
            if visibleActivity.isEmpty {
                emptySectionState(
                    title: "No backend activity yet.",
                    detail: "Run or deploy a backend function to populate this feed."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleActivity.enumerated()), id: \.element.id) { index, log in
                        activityRow(log, showsDivider: index < visibleActivity.count - 1)
                    }
                }
            }
        }
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text(message)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }

    private func metricCard(title: String, value: String, detail: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.geistMono(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Text(value)
                .font(Theme.geist(18, weight: .semibold))
                .foregroundStyle(tone)

            Text(detail)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
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

    private func sectionContainer<Content: View>(
        title: String,
        count: Int,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            sectionHeader(title, count: count, detail: detail, actionTitle: actionTitle, action: action)

            content()
        }
        .padding(Theme.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLG, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }

    private func emptySectionState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.geist(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text(detail)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var functionExpansionBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
            .fill(Theme.surfaceInset)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }

    private func warningRow(
        title: String,
        detail: String,
        actionTitle: String? = nil,
        actionDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: Theme.spacingSM) {
                Text(title)
                    .font(Theme.geist(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                if let actionTitle, let action {
                    Button(actionTitle) {
                        action()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(actionDisabled)
                }
            }

            Text(detail)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }

    private func functionRow(_ function: ProjectBackendFunctionRecord, showsDivider: Bool) -> some View {
        let isExpanded = expandedFunctionIDs.contains(function.id)
        let latestFailure = backendState.latestOpenFailure(for: function.name)
        let recentErrorLogs = backendState.recentLogs
            .filter { log in
                log.isError && log.functionName?.caseInsensitiveCompare(function.name) == .orderedSame
            }
            .prefix(3)

        return VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Button {
                toggleFunctionExpansion(function.id)
            } label: {
                HStack(alignment: .center, spacing: Theme.spacingSM) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.spacingSM) {
                            Text(function.name)
                                .font(Theme.geistMono(13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)

                            badge(function.verifyJWT ? "Auth" : "Public", tone: function.verifyJWT ? Theme.accent : Theme.warning)

                            if latestFailure != nil {
                                badge("Failed", tone: Theme.error)
                            }
                        }

                        Text(function.summary)
                            .font(Theme.geist(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, Theme.spacingMD)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                        .fill(isExpanded ? Theme.surfaceInset : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    detailText(function.sourcePath)
                    detailText("Last deploy: \(function.lastDeployedAt ?? "Never")")

                    if let latestFailure {
                        detailText("Issue: \(latestFailure.errorSummary)")
                    } else if let lastInvocationSummary = function.lastInvocationSummary, !lastInvocationSummary.isEmpty {
                        detailText(lastInvocationSummary)
                    }

                    if !recentErrorLogs.isEmpty {
                        ForEach(Array(recentErrorLogs), id: \.id) { log in
                            detailText("\(log.timestamp)  \(log.message)")
                        }
                    }

                    HStack(spacing: Theme.spacingSM) {
                        Button("Open") {
                            openSource(function.sourcePath)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if let latestFailure {
                            Button(viewModel.isGenerating ? "Working..." : "Fix with AI") {
                                triggerFix(for: latestFailure)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(viewModel.isGenerating)
                        }
                    }
                }
                .padding(Theme.spacingMD)
                .background(functionExpansionBackground)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.bottom, Theme.spacingXS)
            }

            if showsDivider {
                rowDivider()
            }
        }
    }

    private func secretRow(_ secret: ProjectBackendSecretRecord, showsDivider: Bool) -> some View {
        let integrationDefinition = integrationDefinition(for: secret)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.spacingSM) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(secret.name)
                        .font(Theme.geistMono(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Text(secretStatusSummary(secret, integrationDefinition: integrationDefinition))
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 0)

                Text(secret.lastSyncedAt ?? secret.updatedAt)
                    .font(Theme.geistMono(11))
                    .foregroundStyle(Theme.textTertiary)

                if let integrationDefinition {
                    Button("Open") {
                        openIntegration(integrationDefinition.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingMD)

            if showsDivider {
                rowDivider()
            }
        }
    }

    private func secretStatusSummary(
        _ secret: ProjectBackendSecretRecord,
        integrationDefinition: ProjectIntegrationDefinition?
    ) -> String {
        let syncState = secret.lastSyncedAt == nil ? "Pending sync" : "Synced"
        if let integrationDefinition {
            return "\(syncState) · Managed in \(integrationDefinition.title)"
        }
        return syncState
    }

    private func activityRow(_ log: ProjectBackendLogEntry, showsDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.spacingSM) {
                Text(log.functionName ?? "Backend")
                    .font(Theme.geistMono(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 96, alignment: .leading)
                    .padding(.top, 1)

                Text(log.message)
                    .font(Theme.geist(12))
                    .foregroundStyle(log.isError ? Theme.error.opacity(0.92) : Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(log.timestamp)
                    .font(Theme.geistMono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 1)
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingMD)

            if showsDivider {
                rowDivider(leading: Theme.spacingMD + 96 + Theme.spacingSM)
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.spacingSM) {
                    Text(title)
                        .font(Theme.geist(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("\(count)")
                        .font(Theme.geistMono(12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }

                Text(detail)
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func rowDivider(leading: CGFloat = 0) -> some View {
        Divider()
            .overlay(Theme.separator)
            .padding(.leading, leading)
    }

    private func detailText(_ value: String) -> some View {
        Text(value)
            .font(Theme.geistMono(11))
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func badge(_ title: String, tone: Color) -> some View {
        Text(title)
            .font(Theme.geist(10, weight: .semibold))
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.opacity(0.10))
            )
    }

    private func syncExpandedFunctions() {
        expandedFunctionIDs = expandedFunctionIDs.intersection(backendFunctionIDs)
    }

    private func toggleFunctionExpansion(_ functionID: String) {
        if expandedFunctionIDs.contains(functionID) {
            expandedFunctionIDs.remove(functionID)
        } else {
            expandedFunctionIDs.insert(functionID)
        }
    }

    private func linkConnectedSupabaseProject() {
        guard let projectRef = runtimeSupabaseProjectRef,
              let projectURL = runtimeSupabaseURL else {
            statusMessage = "Connect Supabase in Integrations first."
            return
        }

        Task {
            await viewModel.saveProjectBackendState(
                backendState.linking(
                    to: .init(
                        providerID: .supabase,
                        projectRef: projectRef,
                        projectURL: projectURL
                    )
                )
            )
            statusMessage = "Linked Backend to Supabase project `\(projectRef)`."
        }
    }

    private func openSource(_ sourcePath: String) {
        viewModel.focusSourceFile(sourcePath)
        statusMessage = "Opened `\(sourcePath)` in Development."
    }

    private func openIntegration(_ integrationID: ProjectIntegrationID) {
        viewModel.focusEnvironmentIntegration(integrationID)
        statusMessage = "Opened `\(ProjectIntegrations.definition(for: integrationID).title)` in Integrations."
    }

    private func prefillAddSecretPrompt() {
        viewModel.prefillBackendPrompt(
            """
            Add a new backend secret for this project. Ask me only for the secret name and value you actually need, then sync it to Supabase secrets and keep it out of client runtime.
            """
        )
        statusMessage = "Prepared a backend secret prompt in chat."
    }

    private func triggerFix(for failure: ProjectBackendFailureRecord) {
        Task {
            guard let accessToken = await auth.validAccessToken() else {
                statusMessage = "Sign in again to run a backend repair."
                return
            }
            viewModel.fixBackendFailure(failure, accessToken: accessToken)
            statusMessage = "Started an AI repair run for `\(failure.functionName)`."
        }
    }
}

private struct BackendSetupWarning: Identifiable {
    let id: String
    let title: String
    let detail: String
    let primaryActionTitle: String?
    let action: (() -> Void)?

    init(
        id: String,
        title: String,
        detail: String,
        primaryActionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.primaryActionTitle = primaryActionTitle
        self.action = action
    }
}
