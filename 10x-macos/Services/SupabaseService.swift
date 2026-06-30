import Foundation

/// Compatibility shim that previously wrapped the Supabase client.
/// In 11x it routes project/version/message persistence through local SQLite
/// repositories and the local filesystem store.
///
/// Status: temporary compatibility shim to keep call-site churn bounded during
/// Pass 04. It should be renamed/removed once the rest of the app is updated.
enum SupabaseServiceError: LocalizedError {
    case emptyResult(context: String)

    var errorDescription: String? {
        switch self {
        case .emptyResult(let context):
            return "Local persistence returned no rows for \(context)."
        }
    }
}

struct SupabaseSessionSnapshot: Sendable {
    let accessToken: String
    let refreshToken: String
    let userId: String?
    let userEmail: String?
}

enum SupabaseAuthEvent: Sendable {
    case initialSession
    case signedIn
    case signedOut
    case tokenRefreshed
    case userUpdated
    case userDeleted
    case passwordRecovery
    case mfaChallengeVerified
}

struct SupabaseAuthStateUpdate: Sendable {
    let event: SupabaseAuthEvent
    let session: SupabaseSessionSnapshot?
}

/// Direct local persistence client. Replaces the Supabase-backed `SupabaseService`.
actor SupabaseService {
    static let shared = SupabaseService()

    private let projects = ProjectRepository()
    private let versions = VersionRepository()
    private let messages = MessageRepository()
    private let localStore = LocalProjectStore()

    // MARK: - Session compatibility (no-op)

    func setSession(accessToken: String, refreshToken: String?) async throws -> SupabaseSessionSnapshot {
        return SupabaseSessionSnapshot(
            accessToken: accessToken,
            refreshToken: refreshToken ?? "",
            userId: nil,
            userEmail: nil
        )
    }

    func refreshSDKSession() async throws -> SupabaseSessionSnapshot {
        return try await setSession(accessToken: "", refreshToken: "")
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseSessionSnapshot {
        return try await setSession(accessToken: idToken, refreshToken: "")
    }

    func authStateChanges() -> AsyncStream<SupabaseAuthStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func signOut() async { }

    func updateCurrentUser(fullName: String?, givenName: String?, familyName: String?) async throws { }

    // MARK: - Projects

    func fetchProjects(userId: String) async throws -> [BuilderProject] {
        try await projects.fetchProjects(userId: userId)
    }

    func fetchArchivedProjects(userId: String) async throws -> [BuilderProject] {
        try await projects.fetchProjects(userId: userId, status: "archived")
    }

    func createProject(userId: String, name: String, platform: String = "swiftui") async throws -> BuilderProject {
        let project = try await projects.createProject(userId: userId, name: name, platform: platform)
        return project
    }

    func getProject(id: String) async throws -> BuilderProject? {
        try await projects.getProject(id: id)
    }

    func updateProject(id: String, data: UpdateProjectData) async throws -> BuilderProject {
        return try await projects.updateProject(
            id: id,
            name: data.name,
            description: data.description,
            slug: data.slug,
            settings: data.settings
        )
    }

    func archiveProject(id: String) async throws -> BuilderProject {
        try await projects.archiveProject(id: id)
    }

    func unarchiveProject(id: String) async throws -> BuilderProject {
        try await projects.unarchiveProject(id: id)
    }

    func deleteProject(id: String) async throws {
        try await projects.deleteProject(id: id)
    }

    // MARK: - Published App Store Pages (hosted feature disabled in 11x)

    func getPublishedAppStorePage(projectId: String) async throws -> PublishedAppStorePage? { nil }
    func getPublishedAppStorePage(publicSlug: String) async throws -> PublishedAppStorePage? { nil }
    func savePublishedAppStorePage(_ payload: PublishedAppStorePagePayload) async throws -> PublishedAppStorePage {
        throw SupabaseServiceError.emptyResult(context: "hosted app store pages are disabled in 11x local cockpit")
    }
    func unpublishAppStorePage(projectId: String) async throws { }

    // MARK: - Versions

    func fetchVersions(projectId: String) async throws -> [BuilderVersion] {
        try await versions.fetchVersions(projectId: projectId)
    }

    func getVersion(projectId: String, versionId: String) async throws -> BuilderVersion? {
        try await versions.getVersion(projectId: projectId, versionId: versionId)
    }

    func createVersion(
        projectId: String,
        conversationId: String,
        fileTree: [String: String],
        prompt: String
    ) async throws -> BuilderVersion {
        try await versions.createVersion(
            projectId: projectId,
            conversationId: conversationId,
            fileTree: fileTree,
            prompt: prompt
        )
    }

    // MARK: - Conversations & Messages

    func fetchConversation(projectId: String) async throws -> (messages: [BuilderMessage], conversationId: String?) {
        let localMessages = await localStore.loadMessages(projectName: "", projectId: projectId) ?? []
        let conversationId = localMessages.first?.conversationId ?? projectId
        return (localMessages, conversationId)
    }

    func addMessage(
        conversationId: String,
        role: String,
        content: String,
        versionId: String? = nil
    ) async throws -> BuilderMessage {
        let message = BuilderMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: role,
            content: content,
            versionId: versionId,
            createdAt: BuilderChat.timestamp()
        )
        try await messages.addMessage(message, projectId: conversationId)
        return message
    }

    // MARK: - Helpers

    private func requireFirstResult<T>(context: String, _ load: () async throws -> [T]) async throws -> T {
        try firstResult(await load(), context: context)
    }

    private func firstResult<T>(_ results: [T], context: String) throws -> T {
        guard let first = results.first else {
            throw SupabaseServiceError.emptyResult(context: context)
        }
        return first
    }
}

// MARK: - Request Data Types

struct CreateProjectData: Encodable {
    let userId: String
    let name: String
    let slug: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, slug, platform
    }
}

struct UpdateProjectData: Encodable {
    var name: String?
    var description: String?
    var slug: String?
    var settings: [String: AnyCodableValue]?
}

struct CreateVersionData: Encodable {
    let projectId: String
    let conversationId: String
    let versionNumber: Int
    let fileTree: [String: String]
    let prompt: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case conversationId = "conversation_id"
        case versionNumber = "version_number"
        case fileTree = "file_tree"
        case prompt, status
    }
}

struct CreateMessageData: Encodable {
    let conversationId: String
    let role: String
    let content: String
    let versionId: String?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case role, content
        case versionId = "version_id"
    }
}

/// Minimal type for decoding conversation rows (we only need the id).
struct ConversationRow: Decodable {
    let id: String
}
