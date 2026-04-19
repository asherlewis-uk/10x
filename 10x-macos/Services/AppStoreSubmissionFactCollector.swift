import Foundation

struct AppStoreSubmissionProjectSnapshot: Sendable {
    let projectName: String
    let projectDescription: String?
    let projectPlan: String?
    let workspaceDescriptor: ProjectWorkspaceDescriptor
    let fileTree: [String: String]
    let environmentValuesByKey: [String: String]
    let dependencyManifest: ProjectDependencyManifest?
    let backendState: ProjectBackendState
}

enum AppStoreSubmissionFactCollector {
    static func collect(from snapshot: AppStoreSubmissionProjectSnapshot) -> AppStoreSubmissionFacts {
        var facts = AppStoreSubmissionFacts.empty
        facts.appName = snapshot.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        facts.projectSummary = preferredSummary(
            description: snapshot.projectDescription,
            plan: snapshot.projectPlan
        )
        facts.bundleIdentifier = snapshot.workspaceDescriptor.bundleIdentifier ?? ""

        let permissionUsageDescriptions = collectPermissionUsageDescriptions(from: snapshot.fileTree)
        facts.permissionUsageDescriptions = permissionUsageDescriptions
        facts.collectsCameraData = permissionUsageDescriptions["NSCameraUsageDescription"] != nil
        facts.collectsMicrophoneData = permissionUsageDescriptions["NSMicrophoneUsageDescription"] != nil
        facts.collectsPhotoLibraryData = permissionUsageDescriptions["NSPhotoLibraryUsageDescription"] != nil
            || permissionUsageDescriptions["NSPhotoLibraryAddUsageDescription"] != nil
        facts.collectsLocationData = permissionUsageDescriptions["NSLocationWhenInUseUsageDescription"] != nil
            || permissionUsageDescriptions["NSLocationAlwaysAndWhenInUseUsageDescription"] != nil
            || permissionUsageDescriptions["NSLocationAlwaysUsageDescription"] != nil
        facts.collectsContactsData = permissionUsageDescriptions["NSContactsUsageDescription"] != nil
        facts.collectsHealthData = permissionUsageDescriptions["NSHealthClinicalHealthRecordsShareUsageDescription"] != nil
            || permissionUsageDescriptions["NSHealthShareUsageDescription"] != nil
            || permissionUsageDescriptions["NSHealthUpdateUsageDescription"] != nil

        facts.entitlementKeys = collectEntitlementKeys(from: snapshot.fileTree)

        let privacyManifest = collectPrivacyManifest(from: snapshot.fileTree)
        facts.privacyTrackingEnabled = privacyManifest.isTrackingEnabled
        facts.privacyTrackingDomains = privacyManifest.trackingDomains
        facts.requiredReasonAPIs = privacyManifest.requiredReasonAPIs
        if privacyManifest.isTrackingEnabled == true {
            facts.usesTracking = true
        }

        facts.integratedServices = collectIntegratedServices(from: snapshot)
        facts.backendProvider = backendProvider(from: snapshot)
        facts.authProvider = authProvider(from: snapshot)
        facts.usesAccounts = inferUsesAccounts(from: snapshot)
        facts.supportsAccountDeletion = inferSupportsAccountDeletion(from: snapshot)
        facts.usesSubscriptions = inferUsesSubscriptions(from: snapshot)
        facts.usesAnalytics = inferUsesAnalytics(from: snapshot)
        facts.usesTracking = facts.usesTracking || inferUsesTracking(from: snapshot)
        facts.usesAds = inferUsesAds(from: snapshot)
        facts.hasUserGeneratedContent = inferHasUserGeneratedContent(from: snapshot)
        facts.kidFocused = inferKidFocused(from: snapshot)
        facts.inferenceNotes = buildInferenceNotes(
            snapshot: snapshot,
            facts: facts
        )
        return facts.normalized
    }

    private struct PrivacyManifestSummary {
        var isTrackingEnabled: Bool?
        var trackingDomains: [String]
        var requiredReasonAPIs: [String]

        static let empty = Self(
            isTrackingEnabled: nil,
            trackingDomains: [],
            requiredReasonAPIs: []
        )
    }

    private static func preferredSummary(description: String?, plan: String?) -> String {
        for candidate in [description, plan] {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return String(trimmed.prefix(600))
        }
        return ""
    }

    private static func collectPermissionUsageDescriptions(from fileTree: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        for (path, content) in fileTree {
            guard path.lowercased().hasSuffix("info.plist") || content.contains("UsageDescription") else {
                continue
            }
            guard let plist = propertyListObject(from: content) as? [String: Any] else {
                continue
            }
            for (key, value) in plist {
                guard key.hasSuffix("UsageDescription"),
                      let stringValue = value as? String else {
                    continue
                }
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    values[key] = trimmed
                }
            }
        }
        return values
    }

    private static func collectEntitlementKeys(from fileTree: [String: String]) -> [String] {
        var keys: Set<String> = []
        for (path, content) in fileTree {
            guard path.lowercased().hasSuffix(".entitlements"),
                  let plist = propertyListObject(from: content) as? [String: Any] else {
                continue
            }
            keys.formUnion(plist.keys)
        }
        return keys.sorted()
    }

    private static func collectPrivacyManifest(from fileTree: [String: String]) -> PrivacyManifestSummary {
        var summary = PrivacyManifestSummary.empty

        for (path, content) in fileTree {
            guard path.lowercased().hasSuffix("privacyinfo.xcprivacy"),
                  let plist = propertyListObject(from: content) as? [String: Any] else {
                continue
            }

            if let tracking = plist["NSPrivacyTracking"] as? Bool {
                summary.isTrackingEnabled = tracking
            }

            if let domains = plist["NSPrivacyTrackingDomains"] as? [String] {
                summary.trackingDomains.append(contentsOf: domains)
            }

            if let accessedAPIs = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] {
                for item in accessedAPIs {
                    if let api = item["NSPrivacyAccessedAPIType"] as? String,
                       !api.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        summary.requiredReasonAPIs.append(api)
                    }
                }
            }
        }

        summary.trackingDomains = Array(Set(summary.trackingDomains)).sorted()
        summary.requiredReasonAPIs = Array(Set(summary.requiredReasonAPIs)).sorted()
        return summary
    }

    private static func collectIntegratedServices(from snapshot: AppStoreSubmissionProjectSnapshot) -> [String] {
        var services: Set<String> = []

        if !snapshot.environmentValuesByKey["SUPABASE_URL", default: ""].isEmpty {
            services.insert("Supabase")
        }
        if !snapshot.environmentValuesByKey["OPENAI_API_KEY", default: ""].isEmpty
            || snapshot.backendState.secrets.contains(where: {
                ProjectEnvironmentSecurity.normalizedKey($0.name) == "OPENAI_API_KEY"
            }) {
            services.insert("OpenAI")
        }
        if snapshot.backendState.providerID == .supabase {
            services.insert("Supabase")
        }

        for dependency in snapshot.dependencyManifest?.dependencies ?? [] {
            services.insert(dependency.title)
        }

        if containsAny(snapshot.fileTree, patterns: ["StoreKit", "SubscriptionStoreView", ".purchase("]) {
            services.insert("StoreKit")
        }
        if containsAny(snapshot.fileTree, patterns: ["FirebaseAnalytics", "Amplitude", "PostHog", "analytics"]) {
            services.insert("Analytics")
        }
        if containsAny(snapshot.fileTree, patterns: ["ATTrackingManager", "trackingAuthorizationStatus"]) {
            services.insert("App Tracking Transparency")
        }

        return Array(services).sorted()
    }

    private static func backendProvider(from snapshot: AppStoreSubmissionProjectSnapshot) -> String {
        if let provider = snapshot.backendState.providerID?.title,
           !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return provider
        }
        if !snapshot.environmentValuesByKey["SUPABASE_URL", default: ""].isEmpty {
            return "Supabase"
        }
        return containsAny(snapshot.fileTree, patterns: ["URLSession", "fetch(", "https://"])
            ? "Custom API"
            : ""
    }

    private static func authProvider(from snapshot: AppStoreSubmissionProjectSnapshot) -> String {
        if hasSupabaseAuthContext(snapshot),
           (containsAuthCodeSignals(snapshot.fileTree)
            || containsAuthPathContext(snapshot.fileTree)
            || containsAuthUILabels(in: snapshot.fileTree)) {
            return "Supabase Auth"
        }
        if containsAny(snapshot.fileTree, patterns: ["SignInWithAppleButton"]) {
            return "Sign in with Apple"
        }
        if containsAny(snapshot.fileTree, patterns: ["GIDSignIn", "GoogleSignIn"]) {
            return "Google Sign-In"
        }
        return ""
    }

    private static func inferUsesAccounts(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        if !authProvider(from: snapshot).isEmpty {
            return true
        }
        if inferSupportsAccountDeletion(from: snapshot) {
            return true
        }
        return containsAuthCodeSignals(snapshot.fileTree)
            || containsAuthPathContext(snapshot.fileTree)
            || containsAuthUILabels(in: snapshot.fileTree)
    }

    private static func inferSupportsAccountDeletion(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        containsAny(snapshot.fileTree, patterns: [
            "deleteAccount",
            "Delete Account",
            "removeAccount",
            "eraseAccount",
            "account deletion",
        ])
    }

    private static func inferUsesSubscriptions(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        containsAny(snapshot.fileTree, patterns: [
            "StoreKit",
            "SubscriptionStoreView",
            "Product.purchase",
            "Transaction.currentEntitlements",
            "subscription",
            "premium",
        ])
    }

    private static func inferUsesAnalytics(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        containsAny(snapshot.fileTree, patterns: [
            "FirebaseAnalytics",
            "Analytics.logEvent",
            "Amplitude",
            "PostHog",
            "analytics",
        ])
    }

    private static func inferUsesTracking(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        containsAny(snapshot.fileTree, patterns: [
            "ATTrackingManager",
            "trackingAuthorizationStatus",
            "requestTrackingAuthorization",
        ])
    }

    private static func inferUsesAds(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        containsAny(snapshot.fileTree, patterns: [
            "GADBannerView",
            "GoogleMobileAds",
            "AdMob",
            "adUnitID",
            "advertising",
        ])
    }

    private static func inferHasUserGeneratedContent(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        containsAnyRegex(snapshot.fileTree, patterns: [
            #"\bcomment(s)?\b"#,
            #"\bupload(s|ed|ing)?\b"#,
            #"\bfeed\b"#,
        ])
    }

    private static func inferKidFocused(from snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        let candidates = [
            snapshot.projectDescription ?? "",
            snapshot.projectPlan ?? "",
        ]
        return candidates.contains {
            $0.localizedCaseInsensitiveContains("kids")
                || $0.localizedCaseInsensitiveContains("children")
                || $0.localizedCaseInsensitiveContains("family")
        }
    }

    private static func buildInferenceNotes(
        snapshot: AppStoreSubmissionProjectSnapshot,
        facts: AppStoreSubmissionFacts
    ) -> [String] {
        var notes: [String] = []
        if facts.collectsCameraData {
            notes.append("Detected camera permission usage from Info.plist.")
        }
        if facts.collectsMicrophoneData {
            notes.append("Detected microphone permission usage from Info.plist.")
        }
        if facts.collectsPhotoLibraryData {
            notes.append("Detected photo library permission usage from Info.plist.")
        }
        if facts.usesSubscriptions {
            notes.append("Detected StoreKit or subscription-related code.")
        }
        if facts.usesAccounts {
            notes.append("Detected account or sign-in related code.")
        }
        if !facts.requiredReasonAPIs.isEmpty {
            notes.append("Detected required-reason APIs in PrivacyInfo.xcprivacy.")
        }
        if facts.backendProvider == "Supabase" {
            notes.append("Detected Supabase environment or backend linkage.")
        } else if !facts.backendProvider.isEmpty {
            notes.append("Detected backend-related networking code.")
        }
        if facts.usesTracking {
            notes.append("Detected App Tracking Transparency or privacy tracking declarations.")
        }
        if facts.usesAnalytics {
            notes.append("Detected analytics-related code.")
        }
        return notes
    }

    private static func containsAny(
        _ fileTree: [String: String],
        patterns: [String]
    ) -> Bool {
        let loweredPatterns = patterns.map { $0.lowercased() }
        for (path, content) in fileTree {
            let loweredPath = path.lowercased()
            let loweredContent = content.lowercased()
            for pattern in loweredPatterns where loweredPath.contains(pattern) || loweredContent.contains(pattern) {
                return true
            }
        }
        return false
    }

    private static func containsAnyRegex(
        _ fileTree: [String: String],
        patterns: [String]
    ) -> Bool {
        let regexes = patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        guard !regexes.isEmpty else {
            return false
        }

        for (path, content) in fileTree {
            let haystacks = [path, content]
            for haystack in haystacks {
                let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
                if regexes.contains(where: { $0.firstMatch(in: haystack, options: [], range: range) != nil }) {
                    return true
                }
            }
        }
        return false
    }

    private static func containsAnyPathRegex(
        _ fileTree: [String: String],
        patterns: [String]
    ) -> Bool {
        let regexes = patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        guard !regexes.isEmpty else {
            return false
        }

        for path in fileTree.keys {
            let range = NSRange(path.startIndex..<path.endIndex, in: path)
            if regexes.contains(where: { $0.firstMatch(in: path, options: [], range: range) != nil }) {
                return true
            }
        }
        return false
    }

    private static func containsAny(
        _ fileTree: [String: String],
        matchingPathRegex pathPatterns: [String],
        contentPatterns: [String]
    ) -> Bool {
        let pathRegexes = pathPatterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        let loweredContentPatterns = contentPatterns.map { $0.lowercased() }
        guard !pathRegexes.isEmpty, !loweredContentPatterns.isEmpty else {
            return false
        }

        for (path, content) in fileTree {
            let range = NSRange(path.startIndex..<path.endIndex, in: path)
            guard pathRegexes.contains(where: { $0.firstMatch(in: path, options: [], range: range) != nil }) else {
                continue
            }

            let loweredContent = content.lowercased()
            if loweredContentPatterns.contains(where: loweredContent.contains) {
                return true
            }
        }
        return false
    }

    private static func hasSupabaseAuthContext(_ snapshot: AppStoreSubmissionProjectSnapshot) -> Bool {
        if !snapshot.environmentValuesByKey["SUPABASE_URL", default: ""].isEmpty {
            return true
        }
        if snapshot.backendState.providerID == .supabase {
            return true
        }
        return containsAny(snapshot.fileTree, patterns: ["supabase"])
    }

    private static func containsAuthCodeSignals(_ fileTree: [String: String]) -> Bool {
        containsAny(fileTree, patterns: [
            "SignInWithAppleButton",
            "GIDSignIn",
            "GoogleSignIn",
            "signIn(",
            "signUp(",
            "logIn(",
            "login(",
            "createAccount",
            "supabase.auth",
            "auth.signIn",
            "auth.signUp",
            "isAuthenticated",
            "signOut(",
        ])
    }

    private static func containsAuthPathContext(_ fileTree: [String: String]) -> Bool {
        containsAnyPathRegex(fileTree, patterns: [
            #"(?:^|/)(auth|login|signin|signup)[^/]*\.[a-z0-9]+$"#,
        ])
    }

    private static func containsAuthUILabels(in fileTree: [String: String]) -> Bool {
        containsAny(
            fileTree,
            matchingPathRegex: [
                #"(?:^|/)(auth|login|signin|signup)[^/]*\.[a-z0-9]+$"#,
            ],
            contentPatterns: [
                "Create Account",
                "Sign In",
                "Sign Up",
                "Log In",
                "Login",
                "Sign Out",
            ]
        )
    }

    private static func propertyListObject(from content: String) -> Any? {
        guard let data = content.data(using: .utf8) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }
}
