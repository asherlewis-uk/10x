import Foundation

nonisolated enum ProjectSuperwallBootstrapStatus: String, Codable, Sendable, Hashable {
    case linked
    case starterReady
}

nonisolated struct ProjectSuperwallEntitlementRecord: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let identifier: String
    let name: String?
}

nonisolated struct ProjectSuperwallProductRecord: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let identifier: String
    let name: String?
    let period: String?
    let trialPeriodDays: Int?
}

nonisolated struct ProjectSuperwallState: Codable, Sendable, Hashable {
    let organizationID: String?
    let organizationName: String?
    let projectID: String?
    let projectName: String?
    let applicationID: String?
    let applicationName: String?
    let applicationPlatform: String?
    let applicationPublicAPIKey: String?
    let applicationDashboardURL: String?
    let importedBundleID: String?
    let selectedTemplateID: String?
    let selectedTemplateName: String?
    let previewAppUserID: String?
    let entitlements: [ProjectSuperwallEntitlementRecord]
    let products: [ProjectSuperwallProductRecord]
    let paywallID: String?
    let paywallName: String?
    let campaignID: String?
    let campaignName: String?
    let placements: [String]
    let bootstrapStatus: ProjectSuperwallBootstrapStatus?
    let lastSyncedAt: String?

    init(
        organizationID: String? = nil,
        organizationName: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        applicationID: String? = nil,
        applicationName: String? = nil,
        applicationPlatform: String? = nil,
        applicationPublicAPIKey: String? = nil,
        applicationDashboardURL: String? = nil,
        importedBundleID: String? = nil,
        selectedTemplateID: String? = nil,
        selectedTemplateName: String? = nil,
        previewAppUserID: String? = nil,
        entitlements: [ProjectSuperwallEntitlementRecord] = [],
        products: [ProjectSuperwallProductRecord] = [],
        paywallID: String? = nil,
        paywallName: String? = nil,
        campaignID: String? = nil,
        campaignName: String? = nil,
        placements: [String] = [],
        bootstrapStatus: ProjectSuperwallBootstrapStatus? = nil,
        lastSyncedAt: String? = nil
    ) {
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.projectID = projectID
        self.projectName = projectName
        self.applicationID = applicationID
        self.applicationName = applicationName
        self.applicationPlatform = applicationPlatform
        self.applicationPublicAPIKey = applicationPublicAPIKey
        self.applicationDashboardURL = applicationDashboardURL
        self.importedBundleID = importedBundleID
        self.selectedTemplateID = selectedTemplateID
        self.selectedTemplateName = selectedTemplateName
        self.previewAppUserID = previewAppUserID
        self.entitlements = entitlements
        self.products = products
        self.paywallID = paywallID
        self.paywallName = paywallName
        self.campaignID = campaignID
        self.campaignName = campaignName
        self.placements = placements
        self.bootstrapStatus = bootstrapStatus
        self.lastSyncedAt = lastSyncedAt
    }

    nonisolated static let empty = Self()

    var isConfigured: Bool {
        !(applicationID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && !(applicationPublicAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var applicationDashboardLink: URL? {
        if let urlString = applicationDashboardURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            return url
        }
        guard let applicationID = applicationID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !applicationID.isEmpty else {
            return nil
        }
        return URL(string: "https://superwall.com/applications/\(applicationID)/rules")
    }

    var paywallsDashboardURL: URL? {
        guard let dashboardURL = applicationDashboardLink else { return nil }
        guard var components = URLComponents(url: dashboardURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var pathComponents = dashboardURL.pathComponents.filter { $0 != "/" }
        if let last = pathComponents.last,
           last == "rules" || last == "campaigns" {
            pathComponents.removeLast()
        }
        pathComponents.append("paywalls")
        components.path = "/" + pathComponents.joined(separator: "/")
        return components.url
    }

    var templatesDashboardURL: URL? {
        guard let dashboardURL = applicationDashboardLink else { return nil }
        guard var components = URLComponents(url: dashboardURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var pathComponents = dashboardURL.pathComponents.filter { $0 != "/" }
        if let last = pathComponents.last,
           last == "rules" || last == "campaigns" || last == "paywalls" {
            pathComponents.removeLast()
        }
        pathComponents.append("templates")
        components.path = "/" + pathComponents.joined(separator: "/")
        return components.url
    }
}

extension ProjectSuperwallState {
    private nonisolated static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    nonisolated static func suggestedPlacements(plan: String?, tasks: String?) -> [String] {
        let source = [plan, tasks]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")
        guard !source.isEmpty else { return ["upgrade_prompt"] }

        var placements: Set<String> = ["upgrade_prompt"]
        if source.contains("onboarding") {
            placements.insert("onboarding_complete")
        }

        let patterns = [
            #"premium\s+([a-z0-9][a-z0-9 _-]{1,30})"#,
            #"([a-z0-9][a-z0-9 _-]{1,30})\s+premium"#,
            #"paid\s+([a-z0-9][a-z0-9 _-]{1,30})"#,
        ]
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            for match in regex.matches(in: source, range: sourceRange) {
                guard let featureRange = Range(match.range(at: 1), in: source) else { continue }
                let feature = source[featureRange]
                    .components(separatedBy: allowedCharacters.inverted)
                    .filter { !$0.isEmpty }
                    .prefix(3)
                    .joined(separator: "_")
                guard !feature.isEmpty else { continue }
                placements.insert("premium_\(feature)")
            }
        }

        return placements.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    nonisolated func updating(
        organizationID: String? = nil,
        organizationName: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        applicationID: String? = nil,
        applicationName: String? = nil,
        applicationPlatform: String? = nil,
        applicationPublicAPIKey: String? = nil,
        applicationDashboardURL: String? = nil,
        importedBundleID: String? = nil,
        selectedTemplateID: String?? = nil,
        selectedTemplateName: String?? = nil,
        previewAppUserID: String?? = nil,
        entitlements: [ProjectSuperwallEntitlementRecord]? = nil,
        products: [ProjectSuperwallProductRecord]? = nil,
        paywallID: String?? = nil,
        paywallName: String?? = nil,
        campaignID: String?? = nil,
        campaignName: String?? = nil,
        placements: [String]? = nil,
        bootstrapStatus: ProjectSuperwallBootstrapStatus?? = nil,
        lastSyncedAt: String? = nil
    ) -> Self {
        Self(
            organizationID: organizationID ?? self.organizationID,
            organizationName: organizationName ?? self.organizationName,
            projectID: projectID ?? self.projectID,
            projectName: projectName ?? self.projectName,
            applicationID: applicationID ?? self.applicationID,
            applicationName: applicationName ?? self.applicationName,
            applicationPlatform: applicationPlatform ?? self.applicationPlatform,
            applicationPublicAPIKey: applicationPublicAPIKey ?? self.applicationPublicAPIKey,
            applicationDashboardURL: applicationDashboardURL ?? self.applicationDashboardURL,
            importedBundleID: importedBundleID ?? self.importedBundleID,
            selectedTemplateID: selectedTemplateID ?? self.selectedTemplateID,
            selectedTemplateName: selectedTemplateName ?? self.selectedTemplateName,
            previewAppUserID: previewAppUserID ?? self.previewAppUserID,
            entitlements: entitlements ?? self.entitlements,
            products: products ?? self.products,
            paywallID: paywallID ?? self.paywallID,
            paywallName: paywallName ?? self.paywallName,
            campaignID: campaignID ?? self.campaignID,
            campaignName: campaignName ?? self.campaignName,
            placements: placements ?? self.placements,
            bootstrapStatus: bootstrapStatus ?? self.bootstrapStatus,
            lastSyncedAt: lastSyncedAt ?? Self.now()
        )
    }
}
