import Foundation

enum Config {
    // For public builds, defaults are intentionally inert placeholders.
    // Override them with environment variables or Xcode build settings before shipping.
    static var apiBaseURL: String {
        let rawValue = ProcessInfo.processInfo.environment["API_BASE_URL"]
            ?? Bundle.main.infoDictionary?["API_BASE_URL"] as? String
            ?? ""

        return rawValue.isEmpty ? "" : normalizedBaseURL(rawValue)
    }

    static let apiVersion = "v1"
    static let creditUnits = "normalized"
    static let platform = "macos"

    // MARK: Billing / Payments — permanently disabled for 11x local cockpit

    static var billingTestMode: Bool {
        LocalEntitlements.billingTestMode
    }

    static var paymentsEnabled: Bool {
        LocalEntitlements.paymentsEnabled
    }

    static var signupBonusEnabled: Bool {
        LocalEntitlements.signupBonusEnabled
    }

    static var useNativeAppleSignIn: Bool {
        let rawValue = ProcessInfo.processInfo.environment["USE_NATIVE_APPLE_SIGN_IN"]
            ?? Bundle.main.infoDictionary?["USE_NATIVE_APPLE_SIGN_IN"] as? String
            ?? "false"

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return false
        }
    }

    static var appVersion: String {
        ProcessInfo.processInfo.environment["APP_VERSION"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0"
    }

    static var appBuild: String {
        ProcessInfo.processInfo.environment["APP_BUILD"]
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "0"
    }

    static var sparkleFeedURL: String {
        // 11x local cockpit: vendor updater feeds are disabled.
        let configured = ProcessInfo.processInfo.environment["SPARKLE_FEED_URL"]
            ?? Bundle.main.infoDictionary?["SUFeedURL"] as? String
            ?? ""
        return configured.isEmpty ? "" : configured
    }

    static var defaultUpdateChannel: AppUpdateChannel {
        AppUpdateChannel.defaultChannel()
    }

    static var hostedAppsBaseURL: String {
        let raw = ProcessInfo.processInfo.environment["HOSTED_APPS_BASE_URL"]
            ?? Bundle.main.infoDictionary?["HOSTED_APPS_BASE_URL"] as? String
            ?? ""
        return raw.isEmpty ? "" : normalizedBaseURL(raw)
    }

    static var hostedAppsDisplayHost: String {
        URL(string: hostedAppsBaseURL)?.host ?? ""
    }

    static var supabaseURL: String {
        // 11x local cockpit: Supabase is removed; no default URL.
        ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? Bundle.main.infoDictionary?["SUPABASE_URL"] as? String
            ?? ""
    }

    static var supabaseAnonKey: String {
        // 11x local cockpit: Supabase is removed; no default anon key.
        ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String
            ?? ""
    }


    // MARK: - Provider Configuration (OpenAI-compatible BYOK/local gateway)

    static var openAIAPIKey: String {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String
            ?? ""
    }

    static var openAIBaseURL: String {
        let raw = ProcessInfo.processInfo.environment["OPENAI_BASE_URL"]
            ?? Bundle.main.infoDictionary?["OPENAI_BASE_URL"] as? String
            ?? "https://api.openai.com"
        return normalizedBaseURL(raw)
    }

    static var openAIModel: String {
        ProcessInfo.processInfo.environment["OPENAI_MODEL"]
            ?? Bundle.main.infoDictionary?["OPENAI_MODEL"] as? String
            ?? "gpt-4.1"
    }

    private static func boolValue(for key: String, defaultValue: Bool) -> Bool {
        let fallback = defaultValue ? "true" : "false"
        let rawValue = ProcessInfo.processInfo.environment[key]
            ?? Bundle.main.infoDictionary?[key] as? String
            ?? fallback

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return defaultValue
        }
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        var normalized = value
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
