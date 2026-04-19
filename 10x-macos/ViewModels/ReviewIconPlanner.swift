import CryptoKit
import Foundation

enum ReviewIconPlanner {
    struct Draft: Codable, Sendable {
        let concept: String?
        let backgroundColors: [String]?
        let accentColor: String?
        let symbolName: String?
        let monogram: String?
    }

    struct Response: Codable, Sendable {
        let creativeDirection: String?
        let icon: Draft?
    }

    struct Plan: Sendable {
        let creativeDirection: String?
        let normalizedIcon: Draft?
        let rawIcon: Draft?
    }

    static let model = "claude-opus-4-7"

    static let systemPrompt = """
    You are an expert iOS App Store icon creative director. Return ONLY a single JSON object.

    Required JSON shape:
    {
      "creativeDirection": "string",
      "icon": {
        "concept": "string",
        "backgroundColors": ["#RRGGBB", "#RRGGBB"],
        "accentColor": "#RRGGBB",
        "symbolName": "string or null",
        "monogram": "string or null"
      } or null
    }

    Rules:
    - Plan only the icon. Ignore screenshots and description.
    - Use 1 or 2 background colors by default, all valid #RRGGBB hex values.
    - Use a cohesive, premium, slightly muted palette with flat color treatment unless the user's brief explicitly asks otherwise.
    - Allowed symbolName values: \(allowedSymbols.joined(separator: ", ")).
    - Prefer a distinct product-specific mark over a generic letter badge or placeholder symbol.
    - Use a monogram only when it is genuinely stronger than a product-specific mark.
    - Keep the concept bold, simple, premium, and legible at small sizes.
    - Avoid literal stock category metaphors, generic badges, and ornamental marks.
    - Unless the user's brief explicitly asks otherwise, avoid gradients, gloss, bevels, shadows, and 3D depth.
    - Do not wrap the JSON in markdown fences.
    """

    static func promptText(
        project: BuilderProject,
        projectPlan: String?,
        brief: String?,
        sourceCaptures: [PreviewScreenCapture],
        existingState: AppStoreReviewState
    ) -> String {
        [
            "Project name: \(project.name)",
            section("Project description", project.description),
            section("Project plan", projectPlan),
            section("Creative brief", brief),
            sourceCaptures.isEmpty ? nil : "Available preview screens: \(sourceCaptures.map(\.displayName).joined(separator: ", "))",
            sourceCaptures.isEmpty ? nil : "Use the attached preview screens as visual grounding for the icon metaphor and palette.",
            existingStateJSON(existingState, limit: 3500).map { "Existing review state:\n\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    static func parsePlanResponse(
        _ text: String,
        project: BuilderProject,
        projectPlan: String?,
        brief: String?
    ) throws -> Plan {
        let response = try decodedResponse(from: text)
        return Plan(
            creativeDirection: sanitizedLine(response.creativeDirection, maxLength: 220),
            normalizedIcon: normalizedIcon(
                response.icon,
                project: project,
                projectPlan: projectPlan,
                brief: brief
            ),
            rawIcon: response.icon
        )
    }

    static func imagePrompt(
        project: BuilderProject,
        projectPlan: String?,
        brief: String?,
        plan: Plan?
    ) -> String {
        let projectName = sanitizedLine(project.name, maxLength: 120) ?? "Untitled"
        let projectDescription = sanitizedLine(project.description, maxLength: 260)
        let planSummary = sanitizedLine(projectPlan, maxLength: 320)
        let creativeBrief = sanitizedLine(brief, maxLength: 220)
        let concept = sanitizedLine(plan?.normalizedIcon?.concept, maxLength: 120)
            ?? sanitizedLine(plan?.rawIcon?.concept, maxLength: 120)
            ?? subjectHint(
                symbolName: plan?.normalizedIcon?.symbolName ?? plan?.rawIcon?.symbolName,
                monogram: plan?.normalizedIcon?.monogram ?? plan?.rawIcon?.monogram,
                projectDescription: projectDescription ?? creativeBrief ?? planSummary
            )
        let palette = normalizedColors(
            plan?.normalizedIcon?.backgroundColors ?? plan?.rawIcon?.backgroundColors,
            fallback: palette(project: project, brief: brief)
        ).joined(separator: ", ")
        let monogram = sanitizedLine(plan?.normalizedIcon?.monogram ?? plan?.rawIcon?.monogram, maxLength: 2)
        let creativeDirection = sanitizedLine(plan?.creativeDirection, maxLength: 180)

        var lines = imagePromptBaseLines(projectName: projectName)
        lines += [
            projectDescription.map { "Product description: \($0)" },
            planSummary.map { "Product plan: \($0)" },
            creativeBrief.map { "Creative brief: \($0)" },
            creativeDirection.map { "Creative direction: \($0)" },
            "Preferred icon concept: \(concept)",
            palette.isEmpty ? nil : "Anchor the icon in this palette family: \(palette). Unless the user's brief explicitly asks otherwise, use only 1-2 of these colors in the final icon.",
            monogram.map { "A minimal monogram \"\($0)\" is allowed only if it clearly outperforms a product metaphor or illustrated mark." },
            "Do not use any letters unless they are clearly necessary and materially stronger than a non-letter mark.",
            "Prioritize an icon that would still feel recognizable and premium at App Store search-result size.",
            "If choosing between clever detail and a cleaner silhouette, choose the cleaner silhouette.",
            "Unless the user's brief explicitly asks otherwise, keep the icon flat and limited to 1-2 colors.",
            "Unless the user's brief explicitly asks otherwise, avoid gradients, gloss, bevels, shadows, and any 3D rendering.",
            "The result should look like a top-tier App Store icon someone would actually ship.",
        ]

        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    private static let allowedSymbols = [
        "sparkles",
        "bolt.fill",
        "chart.line.uptrend.xyaxis",
        "heart.fill",
        "checkmark.circle.fill",
        "wand.and.stars.inverse",
        "brain.head.profile",
        "play.fill",
        "square.grid.2x2.fill",
        "message.fill",
        "camera.fill",
        "map.fill",
    ]

    private static let iconPalettes = [
        ["#F7F9FC", "#E7EEF8", "#5C7FBD"],
        ["#F8F6F2", "#EEE4D8", "#B47A52"],
        ["#F3F7F6", "#DCE7E3", "#5E847C"],
        ["#F6F7F9", "#E1E7EE", "#556A82"],
        ["#FBF8F2", "#F1E6D6", "#9C745C"],
    ]

    private static let symbolHints = [
        "sparkles": "a crisp radiant starburst or refined spark motif",
        "bolt.fill": "a sharp energetic lightning mark",
        "chart.line.uptrend.xyaxis": "an upward motion mark with momentum",
        "heart.fill": "a bold heart-inspired mark with strong geometry",
        "checkmark.circle.fill": "a confident completion or approval mark",
        "wand.and.stars.inverse": "a refined transformation mark",
        "brain.head.profile": "an intelligence-inspired symbol with clean silhouette",
        "play.fill": "a bold play-shaped motion mark",
        "square.grid.2x2.fill": "a modular grid-inspired mark",
        "message.fill": "a speech or conversation-inspired mark",
        "camera.fill": "a camera-inspired mark",
        "map.fill": "a location or navigation-inspired mark",
    ]

    private static func decodedResponse(from text: String) throws -> Response {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Response.self, from: data) {
            return decoded
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            throw APIError.invalidResponse
        }

        let candidate = String(trimmed[start...end])
        guard let data = candidate.data(using: .utf8) else {
            throw APIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private static func normalizedIcon(
        _ raw: Draft?,
        project: BuilderProject,
        projectPlan: String?,
        brief: String?
    ) -> Draft? {
        guard let raw else {
            return nil
        }

        let fallbackPalette = palette(project: project, brief: brief)
        let backgroundColors = normalizedColors(raw.backgroundColors, fallback: fallbackPalette)
        let accentColor = normalizedHex(raw.accentColor) ?? backgroundColors.last
        let concept = sanitizedLine(raw.concept, maxLength: 120)
        var symbolName = sanitizedLine(raw.symbolName, maxLength: 32)
        if let resolvedSymbolName = symbolName, !allowedSymbols.contains(resolvedSymbolName) {
            symbolName = nil
        }
        var monogram = sanitizedLine(raw.monogram, maxLength: 2)
        if let resolvedMonogram = monogram {
            monogram = String(resolvedMonogram.prefix(2)).uppercased()
            symbolName = nil
        }

        if concept == nil, symbolName == nil, monogram == nil {
            let fallback = subjectHint(
                symbolName: nil,
                monogram: nil,
                projectDescription: sanitizedLine(project.description, maxLength: 260)
                    ?? sanitizedLine(brief, maxLength: 220)
                    ?? sanitizedLine(projectPlan, maxLength: 320)
            )
            return Draft(
                concept: fallback,
                backgroundColors: backgroundColors,
                accentColor: accentColor,
                symbolName: nil,
                monogram: nil
            )
        }

        return Draft(
            concept: concept,
            backgroundColors: backgroundColors,
            accentColor: accentColor,
            symbolName: symbolName,
            monogram: monogram
        )
    }

    private static func palette(project: BuilderProject, brief: String?) -> [String] {
        let seed = [project.name, project.description, brief]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let digest = Insecure.SHA1.hash(data: Data((seed.isEmpty ? "10x" : seed).utf8))
        let bucket = Int(Array(digest).first ?? 0)
        return iconPalettes[bucket % iconPalettes.count]
    }

    private static func normalizedColors(_ values: [String]?, fallback: [String]) -> [String] {
        guard let values else {
            return fallback
        }
        let resolved = values.compactMap(normalizedHex)
        return resolved.count >= 2 ? Array(resolved.prefix(3)) : fallback
    }

    private static func normalizedHex(_ value: String?) -> String? {
        guard var normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        if !normalized.hasPrefix("#") {
            normalized = "#\(normalized)"
        }
        let pattern = "^#[0-9A-Fa-f]{6}$"
        guard normalized.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return normalized.uppercased()
    }

    private static func subjectHint(
        symbolName: String?,
        monogram: String?,
        projectDescription: String?
    ) -> String {
        if let symbolName,
           let symbolHint = symbolHints[symbolName] {
            return symbolHint
        }
        if let monogram = sanitizedLine(monogram, maxLength: 2) {
            return "a memorable monogram built from the letters \(monogram)"
        }
        if let projectDescription {
            return "a distinct icon metaphor based on this product: \(projectDescription)"
        }
        return "a memorable, distinct product mark with strong silhouette"
    }

    private static func existingStateJSON(_ state: AppStoreReviewState, limit: Int) -> String? {
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return String(json.prefix(limit))
    }

    private static func sanitizedLine(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        var cleaned = value
            .replacingOccurrences(of: "•", with: " ")
            .replacingOccurrences(of: "#", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r-–—•"))
        cleaned = cleaned.replacingOccurrences(of: #"[!?]{2,}"#, with: "!", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\.{2,}"#, with: ".", options: .regularExpression)
        if cleaned.count > maxLength {
            cleaned = String(cleaned.prefix(maxLength))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!-"))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func section(_ title: String, _ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return "\(title):\n\(value)"
    }

    private static func imagePromptBaseLines(projectName: String) -> [String?] {
        [
            "Create a premium iOS App Store icon for \"\(projectName)\".",
            "Produce a real shipped-quality app icon illustration, not a placeholder SF Symbol on a gradient.",
            "Output a single finished square icon only. No mockup, no phone frame, no surrounding background, no watermark, no emoji.",
            "Make the artwork full-bleed across the entire square canvas.",
            "The background color or texture must extend flush to all four edges and corners of the image.",
            "Do not place the icon inside an inset rounded-square badge, button, card, tile, sticker, or app-icon-on-a-background presentation.",
            "Do not pre-round the icon into a smaller rounded-square object inside the canvas.",
            "Do not leave any outer white margin, black matte, studio backdrop, frame, or border around the icon artwork.",
            "Apple applies masking later, so deliver full square artwork that reaches the edges.",
            "The icon should feel distinctive, premium, modern, and highly legible at small sizes.",
            "Design an ownable product mark, not a generic SaaS badge.",
            "Use one strong central idea with clean geometry, deliberate silhouette, flat shapes, and polished color control.",
            "The foreground and background should feel integrated into one finished mark, not a white glyph pasted on a flat gradient.",
            "Prefer the cleanest, simplest strong silhouette over a more illustrative or multi-part composition.",
            "Use negative space when it helps the mark feel more iconic and ownable.",
            "Avoid embedded scenes, books, UI elements, mascots, tiny detail, noisy texture, random glow, gimmicky gradients, stock 3D blobs, and default monogram badges.",
            "Avoid the most literal stock category metaphor in its default form. If the first idea is just an arrow, chart, dumbbell, or chat bubble, push it into a more distinctive branded silhouette or choose a better metaphor.",
        ]
    }
}
