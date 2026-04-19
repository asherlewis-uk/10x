import Foundation

enum SuperwallManagementServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case malformedResponse(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Connect Superwall to load your account."
        case .invalidResponse:
            return "Superwall returned an unexpected response."
        case .requestFailed(let statusCode, let message):
            return "Superwall request failed (\(statusCode)): \(message)"
        case .malformedResponse(let context):
            return "Superwall returned incomplete \(context)."
        case .invalidInput(let detail):
            return detail
        }
    }
}

struct SuperwallManagementOrganization: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let slug: String?
}

struct SuperwallManagementApplication: Identifiable, Equatable, Sendable {
    let id: String
    let platform: String
    let name: String
    let publicAPIKey: String
    let bundleID: String?
    let appID: String?
    let slug: String?
    let integrated: Bool
    let archivedAt: String?
    let featuresEnabled: [String]

    nonisolated var dashboardURL: URL? {
        URL(string: "https://superwall.com/applications/\(id)/rules")
    }

    nonisolated var isIOS: Bool {
        platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ios"
    }
}

struct SuperwallManagementProject: Identifiable, Equatable, Sendable {
    let id: String
    let organizationID: String
    let name: String
    let applications: [SuperwallManagementApplication]
    let archived: Bool
    let metadata: [String: String]
    let createdAt: String?
    let updatedAt: String?

    nonisolated func exactIOSApplication(matching bundleID: String?) -> SuperwallManagementApplication? {
        let normalizedBundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let normalizedBundleID, !normalizedBundleID.isEmpty else { return nil }
        return applications.first(where: {
            $0.isIOS && $0.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedBundleID
        })
    }

    nonisolated func preferredIOSApplication(matching bundleID: String?) -> SuperwallManagementApplication? {
        if let exact = exactIOSApplication(matching: bundleID) {
            return exact
        }
        return applications.first(where: \.isIOS)
    }
}

struct SuperwallManagementTemplate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let category: String?
    let visibility: String?
}

struct SuperwallManagementEntitlement: Identifiable, Equatable, Sendable {
    let id: String
    let identifier: String
    let name: String?
}

struct SuperwallManagementProduct: Identifiable, Equatable, Sendable {
    let id: String
    let identifier: String
    let name: String?
    let period: String?
    let trialPeriodDays: Int?
}

nonisolated struct SuperwallManagementPaywallProduct: Equatable, Sendable {
    let store: String?
    let identifier: String
    let referenceName: String?
}

nonisolated struct SuperwallManagementPaywall: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let identifier: String?
    let templateID: String?
    let featureGating: String?
    let products: [SuperwallManagementPaywallProduct]
    let metadata: [String: String]
}

nonisolated struct SuperwallManagementCampaignPlacement: Equatable, Sendable {
    let eventName: String
    let enabled: Bool
    let removeFromOtherCampaigns: Bool
}

nonisolated struct SuperwallManagementCampaignVariant: Equatable, Sendable {
    let type: String?
    let paywallID: String?
    let percentage: Int?
}

nonisolated struct SuperwallManagementCampaignAudience: Equatable, Sendable {
    let enabled: Bool
    let expression: String?
    let description: String?
    let variantOptimization: String?
    let variants: [SuperwallManagementCampaignVariant]
}

nonisolated struct SuperwallManagementCampaign: Identifiable, Equatable, Sendable {
    let id: String
    let description: String
    let notes: String?
    let placements: [SuperwallManagementCampaignPlacement]
    let audiences: [SuperwallManagementCampaignAudience]
}

struct SuperwallManagementAccountSnapshot: Equatable, Sendable {
    let organizations: [SuperwallManagementOrganization]
    let projects: [SuperwallManagementProject]
}

private nonisolated struct SuperwallManagedStarterPaywallSpec: Equatable {
    let name: String
    let identifier: String
    let templateID: String?
    let products: [SuperwallManagementPaywallProduct]
    let featureGating: String
    let metadata: [String: String]
}

private nonisolated struct SuperwallManagedPreviewCampaignSpec: Equatable {
    let description: String
    let notes: String
    let placements: [SuperwallManagementCampaignPlacement]
    let audiences: [SuperwallManagementCampaignAudience]
}

struct SuperwallManagementTokenStore: Sendable {
    static let apiKeyKey = "superwall_management_api_key"

    let store: AuthTokenStore

    nonisolated init(service: String = "\(AuthKeychainStore.defaultService).integrations.superwall-management") {
        self.store = AuthTokenStore(service: service)
    }

    func apiKey(allowUserInteraction: Bool = true) -> String? {
        let value = store.string(
            for: Self.apiKeyKey,
            allowUserInteraction: allowUserInteraction
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    func hasAPIKey(allowUserInteraction: Bool = true) -> Bool {
        if allowUserInteraction {
            return apiKey() != nil
        }
        return store.hasValue(for: Self.apiKeyKey, allowUserInteraction: false)
    }

    func setAPIKey(_ apiKey: String?) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        store.set(trimmed?.isEmpty == false ? trimmed : nil, for: Self.apiKeyKey)
    }

    func clear() {
        store.remove(Self.apiKeyKey)
    }
}

actor SuperwallManagementService {
    static let shared = SuperwallManagementService()
    private static let starterPaywallIdentifier = "tenx-starter-paywall"
    private static let starterCampaignDescription = "10x Starter Preview Campaign"
    private static let starterCampaignNotesPrefix = "Managed by 10x starter preview bootstrap."
    private static let starterPaywallMetadata = [
        "managed_by": "10x",
        "bootstrap": "starter",
    ]

    private let baseURL = URL(string: "https://api.superwall.com")!
    private let session: URLSession
    private let tokenStore: SuperwallManagementTokenStore

    init(
        session: URLSession = {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }(),
        tokenStore: SuperwallManagementTokenStore = .init()
    ) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func hasStoredCredential() -> Bool {
        tokenStore.hasAPIKey(allowUserInteraction: false)
    }

    func storedAPIKey() -> String? {
        tokenStore.apiKey()
    }

    func saveAPIKey(_ apiKey: String?) {
        tokenStore.setAPIKey(apiKey)
    }

    func clearCredential() {
        tokenStore.clear()
    }

    func validateAPIKey(_ apiKey: String) async throws -> SuperwallManagementAccountSnapshot {
        try await loadAccount(apiKeyOverride: apiKey)
    }

    func connect(apiKey: String) async throws -> SuperwallManagementAccountSnapshot {
        let snapshot = try await validateAPIKey(apiKey)
        tokenStore.setAPIKey(apiKey)
        return snapshot
    }

    func loadAccount(apiKeyOverride: String? = nil) async throws -> SuperwallManagementAccountSnapshot {
        let organizations = (try? await fetchOrganizations(apiKeyOverride: apiKeyOverride)) ?? []
        let projects = try await loadProjects(
            organizations: organizations,
            apiKeyOverride: apiKeyOverride
        )
        let resolvedOrganizations = organizations.isEmpty
            ? synthesizedOrganizations(from: projects)
            : organizations
        return SuperwallManagementAccountSnapshot(
            organizations: resolvedOrganizations,
            projects: projects
        )
    }

    func fetchOrganizations(apiKeyOverride: String? = nil) async throws -> [SuperwallManagementOrganization] {
        let data = try await performRequest(
            path: "/v2/me/organizations",
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        return Self.arrayOfDictionaries(from: root)
            .compactMap(Self.organization(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchProjects(
        organizationID: String? = nil,
        apiKeyOverride: String? = nil
    ) async throws -> [SuperwallManagementProject] {
        var queryItems = [URLQueryItem(name: "limit", value: "100")]
        if let organizationID, !organizationID.isEmpty {
            queryItems.append(URLQueryItem(name: "organization_id", value: organizationID))
        }
        let data = try await performRequest(
            path: Self.path("/v2/projects", queryItems: queryItems),
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        return Self.arrayOfDictionaries(from: root)
            .compactMap(Self.project(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchProject(id: String, apiKeyOverride: String? = nil) async throws -> SuperwallManagementProject {
        let data = try await performRequest(
            path: "/v2/projects/\(id)",
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let project = Self.project(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("project details")
        }
        return project
    }

    func listTemplates(
        applicationID: String,
        apiKeyOverride: String? = nil
    ) async throws -> [SuperwallManagementTemplate] {
        let normalizedApplicationID = try Self.requiredTrimmed(applicationID, label: "Application ID")
        let templates = try await fetchTemplates(
            applicationID: normalizedApplicationID,
            visibilities: ["organization", "public"],
            apiKeyOverride: apiKeyOverride
        )
        return templates
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func listPaywalls(
        applicationID: String,
        apiKeyOverride: String? = nil
    ) async throws -> [SuperwallManagementPaywall] {
        let normalizedApplicationID = try Self.requiredTrimmed(applicationID, label: "Application ID")
        let paywalls = try await fetchPaywalls(
            applicationID: normalizedApplicationID,
            apiKeyOverride: apiKeyOverride
        )
        return paywalls
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func bootstrapProject(
        projectName: String,
        bundleID: String,
        state: ProjectSuperwallState = .empty,
        preferredOrganizationID: String? = nil,
        preferredProjectID: String? = nil,
        preferredApplicationID: String? = nil,
        apiKeyOverride: String? = nil
    ) async throws -> ProjectSuperwallState {
        let normalizedProjectName = try Self.requiredTrimmed(projectName, label: "Project name")
        let normalizedBundleID = try Self.requiredTrimmed(bundleID, label: "Bundle ID")
        let snapshot = try await loadAccount(apiKeyOverride: apiKeyOverride)

        let resolvedOrganization = try resolveOrganization(
            preferredOrganizationID ?? state.organizationID,
            organizations: snapshot.organizations
        )

        let existingProjectID = preferredProjectID ?? state.projectID
        let linkedProject: SuperwallManagementProject
        if let existingProjectID,
           let project = snapshot.projects.first(where: { $0.id == existingProjectID }) {
            linkedProject = project
        } else {
            linkedProject = try await createProject(
                name: normalizedProjectName,
                organizationID: resolvedOrganization.id,
                apiKeyOverride: apiKeyOverride
            )
        }

        let existingApplicationID = preferredApplicationID ?? state.applicationID
        var application: SuperwallManagementApplication
        if let existingApplicationID,
           let existing = linkedProject.applications.first(where: { $0.id == existingApplicationID }) {
            application = existing
        } else if let matched = linkedProject.exactIOSApplication(matching: normalizedBundleID) {
            application = matched
        } else {
            application = try await createApplication(
                projectID: linkedProject.id,
                name: normalizedProjectName,
                platform: "ios",
                bundleID: normalizedBundleID,
                apiKeyOverride: apiKeyOverride
            )
        }

        let currentBundleID = application.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if currentBundleID.lowercased() != normalizedBundleID.lowercased() {
            application = try await updateApplication(
                projectID: linkedProject.id,
                applicationID: application.id,
                name: application.name,
                bundleID: normalizedBundleID,
                apiKeyOverride: apiKeyOverride
            )
        }

        return state.updating(
            organizationID: resolvedOrganization.id,
            organizationName: resolvedOrganization.name,
            projectID: linkedProject.id,
            projectName: linkedProject.name,
            applicationID: application.id,
            applicationName: application.name,
            applicationPlatform: application.platform,
            applicationPublicAPIKey: application.publicAPIKey,
            applicationDashboardURL: application.dashboardURL?.absoluteString,
            importedBundleID: normalizedBundleID,
            bootstrapStatus: .linked
        )
    }

    func bootstrapStarterMonetization(
        state: ProjectSuperwallState,
        bundleID: String,
        placements: [String],
        previewAppUserID: String,
        paywallID: String? = nil,
        apiKeyOverride: String? = nil
    ) async throws -> ProjectSuperwallState {
        guard let projectID = state.projectID,
              let applicationID = state.applicationID else {
            throw SuperwallManagementServiceError.invalidInput("Link a Superwall project and iOS application first.")
        }

        let normalizedBundleID = try Self.requiredTrimmed(bundleID, label: "Bundle ID")
        let normalizedPreviewUserID = try Self.requiredTrimmed(previewAppUserID, label: "Preview user ID")
        let normalizedPlacements = Array(
            Set(
                placements
                    .map(Self.normalizedPlacementName)
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let finalPlacements = normalizedPlacements.isEmpty ? ["upgrade_prompt"] : normalizedPlacements
        let preferredPaywallID = paywallID?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? state.paywallID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preferredPaywallID, !preferredPaywallID.isEmpty else {
            throw SuperwallManagementServiceError.invalidInput(
                "Choose an existing Superwall paywall first. Open Paywalls or import a shared paywall link in Superwall, then retry starter setup."
            )
        }

        var nextState = state
        if nextState.bootstrapStatus == .starterReady,
           nextState.projectID == projectID,
           nextState.applicationID == applicationID,
           nextState.paywallID?.trimmingCharacters(in: .whitespacesAndNewlines) == preferredPaywallID,
           !nextState.entitlements.isEmpty,
           !nextState.products.isEmpty,
           !(nextState.paywallID?.isEmpty ?? true),
           !(nextState.campaignID?.isEmpty ?? true) {
            return nextState.updating(
                importedBundleID: normalizedBundleID,
                previewAppUserID: normalizedPreviewUserID,
                placements: finalPlacements,
                bootstrapStatus: .starterReady
            )
        }

        let selectedPaywall = try await resolveStarterPaywall(
            applicationID: applicationID,
            preferredPaywallID: preferredPaywallID,
            apiKeyOverride: apiKeyOverride
        )

        let entitlement = try await createEntitlement(
            projectID: projectID,
            identifier: "pro",
            name: "Pro",
            description: "Generated by 10x starter bootstrap.",
            apiKeyOverride: apiKeyOverride
        )

        let monthlyIdentifier = "\(normalizedBundleID).pro.monthly"
        let yearlyIdentifier = "\(normalizedBundleID).pro.yearly"
        let monthly = try await createProduct(
            projectID: projectID,
            identifier: monthlyIdentifier,
            name: "Pro Monthly",
            period: "month",
            periodCount: 1,
            trialPeriodDays: nil,
            entitlementIDs: [entitlement.id],
            apiKeyOverride: apiKeyOverride
        )
        let yearly = try await createProduct(
            projectID: projectID,
            identifier: yearlyIdentifier,
            name: "Pro Yearly",
            period: "year",
            periodCount: 1,
            trialPeriodDays: 7,
            entitlementIDs: [entitlement.id],
            apiKeyOverride: apiKeyOverride
        )

        let paywall = try await configureStarterPaywall(
            selectedPaywall,
            products: [
                .init(store: "app-store", identifier: monthly.identifier, referenceName: "primary"),
                .init(store: "app-store", identifier: yearly.identifier, referenceName: "secondary"),
            ],
            apiKeyOverride: apiKeyOverride
        )

        let campaign = try await createOrReusePreviewCampaign(
            applicationID: applicationID,
            paywallID: paywall.id,
            placements: finalPlacements,
            previewAppUserID: normalizedPreviewUserID,
            apiKeyOverride: apiKeyOverride
        )

        _ = try? await markUserTestMode(
            appUserID: normalizedPreviewUserID,
            applicationID: applicationID,
            enabled: true,
            apiKeyOverride: apiKeyOverride
        )

        nextState = nextState.updating(
            importedBundleID: normalizedBundleID,
            selectedTemplateID: paywall.templateID,
            selectedTemplateName: .some(nil),
            previewAppUserID: normalizedPreviewUserID,
            entitlements: [
                .init(id: entitlement.id, identifier: entitlement.identifier, name: entitlement.name),
            ],
            products: [
                .init(
                    id: monthly.id,
                    identifier: monthly.identifier,
                    name: monthly.name,
                    period: monthly.period,
                    trialPeriodDays: monthly.trialPeriodDays
                ),
                .init(
                    id: yearly.id,
                    identifier: yearly.identifier,
                    name: yearly.name,
                    period: yearly.period,
                    trialPeriodDays: yearly.trialPeriodDays
                ),
            ],
            paywallID: paywall.id,
            paywallName: paywall.name,
            campaignID: campaign.id,
            campaignName: campaign.description,
            placements: finalPlacements,
            bootstrapStatus: .starterReady
        )

        return nextState
    }

    private func resolveStarterPaywall(
        applicationID: String,
        preferredPaywallID: String,
        apiKeyOverride: String?
    ) async throws -> SuperwallManagementPaywall {
        let paywalls = try await fetchPaywalls(
            applicationID: applicationID,
            apiKeyOverride: apiKeyOverride
        )
        guard let match = paywalls.first(where: { $0.id == preferredPaywallID }) else {
            throw SuperwallManagementServiceError.invalidInput(
                "The selected Superwall paywall is no longer available for this application. Open Paywalls, choose another paywall, or import a shared paywall link, then retry starter setup."
            )
        }
        return try await fetchPaywall(id: match.id, apiKeyOverride: apiKeyOverride)
    }

    func syncPreviewTestUser(
        state: ProjectSuperwallState,
        previewAppUserID: String,
        enabled: Bool = true,
        apiKeyOverride: String? = nil
    ) async throws -> ProjectSuperwallState {
        guard let applicationID = state.applicationID else {
            throw SuperwallManagementServiceError.invalidInput("Link a Superwall application first.")
        }
        let normalizedPreviewUserID = try Self.requiredTrimmed(previewAppUserID, label: "Preview user ID")
        _ = try await markUserTestMode(
            appUserID: normalizedPreviewUserID,
            applicationID: applicationID,
            enabled: enabled,
            apiKeyOverride: apiKeyOverride
        )
        return state.updating(previewAppUserID: normalizedPreviewUserID)
    }

    func statusText(for state: ProjectSuperwallState) -> String {
        let linkedProject = state.projectName ?? "none"
        let linkedApplication = state.applicationName ?? "none"
        let placements = state.placements.isEmpty
            ? "- none"
            : state.placements.map { "- \($0)" }.joined(separator: "\n")
        let template = state.selectedTemplateName ?? "none"
        let products = state.products.isEmpty
            ? "- none"
            : state.products.map { "- \($0.identifier)" }.joined(separator: "\n")
        let dashboardURL = state.applicationDashboardLink?.absoluteString ?? "none"
        let paywallsURL = state.paywallsDashboardURL?.absoluteString ?? "none"
        let templatesURL = state.templatesDashboardURL?.absoluteString ?? "none"

        return """
        Superwall project: \(linkedProject)
        Superwall application: \(linkedApplication)
        Bootstrap status: \(state.bootstrapStatus?.rawValue ?? "unlinked")
        Dashboard: \(dashboardURL)
        Paywalls: \(paywallsURL)
        Templates: \(templatesURL)
        Template: \(template)
        Paywall: \(state.paywallName ?? "none")
        Campaign: \(state.campaignName ?? "none")
        Preview user: \(state.previewAppUserID ?? "none")
        Scope:
        - App code / 10x: `SUPERWALL_PUBLIC_API_KEY`, SDK configuration, placement names, preview test user wiring, and starter bootstrap resources.
        - Superwall dashboard: paywall design, copy, template choice, assets, product attachments, campaign targeting, and experiments.
        - Paywall-first setup: create, duplicate, or import the paywall in Superwall first, then let 10x attach starter products and the preview campaign.
        - To edit the paywall, open the linked Superwall dashboard and use the Paywalls section.
        Placements:
        \(placements)
        Products:
        \(products)
        """
    }

    private func fetchTemplates(
        applicationID: String,
        visibilities: [String],
        apiKeyOverride: String?
    ) async throws -> [SuperwallManagementTemplate] {
        var templates: [SuperwallManagementTemplate] = []

        for visibility in visibilities {
            let data = try await performRequest(
                path: Self.path(
                    "/v2/paywalls/templates",
                    queryItems: [
                        .init(name: "application_id", value: applicationID),
                        .init(name: "visibility", value: visibility),
                        .init(name: "limit", value: "100"),
                    ]
                ),
                method: "GET",
                apiKeyOverride: apiKeyOverride
            )
            let root = try Self.jsonObject(from: data)
            templates.append(contentsOf: Self.arrayOfDictionaries(from: root).compactMap(Self.template(from:)))
        }

        return templates.uniqued(by: \.id)
    }

    private func createProject(
        name: String,
        organizationID: String,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementProject {
        let data = try await performRequest(
            path: "/v2/projects",
            method: "POST",
            body: [
                "name": name,
                "organization_id": Int(organizationID) ?? organizationID,
            ],
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let project = Self.project(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("project creation")
        }
        return project
    }

    private func createApplication(
        projectID: String,
        name: String,
        platform: String,
        bundleID: String,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementApplication {
        let data = try await performRequest(
            path: "/v2/projects/\(projectID)/applications",
            method: "POST",
            body: [
                "name": name,
                "platform": platform,
                "bundle_id": bundleID,
            ],
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let application = Self.application(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("application creation")
        }
        return application
    }

    private func updateApplication(
        projectID: String,
        applicationID: String,
        name: String,
        bundleID: String,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementApplication {
        let data = try await performRequest(
            path: "/v2/projects/\(projectID)/applications/\(applicationID)",
            method: "PATCH",
            body: [
                "name": name,
                "bundle_id": bundleID,
            ],
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let application = Self.application(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("application update")
        }
        return application
    }

    private func createEntitlement(
        projectID: String,
        identifier: String,
        name: String?,
        description: String?,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementEntitlement {
        if let existing = try? await listEntitlements(projectID: projectID, apiKeyOverride: apiKeyOverride)
            .first(where: { $0.identifier == identifier }) {
            return existing
        }

        let data = try await performRequest(
            path: "/v2/entitlements",
            method: "POST",
            body: Self.compactJSON([
                "project_id": projectID,
                "identifier": identifier,
                "name": name,
                "description": description,
            ]),
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let entitlement = Self.entitlement(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("entitlement creation")
        }
        return entitlement
    }

    private func createProduct(
        projectID: String,
        identifier: String,
        name: String?,
        period: String,
        periodCount: Int,
        trialPeriodDays: Int?,
        entitlementIDs: [String],
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementProduct {
        if let existing = try? await listProducts(projectID: projectID, apiKeyOverride: apiKeyOverride)
            .first(where: { $0.identifier == identifier }) {
            return existing
        }

        let data = try await performRequest(
            path: "/v2/products",
            method: "POST",
            body: Self.compactJSON([
                "project_id": projectID,
                "identifier": identifier,
                "name": name,
                "subscription": Self.compactJSON([
                    "period": period,
                    "period_count": periodCount,
                    "trial_period_days": trialPeriodDays,
                ]),
                "entitlements": entitlementIDs,
            ]),
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let product = Self.product(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("product creation")
        }
        return product
    }

    private func configureStarterPaywall(
        _ paywall: SuperwallManagementPaywall,
        products: [SuperwallManagementPaywallProduct],
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementPaywall {
        let spec = SuperwallManagedStarterPaywallSpec(
            name: paywall.name,
            identifier: paywall.identifier ?? Self.starterPaywallIdentifier,
            templateID: paywall.templateID,
            products: Self.canonicalPaywallProducts(products),
            featureGating: paywall.featureGating ?? "gated",
            metadata: paywall.metadata.merging(Self.starterPaywallMetadata) { _, incoming in incoming }
        )

        if paywallNeedsUpdate(paywall, spec: spec) {
            return try await updatePaywall(
                paywallID: paywall.id,
                spec: spec,
                apiKeyOverride: apiKeyOverride
            )
        }
        return paywall
    }

    private func updatePaywall(
        paywallID: String,
        spec: SuperwallManagedStarterPaywallSpec,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementPaywall {
        let data = try await performRequest(
            path: "/v2/paywalls/\(paywallID)",
            method: "PATCH",
            body: [
                "name": spec.name,
                "products": Self.paywallProductPayload(spec.products),
                "feature_gating": spec.featureGating,
                "metadata": spec.metadata,
            ],
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let paywall = Self.paywall(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("paywall update")
        }
        return paywall
    }

    private func createOrReusePreviewCampaign(
        applicationID: String,
        paywallID: String,
        placements: [String],
        previewAppUserID: String,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementCampaign {
        let spec = Self.previewCampaignSpec(
            paywallID: paywallID,
            placements: placements,
            previewAppUserID: previewAppUserID
        )
        let managedCampaigns = try await listCampaigns(applicationID: applicationID, apiKeyOverride: apiKeyOverride)
            .filter { campaign in
                campaign.description == spec.description
                    || (campaign.notes?.hasPrefix(Self.starterCampaignNotesPrefix) ?? false)
            }

        if managedCampaigns.isEmpty {
            return try await createPreviewCampaign(
                applicationID: applicationID,
                spec: spec,
                apiKeyOverride: apiKeyOverride
            )
        }

        var matchingCampaigns: [SuperwallManagementCampaign] = []
        for campaign in managedCampaigns {
            let detailedCampaign = try await fetchCampaign(id: campaign.id, apiKeyOverride: apiKeyOverride)
            if campaignMatchesSpec(detailedCampaign, spec: spec) {
                matchingCampaigns.append(detailedCampaign)
                continue
            }

            throw SuperwallManagementServiceError.invalidInput(
                "Found an existing Superwall preview campaign with conflicting targeting or placements. Update or remove `\(campaign.description)` in Superwall before retrying bootstrap."
            )
        }

        if matchingCampaigns.count > 1 {
            throw SuperwallManagementServiceError.invalidInput(
                "Found multiple matching Superwall preview campaigns. Resolve the duplicate campaigns in Superwall before retrying bootstrap."
            )
        }

        if let matchingCampaign = matchingCampaigns.first {
            return matchingCampaign
        }

        return try await createPreviewCampaign(
            applicationID: applicationID,
            spec: spec,
            apiKeyOverride: apiKeyOverride
        )
    }

    private func createPreviewCampaign(
        applicationID: String,
        spec: SuperwallManagedPreviewCampaignSpec,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementCampaign {
        let data = try await performRequest(
            path: "/v2/campaigns",
            method: "POST",
            body: [
                "application_id": applicationID,
                "description": spec.description,
                "notes": spec.notes,
                "placements": Self.campaignPlacementPayload(spec.placements),
                "audiences": Self.campaignAudiencePayload(spec.audiences),
            ],
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let campaign = Self.campaign(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("campaign creation")
        }
        return campaign
    }

    private func listEntitlements(
        projectID: String,
        apiKeyOverride: String? = nil
    ) async throws -> [SuperwallManagementEntitlement] {
        let data = try await performRequest(
            path: Self.path(
                "/v2/entitlements",
                queryItems: [
                    .init(name: "project_id", value: projectID),
                    .init(name: "limit", value: "100"),
                ]
            ),
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        return Self.arrayOfDictionaries(from: root).compactMap(Self.entitlement(from:))
    }

    private func listProducts(
        projectID: String,
        apiKeyOverride: String? = nil
    ) async throws -> [SuperwallManagementProduct] {
        let data = try await performRequest(
            path: Self.path(
                "/v2/products",
                queryItems: [
                    .init(name: "project_id", value: projectID),
                    .init(name: "platform", value: "ios"),
                    .init(name: "limit", value: "100"),
                ]
            ),
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        return Self.arrayOfDictionaries(from: root).compactMap(Self.product(from:))
    }

    private func fetchPaywalls(
        applicationID: String,
        apiKeyOverride: String? = nil
    ) async throws -> [SuperwallManagementPaywall] {
        let data = try await performRequest(
            path: Self.path(
                "/v2/paywalls",
                queryItems: [
                    .init(name: "application_id", value: applicationID),
                    .init(name: "limit", value: "100"),
                ]
            ),
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        return Self.arrayOfDictionaries(from: root).compactMap(Self.paywall(from:))
    }

    private func fetchPaywall(
        id: String,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementPaywall {
        let data = try await performRequest(
            path: "/v2/paywalls/\(id)",
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let paywall = Self.paywall(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("paywall details")
        }
        return paywall
    }

    private func listCampaigns(
        applicationID: String,
        apiKeyOverride: String? = nil
    ) async throws -> [SuperwallManagementCampaign] {
        let data = try await performRequest(
            path: Self.path(
                "/v2/campaigns",
                queryItems: [
                    .init(name: "application_id", value: applicationID),
                    .init(name: "limit", value: "100"),
                ]
            ),
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        return Self.arrayOfDictionaries(from: root).compactMap(Self.campaign(from:))
    }

    private func fetchCampaign(
        id: String,
        apiKeyOverride: String? = nil
    ) async throws -> SuperwallManagementCampaign {
        let data = try await performRequest(
            path: "/v2/campaigns/\(id)",
            method: "GET",
            apiKeyOverride: apiKeyOverride
        )
        let root = try Self.jsonObject(from: data)
        guard let dictionary = root as? [String: Any],
              let campaign = Self.campaign(from: dictionary) else {
            throw SuperwallManagementServiceError.malformedResponse("campaign details")
        }
        return campaign
    }

    private func markUserTestMode(
        appUserID: String,
        applicationID: String,
        enabled: Bool,
        apiKeyOverride: String? = nil
    ) async throws -> Bool {
        _ = try await performRequest(
            path: "/v2/users/\(appUserID)/test-mode",
            method: "PATCH",
            body: [
                "application_id": applicationID,
                "test_mode_enabled": enabled,
            ],
            apiKeyOverride: apiKeyOverride
        )
        return true
    }

    private func paywallNeedsUpdate(
        _ paywall: SuperwallManagementPaywall,
        spec: SuperwallManagedStarterPaywallSpec
    ) -> Bool {
        if paywall.name != spec.name {
            return true
        }
        if Self.normalizedCaseInsensitiveString(paywall.featureGating) != Self.normalizedCaseInsensitiveString(spec.featureGating) {
            return true
        }

        for (key, value) in spec.metadata {
            if paywall.metadata[key] != value {
                return true
            }
        }

        return Self.canonicalPaywallProducts(paywall.products) != spec.products
    }

    private func campaignMatchesSpec(
        _ campaign: SuperwallManagementCampaign,
        spec: SuperwallManagedPreviewCampaignSpec
    ) -> Bool {
        let normalizedNotes = campaign.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return campaign.description == spec.description
            && (normalizedNotes.isEmpty || normalizedNotes == spec.notes)
            && Self.canonicalCampaignPlacements(campaign.placements) == spec.placements
            && Self.canonicalCampaignAudiences(campaign.audiences) == spec.audiences
    }

    private nonisolated static func previewCampaignSpec(
        paywallID: String,
        placements: [String],
        previewAppUserID: String
    ) -> SuperwallManagedPreviewCampaignSpec {
        let normalizedPlacements = canonicalCampaignPlacements(
            placements.map { placement in
                SuperwallManagementCampaignPlacement(
                    eventName: placement,
                    enabled: true,
                    removeFromOtherCampaigns: false
                )
            }
        )
        let audience = SuperwallManagementCampaignAudience(
            enabled: true,
            expression: previewAudienceExpression(for: previewAppUserID),
            description: "10x preview user only.",
            variantOptimization: "none",
            variants: canonicalCampaignVariants([
                .init(type: "treatment", paywallID: paywallID, percentage: 100),
            ])
        )

        return SuperwallManagedPreviewCampaignSpec(
            description: starterCampaignDescription,
            notes: starterCampaignNotes(previewAppUserID: previewAppUserID, placements: placements),
            placements: normalizedPlacements,
            audiences: canonicalCampaignAudiences([audience])
        )
    }

    private nonisolated static func starterCampaignNotes(
        previewAppUserID: String,
        placements: [String]
    ) -> String {
        let placementSummary = canonicalCampaignPlacements(
            placements.map {
                .init(eventName: $0, enabled: true, removeFromOtherCampaigns: false)
            }
        )
        .map(\.eventName)
        .joined(separator: ",")
        return "\(starterCampaignNotesPrefix) Preview user: \(previewAppUserID). Placements: \(placementSummary)."
    }

    private nonisolated static func previewAudienceExpression(for previewAppUserID: String) -> String {
        "user.id == '\(escapeSingleQuotedLiteral(previewAppUserID))'"
    }

    private nonisolated static func escapeSingleQuotedLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    private nonisolated static func paywallProductPayload(
        _ products: [SuperwallManagementPaywallProduct]
    ) -> [[String: Any]] {
        canonicalPaywallProducts(products).map { product in
            compactJSON([
                "store": product.store,
                "identifier": product.identifier,
                "reference_name": product.referenceName,
            ])
        }
    }

    private nonisolated static func campaignPlacementPayload(
        _ placements: [SuperwallManagementCampaignPlacement]
    ) -> [[String: Any]] {
        canonicalCampaignPlacements(placements).map { placement in
            [
                "event_name": placement.eventName,
                "enabled": placement.enabled,
                "remove_from_other_campaigns": placement.removeFromOtherCampaigns,
            ]
        }
    }

    private nonisolated static func campaignAudiencePayload(
        _ audiences: [SuperwallManagementCampaignAudience]
    ) -> [[String: Any]] {
        canonicalCampaignAudiences(audiences).map { audience in
            compactJSON([
                "enabled": audience.enabled,
                "expression": audience.expression,
                "description": audience.description,
                "variant_optimization": audience.variantOptimization,
                "variants": canonicalCampaignVariants(audience.variants).map { variant in
                    compactJSON([
                        "type": variant.type,
                        "paywall": variant.paywallID,
                        "percentage": variant.percentage,
                    ])
                },
            ])
        }
    }

    private nonisolated static func canonicalPaywallProducts(
        _ products: [SuperwallManagementPaywallProduct]
    ) -> [SuperwallManagementPaywallProduct] {
        products
            .map { product in
                SuperwallManagementPaywallProduct(
                    store: normalizedCaseInsensitiveString(product.store),
                    identifier: product.identifier.trimmingCharacters(in: .whitespacesAndNewlines),
                    referenceName: normalizedString(product.referenceName)
                )
            }
            .sorted {
                ($0.referenceName ?? "", $0.identifier, $0.store ?? "")
                    < ($1.referenceName ?? "", $1.identifier, $1.store ?? "")
            }
    }

    private nonisolated static func canonicalCampaignPlacements(
        _ placements: [SuperwallManagementCampaignPlacement]
    ) -> [SuperwallManagementCampaignPlacement] {
        placements
            .map { placement in
                SuperwallManagementCampaignPlacement(
                    eventName: normalizedPlacementName(placement.eventName),
                    enabled: placement.enabled,
                    removeFromOtherCampaigns: placement.removeFromOtherCampaigns
                )
            }
            .sorted { $0.eventName < $1.eventName }
    }

    private nonisolated static func canonicalCampaignAudiences(
        _ audiences: [SuperwallManagementCampaignAudience]
    ) -> [SuperwallManagementCampaignAudience] {
        audiences
            .map { audience in
                SuperwallManagementCampaignAudience(
                    enabled: audience.enabled,
                    expression: normalizedString(audience.expression),
                    description: normalizedString(audience.description),
                    variantOptimization: normalizedCaseInsensitiveString(audience.variantOptimization),
                    variants: canonicalCampaignVariants(audience.variants)
                )
            }
            .sorted {
                ($0.expression ?? "", $0.description ?? "")
                    < ($1.expression ?? "", $1.description ?? "")
            }
    }

    private nonisolated static func canonicalCampaignVariants(
        _ variants: [SuperwallManagementCampaignVariant]
    ) -> [SuperwallManagementCampaignVariant] {
        variants
            .map { variant in
                SuperwallManagementCampaignVariant(
                    type: normalizedCaseInsensitiveString(variant.type),
                    paywallID: normalizedString(variant.paywallID),
                    percentage: variant.percentage
                )
            }
            .sorted {
                ($0.type ?? "", $0.paywallID ?? "", $0.percentage ?? 0)
                    < ($1.type ?? "", $1.paywallID ?? "", $1.percentage ?? 0)
            }
    }

    private nonisolated static func normalizedString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private nonisolated static func normalizedCaseInsensitiveString(_ value: String?) -> String? {
        normalizedString(value)?.lowercased()
    }

    private func resolveOrganization(
        _ preferredOrganizationID: String?,
        organizations: [SuperwallManagementOrganization]
    ) throws -> SuperwallManagementOrganization {
        if let preferredOrganizationID,
           let existing = organizations.first(where: { $0.id == preferredOrganizationID }) {
            return existing
        }
        if organizations.count == 1, let only = organizations.first {
            return only
        }
        if organizations.isEmpty {
            throw SuperwallManagementServiceError.invalidInput(
                "Superwall did not return an organization or project for this key. Create the first project in Superwall, then reconnect the management key here."
            )
        }
        throw SuperwallManagementServiceError.invalidInput("Choose which Superwall organization should own the new project.")
    }

    private func loadProjects(
        organizations: [SuperwallManagementOrganization],
        apiKeyOverride: String?
    ) async throws -> [SuperwallManagementProject] {
        let loadedProjects: [SuperwallManagementProject]
        if organizations.isEmpty {
            loadedProjects = try await fetchProjects(apiKeyOverride: apiKeyOverride)
        } else {
            var projects: [SuperwallManagementProject] = []
            for organization in organizations {
                let organizationProjects = try await fetchProjects(
                    organizationID: organization.id,
                    apiKeyOverride: apiKeyOverride
                )
                projects.append(contentsOf: organizationProjects)
            }
            loadedProjects = projects
        }

        return loadedProjects
            .uniqued(by: \.id)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func synthesizedOrganizations(
        from projects: [SuperwallManagementProject]
    ) -> [SuperwallManagementOrganization] {
        projects
            .map(\.organizationID)
            .filter { !$0.isEmpty }
            .sorted()
            .map { organizationID in
                SuperwallManagementOrganization(
                    id: organizationID,
                    name: "Organization \(organizationID)",
                    slug: nil
                )
            }
    }

    private func requireAPIKey(_ override: String?) throws -> String {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        guard let apiKey = tokenStore.apiKey() else {
            throw SuperwallManagementServiceError.missingAPIKey
        }
        return apiKey
    }

    private func performRequest(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        apiKeyOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        expectedStatusCodes: Set<Int> = Set(200...299)
    ) async throws -> Data {
        let apiKey = try requireAPIKey(apiKeyOverride)

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw SuperwallManagementServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "10x-macos/\(Config.appVersion) (\(Config.appBuild))",
            forHTTPHeaderField: "User-Agent"
        )
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuperwallManagementServiceError.invalidResponse
        }

        guard expectedStatusCodes.contains(httpResponse.statusCode) else {
            throw SuperwallManagementServiceError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        return data
    }

    private nonisolated static func path(
        _ basePath: String,
        queryItems: [URLQueryItem]
    ) -> String {
        guard var components = URLComponents(string: basePath) else {
            return basePath
        }
        components.queryItems = queryItems
        return components.string ?? basePath
    }

    private nonisolated static func compactJSON(_ dictionary: [String: Any?]) -> [String: Any] {
        dictionary.reduce(into: [String: Any]()) { partialResult, element in
            if let value = element.value {
                partialResult[element.key] = value
            }
        }
    }

    private nonisolated static func requiredTrimmed(_ value: String, label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SuperwallManagementServiceError.invalidInput("\(label) must not be empty.")
        }
        return trimmed
    }

    private nonisolated static func normalizedPlacementName(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted)
            .joined(separator: "_")
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    nonisolated static func jsonObject(from data: Data) throws -> Any {
        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    nonisolated static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "Unknown error" }

        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = firstString(in: root, keys: ["message", "error", "detail"]),
               !message.isEmpty {
                return message
            }
            if let issues = root["issues"] as? [[String: Any]],
               let firstIssue = issues.first,
               let message = firstString(in: firstIssue, keys: ["message"]),
               !message.isEmpty {
                return message
            }
        }

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "Unknown error"
    }

    private nonisolated static func arrayOfDictionaries(from root: Any) -> [[String: Any]] {
        if let dictionaries = root as? [[String: Any]] {
            return dictionaries
        }
        if let dictionary = root as? [String: Any] {
            if let data = dictionary["data"] as? [[String: Any]] {
                return data
            }
            if let items = dictionary["applications"] as? [[String: Any]] {
                return items
            }
            return [dictionary]
        }
        return []
    }

    private nonisolated static func organization(from dictionary: [String: Any]) -> SuperwallManagementOrganization? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let name = firstString(in: dictionary, keys: ["name"]),
              !name.isEmpty else {
            return nil
        }
        return SuperwallManagementOrganization(
            id: id,
            name: name,
            slug: firstString(in: dictionary, keys: ["slug"])
        )
    }

    private nonisolated static func project(from dictionary: [String: Any]) -> SuperwallManagementProject? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let name = firstString(in: dictionary, keys: ["name"]),
              let organizationID = firstID(in: dictionary, keys: ["organization_id", "organizationId"]) else {
            return nil
        }

        let applications = (dictionary["applications"] as? [[String: Any]] ?? [])
            .compactMap(application(from:))

        return SuperwallManagementProject(
            id: id,
            organizationID: organizationID,
            name: name,
            applications: applications,
            archived: firstBool(in: dictionary, keys: ["archived"]) ?? false,
            metadata: dictionary["metadata"] as? [String: String] ?? [:],
            createdAt: firstString(in: dictionary, keys: ["created_at", "createdAt"]),
            updatedAt: firstString(in: dictionary, keys: ["updated_at", "updatedAt"])
        )
    }

    private nonisolated static func application(from dictionary: [String: Any]) -> SuperwallManagementApplication? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let platform = firstString(in: dictionary, keys: ["platform"]),
              let name = firstString(in: dictionary, keys: ["name"]),
              let publicAPIKey = firstString(in: dictionary, keys: ["public_api_key", "publicApiKey"]) else {
            return nil
        }

        return SuperwallManagementApplication(
            id: id,
            platform: platform,
            name: name,
            publicAPIKey: publicAPIKey,
            bundleID: firstString(in: dictionary, keys: ["bundle_id", "bundleId"]),
            appID: firstString(in: dictionary, keys: ["app_id", "appId"]),
            slug: firstString(in: dictionary, keys: ["slug"]),
            integrated: firstBool(in: dictionary, keys: ["integrated"]) ?? false,
            archivedAt: firstString(in: dictionary, keys: ["archived_at", "archivedAt"]),
            featuresEnabled: dictionary["features_enabled"] as? [String] ?? []
        )
    }

    private nonisolated static func template(from dictionary: [String: Any]) -> SuperwallManagementTemplate? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let name = firstString(in: dictionary, keys: ["name"]) else {
            return nil
        }
        return SuperwallManagementTemplate(
            id: id,
            name: name,
            category: firstString(in: dictionary, keys: ["category"]),
            visibility: firstString(in: dictionary, keys: ["visibility"])
        )
    }

    private nonisolated static func entitlement(from dictionary: [String: Any]) -> SuperwallManagementEntitlement? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let identifier = firstString(in: dictionary, keys: ["identifier"]) else {
            return nil
        }
        return SuperwallManagementEntitlement(
            id: id,
            identifier: identifier,
            name: firstString(in: dictionary, keys: ["name"])
        )
    }

    private nonisolated static func product(from dictionary: [String: Any]) -> SuperwallManagementProduct? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let identifier = firstString(in: dictionary, keys: ["identifier"]) else {
            return nil
        }
        let subscription = dictionary["subscription"] as? [String: Any]
        return SuperwallManagementProduct(
            id: id,
            identifier: identifier,
            name: firstString(in: dictionary, keys: ["name"]),
            period: firstString(in: subscription ?? [:], keys: ["period"]),
            trialPeriodDays: firstInt(in: subscription ?? [:], keys: ["trial_period_days", "trialPeriodDays"])
        )
    }

    private nonisolated static func paywall(from dictionary: [String: Any]) -> SuperwallManagementPaywall? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let name = firstString(in: dictionary, keys: ["name"]) else {
            return nil
        }
        let templateDictionary = dictionary["template"] as? [String: Any]
        let productDictionaries =
            (dictionary["products"] as? [[String: Any]])
            ?? (dictionary["product_items"] as? [[String: Any]])
        return SuperwallManagementPaywall(
            id: id,
            name: name,
            identifier: firstString(in: dictionary, keys: ["identifier"]),
            templateID: firstID(in: templateDictionary ?? [:], keys: ["id"]),
            featureGating: firstString(in: dictionary, keys: ["feature_gating", "featureGating"]),
            products: (productDictionaries ?? []).compactMap(paywallProduct(from:)),
            metadata: stringDictionary(from: dictionary["metadata"])
        )
    }

    private nonisolated static func campaign(from dictionary: [String: Any]) -> SuperwallManagementCampaign? {
        guard let id = firstID(in: dictionary, keys: ["id"]),
              let description = firstString(in: dictionary, keys: ["description", "name"]) else {
            return nil
        }
        return SuperwallManagementCampaign(
            id: id,
            description: description,
            notes: firstString(in: dictionary, keys: ["notes"]),
            placements: (dictionary["placements"] as? [[String: Any]] ?? []).compactMap(campaignPlacement(from:)),
            audiences: (dictionary["audiences"] as? [[String: Any]] ?? []).compactMap(campaignAudience(from:))
        )
    }

    private nonisolated static func paywallProduct(from dictionary: [String: Any]) -> SuperwallManagementPaywallProduct? {
        let nestedProduct = dictionary["product"] as? [String: Any]
        guard let identifier = firstString(
            in: dictionary,
            keys: ["identifier", "product_identifier"]
        ) ?? firstString(in: nestedProduct ?? [:], keys: ["identifier"]) else {
            return nil
        }
        return SuperwallManagementPaywallProduct(
            store: firstString(in: dictionary, keys: ["store"]) ?? firstString(in: nestedProduct ?? [:], keys: ["store"]),
            identifier: identifier,
            referenceName: firstString(in: dictionary, keys: ["reference_name", "referenceName"])
        )
    }

    private nonisolated static func campaignPlacement(from dictionary: [String: Any]) -> SuperwallManagementCampaignPlacement? {
        guard let eventName = firstString(in: dictionary, keys: ["event_name", "eventName"]) else {
            return nil
        }
        return SuperwallManagementCampaignPlacement(
            eventName: eventName,
            enabled: firstBool(in: dictionary, keys: ["enabled"]) ?? false,
            removeFromOtherCampaigns: firstBool(in: dictionary, keys: ["remove_from_other_campaigns", "removeFromOtherCampaigns"]) ?? false
        )
    }

    private nonisolated static func campaignAudience(from dictionary: [String: Any]) -> SuperwallManagementCampaignAudience? {
        let variants = (dictionary["variants"] as? [[String: Any]] ?? []).compactMap(campaignVariant(from:))
        return SuperwallManagementCampaignAudience(
            enabled: firstBool(in: dictionary, keys: ["enabled"]) ?? false,
            expression: firstString(in: dictionary, keys: ["expression"]),
            description: firstString(in: dictionary, keys: ["description"]),
            variantOptimization: firstString(in: dictionary, keys: ["variant_optimization", "variantOptimization"]),
            variants: variants
        )
    }

    private nonisolated static func campaignVariant(from dictionary: [String: Any]) -> SuperwallManagementCampaignVariant? {
        let paywallDictionary = dictionary["paywall"] as? [String: Any]
        return SuperwallManagementCampaignVariant(
            type: firstString(in: dictionary, keys: ["type"]),
            paywallID: firstID(in: dictionary, keys: ["paywall", "paywall_id", "paywallId"])
                ?? firstID(in: paywallDictionary ?? [:], keys: ["id"]),
            percentage: firstInt(in: dictionary, keys: ["percentage"])
        )
    }

    private nonisolated static func firstString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private nonisolated static func firstBool(
        in dictionary: [String: Any],
        keys: [String]
    ) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    private nonisolated static func firstInt(
        in dictionary: [String: Any],
        keys: [String]
    ) -> Int? {
        for key in keys {
            if let value = dictionary[key] as? Int {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
            if let value = dictionary[key] as? String,
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
    }

    private nonisolated static func firstID(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        if let string = firstString(in: dictionary, keys: keys) {
            return string
        }
        if let intValue = firstInt(in: dictionary, keys: keys) {
            return String(intValue)
        }
        return nil
    }

    private nonisolated static func stringDictionary(from value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.reduce(into: [String: String]()) { partialResult, element in
            if let stringValue = element.value as? String {
                partialResult[element.key] = stringValue
            } else if let numberValue = element.value as? NSNumber {
                partialResult[element.key] = numberValue.stringValue
            }
        }
    }
}

private extension Sequence {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen: Set<Value> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
