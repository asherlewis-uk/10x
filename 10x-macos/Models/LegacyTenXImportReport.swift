import Foundation

/// Result of importing a legacy 10x project into 11x.
struct LegacyTenXImportReport: Sendable {
    var project: BuilderProject?
    var alreadyImported: Bool = false
    var previousProjectId: String?
    var copiedSourceFiles: [String] = []
    var copiedAssetFiles: [String] = []
    var importedMessageCount: Int = 0
    var importedPlan: Bool = false
    var importedTasks: Bool = false
    var rawMessagesPreserved: Bool = false
    var rawChatsPreserved: Bool = false
    var rawChatStatesPreserved: Int = 0
    var conversationTranscriptAttached: Bool = false
    var unavailable: [String] = []
    var skipped: [String] = []
    var errors: [String] = []

    var succeeded: Bool { project != nil }
}

enum LegacyTenXImportError: LocalizedError {
    case notLegacyProject(String)
    case nothingImportable(String)
    case copyFailed(String)
    case duplicateImport(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .notLegacyProject(let message):
            return message
        case .nothingImportable(let message):
            return message
        case .copyFailed(let message):
            return message
        case .duplicateImport(let message):
            return message
        case .invalidPath(let message):
            return message
        }
    }
}
