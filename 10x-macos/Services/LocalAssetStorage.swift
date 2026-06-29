import CryptoKit
import Foundation

enum LocalAssetKind: String, CaseIterable, Sendable {
    case upload
    case generated
    case preview
    case export
    case log

    var directoryName: String {
        switch self {
        case .upload:
            return "uploads"
        case .generated:
            return "generated"
        case .preview:
            return "previews"
        case .export:
            return "exports"
        case .log:
            return "logs"
        }
    }
}

enum LocalAssetStorageError: LocalizedError, Equatable {
    case emptyRelativePath
    case absolutePathRejected(String)
    case pathTraversalRejected(String)
    case invalidPathComponent(String)
    case storageRootEscape(String)

    var errorDescription: String? {
        switch self {
        case .emptyRelativePath:
            return "Asset path cannot be empty."
        case .absolutePathRejected(let path):
            return "Asset path must be relative under the asset root: \(path)"
        case .pathTraversalRejected(let path):
            return "Asset path traversal is not allowed: \(path)"
        case .invalidPathComponent(let component):
            return "Asset path contains an invalid component: \(component)"
        case .storageRootEscape(let path):
            return "Asset path resolves outside the asset root: \(path)"
        }
    }
}

/// Stores asset bytes under Application Support/11x/assets and records only metadata in SQLite.
actor LocalAssetStorage {
    nonisolated static let assetRootDirectoryName = "assets"

    private let rootURL: URL
    private let repository: AssetRepository

    init(
        rootURL: URL = LocalAssetStorage.defaultAssetRootURL(),
        repository: AssetRepository = AssetRepository()
    ) {
        self.rootURL = rootURL
        self.repository = repository
    }

    nonisolated static func defaultAssetRootURL() -> URL {
        AppIdentity.appSupportDirectory
            .appendingPathComponent(assetRootDirectoryName, isDirectory: true)
    }

    nonisolated static func relativePath(
        projectId: String,
        kind: LocalAssetKind,
        filename: String,
        subdirectories: [String] = []
    ) -> String {
        let projectComponent = safePathComponent(projectId, fallback: "project")
        let directoryComponents = subdirectories.map {
            safePathComponent($0, fallback: "items")
        }
        let fileComponent = safeFilename(filename)
        return (["projects", projectComponent, kind.directoryName] + directoryComponents + [fileComponent])
            .joined(separator: "/")
    }

    nonisolated static func isPortableAssetPath(_ relativePath: String) -> Bool {
        (try? normalizedRelativePath(relativePath))?.hasPrefix("projects/") == true
    }

    nonisolated static func normalizedRelativePath(_ relativePath: String) throws -> String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalAssetStorageError.emptyRelativePath
        }

        let lowercased = trimmed.lowercased()
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || lowercased.hasPrefix("file:") {
            throw LocalAssetStorageError.absolutePathRejected(relativePath)
        }

        if trimmed.contains("\0") || trimmed.contains("\\") {
            throw LocalAssetStorageError.invalidPathComponent(relativePath)
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty else {
            throw LocalAssetStorageError.emptyRelativePath
        }

        for component in components {
            if component == ".." {
                throw LocalAssetStorageError.pathTraversalRejected(relativePath)
            }
            if component.isEmpty || component == "." {
                throw LocalAssetStorageError.invalidPathComponent(component)
            }
        }

        return components.joined(separator: "/")
    }

    nonisolated static func resolvedAssetURL(
        rootURL: URL = defaultAssetRootURL(),
        relativePath: String
    ) throws -> URL {
        let normalizedPath = try normalizedRelativePath(relativePath)
        let root = rootURL.standardizedFileURL
        let url = root.appendingPathComponent(normalizedPath, isDirectory: false).standardizedFileURL
        let rootPath = root.path
        let urlPath = url.path

        guard urlPath.hasPrefix(rootPath + "/") else {
            throw LocalAssetStorageError.storageRootEscape(relativePath)
        }

        return url
    }

    func writeAsset(
        projectId: String,
        kind: LocalAssetKind,
        filename: String,
        mimeType: String?,
        data: Data,
        subdirectories: [String] = []
    ) async throws -> LocalAsset {
        let relativePath = Self.relativePath(
            projectId: projectId,
            kind: kind,
            filename: "\(UUID().uuidString)-\(filename)",
            subdirectories: subdirectories
        )
        return try await writeAsset(
            projectId: projectId,
            kind: kind,
            relativePath: relativePath,
            mimeType: mimeType,
            data: data
        )
    }

    func writeAsset(
        projectId: String,
        kind: LocalAssetKind,
        relativePath: String,
        mimeType: String?,
        data: Data
    ) async throws -> LocalAsset {
        let normalizedPath = try Self.normalizedRelativePath(relativePath)
        let assetURL = try Self.resolvedAssetURL(rootURL: rootURL, relativePath: normalizedPath)

        try FileManager.default.createDirectory(
            at: assetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: assetURL, options: .atomic)

        let now = Self.isoTimestamp()
        let asset = LocalAsset(
            id: Self.assetID(projectId: projectId, relativePath: normalizedPath),
            projectId: projectId,
            kind: kind.rawValue,
            relativePath: normalizedPath,
            mimeType: mimeType,
            sizeBytes: data.count,
            checksum: Self.sha256Hex(data),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        try await repository.saveAsset(asset)
        return asset
    }

    func assetURL(for relativePath: String) throws -> URL {
        try Self.resolvedAssetURL(rootURL: rootURL, relativePath: relativePath)
    }

    func readAsset(relativePath: String) throws -> Data {
        let url = try assetURL(for: relativePath)
        return try Data(contentsOf: url)
    }

    func assets(projectId: String) async throws -> [LocalAsset] {
        try await repository.fetchAssets(projectId: projectId)
    }

    private nonisolated static func assetID(projectId: String, relativePath: String) -> String {
        let seed = "\(projectId)|\(relativePath)"
        return "asset_\(sha256Hex(Data(seed.utf8)))"
    }

    private nonisolated static func safeFilename(_ filename: String) -> String {
        let lastComponent = NSString(string: filename).lastPathComponent
        let sanitized = safePathComponent(lastComponent, fallback: "asset")
        return sanitized.contains(".") ? sanitized : "\(sanitized).bin"
    }

    private nonisolated static func safePathComponent(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private nonisolated static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
