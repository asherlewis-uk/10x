import Foundation

struct AppStoreDocumentSection: Codable, Equatable, Sendable {
    var title: String
    var paragraphs: [String]
    var bullets: [String]

    init(
        title: String,
        paragraphs: [String] = [],
        bullets: [String] = []
    ) {
        self.title = title
        self.paragraphs = paragraphs
        self.bullets = bullets
    }

    var normalized: Self {
        Self(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            paragraphs: paragraphs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            bullets: bullets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    var hasContent: Bool {
        !normalized.title.isEmpty && (!normalized.paragraphs.isEmpty || !normalized.bullets.isEmpty)
    }
}

struct AppStoreGeneratedDocument: Codable, Equatable, Sendable {
    var title: String
    var intro: [String]
    var sections: [AppStoreDocumentSection]

    init(
        title: String = "",
        intro: [String] = [],
        sections: [AppStoreDocumentSection] = []
    ) {
        self.title = title
        self.intro = intro
        self.sections = sections
    }

    static let empty = Self()

    var normalized: Self {
        Self(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            intro: intro
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            sections: sections
                .map(\.normalized)
                .filter(\.hasContent)
        )
    }

    var hasContent: Bool {
        let normalized = normalized
        return !normalized.title.isEmpty && (!normalized.intro.isEmpty || !normalized.sections.isEmpty)
    }

    func markdown(includeTitle: Bool = true) -> String {
        let normalized = normalized
        var lines: [String] = []
        if includeTitle && !normalized.title.isEmpty {
            lines.append("# \(normalized.title)")
            lines.append("")
        }

        for paragraph in normalized.intro {
            lines.append(paragraph)
            lines.append("")
        }

        for (index, section) in normalized.sections.enumerated() {
            lines.append("## \(section.title)")
            lines.append("")

            for paragraph in section.paragraphs {
                lines.append(paragraph)
                lines.append("")
            }

            for bullet in section.bullets {
                lines.append("- \(bullet)")
            }

            if !section.bullets.isEmpty, index < normalized.sections.count - 1 {
                lines.append("")
            }
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AppStoreSubmissionMetadataDraft: Codable, Equatable, Sendable {
    var appStoreDescription: String
    var promotionalText: String
    var keywords: [String]
    var reviewNotes: [String]
    var categorySuggestions: [String]
    var demoAccountChecklist: [String]
    var reviewerContactChecklist: [String]
    var appPrivacyAnswers: [String]
    var ageRatingHints: [String]
    var accessibilityHints: [String]

    init(
        appStoreDescription: String = "",
        promotionalText: String = "",
        keywords: [String] = [],
        reviewNotes: [String] = [],
        categorySuggestions: [String] = [],
        demoAccountChecklist: [String] = [],
        reviewerContactChecklist: [String] = [],
        appPrivacyAnswers: [String] = [],
        ageRatingHints: [String] = [],
        accessibilityHints: [String] = []
    ) {
        self.appStoreDescription = appStoreDescription
        self.promotionalText = promotionalText
        self.keywords = keywords
        self.reviewNotes = reviewNotes
        self.categorySuggestions = categorySuggestions
        self.demoAccountChecklist = demoAccountChecklist
        self.reviewerContactChecklist = reviewerContactChecklist
        self.appPrivacyAnswers = appPrivacyAnswers
        self.ageRatingHints = ageRatingHints
        self.accessibilityHints = accessibilityHints
    }

    static let empty = Self()

    var normalized: Self {
        Self(
            appStoreDescription: appStoreDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            promotionalText: promotionalText.trimmingCharacters(in: .whitespacesAndNewlines),
            keywords: keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            reviewNotes: reviewNotes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            categorySuggestions: categorySuggestions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            demoAccountChecklist: demoAccountChecklist
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            reviewerContactChecklist: reviewerContactChecklist
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            appPrivacyAnswers: appPrivacyAnswers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            ageRatingHints: ageRatingHints
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            accessibilityHints: accessibilityHints
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    var keywordString: String {
        normalized.keywords.joined(separator: ",")
    }
}

struct AppStoreSubmissionFacts: Codable, Equatable, Sendable {
    var appName: String
    var projectSummary: String
    var companyName: String
    var legalEntityName: String
    var supportName: String
    var supportEmail: String
    var contactEmail: String
    var websiteURL: String
    var marketingURL: String
    var accessibilityURL: String
    var jurisdiction: String
    var bundleIdentifier: String
    var backendProvider: String
    var authProvider: String
    var usesAccounts: Bool
    var supportsAccountDeletion: Bool
    var usesSubscriptions: Bool
    var usesAnalytics: Bool
    var usesTracking: Bool
    var usesAds: Bool
    var collectsCameraData: Bool
    var collectsMicrophoneData: Bool
    var collectsPhotoLibraryData: Bool
    var collectsLocationData: Bool
    var collectsContactsData: Bool
    var collectsHealthData: Bool
    var kidFocused: Bool
    var servesEUUsers: Bool
    var hasUserGeneratedContent: Bool
    var permissionUsageDescriptions: [String: String]
    var entitlementKeys: [String]
    var privacyTrackingEnabled: Bool?
    var privacyTrackingDomains: [String]
    var requiredReasonAPIs: [String]
    var integratedServices: [String]
    var inferenceNotes: [String]

    init(
        appName: String = "",
        projectSummary: String = "",
        companyName: String = "",
        legalEntityName: String = "",
        supportName: String = "",
        supportEmail: String = "",
        contactEmail: String = "",
        websiteURL: String = "",
        marketingURL: String = "",
        accessibilityURL: String = "",
        jurisdiction: String = "",
        bundleIdentifier: String = "",
        backendProvider: String = "",
        authProvider: String = "",
        usesAccounts: Bool = false,
        supportsAccountDeletion: Bool = false,
        usesSubscriptions: Bool = false,
        usesAnalytics: Bool = false,
        usesTracking: Bool = false,
        usesAds: Bool = false,
        collectsCameraData: Bool = false,
        collectsMicrophoneData: Bool = false,
        collectsPhotoLibraryData: Bool = false,
        collectsLocationData: Bool = false,
        collectsContactsData: Bool = false,
        collectsHealthData: Bool = false,
        kidFocused: Bool = false,
        servesEUUsers: Bool = false,
        hasUserGeneratedContent: Bool = false,
        permissionUsageDescriptions: [String: String] = [:],
        entitlementKeys: [String] = [],
        privacyTrackingEnabled: Bool? = nil,
        privacyTrackingDomains: [String] = [],
        requiredReasonAPIs: [String] = [],
        integratedServices: [String] = [],
        inferenceNotes: [String] = []
    ) {
        self.appName = appName
        self.projectSummary = projectSummary
        self.companyName = companyName
        self.legalEntityName = legalEntityName
        self.supportName = supportName
        self.supportEmail = supportEmail
        self.contactEmail = contactEmail
        self.websiteURL = websiteURL
        self.marketingURL = marketingURL
        self.accessibilityURL = accessibilityURL
        self.jurisdiction = jurisdiction
        self.bundleIdentifier = bundleIdentifier
        self.backendProvider = backendProvider
        self.authProvider = authProvider
        self.usesAccounts = usesAccounts
        self.supportsAccountDeletion = supportsAccountDeletion
        self.usesSubscriptions = usesSubscriptions
        self.usesAnalytics = usesAnalytics
        self.usesTracking = usesTracking
        self.usesAds = usesAds
        self.collectsCameraData = collectsCameraData
        self.collectsMicrophoneData = collectsMicrophoneData
        self.collectsPhotoLibraryData = collectsPhotoLibraryData
        self.collectsLocationData = collectsLocationData
        self.collectsContactsData = collectsContactsData
        self.collectsHealthData = collectsHealthData
        self.kidFocused = kidFocused
        self.servesEUUsers = servesEUUsers
        self.hasUserGeneratedContent = hasUserGeneratedContent
        self.permissionUsageDescriptions = permissionUsageDescriptions
        self.entitlementKeys = entitlementKeys
        self.privacyTrackingEnabled = privacyTrackingEnabled
        self.privacyTrackingDomains = privacyTrackingDomains
        self.requiredReasonAPIs = requiredReasonAPIs
        self.integratedServices = integratedServices
        self.inferenceNotes = inferenceNotes
    }

    static let empty = Self()

    var normalized: Self {
        Self(
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            projectSummary: projectSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            legalEntityName: legalEntityName.trimmingCharacters(in: .whitespacesAndNewlines),
            supportName: supportName.trimmingCharacters(in: .whitespacesAndNewlines),
            supportEmail: supportEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            contactEmail: contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            websiteURL: websiteURL.trimmingCharacters(in: .whitespacesAndNewlines),
            marketingURL: marketingURL.trimmingCharacters(in: .whitespacesAndNewlines),
            accessibilityURL: accessibilityURL.trimmingCharacters(in: .whitespacesAndNewlines),
            jurisdiction: jurisdiction.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            backendProvider: backendProvider.trimmingCharacters(in: .whitespacesAndNewlines),
            authProvider: authProvider.trimmingCharacters(in: .whitespacesAndNewlines),
            usesAccounts: usesAccounts,
            supportsAccountDeletion: supportsAccountDeletion,
            usesSubscriptions: usesSubscriptions,
            usesAnalytics: usesAnalytics,
            usesTracking: usesTracking,
            usesAds: usesAds,
            collectsCameraData: collectsCameraData,
            collectsMicrophoneData: collectsMicrophoneData,
            collectsPhotoLibraryData: collectsPhotoLibraryData,
            collectsLocationData: collectsLocationData,
            collectsContactsData: collectsContactsData,
            collectsHealthData: collectsHealthData,
            kidFocused: kidFocused,
            servesEUUsers: servesEUUsers,
            hasUserGeneratedContent: hasUserGeneratedContent,
            permissionUsageDescriptions: permissionUsageDescriptions
                .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.value.isEmpty },
            entitlementKeys: entitlementKeys
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted(),
            privacyTrackingEnabled: privacyTrackingEnabled,
            privacyTrackingDomains: privacyTrackingDomains
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted(),
            requiredReasonAPIs: requiredReasonAPIs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted(),
            integratedServices: integratedServices
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted(),
            inferenceNotes: inferenceNotes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

struct AppStoreSubmissionGenerated: Codable, Equatable, Sendable {
    var privacy: AppStoreGeneratedDocument
    var terms: AppStoreGeneratedDocument
    var support: AppStoreGeneratedDocument
    var metadata: AppStoreSubmissionMetadataDraft
    var lastGeneratedAt: String?
    var model: String?
    var warnings: [String]

    init(
        privacy: AppStoreGeneratedDocument = .empty,
        terms: AppStoreGeneratedDocument = .empty,
        support: AppStoreGeneratedDocument = .empty,
        metadata: AppStoreSubmissionMetadataDraft = .empty,
        lastGeneratedAt: String? = nil,
        model: String? = nil,
        warnings: [String] = []
    ) {
        self.privacy = privacy
        self.terms = terms
        self.support = support
        self.metadata = metadata
        self.lastGeneratedAt = lastGeneratedAt
        self.model = model
        self.warnings = warnings
    }

    static let empty = Self()

    var normalized: Self {
        Self(
            privacy: privacy.normalized,
            terms: terms.normalized,
            support: support.normalized,
            metadata: metadata.normalized,
            lastGeneratedAt: lastGeneratedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model?.trimmingCharacters(in: .whitespacesAndNewlines),
            warnings: warnings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

struct AppStoreSubmissionConfirmations: Codable, Equatable, Sendable {
    var confirmedFields: [String: Bool]
    var manualReviewNotes: [String]

    init(
        confirmedFields: [String: Bool] = [:],
        manualReviewNotes: [String] = []
    ) {
        self.confirmedFields = confirmedFields
        self.manualReviewNotes = manualReviewNotes
    }

    static let empty = Self()

    func isConfirmed(_ key: String) -> Bool {
        confirmedFields[key] == true
    }

    mutating func setConfirmed(_ key: String, _ value: Bool) {
        confirmedFields[key] = value
    }

    var normalized: Self {
        Self(
            confirmedFields: confirmedFields,
            manualReviewNotes: manualReviewNotes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

struct AppStoreSubmissionPublishState: Codable, Equatable, Sendable {
    var publicSlug: String
    var locale: String
    var isPublished: Bool
    var lastPublishedAt: String?
    var lastPublishedSlug: String?
    var updatedAt: String?

    init(
        publicSlug: String = "",
        locale: String = "en-US",
        isPublished: Bool = false,
        lastPublishedAt: String? = nil,
        lastPublishedSlug: String? = nil,
        updatedAt: String? = nil
    ) {
        self.publicSlug = publicSlug
        self.locale = locale
        self.isPublished = isPublished
        self.lastPublishedAt = lastPublishedAt
        self.lastPublishedSlug = lastPublishedSlug
        self.updatedAt = updatedAt
    }

    static let empty = Self()

    var normalized: Self {
        Self(
            publicSlug: AppStoreSubmissionDraft.normalizedSlug(publicSlug),
            locale: locale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "en-US"
                : locale.trimmingCharacters(in: .whitespacesAndNewlines),
            isPublished: isPublished,
            lastPublishedAt: lastPublishedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
            lastPublishedSlug: AppStoreSubmissionDraft.normalizedSlug(lastPublishedSlug ?? ""),
            updatedAt: updatedAt?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct AppStoreSubmissionDraft: Codable, Equatable, Sendable {
    var facts: AppStoreSubmissionFacts
    var generated: AppStoreSubmissionGenerated
    var confirmations: AppStoreSubmissionConfirmations
    var publish: AppStoreSubmissionPublishState

    init(
        facts: AppStoreSubmissionFacts = .empty,
        generated: AppStoreSubmissionGenerated = .empty,
        confirmations: AppStoreSubmissionConfirmations = .empty,
        publish: AppStoreSubmissionPublishState = .empty
    ) {
        self.facts = facts
        self.generated = generated
        self.confirmations = confirmations
        self.publish = publish
    }

    static let empty = Self()

    static func normalizedSlug(_ value: String) -> String {
        let lowered = value.lowercased()
        let replaced = lowered.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func normalized(projectName: String) -> Self {
        var next = self
        next.facts = facts.normalized
        next.generated = generated.normalized
        next.confirmations = confirmations.normalized
        next.publish = publish.normalized
        if next.publish.publicSlug.isEmpty {
            next.publish.publicSlug = Self.normalizedSlug(projectName)
        }
        return next
    }

    var hasGeneratedPublicDocuments: Bool {
        generated.privacy.hasContent && generated.terms.hasContent && generated.support.hasContent
    }

    var supportURLPath: String? {
        let slug = publish.normalized.publicSlug
        return slug.isEmpty ? nil : "/\(slug)/support"
    }

    var privacyURLPath: String? {
        let slug = publish.normalized.publicSlug
        return slug.isEmpty ? nil : "/\(slug)/privacy"
    }

    var termsURLPath: String? {
        let slug = publish.normalized.publicSlug
        return slug.isEmpty ? nil : "/\(slug)/terms"
    }

    func hostedURL(baseURL: String, kind: String) -> URL? {
        // 11x local cockpit: hosted page URLs are not generated.
        return nil
    }

    func publishBlockers() -> [String] {
        let normalized = normalized(projectName: facts.appName.isEmpty ? "app" : facts.appName)
        var blockers: [String] = []
        // 11x local cockpit: hosted publishing is disabled.
        blockers.append("Hosted publishing is not available in 11x. Use local export instead.")
        if normalized.publish.publicSlug.isEmpty {
            blockers.append("Choose a public slug before publishing.")
        }
        if !normalized.hasGeneratedPublicDocuments {
            blockers.append("Generate privacy, terms, and support drafts before publishing.")
        }
        if normalized.facts.supportEmail.isEmpty {
            blockers.append("Add a support email before publishing.")
        }
        if normalized.facts.companyName.isEmpty && normalized.facts.legalEntityName.isEmpty {
            blockers.append("Add a company or legal entity name before publishing.")
        }
        if !normalized.confirmations.isConfirmed("support_contact") {
            blockers.append("Confirm the support contact details before publishing.")
        }
        if !normalized.confirmations.isConfirmed("privacy_claims") {
            blockers.append("Confirm the privacy and data-collection claims before publishing.")
        }
        if !normalized.confirmations.isConfirmed("tracking_claims") {
            blockers.append("Confirm the tracking and ads claims before publishing.")
        }
        if !normalized.confirmations.isConfirmed("age_rating") {
            blockers.append("Confirm the age-rating guidance before publishing.")
        }
        return blockers
    }
}

struct PublishedAppStoreBrandSnapshot: Codable, Equatable, Sendable {
    var appName: String
    var companyName: String
    var websiteURL: String?
    var supportEmail: String
    var privacyIntro: [String]
    var termsIntro: [String]
    var supportIntro: [String]
    var updatedAtLabel: String
}

struct PublishedAppStorePage: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let projectId: String
    let publicSlug: String
    let locale: String
    let brandSnapshot: PublishedAppStoreBrandSnapshot
    let privacySections: [AppStoreDocumentSection]
    let termsSections: [AppStoreDocumentSection]
    let supportSections: [AppStoreDocumentSection]
    let supportEmail: String
    let marketingURL: String?
    let accessibilityURL: String?
    let publishedAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case publicSlug = "public_slug"
        case locale
        case brandSnapshot = "brand_snapshot"
        case privacySections = "privacy_sections"
        case termsSections = "terms_sections"
        case supportSections = "support_sections"
        case supportEmail = "support_email"
        case marketingURL = "marketing_url"
        case accessibilityURL = "accessibility_url"
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
    }
}

struct PublishedAppStorePagePayload: Encodable, Sendable {
    let projectId: String
    let publicSlug: String
    let locale: String
    let brandSnapshot: PublishedAppStoreBrandSnapshot
    let privacySections: [AppStoreDocumentSection]
    let termsSections: [AppStoreDocumentSection]
    let supportSections: [AppStoreDocumentSection]
    let supportEmail: String
    let marketingURL: String?
    let accessibilityURL: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case publicSlug = "public_slug"
        case locale
        case brandSnapshot = "brand_snapshot"
        case privacySections = "privacy_sections"
        case termsSections = "terms_sections"
        case supportSections = "support_sections"
        case supportEmail = "support_email"
        case marketingURL = "marketing_url"
        case accessibilityURL = "accessibility_url"
    }
}

extension AppStoreSubmissionDraft {
    func publishedPayload(projectId: String, updatedAtLabel: String) -> PublishedAppStorePagePayload {
        let normalized = normalized(projectName: facts.appName.isEmpty ? "app" : facts.appName)
        let companyName = normalized.facts.companyName.isEmpty
            ? normalized.facts.legalEntityName
            : normalized.facts.companyName
        let brandSnapshot = PublishedAppStoreBrandSnapshot(
            appName: normalized.facts.appName,
            companyName: companyName,
            websiteURL: normalized.facts.websiteURL.isEmpty ? nil : normalized.facts.websiteURL,
            supportEmail: normalized.facts.supportEmail,
            privacyIntro: normalized.generated.privacy.intro,
            termsIntro: normalized.generated.terms.intro,
            supportIntro: normalized.generated.support.intro,
            updatedAtLabel: updatedAtLabel
        )

        return PublishedAppStorePagePayload(
            projectId: projectId,
            publicSlug: normalized.publish.publicSlug,
            locale: normalized.publish.locale,
            brandSnapshot: brandSnapshot,
            privacySections: normalized.generated.privacy.sections,
            termsSections: normalized.generated.terms.sections,
            supportSections: normalized.generated.support.sections,
            supportEmail: normalized.facts.supportEmail,
            marketingURL: normalized.facts.marketingURL.isEmpty ? nil : normalized.facts.marketingURL,
            accessibilityURL: normalized.facts.accessibilityURL.isEmpty ? nil : normalized.facts.accessibilityURL
        )
    }
}

extension BuilderProject {
    static let appStoreSubmissionSettingsKey = "app_store_submission"

    var appStoreSubmissionDraft: AppStoreSubmissionDraft? {
        settings?[Self.appStoreSubmissionSettingsKey]?.decode(AppStoreSubmissionDraft.self)
    }
}
