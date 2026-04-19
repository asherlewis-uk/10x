import AppKit
import AuthenticationServices
import SwiftUI

private struct SuperwallApplicationChoice: Identifiable, Hashable {
    let organizationID: String
    let organizationName: String?
    let projectID: String
    let projectName: String
    let applicationID: String
    let applicationName: String
    let bundleID: String?

    var id: String { applicationID }
}

private struct ManagedIntegrationFieldSummary: Identifiable, Hashable {
    let integrationID: ProjectIntegrationID
    let integrationTitle: String
    let field: ProjectIntegrationField
    let currentValue: String
    let isConfiguredRemotely: Bool

    var id: String { "\(integrationID.rawValue):\(field.envKey)" }

    var isConfigured: Bool {
        !currentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConfiguredRemotely
    }
}

struct EnvironmentVariablesView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL

    @FocusState private var focusedFieldID: String?
    @State private var managedDrafts: [ProjectIntegrationID: [String: String]] = [:]
    @State private var customDraftVariables: [ProjectEnvironmentVariable] = []
    @State private var hasLoadedInitialState = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var revealedSensitiveFieldIDs: Set<String> = []
    @State private var selectedIntegration: ProjectIntegrationID?
    @State private var supabaseSchemaPreview = SupabaseSchemaPreview(
        tables: [],
        migrations: [],
        scannedFileCount: 0,
        sourceSummary: "",
        emptyStateMessage: "Open a local project to inspect Supabase migrations.",
        bootstrapCommand: nil
    )
    @State private var hasLoadedSupabaseManagementState = false
    @State private var hasSupabaseConnection = false
    @State private var supabaseProjects: [SupabaseManagementProject] = []
    @State private var supabaseOrganizations: [SupabaseManagementOrganization] = []
    @State private var supabaseLinkedProjectNamesByRef: [String: String] = [:]
    @State private var selectedSupabaseProjectRef = ""
    @State private var selectedSupabaseMigrationID: String?
    @State private var supabaseAuthProviders: SupabaseAuthProviderSnapshot?
    @State private var isSupabaseConnecting = false
    @State private var isSupabaseCreatingProject = false
    @State private var isSupabaseManagementLoading = false
    @State private var isSupabaseLoadingSchema = false
    @State private var isSupabaseProjectPickerPresented = false
    @State private var supabaseManagementMessage: String?
    @State private var supabaseManagementError: String?
    @State private var hasLoadedSuperwallManagementState = false
    @State private var hasSuperwallConnection = false
    @State private var superwallManagementAPIKey = ""
    @State private var superwallOrganizations: [SuperwallManagementOrganization] = []
    @State private var superwallProjects: [SuperwallManagementProject] = []
    @State private var superwallPaywalls: [SuperwallManagementPaywall] = []
    @State private var superwallLinkedProjectNamesByApplicationID: [String: String] = [:]
    @State private var selectedSuperwallOrganizationID = ""
    @State private var selectedSuperwallProjectID = ""
    @State private var selectedSuperwallApplicationID = ""
    @State private var selectedSuperwallPaywallID = ""
    @State private var superwallSharedPaywallURL = ""
    @State private var isSuperwallConnecting = false
    @State private var isSuperwallManagementLoading = false
    @State private var isSuperwallBootstrappingProject = false
    @State private var isSuperwallBootstrappingStarter = false
    @State private var isSuperwallSyncingPreviewUser = false
    @State private var superwallManagementMessage: String?
    @State private var superwallManagementError: String?
    @State private var superwallTaskTokens: [SuperwallTaskScope: UUID] = [:]

    private var remoteHostedKeys: Set<String> {
        Set(viewModel.projectBackendState.secrets.map { ProjectEnvironmentSecurity.normalizedKey($0.name) })
    }

    private var baselineEnvironmentVariables: [ProjectEnvironmentVariable] {
        ProjectIntegrations.displayVariables(
            existingVariables: viewModel.environmentVariables,
            backendState: viewModel.projectBackendState
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                if let selectedIntegration {
                    integrationDetail(ProjectIntegrations.definition(for: selectedIntegration))
                } else {
                    integrationsIndex
                    keyValueStore
                }

                controlsBar
            }
            .padding(Theme.spacingXL)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.surfaceInset)
        .onAppear {
            syncDraft(force: !hasLoadedInitialState)
            applyPendingIntegrationFocusIfNeeded()
            if selectedIntegration == .supabase {
                loadSupabaseManagementStateIfNeeded(force: !hasLoadedSupabaseManagementState)
            } else if selectedIntegration == .superwall {
                loadSuperwallManagementStateIfNeeded(force: !hasLoadedSuperwallManagementState)
            }
            refreshSupabaseSchemaPreviewIfNeeded()
        }
        .onChange(of: viewModel.environmentVariables) { _, _ in
            syncDraft(force: !hasUnsavedChanges)
        }
        .onChange(of: selectedIntegration) { _, _ in
            if selectedIntegration == .supabase {
                loadSupabaseManagementStateIfNeeded()
            } else if selectedIntegration == .superwall {
                loadSuperwallManagementStateIfNeeded()
            }
            refreshSupabaseSchemaPreviewIfNeeded()
        }
        .onChange(of: viewModel.pendingEnvironmentIntegrationFocus) { _, _ in
            applyPendingIntegrationFocusIfNeeded()
        }
        .onChange(of: viewModel.activeProject?.id) { _, _ in
            superwallTaskTokens = [:]
            selectedSupabaseProjectRef = ""
            supabaseAuthProviders = nil
            supabaseManagementError = nil
            supabaseManagementMessage = nil
            hasLoadedSupabaseManagementState = false
            hasLoadedSuperwallManagementState = false
            selectedSuperwallOrganizationID = ""
            selectedSuperwallProjectID = ""
            selectedSuperwallApplicationID = ""
            selectedSuperwallPaywallID = ""
            superwallSharedPaywallURL = ""
            superwallPaywalls = []
            superwallManagementError = nil
            superwallManagementMessage = nil
            syncDraft(force: true)
            if selectedIntegration == .supabase {
                loadSupabaseManagementStateIfNeeded(force: true)
            } else if selectedIntegration == .superwall {
                loadSuperwallManagementStateIfNeeded(force: true)
            }
        }
        .onChange(of: viewModel.localProjectPath) { _, _ in
            refreshSupabaseSchemaPreviewIfNeeded()
        }
        .onChange(of: viewModel.fileTreeRevision) { _, _ in
            refreshSupabaseSchemaPreviewIfNeeded()
        }
        .onChange(of: viewModel.projectSuperwallState) { _, _ in
            syncSelectedSuperwallContextFromState()
        }
        .task(id: superwallAutoRefreshTaskKey) {
            guard shouldAutoRefreshSuperwallProjects else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    guard shouldAutoRefreshSuperwallProjects,
                          !isSuperwallManagementLoading,
                          !isSuperwallBootstrappingProject else {
                        return
                    }
                    loadSuperwallManagementStateIfNeeded(force: true)
                }
            }
        }
    }

    private var integrationsIndex: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            ForEach(ProjectIntegrations.all) { definition in
                integrationRow(definition)
            }

            if !otherDependencyRequirements.isEmpty {
                otherDependencyRequirementsSection
            }
        }
    }

    private var dependencyRequirementsByIntegration: [ProjectIntegrationID: [ProjectDependencyResolution]] {
        Dictionary(
            grouping: viewModel.resolvedProjectDependencies.compactMap { resolution in
                guard resolution.requirement.integrationID != nil else { return nil }
                return resolution
            },
            by: { $0.requirement.integrationID! }
        )
    }

    private var otherDependencyRequirements: [ProjectDependencyResolution] {
        viewModel.resolvedProjectDependencies.filter { $0.requirement.setupSurface == .external }
    }

    private func openIntegrationDetail(_ id: ProjectIntegrationID) {
        selectedIntegration = id
        if id == .supabase {
            loadSupabaseManagementStateIfNeeded(force: !hasLoadedSupabaseManagementState)
        } else if id == .superwall {
            loadSuperwallManagementStateIfNeeded(force: !hasLoadedSuperwallManagementState)
        }
    }

    private func integrationRow(_ definition: ProjectIntegrationDefinition) -> some View {
        let statuses = definition.capabilityStatuses(
            values: managedDrafts[definition.id] ?? [:],
            remoteHostedKeys: remoteHostedKeys
        )
        let isConfigured = statuses.allSatisfy(\.isReady)
        let planRequirements = dependencyRequirementsByIntegration[definition.id] ?? []
        let shouldShowRequiredBadge = !isConfigured && !planRequirements.isEmpty

        return Button {
            openIntegrationDetail(definition.id)
        } label: {
            HStack(alignment: .center, spacing: Theme.spacingMD) {
                integrationLogo(for: definition.id, size: 24)

                Text(definition.title)
                    .font(Theme.geist(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 12)

                if shouldShowRequiredBadge {
                    dependencyPlanBadge()
                }

                if isConfigured {
                    configuredIndicator
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func integrationDetail(_ definition: ProjectIntegrationDefinition) -> some View {
        let statuses = definition.capabilityStatuses(
            values: managedDrafts[definition.id] ?? [:],
            remoteHostedKeys: remoteHostedKeys
        )
        let isConfigured = statuses.allSatisfy(\.isReady)

        return VStack(alignment: .leading, spacing: Theme.spacingLG) {
            ZStack {
                HStack(alignment: .center, spacing: Theme.spacingMD) {
                    Button {
                        selectedIntegration = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(Theme.geist(12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 10) {
                        integrationLogo(for: definition.id, size: 28)

                        Text(definition.title)
                            .font(Theme.geist(18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                integrationSetupStatusBadge(isConfigured: isConfigured)
            }

            if definition.id == .supabase {
                if shouldShowSupabaseLoadingPanel {
                    supabaseLoadingPanel
                } else if hasSupabaseConnection, selectedSupabaseProject == nil {
                    supabaseProjectLinkingPanel
                } else {
                    supabaseConnectionPanel
                    if selectedSupabaseProject != nil {
                        supabaseDatabaseVisualizer
                    }
                }
            } else if definition.id == .superwall {
                if shouldShowSuperwallLoadingPanel {
                    superwallLoadingPanel
                } else if shouldShowSuperwallProjectLinkingPanel {
                    superwallProjectLinkingPanel
                } else {
                    superwallConnectionPanel
                }
            } else {
                let guidanceSections = definition.visibleGuidanceSections(
                    values: managedDrafts[definition.id] ?? [:],
                    remoteHostedKeys: remoteHostedKeys
                )

                if !definition.clientFields.isEmpty {
                    managedFieldCard(
                        title: "Client Keys",
                        detail: "These values are app-readable at runtime. Only put keys here if they are safe to expose publicly in the client and save in the project's `.env.local`.",
                        definition: definition,
                        fields: definition.clientFields
                    )
                }

                if !definition.hostedFields.isEmpty {
                    managedFieldCard(
                        title: "Backend Secrets",
                        detail: "These values stay backend-only. 10x syncs them to Supabase secrets, never writes them into project files, and never injects them into app runtime.",
                        definition: definition,
                        fields: definition.hostedFields
                    )
                }

                if !guidanceSections.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(guidanceSections) { section in
                            guidanceSection(section)
                        }
                    }
                }
            }
        }
    }

    private func managedFieldCard(
        title: String,
        detail: String,
        definition: ProjectIntegrationDefinition,
        fields: [ProjectIntegrationField]
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text(title)
                .font(Theme.geist(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(detail)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                ForEach(fields) { field in
                    managedFieldRow(definition: definition, field: field)
                }
            }
        }
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private var selectedSupabaseProject: SupabaseManagementProject? {
        supabaseProjects.first { $0.ref == selectedSupabaseProjectRef }
    }

    private var selectedSupabaseDashboardURL: URL? {
        selectedSupabaseProject?.dashboardURL
    }

    private var selectedSupabaseAuthProvidersDashboardURL: URL? {
        selectedSupabaseProject?.authProvidersDashboardURL
    }

    private var selectedSupabaseURLConfigurationDashboardURL: URL? {
        selectedSupabaseProject?.authURLConfigurationDashboardURL
    }

    private var selectedSupabaseEmailTemplatesDashboardURL: URL? {
        selectedSupabaseProject?.authTemplatesDashboardURL
    }

    private var selectedSupabaseAuthCallbackURL: String? {
        selectedSupabaseProject.map { "https://\($0.ref).supabase.co/auth/v1/callback" }
    }

    private var currentProjectName: String {
        let trimmed = viewModel.activeProject?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "10x Project" : trimmed
    }

    private var currentBundleID: String {
        XcodePreviewService.bundleId(from: currentProjectName)
    }

    private var superwallProjectSetupGuideURL: URL? {
        URL(string: "https://superwall.com/docs/dashboard/creating-applications")
    }

    private var superwallKeysGuideURL: URL? {
        URL(string: "https://superwall.com/docs/dashboard/dashboard-settings/overview-settings-keys")
    }

    private var hasSavedSupabaseProjectLink: Bool {
        !(managedDrafts[.supabase]?["SUPABASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    private var selectedSupabaseProjectLinkedElsewhereName: String? {
        guard !selectedSupabaseProjectRef.isEmpty else { return nil }
        return supabaseLinkedProjectNamesByRef[selectedSupabaseProjectRef]
    }

    private var selectedSupabaseMigration: SupabaseSchemaPreview.Migration? {
        if let selectedSupabaseMigrationID {
            return supabaseSchemaPreview.migrations.first { $0.id == selectedSupabaseMigrationID }
        }
        return supabaseSchemaPreview.migrations.first
    }

    private var selectedSuperwallProject: SuperwallManagementProject? {
        superwallProjects.first { $0.id == selectedSuperwallProjectID }
    }

    private var selectedSuperwallApplication: SuperwallManagementApplication? {
        selectedSuperwallProject?.applications.first(where: { $0.id == selectedSuperwallApplicationID })
            ?? superwallProjects.lazy.compactMap { project in
                project.applications.first(where: { $0.id == selectedSuperwallApplicationID })
            }.first
    }

    private var selectedSuperwallPaywall: SuperwallManagementPaywall? {
        superwallPaywalls.first { $0.id == selectedSuperwallPaywallID }
    }

    private var selectedSuperwallApplicationLinkedElsewhereName: String? {
        guard let applicationID = selectedSuperwallApplication?.id else { return nil }
        return superwallLinkedProjectNamesByApplicationID[applicationID]
    }

    private var filteredSuperwallProjects: [SuperwallManagementProject] {
        guard !selectedSuperwallOrganizationID.isEmpty else { return superwallProjects }
        return superwallProjects.filter { $0.organizationID == selectedSuperwallOrganizationID }
    }

    private var hasLinkedSuperwallApplication: Bool {
        !(viewModel.projectSuperwallState.applicationID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var linkedSuperwallDashboardURL: URL? {
        viewModel.projectSuperwallState.applicationDashboardLink
    }

    private var linkedSuperwallPaywallsDashboardURL: URL? {
        viewModel.projectSuperwallState.paywallsDashboardURL
    }

    private var linkedSuperwallTemplatesDashboardURL: URL? {
        viewModel.projectSuperwallState.templatesDashboardURL
    }

    private var shouldShowSuperwallProjectLinkingPanel: Bool {
        hasSuperwallConnection && !hasLinkedSuperwallApplication
    }

    private var shouldAutoRefreshSuperwallProjects: Bool {
        selectedIntegration == .superwall && shouldShowSuperwallProjectLinkingPanel
    }

    private var superwallAutoRefreshTaskKey: String {
        "\(selectedIntegration?.rawValue ?? "none"):\(viewModel.activeProject?.id ?? "none"):\(shouldShowSuperwallProjectLinkingPanel)"
    }

    private var superwallAvailableApplications: [SuperwallApplicationChoice] {
        superwallProjects
            .flatMap { project in
                project.applications.compactMap { application in
                    guard application.isIOS,
                          superwallLinkedProjectNamesByApplicationID[application.id] == nil else { return nil }
                    let organizationName = superwallOrganizations.first(where: { $0.id == project.organizationID })?.name
                    return SuperwallApplicationChoice(
                        organizationID: project.organizationID,
                        organizationName: organizationName,
                        projectID: project.id,
                        projectName: project.name,
                        applicationID: application.id,
                        applicationName: application.name,
                        bundleID: application.bundleID
                    )
                }
            }
            .sorted {
                if $0.projectName != $1.projectName {
                    return $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending
                }
                return $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
            }
    }

    private var superwallMatchingApplications: [SuperwallApplicationChoice] {
        superwallAvailableApplications.filter {
            $0.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == currentBundleID.lowercased()
        }
    }

    private var suggestedSuperwallApplication: SuperwallApplicationChoice? {
        superwallMatchingApplications.count == 1 ? superwallMatchingApplications[0] : nil
    }

    private var superwallProjectsForLinking: [SuperwallManagementProject] {
        superwallProjects.filter { project in
            let iosApplications = project.applications.filter(\.isIOS)
            guard !iosApplications.isEmpty else { return true }
            return iosApplications.allSatisfy { application in
                superwallLinkedProjectNamesByApplicationID[application.id] == nil
            }
        }
    }

    private var superwallPreviewUserID: String {
        let fallbackProjectID = viewModel.activeProject?.id ?? "preview"
        return viewModel.projectSuperwallState.previewAppUserID ?? "tenx-preview-\(fallbackProjectID)"
    }

    private var configuredIndicator: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.success)
    }

    private var shouldShowSupabaseLoadingPanel: Bool {
        // Keep the initial Supabase check in a loading state so the disconnected UI
        // does not flash before we know whether the account is already connected.
        isSupabaseManagementLoading && selectedSupabaseProject == nil
    }

    private var shouldShowSuperwallLoadingPanel: Bool {
        isSuperwallManagementLoading && !hasSuperwallConnection
    }

    private func setSuperwallStatus(error: String? = nil, message: String? = nil) {
        superwallManagementError = error
        superwallManagementMessage = message
    }

    private func applySuperwallAccount(_ account: SuperwallManagementAccountSnapshot, message: String?) {
        hasSuperwallConnection = true
        superwallOrganizations = account.organizations
        superwallProjects = account.projects
        isSuperwallConnecting = false
        isSuperwallManagementLoading = false
        setSuperwallStatus(message: message)
        refreshSuperwallLinkedProjects()
        syncSelectedSuperwallContextFromState()
    }

    private func requireSuperwallConnection() -> Bool {
        guard hasSuperwallConnection else {
            setSuperwallStatus(error: "Connect Superwall first.")
            return false
        }
        return true
    }

    private func requireLinkedSuperwallApplication() -> Bool {
        guard requireSuperwallConnection() else { return false }
        guard viewModel.projectSuperwallState.applicationID != nil else {
            setSuperwallStatus(error: "Link a Superwall application first.")
            return false
        }
        return true
    }

    @MainActor
    private func runSuperwallTask<Result>(
        scope: SuperwallTaskScope,
        context: SuperwallErrorContext,
        start: @escaping () -> Void = {},
        finish: @escaping () -> Void = {},
        operation: @escaping () async throws -> Result,
        onSuccess: @escaping (Result) -> Void,
        onFailure: ((Error) -> Void)? = nil
    ) {
        let taskToken = UUID()
        superwallTaskTokens[scope] = taskToken
        start()
        Task {
            do {
                let result = try await operation()
                await MainActor.run {
                    // A background refresh should not overwrite a newer connect/link result.
                    guard superwallTaskTokens[scope] == taskToken else { return }
                    finish()
                    onSuccess(result)
                }
            } catch {
                await MainActor.run {
                    // Drop stale failures for the same reason we drop stale successes.
                    guard superwallTaskTokens[scope] == taskToken else { return }
                    finish()
                    if let onFailure {
                        onFailure(error)
                    } else {
                        setSuperwallStatus(error: friendlySuperwallErrorMessage(for: error, context: context))
                    }
                }
            }
        }
    }

    private func integrationSetupStatusBadge(isConfigured: Bool) -> some View {
        let title = isConfigured ? "Configured" : "Needs Setup"
        let tint = isConfigured ? Theme.success : Theme.warning

        return Text(title)
            .font(Theme.geist(10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.2), lineWidth: 1)
            )
    }

    private func dependencyPlanBadge() -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.warning)
                .frame(width: 6, height: 6)

            Text("Required")
                .font(Theme.geist(10, weight: .semibold))
                .foregroundStyle(Theme.warning)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.warning.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.warning.opacity(0.18), lineWidth: 1)
        )
    }

    private func dependencyRequirementCallout(
        _ resolutions: [ProjectDependencyResolution],
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text(title)
                .font(Theme.geist(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(resolutions, id: \.requirement.id) { resolution in
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    HStack {
                        Spacer()
                        dependencySetupStatusBadge(for: resolution)
                        Spacer()
                    }

                    HStack(alignment: .center, spacing: Theme.spacingSM) {
                        Text(resolution.requirement.title)
                            .font(Theme.geist(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        dependencySafetyBadge(resolution.requirement.safety)

                        Spacer(minLength: 0)
                    }

                    Text(resolution.requirement.summary)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.spacingMD)
                .background(Theme.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
            }
        }
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private func dependencySetupStatusBadge(for resolution: ProjectDependencyResolution) -> some View {
        let title = resolution.isResolved ? "Configured" : "Needs Setup"
        let tint = resolution.isResolved ? Theme.success : Theme.warning

        return Text(title)
            .font(Theme.geist(10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.2), lineWidth: 1)
            )
    }

    private func dependencySafetyBadge(_ safety: ProjectDependencySafety) -> some View {
        Text(safety.title)
            .font(Theme.geist(10, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.surfaceInset)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
            .help(safety.detail)
    }

    private var otherDependencyRequirementsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text("Other required dependencies")
                .font(Theme.geist(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            dependencyRequirementCallout(otherDependencyRequirements, title: "Setup outside built-in integrations")
        }
    }

    @ViewBuilder
    private func integrationLogo(for id: ProjectIntegrationID, size: CGFloat) -> some View {
        let assetName = switch id {
        case .openAI: "OpenAILogo"
        case .supabase: "SupabaseLogo"
        case .superwall: "SuperwallLogo"
        }

        if id == .openAI {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: size, height: size)
        } else {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }

    private func managedFieldRow(
        definition: ProjectIntegrationDefinition,
        field: ProjectIntegrationField
    ) -> some View {
        let fieldID = "managed:\(definition.id.rawValue):\(field.envKey)"
        let isSensitive = field.scope == .hosted
        let currentValue = managedDrafts[definition.id]?[field.envKey] ?? ""
        let isConfiguredRemotely =
            isSensitive
                && currentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && remoteHostedKeys.contains(field.envKey)
        let shouldReveal = !isSensitive || revealedSensitiveFieldIDs.contains(fieldID)
        let fieldValidationMessage = ProjectIntegrations.validationMessage(
            for: definition.id,
            envKey: field.envKey,
            value: currentValue
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text(field.label)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(alignment: .center, spacing: Theme.spacingSM) {
                tableField(
                    text: binding(for: definition.id, envKey: field.envKey),
                    fieldID: fieldID,
                    placeholder: isConfiguredRemotely
                        ? "Configured in Supabase. Enter a new value to rotate it."
                        : field.placeholder,
                    isSecure: isSensitive && !shouldReveal,
                    font: Theme.geistMono(12, weight: .medium),
                    validationTint: fieldValidationMessage == nil ? nil : Theme.warning
                )

                if isSensitive {
                    Button {
                        toggleSensitiveValueVisibility(id: fieldID)
                    } label: {
                        Image(systemName: shouldReveal ? "eye.slash" : "eye")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(shouldReveal ? "Hide value" : "Show value")
                }
            }

            if let fieldValidationMessage {
                Text(fieldValidationMessage)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isConfiguredRemotely {
                Text("Configured in Supabase. Leave this blank to keep the current remote value, or enter a new one to rotate it.")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !field.helperText.isEmpty {
                Text(field.helperText)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func guidanceSection(_ section: ProjectIntegrationGuidanceSection) -> some View {
        MarkdownTextView(text: section.markdown, animateTransitions: false)
    }

    private var supabaseDatabaseVisualizer: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .top, spacing: Theme.spacingMD) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database")
                        .font(Theme.geist(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(supabaseSchemaPreview.sourceSummary.isEmpty ? "User-created tables only" : supabaseSchemaPreview.sourceSummary)
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if isSupabaseLoadingSchema {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let project = selectedSupabaseProject {
                        secondaryCapsuleButton("Refresh", systemImage: "arrow.clockwise") {
                            loadSupabaseProject(project)
                        }
                    }
                }
            }

            HStack(spacing: Theme.spacingSM) {
                supabaseMetricCard(title: "Tables", value: "\(supabaseSchemaPreview.tableCount)")
                supabaseMetricCard(title: "Migrations", value: "\(supabaseSchemaPreview.migrationCount)")
                if selectedSupabaseProject != nil {
                    supabaseMetricCard(title: "Source", value: "Live")
                } else {
                    supabaseMetricCard(title: "Source", value: "Local")
                }
            }

            if supabaseSchemaPreview.isEmpty {
                Text(supabaseSchemaPreview.emptyStateMessage ?? "No local schema data available.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.spacingMD)],
                    spacing: Theme.spacingMD
                ) {
                    ForEach(supabaseSchemaPreview.tables) { table in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(table.displayName)
                                    .font(Theme.geistMono(12, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)

                                Spacer()

                                Text("\(table.columns.count)")
                                    .font(Theme.geist(10, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }

                            if table.columns.isEmpty {
                                Text("No columns parsed yet.")
                                    .font(Theme.geist(12))
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(table.columns, id: \.self) { column in
                                        Text(column)
                                            .font(Theme.geist(11))
                                            .foregroundStyle(Theme.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                                    .fill(Theme.surfaceInset)
                                            )
                                    }
                                }
                            }
                        }
                        .padding(Theme.spacingMD)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceInset)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
                    }
                }
            }

            supabaseMigrationsPanel
        }
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private var supabaseMigrationsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .center, spacing: Theme.spacingSM) {
                Text("SQL Migrations")
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if let bootstrapCommand = supabaseSchemaPreview.bootstrapCommand {
                    secondaryCapsuleButton("Copy Reset Command", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bootstrapCommand, forType: .string)
                        supabaseManagementMessage = "Reset command copied."
                        supabaseManagementError = nil
                    }
                }
            }

            if let bootstrapCommand = supabaseSchemaPreview.bootstrapCommand {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create the local database from scratch")
                        .font(Theme.geist(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)

                    Text(bootstrapCommand)
                        .font(Theme.geistMono(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .fill(Theme.surfaceInset)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                }
            }

            if supabaseSchemaPreview.migrations.isEmpty {
                Text("No local SQL migrations found in this project.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: Theme.spacingMD) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(supabaseSchemaPreview.migrations) { migration in
                            Button {
                                selectedSupabaseMigrationID = migration.id
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(migration.fileName)
                                        .font(Theme.geistMono(11, weight: .semibold))
                                        .foregroundStyle(
                                            selectedSupabaseMigration?.id == migration.id ? Theme.textPrimary : Theme.textSecondary
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(migration.relativePath)
                                        .font(Theme.geist(10))
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                        .fill(
                                            selectedSupabaseMigration?.id == migration.id
                                                ? Theme.accent.opacity(0.10)
                                                : Theme.surfaceInset
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                        .stroke(
                                            selectedSupabaseMigration?.id == migration.id
                                                ? Theme.accent.opacity(0.35)
                                                : Theme.separator,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 240, alignment: .topLeading)

                    if let migration = selectedSupabaseMigration {
                        ScrollView {
                            Text(migration.sql.isEmpty ? "-- Empty migration" : migration.sql)
                                .font(Theme.geistMono(11, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 220)
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
            }
        }
    }

    private var supabaseConnectionPanel: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            HStack(alignment: .center, spacing: Theme.spacingLG) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedSupabaseProject?.name ?? (hasSupabaseConnection ? "No Supabase project linked" : "Connect Supabase"))
                        .font(Theme.geist(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if selectedSupabaseProject != nil {
                        Text("Connected for auth and database access.")
                            .font(Theme.geist(11))
                            .foregroundStyle(Theme.textTertiary)
                    } else if hasSupabaseConnection {
                        Text("Create one for \(currentProjectName) or link an unused one.")
                            .font(Theme.geist(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Spacer()

                if hasSupabaseConnection {
                    if selectedSupabaseProject == nil {
                        HStack(spacing: 8) {
                            supabaseCreateProjectButton
                            supabaseProjectPickerButton
                        }
                    } else {
                        supabaseManageMenu
                    }
                } else {
                    primaryCapsuleButton(
                        isSupabaseConnecting ? "Connecting..." : "Connect Supabase",
                        systemImage: "link"
                    ) {
                        connectSupabaseAccount()
                    }
                    .disabled(isSupabaseConnecting)
                }
            }

            if isSupabaseCreatingProject {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Creating the Supabase project for \(currentProjectName). This can take a few minutes.")
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let linkedProjectName = selectedSupabaseProjectLinkedElsewhereName {
                supabaseStatusBanner(
                    text: "This Supabase project is already linked to \(linkedProjectName).",
                    tint: Theme.warning
                )
            }

            if let supabaseAuthProviders {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Auth")
                        .font(Theme.geist(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 8) {
                        authProviderBadge(title: "Email", enabled: supabaseAuthProviders.emailEnabled)
                        authProviderBadge(title: "Apple", enabled: supabaseAuthProviders.appleEnabled)
                        authProviderBadge(title: "Google", enabled: supabaseAuthProviders.googleEnabled)
                    }
                }
            }

            if let project = selectedSupabaseProject {
                supabaseAuthSetupCard(project)
            }

            if let supabaseManagementError {
                supabaseStatusBanner(text: supabaseManagementError, tint: Theme.warning)
            } else if let supabaseManagementMessage {
                supabaseStatusBanner(text: supabaseManagementMessage, tint: Theme.textTertiary)
            }
        }
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private var superwallConnectionPanel: some View {
        let starterReady = viewModel.projectSuperwallState.bootstrapStatus == .starterReady
        let displayedPaywallName = selectedSuperwallPaywall?.name ?? viewModel.projectSuperwallState.paywallName
        return Group {
            if hasSuperwallConnection {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    integrationSectionCard(
                        title: "Paywall Setup",
                        detail: starterReady
                            ? "This paywall is wired for preview mode. Edit it in Superwall, then rerun setup if you need to refresh products or targeting."
                            : "Choose an existing paywall or import one in Superwall first, then let 10x attach starter products and the preview campaign."
                    ) {
                        VStack(alignment: .leading, spacing: Theme.spacingMD) {
                            if let paywallName = displayedPaywallName {
                                superwallDetailLine(label: "Paywall", value: paywallName)
                            } else {
                                Text("No paywall selected yet.")
                                    .font(Theme.geist(11))
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            if let campaignName = viewModel.projectSuperwallState.campaignName {
                                superwallDetailLine(label: "Campaign", value: campaignName)
                            }

                            if !viewModel.projectSuperwallState.placements.isEmpty {
                                superwallDetailLine(
                                    label: "Placements",
                                    value: viewModel.projectSuperwallState.placements.joined(separator: ", ")
                                )
                            }

                            superwallSelectionRow(
                                title: "Selected Paywall",
                                detail: "10x will attach starter products and the preview campaign to this paywall without creating a new one."
                            ) {
                                superwallPaywallMenu
                            }

                            if superwallPaywalls.isEmpty {
                                Text("No paywalls are loaded for this app yet. Open Superwall Paywalls or paste a shared paywall link below, duplicate or create one there, then refresh this list.")
                                    .font(Theme.geist(11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Import Shared Paywall")
                                    .font(Theme.geist(11, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)

                                Text("Paste a public Superwall paywall share link. 10x will open it so you can duplicate it into the linked app, then refresh Paywalls and select it here.")
                                    .font(Theme.geist(11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(alignment: .center, spacing: 8) {
                                    tableField(
                                        text: $superwallSharedPaywallURL,
                                        fieldID: "superwall.sharedPaywallURL",
                                        placeholder: "https://superwall.com/...",
                                        isSecure: false,
                                        font: Theme.geist(11)
                                    )

                                    secondaryCapsuleButton("Open Link", systemImage: "arrow.up.right.square") {
                                        openSuperwallSharedPaywallLink()
                                    }
                                    .disabled(superwallSharedPaywallURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }

                            HStack(spacing: 8) {
                                secondaryCapsuleButton("Open Paywalls", systemImage: "rectangle.on.rectangle") {
                                    openSuperwallPaywallsDashboard()
                                }
                                .disabled(linkedSuperwallPaywallsDashboardURL == nil)

                                secondaryCapsuleButton("Open Templates", systemImage: "square.grid.2x2") {
                                    openSuperwallTemplatesDashboard()
                                }
                                .disabled(linkedSuperwallTemplatesDashboardURL == nil)

                                secondaryCapsuleButton("Refresh Paywalls", systemImage: "arrow.clockwise") {
                                    if let applicationID = viewModel.projectSuperwallState.applicationID {
                                        loadSuperwallPaywallsIfNeeded(applicationID: applicationID, force: true)
                                    }
                                }
                                .disabled(viewModel.projectSuperwallState.applicationID == nil)

                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 8) {
                                primaryCapsuleButton(
                                    isSuperwallBootstrappingStarter
                                        ? "Finishing..."
                                        : (starterReady ? "Refresh Setup" : "Finish Setup"),
                                    systemImage: "wand.and.stars"
                                ) {
                                    bootstrapSuperwallStarterMonetization()
                                }
                                .disabled(
                                    isSuperwallBootstrappingStarter
                                        || isSuperwallSyncingPreviewUser
                                        || selectedSuperwallPaywallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )

                                secondaryCapsuleButton(
                                    isSuperwallSyncingPreviewUser ? "Syncing..." : "Sync Test User",
                                    systemImage: "person.crop.circle.badge.checkmark"
                                ) {
                                    syncSuperwallPreviewTestUser()
                                }
                                .disabled(isSuperwallSyncingPreviewUser || isSuperwallBootstrappingStarter)

                                Spacer(minLength: 0)
                                superwallManageMenu
                            }
                        }
                    }

                    superwallManagementScopeCard

                    if let superwallManagementError {
                        supabaseStatusBanner(text: superwallManagementError, tint: Theme.warning)
                    } else if let superwallManagementMessage {
                        supabaseStatusBanner(text: superwallManagementMessage, tint: Theme.textTertiary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    HStack(alignment: .center, spacing: Theme.spacingLG) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect Superwall")
                                .font(Theme.geist(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)

                            Text("Connect the Superwall management API once so 10x can discover your projects, link the iOS app, and sync its runtime config.")
                                .font(Theme.geist(11))
                                .foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }

                    integrationSectionCard(
                        title: "Connect your Superwall account",
                        detail: "Paste the org management API key. 10x stores it in local Keychain, not in project files."
                    ) {
                        VStack(alignment: .leading, spacing: Theme.spacingMD) {
                            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                                Text("Management API Key")
                                    .font(Theme.geist(12, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)

                                HStack(spacing: Theme.spacingSM) {
                                    tableField(
                                        text: $superwallManagementAPIKey,
                                        fieldID: "superwall:management-api-key",
                                        placeholder: "sw_live_...",
                                        isSecure: true,
                                        font: Theme.geistMono(12, weight: .medium)
                                    )

                                    primaryCapsuleButton(
                                        isSuperwallConnecting ? "Connecting..." : "Connect",
                                        systemImage: "link"
                                    ) {
                                        connectSuperwallAccount()
                                    }
                                    .disabled(
                                        isSuperwallConnecting
                                            || superwallManagementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    )
                                }
                            }

                            if let superwallKeysGuideURL {
                                secondaryCapsuleButton("API Keys", systemImage: "key") {
                                    openURL(superwallKeysGuideURL)
                                }
                            }
                        }
                    }

                    if let superwallManagementError {
                        supabaseStatusBanner(text: superwallManagementError, tint: Theme.warning)
                    } else if let superwallManagementMessage {
                        supabaseStatusBanner(text: superwallManagementMessage, tint: Theme.textTertiary)
                    }
                }
                .padding(Theme.spacingLG)
                .background(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
            }
        }
    }

    private var superwallProjectLinkingPanel: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                HStack(alignment: .top, spacing: Theme.spacingMD) {
                    Spacer()

                    Button {
                        loadSuperwallManagementStateIfNeeded(force: true)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(Theme.geist(12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSuperwallManagementLoading || isSuperwallBootstrappingProject)
                }

                HStack(alignment: .top, spacing: Theme.spacingXL) {
                    VStack(alignment: .leading, spacing: Theme.spacingMD) {
                        superwallDetailLine(label: "Project Name", value: currentProjectName)
                        superwallDetailLine(label: "App Name", value: currentProjectName)
                        superwallDetailLine(label: "Platform", value: "iOS")
                    }

                    if let suggestedSuperwallApplication {
                        secondaryCapsuleButton(
                            isSuperwallBootstrappingProject ? "Linking..." : "Link Matching App",
                            systemImage: "link"
                        ) {
                            linkSuperwallApplication(suggestedSuperwallApplication)
                        }
                        .disabled(isSuperwallBootstrappingProject)
                    }
                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: Theme.spacingMD) {
                        superwallDetailLine(label: "Release State", value: "Not released yet")
                        superwallDetailLine(label: "Bundle ID", value: currentBundleID, monospaced: true)
                    }
                }

                if !superwallProjectsForLinking.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.spacingSM) {
                        ForEach(superwallProjectsForLinking) { project in
                            superwallLinkingProjectRow(project)
                        }
                    }
                }

                if superwallMatchingApplications.count > 1 {
                    supabaseStatusBanner(
                        text: "Multiple Superwall iOS apps already use bundle ID `\(currentBundleID)`. Link the correct one below.",
                        tint: Theme.warning
                    )
                } else if let linkedProjectName = selectedSuperwallApplicationLinkedElsewhereName {
                    supabaseStatusBanner(
                        text: "This Superwall application is already linked to \(linkedProjectName).",
                        tint: Theme.warning
                    )
                }

                if let superwallManagementError {
                    supabaseStatusBanner(text: superwallManagementError, tint: Theme.warning)
                } else if let superwallManagementMessage {
                    supabaseStatusBanner(text: superwallManagementMessage, tint: Theme.textTertiary)
                }

                if let superwallProjectSetupGuideURL {
                    primaryCapsuleButton("Create iOS App", systemImage: "arrow.up.right.square") {
                        openURL(superwallProjectSetupGuideURL)
                    }
                }
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private func superwallLinkingProjectRow(_ project: SuperwallManagementProject) -> some View {
        let applications = project.applications.filter { application in
            application.isIOS && superwallLinkedProjectNamesByApplicationID[application.id] == nil
        }

        return VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text(project.name)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if applications.isEmpty {
                Text("No iOS apps yet.")
                    .font(Theme.geist(10))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(applications) { application in
                    let choice = SuperwallApplicationChoice(
                        organizationID: project.organizationID,
                        organizationName: superwallOrganizations.first(where: { $0.id == project.organizationID })?.name,
                        projectID: project.id,
                        projectName: project.name,
                        applicationID: application.id,
                        applicationName: application.name,
                        bundleID: application.bundleID
                    )
                    let bundleID = application.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let isBundleMatch = bundleID.lowercased() == currentBundleID.lowercased()
                    let linkedProjectName = superwallLinkedProjectNamesByApplicationID[application.id]
                    let isLinkedElsewhere = linkedProjectName != nil && linkedProjectName != currentProjectName

                    HStack(alignment: .center, spacing: Theme.spacingMD) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(application.name)
                                .font(Theme.geist(11, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)

                            if !bundleID.isEmpty {
                                Text(bundleID)
                                    .font(Theme.geistMono(10, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                                    .textSelection(.enabled)
                            }
                        }

                        Spacer(minLength: 12)

                        if isBundleMatch {
                            Text("Match")
                                .font(Theme.geist(10, weight: .semibold))
                                .foregroundStyle(Theme.success)
                        }

                        secondaryCapsuleButton(
                            isSuperwallBootstrappingProject ? "Linking..." : "Link",
                            systemImage: "link"
                        ) {
                            linkSuperwallApplication(choice)
                        }
                        .disabled(isSuperwallBootstrappingProject || isLinkedElsewhere)
                    }

                    if let linkedProjectName, isLinkedElsewhere {
                        Text("Linked to \(linkedProjectName)")
                            .font(Theme.geist(10))
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
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

    private func integrationSectionCard<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text(title)
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(detail)
                .font(Theme.geist(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .padding(Theme.spacingLG)
        .background(Theme.surfaceInset)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private func supabaseAuthSetupCard(_ project: SupabaseManagementProject) -> some View {
        let callbackURL = selectedSupabaseAuthCallbackURL ?? "https://\(project.ref).supabase.co/auth/v1/callback"
        let emailConfirmationGuidance: String
        if supabaseAuthProviders?.emailConfirmationsEnabled == true {
            emailConfirmationGuidance = "Confirm Email is currently required. If users are blocked, verify the Email provider toggle, URL Configuration, and the confirmation email template."
        } else if supabaseAuthProviders?.emailConfirmationsEnabled == false {
            emailConfirmationGuidance = "Confirm Email is currently disabled. Turn it on in Auth > Providers > Email if users should verify before first sign-in."
        } else {
            emailConfirmationGuidance = "Use Auth > Providers > Email to decide whether Confirm Email should be required, then verify URL Configuration and templates."
        }

        return integrationSectionCard(
            title: "Auth Setup",
            detail: "Provider credentials and email confirmation live in Supabase. The client keys here only connect the app to this project."
        ) {
            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        secondaryCapsuleButton("Auth Providers", systemImage: "person.badge.key") {
                            openSelectedSupabaseDashboardURL(
                                selectedSupabaseAuthProvidersDashboardURL,
                                successMessage: "Opened Supabase Auth Providers."
                            )
                        }
                        .disabled(selectedSupabaseAuthProvidersDashboardURL == nil)

                        secondaryCapsuleButton("URL Configuration", systemImage: "link.badge.plus") {
                            openSelectedSupabaseDashboardURL(
                                selectedSupabaseURLConfigurationDashboardURL,
                                successMessage: "Opened Supabase URL Configuration."
                            )
                        }
                        .disabled(selectedSupabaseURLConfigurationDashboardURL == nil)
                    }

                    HStack(spacing: 8) {
                        secondaryCapsuleButton("Email Templates", systemImage: "envelope") {
                            openSelectedSupabaseDashboardURL(
                                selectedSupabaseEmailTemplatesDashboardURL,
                                successMessage: "Opened Supabase Email Templates."
                            )
                        }
                        .disabled(selectedSupabaseEmailTemplatesDashboardURL == nil)

                        secondaryCapsuleButton("Open Project", systemImage: "arrow.up.right.square") {
                            openSelectedSupabaseProject()
                        }
                        .disabled(selectedSupabaseDashboardURL == nil)
                    }
                }

                MarkdownTextView(
                    text: """
                    - **App code scope:** native Apple/Google button flow, `redirectTo` or deep-link handling, and exchanging the returned credential into a real Supabase session.
                    - **Supabase scope:** provider enable toggles, provider Client IDs and Client Secrets, Confirm Email behavior, Site URL, Redirect URLs, Email Templates, and SMTP delivery.
                    - **Apple:** In **Auth > Providers > Apple** fill **Client IDs** and **Secret**. In Apple Developer create an App ID, Services ID, and Sign in with Apple key. Copy the Callback URL from Supabase. For most hosted projects it is `\(callbackURL)`. If this project uses a custom Auth domain, use the Callback URL shown on the provider page instead.
                    - **Google:** In **Auth > Providers > Google** fill **Client ID** and **Secret**. In Google Cloud create a web OAuth client and add `\(callbackURL)` as an authorized redirect URI.
                    - **Email Confirmation:** \(emailConfirmationGuidance)
                    """,
                    animateTransitions: false
                )
            }
        }
    }

    private var superwallManagementScopeCard: some View {
        let dashboardURL = linkedSuperwallDashboardURL?.absoluteString ?? "Link a Superwall app to get the dashboard URL."
        let paywallsURL = linkedSuperwallPaywallsDashboardURL?.absoluteString ?? dashboardURL
        let paywallName = viewModel.projectSuperwallState.paywallName ?? "the linked paywall"

        return integrationSectionCard(
            title: "Dashboard Ownership",
            detail: "10x wires runtime config and starter resources. Visual paywall editing still happens in Superwall."
        ) {
            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                HStack(spacing: 8) {
                    secondaryCapsuleButton("Open Dashboard", systemImage: "arrow.up.right.square") {
                        openSuperwallDashboard()
                    }
                    .disabled(linkedSuperwallDashboardURL == nil)

                    secondaryCapsuleButton("Open Paywalls", systemImage: "rectangle.on.rectangle") {
                        openSuperwallPaywallsDashboard()
                    }
                    .disabled(linkedSuperwallPaywallsDashboardURL == nil)
                }

                MarkdownTextView(
                    text: """
                    - **App code / 10x scope:** `SUPERWALL_PUBLIC_API_KEY`, SDK configuration, placement names, preview test-user wiring, and starter bootstrap resources.
                    - **Superwall scope:** paywall design, copy, templates, shared-link imports, assets, product attachments, campaign targeting, and experiments.
                    - **Dashboard:** \(dashboardURL)
                    - **Paywalls:** \(paywallsURL)
                    - **Edit the paywall:** open the linked Superwall dashboard and use **Paywalls** to update \(paywallName).
                    - **Create or import first:** if setup is blocked, build or duplicate the paywall in Superwall first, then come back and run **Finish Setup** here.
                    """,
                    animateTransitions: false
                )
            }
        }
    }

    private func superwallSelectionRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.geist(11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(detail)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            control()
        }
    }

    private func superwallSummaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.geist(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Text(value)
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .fill(Theme.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }

    private func superwallDetailLine(label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.geist(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Text(value)
                .font(monospaced ? Theme.geistMono(11, weight: .medium) : Theme.geist(11, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
    }

    private var superwallLoadingPanel: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: Theme.spacingMD) {
                ProgressView()
                    .controlSize(.small)

                Text("Loading your Superwall account...")
                    .font(Theme.geist(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Text("Checking the saved Superwall connection for \(currentProjectName).")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private var superwallManageMenu: some View {
        Menu {
            Button("Open Dashboard", systemImage: "arrow.up.right.square") {
                openSuperwallDashboard()
            }
            .disabled(linkedSuperwallDashboardURL == nil)

            Button("Open Paywalls", systemImage: "rectangle.on.rectangle") {
                openSuperwallPaywallsDashboard()
            }
            .disabled(linkedSuperwallPaywallsDashboardURL == nil)

            Button("Open Templates", systemImage: "square.grid.2x2") {
                openSuperwallTemplatesDashboard()
            }
            .disabled(linkedSuperwallTemplatesDashboardURL == nil)

            Button("Refresh Paywalls", systemImage: "arrow.clockwise.circle") {
                if let applicationID = viewModel.projectSuperwallState.applicationID {
                    loadSuperwallPaywallsIfNeeded(applicationID: applicationID, force: true)
                }
            }
            .disabled(viewModel.projectSuperwallState.applicationID == nil)

            Divider()

            Button("Refresh", systemImage: "arrow.clockwise") {
                loadSuperwallManagementStateIfNeeded(force: true)
            }

            Divider()

            Button("Disconnect", systemImage: "xmark") {
                disconnectSuperwallAccount()
            }
        } label: {
            Label("Manage", systemImage: "ellipsis.circle")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.surfaceInset)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private var superwallExistingApplicationMenu: some View {
        Menu {
            ForEach(superwallAvailableApplications) { application in
                Button("\(application.projectName) / \(application.applicationName)") {
                    linkSuperwallApplication(application)
                }
            }
        } label: {
            Label("Use Existing App", systemImage: "chevron.up.chevron.down")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.surfaceInset)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private var superwallOrganizationMenu: some View {
        Menu {
            if superwallOrganizations.isEmpty {
                Text("No organizations")
            } else {
                ForEach(superwallOrganizations) { organization in
                    Button(organization.name) {
                        selectedSuperwallOrganizationID = organization.id
                        selectedSuperwallProjectID = ""
                        selectedSuperwallApplicationID = ""
                        selectedSuperwallPaywallID = ""
                        superwallPaywalls = []
                    }
                }
            }
        } label: {
            Label(
                superwallOrganizations.first(where: { $0.id == selectedSuperwallOrganizationID })?.name ?? "Choose Org",
                systemImage: "building.2"
            )
            .font(Theme.geist(12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private var superwallProjectMenu: some View {
        Menu {
            Button("Create New Project") {
                selectedSuperwallProjectID = ""
                selectedSuperwallApplicationID = ""
            }

            if !filteredSuperwallProjects.isEmpty {
                Divider()
            }

            ForEach(filteredSuperwallProjects) { project in
                Button(project.name) {
                    selectedSuperwallProjectID = project.id
                    selectedSuperwallApplicationID = project.preferredIOSApplication(matching: currentBundleID)?.id ?? ""
                    selectedSuperwallPaywallID = ""
                    superwallPaywalls = []
                    if !selectedSuperwallApplicationID.isEmpty {
                        loadSuperwallPaywallsIfNeeded(applicationID: selectedSuperwallApplicationID, force: true)
                    }
                }
            }
        } label: {
            Label(selectedSuperwallProject?.name ?? "Create / Choose Project", systemImage: "shippingbox")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(filteredSuperwallProjects.isEmpty && superwallOrganizations.isEmpty)
    }

    private var superwallApplicationMenu: some View {
        Menu {
            Button("Create / Auto-match iOS App") {
                selectedSuperwallApplicationID = ""
                selectedSuperwallPaywallID = ""
                superwallPaywalls = []
            }

            let applications = selectedSuperwallProject?.applications.filter(\.isIOS) ?? []
            if !applications.isEmpty {
                Divider()
            }

            ForEach(applications) { application in
                Button(application.name) {
                    selectedSuperwallApplicationID = application.id
                    selectedSuperwallPaywallID = ""
                    loadSuperwallPaywallsIfNeeded(applicationID: application.id, force: true)
                }
                .disabled(
                    superwallLinkedProjectNamesByApplicationID[application.id] != nil
                        && superwallLinkedProjectNamesByApplicationID[application.id] != currentProjectName
                )
            }
        } label: {
            Label(selectedSuperwallApplication?.name ?? "Create / Choose iOS App", systemImage: "iphone")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(selectedSuperwallProject == nil)
    }

    private var superwallPaywallMenu: some View {
        Menu {
            ForEach(superwallPaywalls) { paywall in
                Button(paywall.name) {
                    selectedSuperwallPaywallID = paywall.id
                }
            }
        } label: {
            Label(
                selectedSuperwallPaywall?.name ?? viewModel.projectSuperwallState.paywallName ?? "Choose Paywall",
                systemImage: "rectangle.on.rectangle"
            )
            .font(Theme.geist(12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(superwallPaywalls.isEmpty && viewModel.projectSuperwallState.paywallName == nil)
    }

    private var supabaseLoadingPanel: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: Theme.spacingMD) {
                ProgressView()
                    .controlSize(.small)

                Text(hasSavedSupabaseProjectLink ? "Loading the linked Supabase project..." : "Loading your Supabase projects...")
                    .font(Theme.geist(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Text(hasSavedSupabaseProjectLink ? "Checking the saved connection for \(currentProjectName)." : "Checking your Supabase connection for \(currentProjectName).")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private var supabaseProjectLinkingPanel: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: Theme.spacingMD) {
                if isSupabaseCreatingProject {
                    ProgressView()
                        .controlSize(.small)

                    Text("Creating the Supabase project for \(currentProjectName). This can take a few minutes.")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        supabaseCreateProjectButton
                        supabaseProjectPickerButton
                    }
                }

                if let supabaseManagementError {
                    supabaseStatusBanner(text: supabaseManagementError, tint: Theme.warning)
                } else if let supabaseManagementMessage {
                    supabaseStatusBanner(text: supabaseManagementMessage, tint: Theme.textTertiary)
                }
            }
            .frame(maxWidth: 360)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(Theme.spacingLG)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
    }

    private var supabaseManageMenu: some View {
        Menu {
            Button("Open in Supabase", systemImage: "arrow.up.right.square") {
                openSelectedSupabaseProject()
            }
            .disabled(selectedSupabaseProject == nil)

            Button("Refresh", systemImage: "arrow.clockwise") {
                loadSupabaseManagementStateIfNeeded(force: true)
            }

            Button("Reconnect", systemImage: "link") {
                connectSupabaseAccount()
            }
            .disabled(isSupabaseConnecting)

            Divider()

            Button("Disconnect", systemImage: "xmark") {
                disconnectSupabaseAccount()
            }
        } label: {
            Label("Manage", systemImage: "ellipsis.circle")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.surfaceInset)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var supabaseCreateProjectButton: some View {
        if supabaseOrganizations.count > 1 {
            Menu {
                ForEach(supabaseOrganizations) { organization in
                    Button(organization.name) {
                        createSupabaseProject(in: organization)
                    }
                }
            } label: {
                supabasePrimaryButtonLabel(isSupabaseCreatingProject ? "Creating..." : "Create Project", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .disabled(isSupabaseCreatingProject || isSupabaseLoadingSchema)
        } else {
            primaryCapsuleButton(
                isSupabaseCreatingProject ? "Creating..." : "Create Project",
                systemImage: "plus"
            ) {
                createSupabaseProject(in: supabaseOrganizations.first)
            }
            .disabled(isSupabaseCreatingProject || isSupabaseLoadingSchema)
        }
    }

    private var supabaseProjectPickerButton: some View {
        Button {
            isSupabaseProjectPickerPresented = true
        } label: {
            Label("Select Existing", systemImage: "chevron.up.chevron.down")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.surfaceInset)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(supabaseProjects.isEmpty || isSupabaseCreatingProject || isSupabaseLoadingSchema)
        .popover(isPresented: $isSupabaseProjectPickerPresented, arrowEdge: .bottom) {
            supabaseProjectPickerPopover
        }
    }

    private var supabaseProjectPickerPopover: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Select a Supabase project")
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if supabaseProjects.isEmpty {
                Text("No Supabase projects found on this account.")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(supabaseProjects) { project in
                            supabaseProjectPickerRow(project)
                        }
                    }
                }
                .frame(width: 340)
                .frame(maxHeight: 320)
            }
        }
        .padding(Theme.spacingLG)
        .background(Theme.surface)
    }

    private func supabaseProjectPickerRow(_ project: SupabaseManagementProject) -> some View {
        let linkedProjectName = supabaseLinkedProjectNamesByRef[project.ref]
        let isLinkedElsewhere = linkedProjectName != nil && project.ref != selectedSupabaseProjectRef

        return Button {
            selectSupabaseProject(project)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(Theme.geist(12, weight: .semibold))
                        .foregroundStyle(isLinkedElsewhere ? Theme.textTertiary : Theme.textPrimary)

                    if let linkedProjectName {
                        Text("Linked to \(linkedProjectName)")
                            .font(Theme.geist(10, weight: .medium))
                            .foregroundStyle(isLinkedElsewhere ? Theme.warning : Theme.textTertiary)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .fill(project.ref == selectedSupabaseProjectRef ? Theme.accent.opacity(0.10) : Theme.surfaceInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(
                        project.ref == selectedSupabaseProjectRef ? Theme.accent.opacity(0.30) : Theme.separator,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLinkedElsewhere)
    }

    private func supabaseMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.geist(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Text(value)
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .fill(Theme.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }

    private func supabasePrimaryButtonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Theme.geist(12, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.accent)
            )
    }

    private func primaryCapsuleButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            supabasePrimaryButtonLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func secondaryCapsuleButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.surfaceInset)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func supabaseInfoChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(Theme.geist(10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
    }

    private func supabaseStatusBanner(text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.geist(11))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            )
    }

    private func authProviderBadge(title: String, enabled: Bool?) -> some View {
        let isEnabled = enabled == true
        let foreground = isEnabled ? Theme.success : Theme.textTertiary
        let background = isEnabled ? Theme.success.opacity(0.10) : Theme.surfaceInset

        return HStack(spacing: 6) {
            Circle()
                .fill(foreground)
                .frame(width: 6, height: 6)

            Text(title)
                .font(Theme.geist(11, weight: .medium))
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(background)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
    }

    private var controlsBar: some View {
        HStack(alignment: .center, spacing: Theme.spacingSM) {
            if selectedIntegration == nil {
                Button {
                    addVariable(scope: .client)
                } label: {
                    Label("Add Client Key", systemImage: "plus")
                        .font(Theme.geist(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.surface)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    addVariable(scope: .hosted)
                } label: {
                    Label("Add Backend Secret", systemImage: "lock")
                        .font(Theme.geist(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.surface)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Group {
                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(Theme.warning)
                } else if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(Theme.textTertiary)
                } else if !saveSummary.isEmpty {
                    Text(saveSummary)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .font(Theme.geist(12))
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                save()
            } label: {
                Text(isSaving ? "Saving..." : "Save")
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(hasUnsavedChanges ? Theme.accent : Theme.accent.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasUnsavedChanges || validationMessage != nil || isSaving)
        }
    }

    private var keyValueStore: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            customVariableSection(
                title: "Client Keys",
                detail: "App-readable runtime config. Only put values here if they are safe to expose publicly in the client and save in the project's `.env.local`.",
                scope: .client,
                variables: clientCustomDraftVariables
            )

            customVariableSection(
                title: "Backend Keys",
                detail: "Server-only or backend-facing values synced to Supabase secrets. They are never written into the generated project or exposed to app runtime.",
                scope: .hosted,
                variables: hostedCustomDraftVariables
            )
        }
    }

    private func customVariableSection(
        title: String,
        detail: String,
        scope: ProjectEnvironmentScope,
        variables: [ProjectEnvironmentVariable]
    ) -> some View {
        let managedSummaries = configuredManagedIntegrationFieldSummaries(for: scope)
        let hasVisibleRows = !managedSummaries.isEmpty || !variables.isEmpty

        return VStack(alignment: .leading, spacing: Theme.spacingMD) {
            Text(title)
                .font(Theme.geist(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(detail)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                headerRow

                if !hasVisibleRows {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)

                    Text("No \(title.lowercased()) yet.")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.spacingLG)
                        .padding(.vertical, Theme.spacingLG)
                } else {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)

                    ForEach(Array(managedSummaries.enumerated()), id: \.element.id) { index, summary in
                        managedIntegrationRow(summary)

                        if index < managedSummaries.count - 1 || !variables.isEmpty {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                        }
                    }

                    ForEach(variables) { variable in
                        variableRow(variable: customVariableBinding(id: variable.id))

                        if variable.id != variables.last?.id {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous))
        }
    }

    private func configuredManagedIntegrationFieldSummaries(
        for scope: ProjectEnvironmentScope
    ) -> [ManagedIntegrationFieldSummary] {
        ProjectIntegrations.all
            .flatMap { definition in
                definition.fields
                    .filter { $0.scope == scope }
                    .map { field in
                        let currentValue = managedDrafts[definition.id]?[field.envKey] ?? ""
                        let isConfiguredRemotely =
                            scope == .hosted
                                && currentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && remoteHostedKeys.contains(field.envKey)
                        return ManagedIntegrationFieldSummary(
                            integrationID: definition.id,
                            integrationTitle: definition.title,
                            field: field,
                            currentValue: currentValue,
                            isConfiguredRemotely: isConfiguredRemotely
                        )
                    }
            }
            .filter(\.isConfigured)
            .sorted {
                if $0.integrationTitle != $1.integrationTitle {
                    return $0.integrationTitle.localizedCaseInsensitiveCompare($1.integrationTitle) == .orderedAscending
                }
                return $0.field.envKey.localizedCaseInsensitiveCompare($1.field.envKey) == .orderedAscending
            }
    }

    private func managedIntegrationRow(
        _ summary: ManagedIntegrationFieldSummary
    ) -> some View {
        Button {
            openIntegrationDetail(summary.integrationID)
        } label: {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.field.envKey)
                        .font(Theme.geistMono(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)

                    Text("\(summary.integrationTitle) · \(summary.field.label) · \(scopeSummary(for: summary.field.scope))")
                        .font(Theme.geist(10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(width: 260, alignment: .leading)

                managedIntegrationValueCell(summary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func managedIntegrationValueCell(
        _ summary: ManagedIntegrationFieldSummary
    ) -> some View {
        if summary.field.scope == .hosted && summary.isConfiguredRemotely && summary.currentValue.isEmpty {
            HStack(spacing: Theme.spacingSM) {
                Text("Configured in Supabase")
                    .font(Theme.geistMono(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Text("Backend storage")
                    .font(Theme.geist(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(summary.currentValue)
                .font(Theme.geistMono(12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: Theme.spacingLG) {
            Text("Variable")
                .font(Theme.geistMono(12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 260, alignment: .leading)

            Text("Value")
                .font(Theme.geistMono(12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: 28, height: 1)
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingMD)
    }

    private func variableRow(variable: Binding<ProjectEnvironmentVariable>) -> some View {
        let variableID = variable.wrappedValue.id
        let keyPlaceholder = variable.wrappedValue.scope == .hosted ? "OPENAI_API_KEY" : "PUBLIC_API_BASE_URL"

        return HStack(alignment: .top, spacing: Theme.spacingLG) {
            VStack(alignment: .leading, spacing: 6) {
                tableField(
                    text: variable.key,
                    fieldID: "custom:\(variableID):key",
                    placeholder: keyPlaceholder,
                    isSecure: false,
                    font: Theme.geistMono(12, weight: .medium)
                )

                rowMeta(for: variable.wrappedValue)
            }
            .frame(width: 260, alignment: .leading)

            valueField(variable: variable)

            Button {
                removeVariable(id: variableID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Remove variable")
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, 10)
    }

    private func valueField(variable: Binding<ProjectEnvironmentVariable>) -> some View {
        let variableID = variable.wrappedValue.id
        let isSensitive = variable.wrappedValue.scope == .hosted
        let fieldID = "custom:\(variableID):value"
        let shouldRevealValue = !isSensitive || revealedSensitiveFieldIDs.contains(fieldID)

        return HStack(alignment: .center, spacing: Theme.spacingSM) {
            tableField(
                text: variable.value,
                fieldID: fieldID,
                placeholder: isSensitive ? "Secret value" : "Value",
                isSecure: isSensitive && !shouldRevealValue,
                font: Theme.geistMono(12, weight: .medium)
            )

            if isSensitive {
                Button {
                    toggleSensitiveValueVisibility(id: fieldID)
                } label: {
                    Image(systemName: shouldRevealValue ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(shouldRevealValue ? "Hide value" : "Show value")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowMeta(for variable: ProjectEnvironmentVariable) -> some View {
        let status = rowSaveState(for: variable)

        switch status {
        case .empty:
            Text("Use letters, numbers, and underscores.")
                .font(Theme.geist(10))
                .foregroundStyle(Theme.textTertiary)
        case .saved, .unsaved:
            HStack(spacing: 6) {
                Circle()
                    .fill(status.foreground)
                    .frame(width: 6, height: 6)

                Text("\(status.inlineLabel) · \(scopeSummary(for: variable.scope)) · \(storageLabel(for: variable.scope))")
                    .font(Theme.geist(10, weight: .medium))
                    .foregroundStyle(status.foreground)
            }
        }
    }

    private func scopeSummary(for scope: ProjectEnvironmentScope) -> String {
        switch scope {
        case .client:
            return "Public client"
        case .hosted:
            return "Backend secret"
        }
    }

    private func storageLabel(for scope: ProjectEnvironmentScope) -> String {
        scope == .hosted ? "Backend storage" : "`.env.local`"
    }

    private func tableField(
        text: Binding<String>,
        fieldID: String,
        placeholder: String,
        isSecure: Bool,
        font: Font,
        validationTint: Color? = nil
    ) -> some View {
        let isFocused = focusedFieldID == fieldID
        let strokeColor: Color
        if let validationTint {
            strokeColor = validationTint.opacity(isFocused ? 0.55 : 0.35)
        } else {
            strokeColor = isFocused ? Theme.accent.opacity(0.35) : Theme.separator
        }

        return Group {
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
            }
        }
        .font(font)
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .fill(isFocused ? (validationTint ?? Theme.accent).opacity(0.10) : Theme.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .focused($focusedFieldID, equals: fieldID)
    }

    private var meaningfulCustomDraftVariables: [ProjectEnvironmentVariable] {
        customDraftVariables.filter(Self.hasMeaningfulContent)
    }

    private var clientCustomDraftVariables: [ProjectEnvironmentVariable] {
        customDraftVariables.filter { $0.scope == .client }
    }

    private var hostedCustomDraftVariables: [ProjectEnvironmentVariable] {
        customDraftVariables.filter { $0.scope == .hosted }
    }

    private var normalizedCustomDraftVariables: [ProjectEnvironmentVariable] {
        customDraftVariables.compactMap { variable in
            let trimmedKey = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasContent = !trimmedKey.isEmpty || !variable.value.isEmpty
            guard hasContent else { return nil }

            return ProjectEnvironmentVariable(
                id: variable.id,
                key: trimmedKey,
                description: variable.description,
                value: variable.value,
                scope: variable.scope
            )
        }
    }

    private var payloadVariables: [ProjectEnvironmentVariable] {
        ProjectIntegrations.mergedVariables(
            managedDrafts: managedDrafts,
            customVariables: normalizedCustomDraftVariables,
            existingVariables: baselineEnvironmentVariables,
            remoteHostedKeys: remoteHostedKeys
        )
    }

    private var hasUnsavedChanges: Bool {
        canonicalVariables(payloadVariables) != canonicalVariables(baselineEnvironmentVariables)
    }

    private var validationMessage: String? {
        for definition in ProjectIntegrations.all {
            let values = managedDrafts[definition.id] ?? [:]
            for field in definition.fields {
                if let fieldValidationMessage = ProjectIntegrations.validationMessage(
                    for: definition.id,
                    envKey: field.envKey,
                    value: values[field.envKey] ?? ""
                ) {
                    return "\(definition.title) \(field.label): \(fieldValidationMessage)"
                }
            }
        }

        let hasHostedValues = ProjectIntegrations.all.contains { definition in
            definition.fields.contains { field in
                field.scope == .hosted
                    && !(managedDrafts[definition.id]?[field.envKey]?
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
        }
        if hasHostedValues,
           managedDrafts[.supabase]?["SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            return "Connect Supabase before saving hosted keys."
        }

        var seenKeys: Set<String> = []

        for variable in customDraftVariables {
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasValue = !variable.value.isEmpty

            if key.isEmpty {
                if hasValue {
                    return "Add a variable name before saving."
                }
                continue
            }

            if ProjectIntegrations.managedKeys.contains(key) {
                return "`\(key)` is managed on its own integration page."
            }

            if key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) == nil {
                return "Variable names can contain letters, numbers, and underscores, and cannot start with a number."
            }

            if !seenKeys.insert(key).inserted {
                return "Duplicate variable names aren't allowed."
            }
        }

        return nil
    }

    private func syncDraft(force: Bool) {
        guard force else { return }
        applyDraftState(from: baselineEnvironmentVariables)
        syncSelectedSupabaseProjectFromDrafts()
        syncSelectedSuperwallContextFromState()
        revealedSensitiveFieldIDs = []
        hasLoadedInitialState = true
        statusMessage = nil
    }

    private func applyDraftState(from variables: [ProjectEnvironmentVariable]) {
        managedDrafts = Dictionary(
            uniqueKeysWithValues: ProjectIntegrations.all.map { definition in
                (definition.id, ProjectIntegrations.values(for: definition, in: variables))
            }
        )

        let custom = ProjectIntegrations.customVariables(from: variables)
        customDraftVariables = custom
    }

    private func applyPendingIntegrationFocusIfNeeded() {
        guard let pending = viewModel.pendingEnvironmentIntegrationFocus else { return }
        selectedIntegration = pending
        viewModel.pendingEnvironmentIntegrationFocus = nil
    }

    private func binding(for integrationID: ProjectIntegrationID, envKey: String) -> Binding<String> {
        Binding(
            get: {
                managedDrafts[integrationID]?[envKey] ?? ""
            },
            set: { newValue in
                var values = managedDrafts[integrationID] ?? [:]
                values[envKey] = newValue
                managedDrafts[integrationID] = values
                statusMessage = nil

                if integrationID == .supabase {
                    syncSelectedSupabaseProjectFromDrafts()
                }
            }
        )
    }

    private func customVariableBinding(id: String) -> Binding<ProjectEnvironmentVariable> {
        Binding(
            get: {
                customDraftVariables.first(where: { $0.id == id }) ?? ProjectEnvironmentVariable(id: id)
            },
            set: { updated in
                guard let index = customDraftVariables.firstIndex(where: { $0.id == id }) else { return }
                customDraftVariables[index] = updated
                statusMessage = nil
            }
        )
    }

    private func addVariable(scope: ProjectEnvironmentScope) {
        let newVariable = ProjectEnvironmentVariable(scope: scope)
        customDraftVariables.append(newVariable)
        focusedFieldID = "custom:\(newVariable.id):key"
        statusMessage = nil
    }

    private func removeVariable(id: String) {
        customDraftVariables.removeAll { $0.id == id }
        revealedSensitiveFieldIDs = Set(revealedSensitiveFieldIDs.filter { !$0.contains(id) })
        if focusedFieldID?.contains(id) == true {
            focusedFieldID = nil
        }
        statusMessage = nil
    }

    private func toggleSensitiveValueVisibility(id: String) {
        if revealedSensitiveFieldIDs.contains(id) {
            revealedSensitiveFieldIDs.remove(id)
        } else {
            revealedSensitiveFieldIDs.insert(id)
        }
    }

    private func save() {
        guard validationMessage == nil else { return }

        let payload = payloadVariables
        isSaving = true
        statusMessage = nil

        Task {
            do {
                try await viewModel.saveEnvironmentVariables(payload)

                await MainActor.run {
                    applyDraftState(from: payload)
                    isSaving = false
                    statusMessage = payload.isEmpty ? "Integrations cleared." : "Integrations saved."
                    refreshSupabaseSchemaPreviewIfNeeded()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private var saveSummary: String {
        let configuredManagedCount = ProjectIntegrations.all.reduce(0) { partialResult, definition in
            partialResult + definition.fields.filter { field in
                !(managedDrafts[definition.id]?[field.envKey]?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    || remoteHostedKeys.contains(field.envKey)
            }.count
        }
        let customCount = meaningfulCustomDraftVariables.count
        let totalCount = configuredManagedCount + customCount

        guard totalCount > 0 else { return "No integration keys added yet." }
        if hasUnsavedChanges {
            return "Changes ready to save"
        }
        return "\(totalCount) integration key\(totalCount == 1 ? "" : "s") configured"
    }

    private func rowSaveState(for variable: ProjectEnvironmentVariable) -> RowSaveState {
        guard Self.hasMeaningfulContent(variable) else { return .empty }

        let normalizedVariable = ProjectEnvironmentVariable(
            id: variable.id,
            key: variable.key.trimmingCharacters(in: .whitespacesAndNewlines),
            description: variable.description,
            value: variable.value,
            scope: variable.scope
        )

        let currentCustomVariables = ProjectIntegrations.customVariables(from: baselineEnvironmentVariables)
        return currentCustomVariables.contains(normalizedVariable) ? .saved : .unsaved
    }

    private func refreshSupabaseSchemaPreviewIfNeeded() {
        guard selectedIntegration == .supabase else { return }
        guard selectedSupabaseProjectRef.isEmpty else { return }
        supabaseSchemaPreview = SupabaseSchemaVisualizer.load(from: viewModel.localProjectPath)
        syncSelectedSupabaseMigration()
    }

    private func refreshSupabaseLinkedProjects() {
        guard let currentProjectID = viewModel.activeProject?.id else {
            supabaseLinkedProjectNamesByRef = [:]
            return
        }

        let allProjects = viewModel.projects + viewModel.archivedProjects
        Task {
            var linkedProjectNamesByRef: [String: String] = [:]

            for project in allProjects where project.id != currentProjectID {
                let variables = await viewModel.localStore.loadEnvironmentVariables(
                    projectName: project.name,
                    projectId: project.id
                )
                guard let url = variables.first(where: { $0.normalizedKey == "SUPABASE_URL" })?.value,
                      let ref = SupabaseManagementService.projectRef(from: url) else {
                    continue
                }
                linkedProjectNamesByRef[ref] = project.name
            }

            await MainActor.run {
                supabaseLinkedProjectNamesByRef = linkedProjectNamesByRef
            }
        }
    }

    private func selectSupabaseProject(_ project: SupabaseManagementProject) {
        if let linkedProjectName = supabaseLinkedProjectNamesByRef[project.ref],
           project.ref != selectedSupabaseProjectRef {
            supabaseManagementError = "\(project.name) is already linked to \(linkedProjectName)."
            supabaseManagementMessage = nil
            return
        }

        isSupabaseProjectPickerPresented = false
        loadSupabaseProject(project)
    }

    private func loadSupabaseManagementStateIfNeeded(force: Bool = false) {
        guard force || !hasLoadedSupabaseManagementState else {
            refreshSupabaseLinkedProjects()
            syncSelectedSupabaseProjectFromDrafts()
            return
        }

        hasLoadedSupabaseManagementState = true
        isSupabaseManagementLoading = true

        Task {
            let oauthService = SupabaseManagementOAuthService.shared

            guard oauthService.hasUsableSession() else {
                await MainActor.run {
                    resetSupabaseManagementState()
                }
                return
            }

            do {
                let service = try await authenticatedSupabaseManagementService()
                let account = try await loadSupabaseManagementAccount(using: service)
                let hasSavedProjectLink = !(managedDrafts[.supabase]?["SUPABASE_URL"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty

                await MainActor.run {
                    hasSupabaseConnection = true
                    supabaseProjects = account.projects
                    supabaseOrganizations = account.organizations
                    isSupabaseManagementLoading = false
                    supabaseManagementError = nil
                    supabaseManagementMessage = selectedSupabaseProjectRef.isEmpty && !hasSavedProjectLink
                        ? "Choose a project for \(currentProjectName)."
                        : nil
                    refreshSupabaseLinkedProjects()
                    syncSelectedSupabaseProjectFromDrafts()
                }
            } catch {
                await MainActor.run {
                    resetSupabaseManagementState(error: friendlySupabaseErrorMessage(for: error, context: .loadAccount))
                }
            }
        }
    }

    private func connectSupabaseAccount() {
        isSupabaseConnecting = true
        supabaseManagementError = nil
        supabaseManagementMessage = nil

        Task {
            do {
                let appAccessToken = try await requireAuthenticatedAppAccessToken()
                try await SupabaseManagementOAuthService.shared.connect(appAccessToken: appAccessToken)
                let account = try await loadSupabaseManagementAccount()

                await MainActor.run {
                    hasSupabaseConnection = true
                    supabaseProjects = account.projects
                    supabaseOrganizations = account.organizations
                    isSupabaseConnecting = false
                    supabaseManagementMessage = account.projects.isEmpty
                        ? "Supabase connected. Create the first project for \(currentProjectName)."
                        : "Supabase connected."
                    supabaseManagementError = nil
                    refreshSupabaseLinkedProjects()
                    syncSelectedSupabaseProjectFromDrafts()
                }
            } catch {
                await MainActor.run {
                    isSupabaseConnecting = false
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        supabaseManagementError = nil
                        supabaseManagementMessage = nil
                        return
                    }
                    hasSupabaseConnection = SupabaseManagementOAuthService.shared.hasUsableSession()
                    supabaseManagementError = friendlySupabaseErrorMessage(for: error, context: .connect)
                    if !hasSupabaseConnection {
                        resetSupabaseManagementState(error: friendlySupabaseErrorMessage(for: error, context: .connect))
                    }
                }
            }
        }
    }

    private func createSupabaseProject(in organization: SupabaseManagementOrganization?) {
        isSupabaseCreatingProject = true
        isSupabaseProjectPickerPresented = false
        supabaseManagementError = nil
        supabaseManagementMessage = "Creating \(currentProjectName)..."

        Task {
            do {
                let service = try await authenticatedSupabaseManagementService()
                let organization = try await resolveSupabaseOrganization(from: organization, service: service)
                let project = try await service.createProject(name: currentProjectName, organization: organization)
                let details = try await service.waitForProvisionedProject(ref: project.ref)
                async let liveSchemaTask = service.fetchLiveSchemaPreview(for: details.project.ref)
                async let accountTask = loadSupabaseManagementAccount(using: service)
                let liveSchema = try? await liveSchemaTask
                let account = try await accountTask

                await MainActor.run {
                    supabaseProjects = account.projects
                    supabaseOrganizations = account.organizations
                    isSupabaseCreatingProject = false
                    applySupabaseConnection(details, liveSchema: liveSchema)
                    supabaseManagementMessage = "\(details.project.name) created."
                    refreshSupabaseLinkedProjects()
                }
            } catch {
                await MainActor.run {
                    isSupabaseCreatingProject = false
                    supabaseManagementError = friendlySupabaseErrorMessage(for: error, context: .createProject)
                    supabaseManagementMessage = nil
                }
            }
        }
    }

    private func resolveSupabaseOrganization(
        from organization: SupabaseManagementOrganization?,
        service: SupabaseManagementService
    ) async throws -> SupabaseManagementOrganization {
        if let organization {
            return organization
        }

        let organizations = try await service.fetchOrganizations()
        await MainActor.run {
            supabaseOrganizations = organizations
        }

        if organizations.count == 1, let organization = organizations.first {
            return organization
        }

        if organizations.isEmpty {
            throw SupabaseManagementServiceError.invalidInput("No Supabase organization is available on this account.")
        }

        throw SupabaseManagementServiceError.invalidInput("Choose which Supabase organization should own the new project.")
    }

    private func disconnectSupabaseAccount() {
        SupabaseManagementOAuthService.shared.disconnect()

        Task { @MainActor in
            isSupabaseCreatingProject = false
            isSupabaseProjectPickerPresented = false
            resetSupabaseManagementState()
        }
    }

    private func openSelectedSupabaseProject() {
        openSelectedSupabaseDashboardURL(
            selectedSupabaseDashboardURL,
            successMessage: "Opened the linked Supabase project."
        )
    }

    private func openSelectedSupabaseDashboardURL(_ url: URL?, successMessage: String) {
        guard let url else {
            supabaseManagementError = friendlySupabaseErrorMessage(
                for: APIError.invalidResponse,
                context: .openProject
            )
            supabaseManagementMessage = nil
            return
        }
        guard NSWorkspace.shared.open(url) else {
            supabaseManagementError = friendlySupabaseErrorMessage(
                for: APIError.invalidResponse,
                context: .openProject
            )
            supabaseManagementMessage = nil
            return
        }

        supabaseManagementError = nil
        supabaseManagementMessage = successMessage
    }

    private func requireAuthenticatedAppAccessToken() async throws -> String {
        guard let accessToken = await auth.validAccessToken() else {
            throw SupabaseManagementOAuthError.missingAppSession
        }
        return accessToken
    }

    private func authenticatedSupabaseManagementService() async throws -> SupabaseManagementService {
        let appAccessToken = try await requireAuthenticatedAppAccessToken()
        _ = try await SupabaseManagementOAuthService.shared.validAccessToken(appAccessToken: appAccessToken)
        return .shared
    }

    private func loadSupabaseManagementAccount(
        using service: SupabaseManagementService = .shared
    ) async throws -> (
        projects: [SupabaseManagementProject],
        organizations: [SupabaseManagementOrganization]
    ) {
        async let projectsTask = service.fetchProjects()
        async let organizationsTask = service.fetchOrganizations()
        return (
            projects: try await projectsTask,
            organizations: (try? await organizationsTask) ?? []
        )
    }

    private func resetSupabaseManagementState(error: String? = nil, message: String? = nil) {
        hasSupabaseConnection = false
        supabaseProjects = []
        supabaseOrganizations = []
        supabaseLinkedProjectNamesByRef = [:]
        selectedSupabaseProjectRef = ""
        supabaseAuthProviders = nil
        isSupabaseManagementLoading = false
        supabaseManagementError = error
        supabaseManagementMessage = message
        isSupabaseLoadingSchema = false
        refreshSupabaseSchemaPreviewIfNeeded()
        syncSelectedSupabaseMigration()
    }

    private func syncSelectedSupabaseProjectFromDrafts() {
        guard !supabaseProjects.isEmpty else {
            selectedSupabaseProjectRef = ""
            supabaseAuthProviders = nil
            refreshSupabaseSchemaPreviewIfNeeded()
            return
        }

        let currentURL = {
            let draftURL = managedDrafts[.supabase]?["SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !draftURL.isEmpty {
                return draftURL
            }
            let linkedURL = viewModel.projectBackendState.linkedProjectURL?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !linkedURL.isEmpty {
                return linkedURL
            }
            let linkedRef = viewModel.projectBackendState.linkedProjectRef?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return linkedRef.isEmpty ? "" : "https://\(linkedRef).supabase.co"
        }()
        guard let matchedRef = SupabaseManagementService.projectRef(from: currentURL),
              let matchedProject = supabaseProjects.first(where: { $0.ref == matchedRef }) else {
            selectedSupabaseProjectRef = ""
            supabaseAuthProviders = nil
            refreshSupabaseSchemaPreviewIfNeeded()
            return
        }

        guard matchedProject.ref != selectedSupabaseProjectRef || supabaseAuthProviders == nil else {
            return
        }

        selectedSupabaseProjectRef = matchedProject.ref
        loadSupabaseProject(matchedProject)
    }

    private func loadSupabaseProject(_ project: SupabaseManagementProject) {
        selectedSupabaseProjectRef = project.ref
        supabaseAuthProviders = nil
        supabaseManagementError = nil
        supabaseManagementMessage = "Loading \(project.name)..."
        isSupabaseLoadingSchema = true

        Task {
            do {
                let service = try await authenticatedSupabaseManagementService()
                let details = try await service.fetchConnectionDetails(for: project)
                let liveSchema = try? await service.fetchLiveSchemaPreview(for: project.ref)

                await MainActor.run {
                    guard selectedSupabaseProjectRef == project.ref else { return }
                    applySupabaseConnection(details, liveSchema: liveSchema)
                }
            } catch {
                await MainActor.run {
                    guard selectedSupabaseProjectRef == project.ref else { return }
                    isSupabaseLoadingSchema = false
                    supabaseManagementError = friendlySupabaseErrorMessage(for: error, context: .loadProject)
                    supabaseManagementMessage = nil
                    supabaseAuthProviders = nil
                    selectedSupabaseProjectRef = project.ref
                    supabaseSchemaPreview = SupabaseSchemaVisualizer.load(from: viewModel.localProjectPath)
                    syncSelectedSupabaseMigration()
                }
            }
        }
    }

    private func applySupabaseConnection(
        _ details: SupabaseProjectConnectionDetails,
        liveSchema: SupabaseSchemaPreview?
    ) {
        var values = managedDrafts[.supabase] ?? [:]
        values["SUPABASE_URL"] = details.url
        values["SUPABASE_ANON_KEY"] = details.publishableKey
        values["SUPABASE_PUBLISHABLE_KEY"] = details.publishableKey
        managedDrafts[.supabase] = values

        selectedSupabaseProjectRef = details.project.ref
        supabaseAuthProviders = details.authProviders
        isSupabaseLoadingSchema = false
        supabaseManagementError = nil
        supabaseManagementMessage = nil
        let localPreview = SupabaseSchemaVisualizer.load(from: viewModel.localProjectPath)
        supabaseSchemaPreview = (liveSchema ?? localPreview).mergingMetadata(from: localPreview)
        syncSelectedSupabaseMigration()
        statusMessage = nil
        persistSupabaseConnectionSelectionIfNeeded()
    }

    private func persistSupabaseConnectionSelectionIfNeeded() {
        let mergedVariables = payloadVariables
        guard canonicalVariables(mergedVariables) != canonicalVariables(viewModel.environmentVariables) else {
            return
        }

        Task {
            try? await viewModel.saveEnvironmentVariables(mergedVariables)
        }
    }

    private func loadSuperwallManagementStateIfNeeded(force: Bool = false) {
        guard force || !hasLoadedSuperwallManagementState else {
            refreshSuperwallLinkedProjects()
            syncSelectedSuperwallContextFromState()
            return
        }

        hasLoadedSuperwallManagementState = true
        isSuperwallManagementLoading = true

        runSuperwallTask(
            scope: .account,
            context: .loadAccount,
            finish: { isSuperwallManagementLoading = false },
            operation: {
                let service = SuperwallManagementService.shared
                guard await service.hasStoredCredential() else {
                    throw SuperwallManagementServiceError.missingAPIKey
                }
                return try await service.loadAccount()
            },
            onSuccess: { account in
                applySuperwallAccount(account, message: nil)
            },
            onFailure: { error in
                if case SuperwallManagementServiceError.missingAPIKey = error {
                    resetSuperwallManagementState()
                } else {
                    resetSuperwallManagementState(
                        error: friendlySuperwallErrorMessage(for: error, context: .loadAccount)
                    )
                }
            }
        )
    }

    private func connectSuperwallAccount() {
        let apiKey = superwallManagementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            setSuperwallStatus(error: "Enter a Superwall management API key first.")
            return
        }

        runSuperwallTask(
            scope: .account,
            context: .connect,
            start: {
                isSuperwallConnecting = true
                setSuperwallStatus()
            },
            finish: { isSuperwallConnecting = false },
            operation: {
                try await SuperwallManagementService.shared.connect(apiKey: apiKey)
            },
            onSuccess: { account in
                superwallManagementAPIKey = ""
                applySuperwallAccount(
                    account,
                    message: account.projects.isEmpty ? nil : "Superwall connected."
                )
            },
            onFailure: { error in
                resetSuperwallManagementState(
                    error: friendlySuperwallErrorMessage(for: error, context: .connect)
                )
            }
        )
    }

    private func disconnectSuperwallAccount() {
        Task {
            await SuperwallManagementService.shared.clearCredential()
            await MainActor.run {
                resetSuperwallManagementState(message: "Superwall disconnected.")
            }
        }
    }

    private func refreshSuperwallLinkedProjects() {
        guard let currentProjectID = viewModel.activeProject?.id else {
            superwallLinkedProjectNamesByApplicationID = [:]
            return
        }

        let allProjects = viewModel.projects + viewModel.archivedProjects
        superwallLinkedProjectNamesByApplicationID = Dictionary(
            uniqueKeysWithValues: allProjects.compactMap { project in
                guard project.id != currentProjectID,
                      let applicationID = project.superwallState?.applicationID,
                      !applicationID.isEmpty else {
                    return nil
                }
                return (applicationID, project.name)
            }
        )
    }

    private func syncSelectedSuperwallContextFromState() {
        let state = viewModel.projectSuperwallState

        if let organizationID = state.organizationID,
           superwallOrganizations.contains(where: { $0.id == organizationID }) {
            selectedSuperwallOrganizationID = organizationID
        } else if state.organizationID == nil {
            selectedSuperwallOrganizationID = ""
        }

        if let projectID = state.projectID,
           superwallProjects.contains(where: { $0.id == projectID }) {
            selectedSuperwallProjectID = projectID
        } else if state.projectID == nil {
            selectedSuperwallProjectID = ""
        }

        if let applicationID = state.applicationID,
           selectedSuperwallProject?.applications.contains(where: { $0.id == applicationID }) == true
            || superwallProjects.contains(where: { $0.applications.contains(where: { $0.id == applicationID }) }) {
            selectedSuperwallApplicationID = applicationID
            loadSuperwallPaywallsIfNeeded(applicationID: applicationID)
        } else if state.applicationID == nil {
            selectedSuperwallApplicationID = ""
            superwallPaywalls = []
        }

        if let paywallID = state.paywallID, !paywallID.isEmpty {
            selectedSuperwallPaywallID = paywallID
        } else {
            selectedSuperwallPaywallID = ""
        }
    }

    private func loadSuperwallPaywallsIfNeeded(applicationID: String, force: Bool = false) {
        let trimmedApplicationID = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApplicationID.isEmpty else {
            superwallPaywalls = []
            selectedSuperwallPaywallID = ""
            return
        }

        if !force,
           selectedSuperwallApplicationID == trimmedApplicationID,
           !superwallPaywalls.isEmpty {
            return
        }

        runSuperwallTask(
            scope: .paywalls,
            context: .paywalls,
            operation: {
                try await SuperwallManagementService.shared.listPaywalls(applicationID: trimmedApplicationID)
            },
            onSuccess: { paywalls in
                superwallPaywalls = paywalls
                guard selectedSuperwallPaywallID.isEmpty
                        || !paywalls.contains(where: { $0.id == selectedSuperwallPaywallID }) else {
                    return
                }
                if let savedPaywallID = viewModel.projectSuperwallState.paywallID,
                   paywalls.contains(where: { $0.id == savedPaywallID }) {
                    selectedSuperwallPaywallID = savedPaywallID
                } else if paywalls.count == 1 {
                    selectedSuperwallPaywallID = paywalls[0].id
                } else {
                    selectedSuperwallPaywallID = ""
                }
            },
            onFailure: { error in
                superwallPaywalls = []
                guard superwallManagementError == nil else { return }
                superwallManagementError = friendlySuperwallErrorMessage(for: error, context: .paywalls)
            }
        )
    }

    private func linkSuperwallApplication(_ application: SuperwallApplicationChoice) {
        selectedSuperwallOrganizationID = application.organizationID
        selectedSuperwallProjectID = application.projectID
        selectedSuperwallApplicationID = application.applicationID
        selectedSuperwallPaywallID = ""
        superwallPaywalls = []
        bootstrapSuperwallProjectLink()
    }

    private func bootstrapSuperwallProjectLink() {
        guard requireSuperwallConnection() else { return }

        if let linkedProjectName = selectedSuperwallApplicationLinkedElsewhereName,
           selectedSuperwallApplication?.id != viewModel.projectSuperwallState.applicationID {
            setSuperwallStatus(error: "This Superwall application is already linked to \(linkedProjectName).")
            return
        }

        runSuperwallTask(
            scope: .projectLink,
            context: .bootstrapProject,
            start: {
                isSuperwallBootstrappingProject = true
                setSuperwallStatus(message: "Linking Superwall project and application...")
            },
            finish: { isSuperwallBootstrappingProject = false },
            operation: {
                try await SuperwallManagementService.shared.bootstrapProject(
                    projectName: currentProjectName,
                    bundleID: currentBundleID,
                    state: viewModel.projectSuperwallState,
                    preferredOrganizationID: selectedSuperwallOrganizationID.isEmpty ? nil : selectedSuperwallOrganizationID,
                    preferredProjectID: selectedSuperwallProjectID.isEmpty ? nil : selectedSuperwallProjectID,
                    preferredApplicationID: selectedSuperwallApplicationID.isEmpty ? nil : selectedSuperwallApplicationID
                )
            },
            onSuccess: { state in
                Task {
                    await viewModel.saveProjectSuperwallState(state)
                    await persistSuperwallPublicRuntimeKeyIfNeeded(state.applicationPublicAPIKey)
                    await MainActor.run {
                        setSuperwallStatus(message: "Linked \(state.projectName ?? "Superwall project").")
                        refreshSuperwallLinkedProjects()
                        syncSelectedSuperwallContextFromState()
                        if let applicationID = state.applicationID {
                            loadSuperwallPaywallsIfNeeded(applicationID: applicationID, force: true)
                        }
                    }
                }
            }
        )
    }

    private func bootstrapSuperwallStarterMonetization() {
        guard requireLinkedSuperwallApplication() else { return }

        runSuperwallTask(
            scope: .starter,
            context: .bootstrapStarter,
            start: {
                isSuperwallBootstrappingStarter = true
                setSuperwallStatus(message: "Attaching starter Superwall products and preview campaign to the selected paywall.")
            },
            finish: { isSuperwallBootstrappingStarter = false },
            operation: {
                try await SuperwallManagementService.shared.bootstrapStarterMonetization(
                    state: viewModel.projectSuperwallState,
                    bundleID: currentBundleID,
                    placements: ProjectSuperwallState.suggestedPlacements(
                        plan: viewModel.projectPlan,
                        tasks: viewModel.projectTasks
                    ),
                    previewAppUserID: superwallPreviewUserID,
                    paywallID: selectedSuperwallPaywallID.isEmpty ? nil : selectedSuperwallPaywallID
                )
            },
            onSuccess: { state in
                Task {
                    await viewModel.saveProjectSuperwallState(state)
                    await persistSuperwallPublicRuntimeKeyIfNeeded(state.applicationPublicAPIKey)
                    await MainActor.run {
                        setSuperwallStatus(message: "Superwall starter monetization is ready for preview/test mode.")
                        if let applicationID = state.applicationID {
                            loadSuperwallPaywallsIfNeeded(applicationID: applicationID, force: true)
                        }
                        selectedSuperwallPaywallID = state.paywallID ?? selectedSuperwallPaywallID
                        refreshSuperwallLinkedProjects()
                    }
                }
            }
        )
    }

    private func syncSuperwallPreviewTestUser() {
        guard requireLinkedSuperwallApplication() else { return }

        runSuperwallTask(
            scope: .previewUser,
            context: .syncPreviewUser,
            start: {
                isSuperwallSyncingPreviewUser = true
                setSuperwallStatus(message: "Syncing preview user test mode...")
            },
            finish: { isSuperwallSyncingPreviewUser = false },
            operation: {
                try await SuperwallManagementService.shared.syncPreviewTestUser(
                    state: viewModel.projectSuperwallState,
                    previewAppUserID: superwallPreviewUserID
                )
            },
            onSuccess: { state in
                Task {
                    await viewModel.saveProjectSuperwallState(state)
                    await MainActor.run {
                        setSuperwallStatus(message: "Preview user synced for Superwall test mode.")
                    }
                }
            }
        )
    }

    private func openSuperwallDashboard() {
        guard let url = linkedSuperwallDashboardURL,
              NSWorkspace.shared.open(url) else {
            setSuperwallStatus(error: "Link a Superwall application first.")
            return
        }

        setSuperwallStatus(message: "Opened the linked Superwall dashboard.")
    }

    private func openSuperwallPaywallsDashboard() {
        guard let url = linkedSuperwallPaywallsDashboardURL,
              NSWorkspace.shared.open(url) else {
            setSuperwallStatus(error: "Link a Superwall application first.")
            return
        }

        setSuperwallStatus(message: "Opened the linked Superwall paywalls.")
    }

    private func openSuperwallTemplatesDashboard() {
        guard let url = linkedSuperwallTemplatesDashboardURL,
              NSWorkspace.shared.open(url) else {
            setSuperwallStatus(error: "Link a Superwall application first.")
            return
        }

        setSuperwallStatus(message: "Opened the linked Superwall templates.")
    }

    private func openSuperwallSharedPaywallLink() {
        let trimmed = superwallSharedPaywallURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host.contains("superwall.com"),
              NSWorkspace.shared.open(url) else {
            setSuperwallStatus(error: "Enter a valid public Superwall paywall share link first.")
            return
        }

        setSuperwallStatus(
            message: "Opened the Superwall share link. Duplicate the paywall into the linked app, then refresh Paywalls and select it here."
        )
    }

    private func persistSuperwallPublicRuntimeKeyIfNeeded(_ publicAPIKey: String?) async {
        let trimmedValue = publicAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedValue.isEmpty else { return }

        let nextVariables: [ProjectEnvironmentVariable]? = await MainActor.run {
            let currentValue = managedDrafts[.superwall]?["SUPERWALL_PUBLIC_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard currentValue != trimmedValue,
                  let field = ProjectIntegrations.definition(for: .superwall).fields.first(where: { $0.envKey == "SUPERWALL_PUBLIC_API_KEY" }) else {
                return nil
            }

            var values = managedDrafts[.superwall] ?? [:]
            values["SUPERWALL_PUBLIC_API_KEY"] = trimmedValue
            managedDrafts[.superwall] = values
            statusMessage = nil

            var mergedVariables = payloadVariables.filter { $0.normalizedKey != "SUPERWALL_PUBLIC_API_KEY" }
            let existingID = viewModel.environmentVariables.first { $0.normalizedKey == "SUPERWALL_PUBLIC_API_KEY" }?.id
            mergedVariables.append(
                ProjectEnvironmentVariable(
                    id: existingID ?? UUID().uuidString,
                    key: "SUPERWALL_PUBLIC_API_KEY",
                    description: field.description,
                    value: trimmedValue,
                    scope: field.scope
                )
            )
            return mergedVariables
        }

        guard let nextVariables else { return }
        try? await viewModel.saveEnvironmentVariables(nextVariables)
    }

    private func resetSuperwallManagementState(error: String? = nil, message: String? = nil) {
        superwallTaskTokens = [:]
        hasSuperwallConnection = false
        superwallOrganizations = []
        superwallProjects = []
        superwallPaywalls = []
        superwallLinkedProjectNamesByApplicationID = [:]
        selectedSuperwallOrganizationID = ""
        selectedSuperwallProjectID = ""
        selectedSuperwallApplicationID = ""
        selectedSuperwallPaywallID = ""
        superwallSharedPaywallURL = ""
        isSuperwallManagementLoading = false
        isSuperwallConnecting = false
        isSuperwallBootstrappingProject = false
        isSuperwallBootstrappingStarter = false
        isSuperwallSyncingPreviewUser = false
        setSuperwallStatus(error: error, message: message)
    }

    private func friendlySupabaseErrorMessage(
        for error: Error,
        context: SupabaseErrorContext
    ) -> String {
        switch error {
        case SupabaseManagementOAuthError.missingAppSession, APIError.unauthorized:
            return "Sign in to 10x again, then reconnect Supabase."
        case SupabaseManagementOAuthError.expiredSession:
            return "Your Supabase connection expired. Reconnect Supabase and try again."
        case SupabaseManagementOAuthError.oauthFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "\(context.failurePrefix) Try again." : "\(context.failurePrefix) \(trimmed)"
        case SupabaseManagementOAuthError.invalidAuthorizeURL,
             SupabaseManagementOAuthError.callbackMissing,
             SupabaseManagementOAuthError.codeMissing,
             SupabaseManagementOAuthError.stateMismatch:
            return "Supabase sign-in did not finish cleanly. Try connecting again."
        case SupabaseManagementServiceError.missingAccessToken:
            return "Reconnect Supabase to keep using your projects."
        case SupabaseManagementServiceError.invalidInput(let detail):
            return detail
        case SupabaseManagementServiceError.missingPublishableKey:
            return "This Supabase project is missing a client key. Check the project settings and try again."
        case SupabaseManagementServiceError.invalidResponse,
             SupabaseManagementServiceError.malformedResponse(_):
            return "\(context.failurePrefix) Supabase returned incomplete project details."
        case SupabaseManagementServiceError.requestFailed(let statusCode, let message):
            if statusCode == 401 || statusCode == 403 {
                return "Supabase denied that request. Reconnect Supabase and try again."
            }
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "Unknown error"
                ? "\(context.failurePrefix) Try again in a moment."
                : "\(context.failurePrefix) \(trimmed)"
        case APIError.networkError(_), is URLError:
            return "Couldn't reach Supabase. Check your connection and try again."
        case APIError.serverError(_, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "Unknown error"
                ? "\(context.failurePrefix) Try again in a moment."
                : "\(context.failurePrefix) \(trimmed)"
        case APIError.invalidURL, APIError.invalidResponse, APIError.decodingError(_):
            return "\(context.failurePrefix) Try again in a moment."
        default:
            let trimmed = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "\(context.failurePrefix) Try again in a moment." : "\(context.failurePrefix) \(trimmed)"
        }
    }

    private func friendlySuperwallErrorMessage(
        for error: Error,
        context: SuperwallErrorContext
    ) -> String {
        switch error {
        case SuperwallManagementServiceError.missingAPIKey:
            return "Connect Superwall again to keep using the linked account."
        case SuperwallManagementServiceError.invalidInput(let detail):
            return detail
        case SuperwallManagementServiceError.invalidResponse,
             SuperwallManagementServiceError.malformedResponse(_):
            return "\(context.failurePrefix) Superwall returned incomplete account data."
        case SuperwallManagementServiceError.requestFailed(let statusCode, let message):
            if statusCode == 401 || statusCode == 403 {
                return "Superwall denied that request. Reconnect with a valid management API key and try again."
            }
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "Unknown error"
                ? "\(context.failurePrefix) Try again in a moment."
                : "\(context.failurePrefix) \(trimmed)"
        case APIError.networkError(_), is URLError:
            return "Couldn't reach Superwall. Check your connection and try again."
        default:
            let trimmed = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "\(context.failurePrefix) Try again in a moment." : "\(context.failurePrefix) \(trimmed)"
        }
    }

    private func syncSelectedSupabaseMigration() {
        if let selectedSupabaseMigrationID,
           supabaseSchemaPreview.migrations.contains(where: { $0.id == selectedSupabaseMigrationID }) {
            return
        }
        selectedSupabaseMigrationID = supabaseSchemaPreview.migrations.first?.id
    }

    private nonisolated static func hasMeaningfulContent(_ variable: ProjectEnvironmentVariable) -> Bool {
        let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty || !variable.value.isEmpty
    }

    private func canonicalVariables(_ variables: [ProjectEnvironmentVariable]) -> [CanonicalVariable] {
        variables
            .map {
                CanonicalVariable(
                    key: $0.key.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: $0.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    value: $0.value,
                    scope: $0.scope
                )
            }
            .filter { !$0.key.isEmpty }
            .sorted()
    }

    private struct CanonicalVariable: Equatable, Comparable {
        let key: String
        let description: String
        let value: String
        let scope: ProjectEnvironmentScope

        static func < (lhs: CanonicalVariable, rhs: CanonicalVariable) -> Bool {
            if lhs.key != rhs.key {
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            if lhs.scope != rhs.scope {
                return lhs.scope.rawValue.localizedCaseInsensitiveCompare(rhs.scope.rawValue) == .orderedAscending
            }
            if lhs.description != rhs.description {
                return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
            }
            return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
        }
    }

    private enum RowSaveState: Equatable {
        case empty
        case saved
        case unsaved

        var inlineLabel: String {
            switch self {
            case .empty:
                return "Draft"
            case .saved:
                return "Saved"
            case .unsaved:
                return "Needs save"
            }
        }

        var foreground: Color {
            switch self {
            case .empty:
                return Theme.textTertiary
            case .saved:
                return Theme.accent
            case .unsaved:
                return Theme.warning
            }
        }
    }

    private enum SupabaseErrorContext {
        case connect
        case createProject
        case loadAccount
        case loadProject
        case openProject

        var failurePrefix: String {
            switch self {
            case .connect:
                return "Couldn't connect Supabase."
            case .createProject:
                return "Couldn't create the Supabase project."
            case .loadAccount:
                return "Couldn't load your Supabase projects."
            case .loadProject:
                return "Couldn't use this Supabase project."
            case .openProject:
                return "Couldn't open the Supabase dashboard."
            }
        }
    }

    private enum SuperwallErrorContext {
        case connect
        case loadAccount
        case bootstrapProject
        case bootstrapStarter
        case syncPreviewUser
        case paywalls

        var failurePrefix: String {
            switch self {
            case .connect:
                return "Couldn't connect Superwall."
            case .loadAccount:
                return "Couldn't load your Superwall account."
            case .bootstrapProject:
                return "Couldn't link the Superwall project and iOS application."
            case .bootstrapStarter:
                return "Couldn't create the Superwall starter monetization setup."
            case .syncPreviewUser:
                return "Couldn't sync the Superwall preview user."
            case .paywalls:
                return "Couldn't load Superwall paywalls."
            }
        }
    }

    private enum SuperwallTaskScope: Hashable {
        case account
        case paywalls
        case projectLink
        case starter
        case previewUser
    }
}
