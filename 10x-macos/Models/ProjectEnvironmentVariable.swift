import Foundation

enum ProjectEnvironmentScope: String, Codable, Sendable, CaseIterable {
    case client
    case hosted

    nonisolated static func inferred(for key: String) -> Self {
        ProjectEnvironmentSecurity.isSensitive(key: key) ? .hosted : .client
    }

    var title: String {
        switch self {
        case .client:
            return "Client"
        case .hosted:
            return "Hosted"
        }
    }
}

struct ProjectEnvironmentVariable: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var key: String
    var description: String
    var value: String
    var scope: ProjectEnvironmentScope

    nonisolated init(
        id: String = UUID().uuidString,
        key: String = "",
        description: String = "",
        value: String = "",
        scope: ProjectEnvironmentScope? = nil
    ) {
        self.id = id
        self.key = key
        self.description = description
        self.value = value
        self.scope = scope ?? ProjectEnvironmentScope.inferred(for: key)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case description
        case value
        case scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        scope = try container.decodeIfPresent(ProjectEnvironmentScope.self, forKey: .scope)
            ?? ProjectEnvironmentScope.inferred(for: key)
    }

    nonisolated var normalizedKey: String {
        ProjectEnvironmentSecurity.normalizedKey(key)
    }

    nonisolated var isSensitive: Bool {
        scope == .hosted
    }
}
