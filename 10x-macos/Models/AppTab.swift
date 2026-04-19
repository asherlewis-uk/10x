import Foundation

/// Represents an open tab in the app.
struct AppTab: Identifiable, Equatable, Codable {
    let id: String
    var kind: Kind
    var label: String
    var projectId: String?

    enum Kind: String, Equatable, Codable {
        case project       // Full builder workspace (chat + preview)
        case billing       // Global billing and plan management
        case account       // Profile & billing page
    }

    static func project(name: String, projectId: String) -> AppTab {
        AppTab(id: UUID().uuidString, kind: .project, label: name, projectId: projectId)
    }

    static func billing() -> AppTab {
        AppTab(id: UUID().uuidString, kind: .billing, label: "Billing", projectId: nil)
    }

    static func account() -> AppTab {
        AppTab(id: UUID().uuidString, kind: .account, label: "Account", projectId: nil)
    }

    var icon: String {
        switch kind {
        case .project: "hammer.fill"
        case .billing: "creditcard.fill"
        case .account: "person.crop.circle"
        }
    }
}
