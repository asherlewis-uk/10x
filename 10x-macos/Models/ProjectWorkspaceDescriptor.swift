import Foundation

nonisolated enum XcodeContainerKind: String, Codable, Sendable {
    case project
    case workspace

    init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "xcodeproj":
            self = .project
        case "xcworkspace":
            self = .workspace
        default:
            return nil
        }
    }
}

nonisolated struct ImportedProjectMetadata: Sendable, Equatable {
    static let originKey = "project_origin"
    static let importedOriginValue = "imported"
    static let workspaceRootRelativePathKey = "workspace_root_relative_path"
    static let xcodeContainerRelativePathKey = "xcode_container_relative_path"
    static let xcodeContainerKindKey = "xcode_container_kind"
    static let schemeKey = "xcode_scheme"
    static let bundleIdentifierKey = "bundle_identifier"

    let workspaceRootRelativePath: String
    let xcodeContainerRelativePath: String
    let xcodeContainerKind: XcodeContainerKind
    let scheme: String
    let bundleIdentifier: String?

    var settingsDictionary: [String: AnyCodableValue] {
        var settings: [String: AnyCodableValue] = [
            Self.originKey: .string(Self.importedOriginValue),
            Self.workspaceRootRelativePathKey: .string(workspaceRootRelativePath),
            Self.xcodeContainerRelativePathKey: .string(xcodeContainerRelativePath),
            Self.xcodeContainerKindKey: .string(xcodeContainerKind.rawValue),
            Self.schemeKey: .string(scheme),
        ]

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            settings[Self.bundleIdentifierKey] = .string(bundleIdentifier)
        }

        return settings
    }
}

nonisolated struct ProjectWorkspaceDescriptor: Sendable {
    let workspaceRootRelativePath: String
    let xcodeContainerRelativePath: String?
    let xcodeContainerKind: XcodeContainerKind?
    let scheme: String?
    let bundleIdentifier: String?
    let isImported: Bool

    static func resolve(for project: BuilderProject) -> Self {
        if let imported = project.importedProjectMetadata {
            return Self(
                workspaceRootRelativePath: imported.workspaceRootRelativePath,
                xcodeContainerRelativePath: imported.xcodeContainerRelativePath,
                xcodeContainerKind: imported.xcodeContainerKind,
                scheme: imported.scheme,
                bundleIdentifier: imported.bundleIdentifier,
                isImported: true
            )
        }

        let targetName = XcodePreviewService.targetName(from: project.name)
        return Self(
            workspaceRootRelativePath: "ios/\(targetName)",
            xcodeContainerRelativePath: "ios/\(targetName).xcodeproj",
            xcodeContainerKind: .project,
            scheme: targetName,
            bundleIdentifier: XcodePreviewService.bundleId(from: project.name),
            isImported: false
        )
    }

    func workspaceRootURL(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(workspaceRootRelativePath, isDirectory: true)
    }

    func xcodeContainerURL(projectRoot: URL) -> URL? {
        guard let xcodeContainerRelativePath, !xcodeContainerRelativePath.isEmpty else {
            return nil
        }
        return projectRoot.appendingPathComponent(xcodeContainerRelativePath)
    }
}

extension BuilderProject {
    var importedProjectMetadata: ImportedProjectMetadata? {
        guard settings?[ImportedProjectMetadata.originKey]?.stringValue
            == ImportedProjectMetadata.importedOriginValue
        else {
            return nil
        }

        guard let workspaceRootRelativePath = settings?[
            ImportedProjectMetadata.workspaceRootRelativePathKey
        ]?.trimmedStringValue,
        let xcodeContainerRelativePath = settings?[
            ImportedProjectMetadata.xcodeContainerRelativePathKey
        ]?.trimmedStringValue,
        let scheme = settings?[ImportedProjectMetadata.schemeKey]?.trimmedStringValue
        else {
            return nil
        }

        let containerKind = settings?[ImportedProjectMetadata.xcodeContainerKindKey]?.trimmedStringValue
            .flatMap(XcodeContainerKind.init(rawValue:))
            ?? XcodeContainerKind(pathExtension: URL(fileURLWithPath: xcodeContainerRelativePath).pathExtension)

        guard let xcodeContainerKind = containerKind else {
            return nil
        }

        return ImportedProjectMetadata(
            workspaceRootRelativePath: workspaceRootRelativePath,
            xcodeContainerRelativePath: xcodeContainerRelativePath,
            xcodeContainerKind: xcodeContainerKind,
            scheme: scheme,
            bundleIdentifier: settings?[ImportedProjectMetadata.bundleIdentifierKey]?.trimmedStringValue
        )
    }

    var workspaceDescriptor: ProjectWorkspaceDescriptor {
        ProjectWorkspaceDescriptor.resolve(for: self)
    }
}

extension AnyCodableValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var trimmedStringValue: String? {
        guard let stringValue else { return nil }
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
