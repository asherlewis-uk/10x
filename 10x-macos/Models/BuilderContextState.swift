import Foundation

enum BuilderContextArtifactCategory: String, Codable, Sendable, Hashable {
    case fileRead
    case fileChange
    case command
    case research
    case question
    case planning
    case skill
    case other
}

struct BuilderContextArtifact: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let category: BuilderContextArtifactCategory
    let title: String
    let detail: String
    let sourceTool: String?
    let relatedPaths: [String]
    let createdAt: String

    init(
        id: String = UUID().uuidString,
        category: BuilderContextArtifactCategory,
        title: String,
        detail: String,
        sourceTool: String? = nil,
        relatedPaths: [String] = [],
        createdAt: String = BuilderChat.timestamp()
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.sourceTool = sourceTool
        self.relatedPaths = relatedPaths
        self.createdAt = createdAt
    }

    var promptLine: String {
        let toolPrefix: String
        if let sourceTool, !sourceTool.isEmpty {
            toolPrefix = "[\(sourceTool)] "
        } else {
            toolPrefix = ""
        }

        let compactDetail = Self.compact(detail, maxLength: 140)
        if compactDetail.isEmpty {
            return "- \(toolPrefix)\(title)"
        }
        return "- \(toolPrefix)\(title): \(compactDetail)"
    }

    private static func compact(_ text: String, maxLength: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count > maxLength else { return normalized }

        let prefix = String(normalized.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]) + "..."
        }
        return prefix + "..."
    }
}

struct BuilderContextState: Codable, Sendable, Hashable {
    var schemaVersion: Int
    var taskOverview: [String]
    var currentState: [String]
    var decisions: [String]
    var blockers: [String]
    var nextSteps: [String]
    var userPreferences: [String]
    var filesInFocus: [String]
    var recentRequests: [String]
    var artifacts: [BuilderContextArtifact]
    var updatedAt: String

    init(
        schemaVersion: Int = 1,
        taskOverview: [String] = [],
        currentState: [String] = [],
        decisions: [String] = [],
        blockers: [String] = [],
        nextSteps: [String] = [],
        userPreferences: [String] = [],
        filesInFocus: [String] = [],
        recentRequests: [String] = [],
        artifacts: [BuilderContextArtifact] = [],
        updatedAt: String = BuilderChat.timestamp()
    ) {
        self.schemaVersion = schemaVersion
        self.taskOverview = taskOverview
        self.currentState = currentState
        self.decisions = decisions
        self.blockers = blockers
        self.nextSteps = nextSteps
        self.userPreferences = userPreferences
        self.filesInFocus = filesInFocus
        self.recentRequests = recentRequests
        self.artifacts = artifacts
        self.updatedAt = updatedAt
    }

    var hasContent: Bool {
        !taskOverview.isEmpty
            || !currentState.isEmpty
            || !decisions.isEmpty
            || !blockers.isEmpty
            || !nextSteps.isEmpty
            || !userPreferences.isEmpty
            || !filesInFocus.isEmpty
            || !recentRequests.isEmpty
            || !artifacts.isEmpty
    }

    func promptBlock(maxArtifactCount: Int = 8) -> String {
        var sections = [
            "<context_memory>",
            "Use this as compacted background context. Recent raw messages below are more detailed. Re-read files before editing if exact contents matter."
        ]

        if let section = Self.promptSection(title: "Task overview", items: taskOverview) {
            sections.append(section)
        }
        if let section = Self.promptSection(title: "Current state", items: currentState) {
            sections.append(section)
        }
        if let section = Self.promptSection(title: "Key decisions", items: decisions) {
            sections.append(section)
        }
        if let section = Self.promptSection(title: "Open blockers", items: blockers) {
            sections.append(section)
        }
        if let section = Self.promptSection(title: "Next steps", items: nextSteps) {
            sections.append(section)
        }
        if let section = Self.promptSection(title: "User preferences", items: userPreferences) {
            sections.append(section)
        }
        if let section = Self.promptSection(title: "Files in focus", items: filesInFocus) {
            sections.append(section)
        }
        if let section = Self.promptSection(title: "Recent requests", items: recentRequests) {
            sections.append(section)
        }

        let artifactLines = artifacts.prefix(maxArtifactCount).map(\.promptLine)
        if !artifactLines.isEmpty {
            sections.append("""
            ## Recent receipts
            \(artifactLines.joined(separator: "\n"))
            """)
        }

        sections.append("</context_memory>")
        return sections.joined(separator: "\n\n")
    }

    private static func promptSection(title: String, items: [String]) -> String? {
        let normalized = items
            .map { compact($0, maxLength: 180) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return nil }
        return """
        ## \(title.capitalized)
        \(normalized.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static func compact(_ text: String, maxLength: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count > maxLength else { return normalized }

        let prefix = String(normalized.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]) + "..."
        }
        return prefix + "..."
    }

    nonisolated static let empty = BuilderContextState()
}
