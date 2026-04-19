import Foundation

enum AppUpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    static let userDefaultsKey = "preferredUpdateChannel"
    static let infoPlistKey = "DEFAULT_UPDATE_CHANNEL"
    static let betaSparkleChannel = "beta"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return "Stable"
        case .beta:
            return "Beta"
        }
    }

    var summary: String {
        switch self {
        case .stable:
            return "Only install stable releases from the default update channel."
        case .beta:
            return "Install beta releases when available while still seeing stable releases. Switching does not downgrade from a newer stable build."
        }
    }

    var sparkleAllowedChannels: Set<String> {
        switch self {
        case .stable:
            return []
        case .beta:
            return [Self.betaSparkleChannel]
        }
    }

    static func resolved(preferenceRawValue: String?, defaultRawValue: String?) -> Self {
        if let preferenceRawValue, let channel = Self(rawValue: preferenceRawValue) {
            return channel
        }
        if let defaultRawValue, let channel = Self(rawValue: defaultRawValue) {
            return channel
        }
        return .stable
    }

    static func defaultChannel(bundle: Bundle = .main) -> Self {
        resolved(
            preferenceRawValue: nil,
            defaultRawValue: bundle.object(forInfoDictionaryKey: infoPlistKey) as? String
        )
    }

    static func preferredChannel(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Self {
        resolved(
            preferenceRawValue: defaults.string(forKey: userDefaultsKey),
            defaultRawValue: bundle.object(forInfoDictionaryKey: infoPlistKey) as? String
        )
    }

    func persist(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    static func browserReleaseNotesURL(from url: URL?) -> URL? {
        guard
            let url,
            url.pathExtension.caseInsensitiveCompare("html") == .orderedSame,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        let path = components.path
        let isChannelReleaseNotesPath =
            path.contains("/stable/release-notes/") || path.contains("/beta/release-notes/")

        guard isChannelReleaseNotesPath else {
            return url
        }

        components.path = (path as NSString).deletingPathExtension
        return components.url ?? url
    }
}
