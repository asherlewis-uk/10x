import Foundation
import Supabase

enum SupabaseServiceError: LocalizedError {
    case emptyResult(context: String)

    var errorDescription: String? {
        switch self {
        case .emptyResult(let context):
            return "Supabase returned no rows for \(context)."
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

private final class VolatileAuthLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

/// Direct Supabase client for all database CRUD operations.
/// Replaces BuilderService — no more routing through the FastAPI middleman.
actor SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: VolatileAuthLocalStorage(),
                    emitLocalSessionAsInitialSession: false
                )
            )
        )
    }

    /// Sync the user's auth session so RLS works on all queries.
    func setSession(accessToken: String, refreshToken: String?) async throws -> SupabaseSessionSnapshot {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw AuthError.sessionMissing
        }
        let session = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
        return Self.snapshot(from: session)
    }

    /// Refresh the session via the SDK's in-memory tokens.
    /// Returns fresh tokens and user info from the SDK session.
    func refreshSDKSession() async throws -> SupabaseSessionSnapshot {
        let session = try await client.auth.refreshSession()
        return Self.snapshot(from: session)
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseSessionSnapshot {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
        return Self.snapshot(from: session)
    }

    func authStateChanges() -> AsyncStream<SupabaseAuthStateUpdate> {
        let upstream = client.auth.authStateChanges

        return AsyncStream { continuation in
            let task = Task {
                for await change in upstream {
                    continuation.yield(
                        SupabaseAuthStateUpdate(
                            event: Self.mapAuthEvent(change.event),
                            session: change.session.map(Self.snapshot(from:))
                        )
                    )
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func updateCurrentUser(fullName: String?, givenName: String?, familyName: String?) async throws {
        var metadata: [String: AnyJSON] = [:]
        if let fullName, !fullName.isEmpty {
            metadata["full_name"] = .string(fullName)
        }
        if let givenName, !givenName.isEmpty {
            metadata["given_name"] = .string(givenName)
        }
        if let familyName, !familyName.isEmpty {
            metadata["family_name"] = .string(familyName)
        }

        guard !metadata.isEmpty else { return }
        _ = try await client.auth.update(user: UserAttributes(data: metadata))
    }

    // MARK: - Projects

    func fetchProjects(userId: String) async throws -> [BuilderProject] {
        try await client.from("builder_projects")
            .select()
            .eq("user_id", value: userId)
            .neq("status", value: "archived")
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func fetchArchivedProjects(userId: String) async throws -> [BuilderProject] {
        try await client.from("builder_projects")
            .select()
            .eq("user_id", value: userId)
            .eq("status", value: "archived")
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func createProject(userId: String, name: String, platform: String = "swiftui") async throws -> BuilderProject {
        let data = CreateProjectData(
            userId: userId,
            name: name,
            slug: Self.slugify(name),
            platform: platform
        )
        return try await requireFirstResult(context: "creating project `\(name)`") {
            try await client.from("builder_projects")
                .insert(data)
                .select()
                .execute()
                .value
        }
    }

    func getProject(id: String) async throws -> BuilderProject? {
        let results: [BuilderProject] = try await client.from("builder_projects")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        return results.first
    }

    func updateProject(id: String, data: UpdateProjectData) async throws -> BuilderProject {
        let results: [BuilderProject] = try await client.from("builder_projects")
            .update(data)
            .eq("id", value: id)
            .select()
            .execute()
            .value
        if let project = results.first {
            return project
        }
        if let existing = try await getProject(id: id) {
            return existing
        }
        throw SupabaseServiceError.emptyResult(context: "updating project `\(id)`")
    }

    func archiveProject(id: String) async throws -> BuilderProject {
        return try await requireFirstResult(context: "archiving project `\(id)`") {
            try await client.from("builder_projects")
                .update(["status": "archived"])
                .eq("id", value: id)
                .select()
                .execute()
                .value
        }
    }

    func unarchiveProject(id: String) async throws -> BuilderProject {
        return try await requireFirstResult(context: "unarchiving project `\(id)`") {
            try await client.from("builder_projects")
                .update(["status": "active"])
                .eq("id", value: id)
                .select()
                .execute()
                .value
        }
    }

    func deleteProject(id: String) async throws {
        try await client.from("builder_projects")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Published App Store Pages

    func getPublishedAppStorePage(projectId: String) async throws -> PublishedAppStorePage? {
        let results: [PublishedAppStorePage] = try await client.from("published_app_store_pages")
            .select()
            .eq("project_id", value: projectId)
            .limit(1)
            .execute()
            .value
        return results.first
    }

    func getPublishedAppStorePage(publicSlug: String) async throws -> PublishedAppStorePage? {
        let results: [PublishedAppStorePage] = try await client.from("published_app_store_pages")
            .select()
            .eq("public_slug", value: publicSlug)
            .limit(1)
            .execute()
            .value
        return results.first
    }

    func savePublishedAppStorePage(_ payload: PublishedAppStorePagePayload) async throws -> PublishedAppStorePage {
        if let existing = try await getPublishedAppStorePage(projectId: payload.projectId) {
            let results: [PublishedAppStorePage] = try await client.from("published_app_store_pages")
                .update(payload)
                .eq("id", value: existing.id)
                .select()
                .execute()
                .value
            return try firstResult(results, context: "updating published app store page for `\(payload.projectId)`")
        }

        let results: [PublishedAppStorePage] = try await client.from("published_app_store_pages")
            .insert(payload)
            .select()
            .execute()
            .value
        return try firstResult(results, context: "creating published app store page for `\(payload.projectId)`")
    }

    func unpublishAppStorePage(projectId: String) async throws {
        try await client.from("published_app_store_pages")
            .delete()
            .eq("project_id", value: projectId)
            .execute()
    }

    // MARK: - Versions

    func fetchVersions(projectId: String) async throws -> [BuilderVersion] {
        try await client.from("builder_versions")
            .select()
            .eq("project_id", value: projectId)
            .order("version_number", ascending: false)
            .execute()
            .value
    }

    func getVersion(projectId: String, versionId: String) async throws -> BuilderVersion? {
        let results: [BuilderVersion] = try await client.from("builder_versions")
            .select()
            .eq("id", value: versionId)
            .eq("project_id", value: projectId)
            .execute()
            .value
        return results.first
    }

    func createVersion(
        projectId: String,
        conversationId: String,
        fileTree: [String: String],
        prompt: String
    ) async throws -> BuilderVersion {
        // Get next version number
        let existing = try await fetchVersions(projectId: projectId)
        let nextNum = (existing.first?.versionNumber ?? 0) + 1

        let data = CreateVersionData(
            projectId: projectId,
            conversationId: conversationId,
            versionNumber: nextNum,
            fileTree: fileTree,
            prompt: prompt,
            status: "ready"
        )
        let version: BuilderVersion = try await requireFirstResult(
            context: "creating version for project `\(projectId)`"
        ) {
            try await client.from("builder_versions")
                .insert(data)
                .select()
                .execute()
                .value
        }

        // Update project's current_version_id
        try await client.from("builder_projects")
            .update(["current_version_id": version.id])
            .eq("id", value: projectId)
            .execute()

        return version
    }

    // MARK: - Conversations & Messages

    func fetchConversation(projectId: String) async throws -> (messages: [BuilderMessage], conversationId: String?) {
        let convos: [ConversationRow] = try await client.from("builder_conversations")
            .select()
            .eq("project_id", value: projectId)
            .execute()
            .value

        guard let convo = convos.first else { return ([], nil) }

        let messages: [BuilderMessage] = try await client.from("builder_messages")
            .select()
            .eq("conversation_id", value: convo.id)
            .order("created_at", ascending: true)
            .execute()
            .value

        return (messages, convo.id)
    }

    func addMessage(
        conversationId: String,
        role: String,
        content: String,
        versionId: String? = nil
    ) async throws -> BuilderMessage {
        let data = CreateMessageData(
            conversationId: conversationId,
            role: role,
            content: content,
            versionId: versionId
        )
        return try await requireFirstResult(context: "adding message to conversation `\(conversationId)`") {
            try await client.from("builder_messages")
                .insert(data)
                .select()
                .execute()
                .value
        }
    }

    // MARK: - Helpers

    private func requireFirstResult<T>(context: String, _ load: () async throws -> [T]) async throws -> T {
        try firstResult(try await load(), context: context)
    }

    private func firstResult<T>(_ results: [T], context: String) throws -> T {
        guard let first = results.first else {
            throw SupabaseServiceError.emptyResult(context: context)
        }
        return first
    }

    private static func snapshot(from session: Session) -> SupabaseSessionSnapshot {
        SupabaseSessionSnapshot(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userId: session.user.id.uuidString,
            userEmail: session.user.email
        )
    }

    private static func mapAuthEvent(_ event: AuthChangeEvent) -> SupabaseAuthEvent {
        switch event {
        case .initialSession:
            return .initialSession
        case .passwordRecovery:
            return .passwordRecovery
        case .signedIn:
            return .signedIn
        case .signedOut:
            return .signedOut
        case .tokenRefreshed:
            return .tokenRefreshed
        case .userUpdated:
            return .userUpdated
        case .userDeleted:
            return .userDeleted
        case .mfaChallengeVerified:
            return .mfaChallengeVerified
        }
    }

    private static func slugify(_ name: String) -> String {
        let slug = name.lowercased()
            .replacing(/[^a-z0-9]+/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let hex = (0..<3).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
        return "\(slug)-\(hex)"
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
