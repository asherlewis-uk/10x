import Foundation

nonisolated struct BuilderProjectStatusState: Codable, Sendable, Equatable {
    var plan: String?
    var tasks: String?
    var warnings: [BuilderProjectWarning]
    var dependencyManifest: ProjectDependencyManifest?

    init(
        plan: String? = nil,
        tasks: String? = nil,
        warnings: [BuilderProjectWarning] = [],
        dependencyManifest: ProjectDependencyManifest? = nil
    ) {
        self.plan = Self.normalized(plan)
        self.tasks = Self.normalized(tasks)
        self.warnings = warnings
        self.dependencyManifest = dependencyManifest
    }

    var hasContent: Bool {
        plan != nil || tasks != nil || !warnings.isEmpty || dependencyManifest != nil
    }

    static func resolve(
        projectStatus: BuilderProjectStatusState?,
        chatState: BuilderChatState,
        projectDependencyManifest: ProjectDependencyManifest? = nil
    ) -> BuilderProjectStatusState {
        let explicitStatus = projectStatus ?? .empty
        return BuilderProjectStatusState(
            plan: explicitStatus.plan ?? chatState.plan,
            tasks: explicitStatus.tasks ?? chatState.tasks,
            warnings: explicitStatus.warnings.isEmpty ? chatState.warnings : explicitStatus.warnings,
            dependencyManifest: explicitStatus.dependencyManifest ?? projectDependencyManifest
        )
    }

    static func merged(
        projectStatus: BuilderProjectStatusState?,
        projectDependencyManifest: ProjectDependencyManifest?
    ) -> BuilderProjectStatusState? {
        switch (projectStatus, projectDependencyManifest) {
        case (.none, .none):
            return nil
        case (.none, .some(let manifest)):
            return BuilderProjectStatusState(dependencyManifest: manifest)
        case (.some(var status), .some(let manifest)):
            if status.dependencyManifest == nil {
                status.dependencyManifest = manifest
            }
            return status
        case (.some(let status), .none):
            return status
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    nonisolated static let empty = BuilderProjectStatusState()
}
