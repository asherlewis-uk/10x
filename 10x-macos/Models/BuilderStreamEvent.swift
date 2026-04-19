import Foundation

/// A single question from an ask_user event.
struct AskUserQuestion: Codable, Sendable, Hashable {
    let question: String
    let options: [String]?
    let multiSelect: Bool
}
