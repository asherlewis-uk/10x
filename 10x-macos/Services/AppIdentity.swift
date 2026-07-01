import Foundation

enum AppIdentity {
    nonisolated static let displayName = "11x"
    nonisolated static let bundleIdentifier = "app.kasey.11x"
    nonisolated static let urlScheme = "elevenx"
    nonisolated static let appSupportDirectoryName = "11x"
    nonisolated static let preferencesNamespace = "app.kasey.11x"
    nonisolated static let keychainServiceNamespace = "app.kasey.11x"
    nonisolated static let keychainAccessGroupSuffix = "app.kasey.11x.shared"
    nonisolated static let ownedDomain = "asherlewis.online"
    nonisolated static let universalLinkRoutePrefix = "/11x/"

    nonisolated static let localBadgeTitle = "11x"
    nonisolated static let localBadgeDetails = [
        "Single-user cockpit",
        "Unlimited local",
        "Local workspace",
    ]

    nonisolated static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }
}
