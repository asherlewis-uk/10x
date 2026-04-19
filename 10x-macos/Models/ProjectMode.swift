import Foundation

/// The active mode for a project workspace.
/// Each mode tailors the AI's system prompt, sidebar, and preview panel.
enum ProjectMode: String, Codable, CaseIterable, Sendable {
    case plan       // Research, architecture, requirements
    case build      // SwiftUI code generation

    var label: String {
        switch self {
        case .plan: "Plan"
        case .build: "Build"
        }
    }

    var icon: String {
        switch self {
        case .plan: "lightbulb.fill"
        case .build: "hammer.fill"
        }
    }

    var description: String {
        switch self {
        case .plan: "Research & plan your app"
        case .build: "Write SwiftUI code"
        }
    }
}
