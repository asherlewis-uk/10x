import Foundation

/// Manages agent skills bundled inside 10x-macos, with the 10x API used as a
/// fallback for older skills that are not yet shipped locally.
actor SkillsManager {
    private let api = APIClient()

    /// Cached skill registry (name + description). Populated on first fetch.
    private var cachedRegistry: [SkillRegistryEntry] = []
    private var registryLoaded = false

    // MARK: - Registry (lightweight, cached)

    /// Fetch the skill registry from the API (or return cached).
    func fetchRegistry(accessToken: String) async -> [SkillRegistryEntry] {
        if !registryLoaded {
            do {
                let response: SkillsListResponse = try await api.get(
                    APIClient.builderSkills(),
                    accessToken: accessToken
                )
                cachedRegistry = response.skills
                registryLoaded = true
            } catch {
                print("[skills] Failed to fetch remote registry: \(error.localizedDescription)")
            }
        }
        return Self.mergedRegistry(
            bundled: BundledSkillsCatalog.registry,
            remote: cachedRegistry
        )
    }

    func catalogSection(accessToken: String) async -> String? {
        let registry = await fetchRegistry(accessToken: accessToken)
        guard !registry.isEmpty else { return nil }

        return """
        ## Skills Catalog
        Use exact skill names from this catalog when a request clearly matches one of these domains.

        \(registry.map { Self.renderedRegistryEntry($0, tagLimit: 4, compact: true) }.joined(separator: "\n"))
        """
    }

    /// Invalidate the cached registry so the next fetch hits the API.
    func invalidateCache() {
        cachedRegistry = []
        registryLoaded = false
    }

    // MARK: - Tool Handlers

    /// List all available skills. Returns formatted text for Claude.
    func listSkills(accessToken: String) async -> String {
        let registry = await fetchRegistry(accessToken: accessToken)
        if registry.isEmpty {
            return "No skills available."
        }
        let lines = registry.map { Self.renderedRegistryEntry($0, tagLimit: 4, compact: false) }

        return """
        Available skills:
        Review this catalog, then call `use_skill` for each clearly relevant specialized domain before planning or implementation.

        \(lines.joined(separator: "\n"))
        """
    }

    /// Load full skill content by name. Returns formatted text for Claude.
    func useSkill(name: String, accessToken: String) async -> String {
        do {
            let response = try await fetchSkill(name: name, accessToken: accessToken)
            return """
            # Skill: \(response.name)
            \(response.description)

            \(response.content)
            """
        } catch {
            let registry = await fetchRegistry(accessToken: accessToken)
            let available = registry.map(\.name).joined(separator: ", ")
            return "Skill '\(name)' not found. Available skills: \(available.isEmpty ? "(none)" : available)"
        }
    }

    private func fetchSkill(name: String, accessToken: String) async throws -> SkillContentResponse {
        if let localSkill = BundledSkillsCatalog.skill(named: name) {
            return localSkill
        }
        let response: SkillContentResponse = try await api.get(
            APIClient.builderSkills(name),
            accessToken: accessToken
        )
        return response
    }

    private nonisolated static func renderedRegistryEntry(
        _ entry: SkillRegistryEntry,
        tagLimit: Int,
        compact: Bool
    ) -> String {
        let tags = entry.tags
            .prefix(tagLimit)
            .map { "`\($0)`" }
            .joined(separator: ", ")

        if compact {
            if tags.isEmpty {
                return "- `\(entry.name)` — \(entry.displayTitle)"
            }
            return "- `\(entry.name)` — \(entry.displayTitle): \(tags)"
        }

        if tags.isEmpty {
            return "- **\(entry.displayTitle)** (`\(entry.name)`): \(entry.userFacingDescription)"
        }

        return "- **\(entry.displayTitle)** (`\(entry.name)`): \(entry.userFacingDescription) Tags: \(tags)"
    }

    private static func mergedRegistry(
        bundled: [SkillRegistryEntry],
        remote: [SkillRegistryEntry]
    ) -> [SkillRegistryEntry] {
        var mergedByName: [String: SkillRegistryEntry] = [:]

        for entry in remote {
            mergedByName[entry.name.lowercased()] = entry
        }

        for entry in bundled {
            // Bundled skills win so product-critical guidance stays local-first.
            mergedByName[entry.name.lowercased()] = entry
        }

        return mergedByName.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - Response Models

nonisolated struct SkillRegistryEntry: Codable, Sendable {
    let name: String
    let description: String
    let tags: [String]
}

nonisolated struct SkillsListResponse: Codable, Sendable {
    let skills: [SkillRegistryEntry]
}

nonisolated struct SkillContentResponse: Codable, Sendable {
    let name: String
    let description: String
    let tags: [String]
    let content: String
}

enum SkillPresentation {
    nonisolated static func title(for name: String) -> String {
        switch normalized(name) {
        case "3d-effects":
            return "3D & Spatial"
        case "algorithms":
            return "Algorithms"
        case "animations":
            return "Motion Design"
        case "audio":
            return "Audio & Voice"
        case "camera-and-media":
            return "Camera & Media"
        case "image-editing":
            return "Image Editing"
        case "maps-and-location":
            return "Maps & Location"
        case "ml-and-vision":
            return "Vision & Tracking"
        case "project-start":
            return "Project Setup"
        case "ui-design":
            return "UI Polish"
        case "onboarding":
            return "Onboarding Flow"
        case "ai-models":
            return "AI Features"
        case "backend":
            return "Backend"
        case "supabase":
            return "Supabase"
        case "superwall":
            return "Superwall"
        case "app-store-assets":
            return "App Store Assets"
        case "monetization":
            return "Monetization"
        default:
            return humanized(name)
        }
    }

    nonisolated static func description(for name: String) -> String {
        switch normalized(name) {
        case "3d-effects":
            return "Build product viewers, AR previews, scanned objects, and other true 3D or spatial interactions."
        case "algorithms":
            return "Design ranked feeds, recommendation systems, matching logic, and TikTok-style personalization loops."
        case "animations":
            return "Create polished motion, springy transitions, sequenced reveals, and more physical-feeling UI."
        case "audio":
            return "Handle playback, voice recording, waveforms, audio analysis, and sound-driven interactions."
        case "camera-and-media":
            return "Capture photos or video, build custom camera flows, and process visual media inside the app."
        case "image-editing":
            return "Build photo editors, filter stacks, crop and rotate flows, masks, overlays, and export pipelines."
        case "maps-and-location":
            return "Show maps, follow the user's location, draw routes, and build place-aware experiences."
        case "ml-and-vision":
            return "Add pose tracking, hand tracking, video analysis, object recognition, or on-device Vision and Core ML features."
        case "project-start":
            return "Shape the concept, define the MVP, and get the app structure pointed in the right direction."
        case "ui-design":
            return "Improve layout, hierarchy, spacing, components, and overall visual quality."
        case "onboarding":
            return "Design the first-run experience, welcome screens, sign-up, and guided setup."
        case "ai-models":
            return "Add model-powered features, choose the right AI behavior, and design the response UX."
        case "backend":
            return "Plan and operate the managed Supabase backend path with named functions, backend secrets, deploy approvals, and no-proxy rules."
        case "supabase":
            return "Wire up Supabase auth, database access, RLS-aware client flows, and provider configuration with iOS-safe patterns."
        case "superwall":
            return "Wire up Superwall account linking, paywall placements, dashboard bootstrap, test-mode setup, and subscription-aware iOS runtime flows."
        case "app-store-assets":
            return "Generate premium App Store icons, screenshots, and listing copy with cohesive art direction, stronger color taste, and captured app views."
        case "monetization":
            return "Plan subscriptions, pricing, paywalls, and upgrade moments that fit the product."
        default:
            return "Guide the build around \(title(for: name).lowercased()) decisions and implementation details."
        }
    }

    nonisolated static func iconName(for name: String) -> String {
        switch normalized(name) {
        case "3d-effects":
            return "cube.transparent"
        case "algorithms":
            return "point.3.connected.trianglepath.dotted"
        case "animations":
            return "sparkles"
        case "audio":
            return "waveform"
        case "camera-and-media":
            return "camera"
        case "image-editing":
            return "wand.and.stars"
        case "maps-and-location":
            return "map"
        case "ml-and-vision":
            return "viewfinder"
        case "project-start":
            return "flag.2.crossed"
        case "ui-design":
            return "paintpalette"
        case "onboarding":
            return "hand.wave"
        case "ai-models":
            return "brain.head.profile"
        case "backend":
            return "server.rack"
        case "supabase":
            return "cylinder.split.1x2"
        case "superwall":
            return "rectangle.portrait.on.rectangle.portrait.angled"
        case "app-store-assets":
            return "sparkles.rectangle.stack"
        case "monetization":
            return "creditcard"
        default:
            return "sparkles"
        }
    }

    private nonisolated static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private nonisolated static func humanized(_ name: String) -> String {
        normalized(name)
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

extension SkillRegistryEntry {
    nonisolated var displayTitle: String { SkillPresentation.title(for: name) }
    nonisolated var userFacingDescription: String { SkillPresentation.description(for: name) }
    nonisolated var iconName: String { SkillPresentation.iconName(for: name) }
}
