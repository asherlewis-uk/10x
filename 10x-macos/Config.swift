import Foundation

enum Config {
    // For public builds, defaults are intentionally inert placeholders.
    // Override them with environment variables or Xcode build settings before shipping.
    static var apiBaseURL: String {
        let rawValue = ProcessInfo.processInfo.environment["API_BASE_URL"]
            ?? Bundle.main.infoDictionary?["API_BASE_URL"] as? String
            ?? "http://localhost:8000"

        return normalizedBaseURL(rawValue)
    }

    static let apiVersion = "v1"
    static let creditUnits = "normalized"
    static let platform = "macos"
    static var billingTestMode: Bool {
        boolValue(for: "BILLING_TEST_MODE", defaultValue: false)
    }

    static var paymentsEnabled: Bool {
        boolValue(for: "PAYMENTS_ENABLED", defaultValue: true)
    }

    static var signupBonusEnabled: Bool {
        boolValue(for: "SIGNUP_BONUS_ENABLED", defaultValue: true)
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
        ProcessInfo.processInfo.environment["SPARKLE_FEED_URL"]
            ?? Bundle.main.infoDictionary?["SUFeedURL"] as? String
            ?? ""
    }

    static var defaultUpdateChannel: AppUpdateChannel {
        AppUpdateChannel.defaultChannel()
    }

    static var hostedAppsBaseURL: String {
        normalizedBaseURL(
            ProcessInfo.processInfo.environment["HOSTED_APPS_BASE_URL"]
                ?? "https://apps.example.invalid"
        )
    }

    static var hostedAppsDisplayHost: String {
        URL(string: hostedAppsBaseURL)?.host ?? "apps.example.invalid"
    }

    static var supabaseURL: String {
        ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? Bundle.main.infoDictionary?["SUPABASE_URL"] as? String
            ?? "https://your-project-ref.supabase.co"
    }

    static var supabaseAnonKey: String {
        ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String
            ?? "sb_publishable_your_key"
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
