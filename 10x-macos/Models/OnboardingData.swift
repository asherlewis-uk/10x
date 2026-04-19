import Foundation

/// Captures user preferences from the app creation onboarding flow.
public struct OnboardingData: Codable {
    public var designStyle: DesignStyle?
    public var targetAudience: [TargetAudience] = []
    public var additionalDetails: String = ""
    public var colorOverrides: [String: String] = [:]  // e.g. "primary" -> "#FF0000"

    public init(
        designStyle: DesignStyle? = nil,
        targetAudience: [TargetAudience] = [],
        additionalDetails: String = "",
        colorOverrides: [String: String] = [:]
    ) {
        self.designStyle = designStyle
        self.targetAudience = targetAudience
        self.additionalDetails = additionalDetails
        self.colorOverrides = colorOverrides
    }

    /// Build a context string to append to the user's initial prompt.
    public func contextString() -> String? {
        var parts: [String] = []

        if let style = designStyle {
            parts.append("Design style: \(style.label) (\(style.subtitle)) — e.g. \(style.examples.joined(separator: ", "))")
        }

        // Color palette
        if !colorOverrides.isEmpty {
            let colorParts = colorOverrides.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
            parts.append("Color palette: \(colorParts)")
        }

        if !targetAudience.isEmpty {
            parts.append("Target audience: \(targetAudience.map(\.label).joined(separator: ", "))")
        }

        if !additionalDetails.isEmpty {
            parts.append("Additional details: \(additionalDetails)")
        }

        guard !parts.isEmpty else { return nil }
        return "\n\n---\nUser preferences from onboarding:\n" + parts.joined(separator: "\n")
    }
}

// MARK: - App Features

enum AppFeature: String, CaseIterable, Identifiable {
    case socialFeed
    case itemDiscovery
    case uploadTrack
    case messaging
    case mapsLocation
    case marketplace
    case profiles
    case camera
    case dashboard
    case settings
    case onboarding
    case lists

    var id: String { rawValue }

    var label: String {
        switch self {
        case .socialFeed: "Social Feed"
        case .itemDiscovery: "Item Discovery"
        case .uploadTrack: "Upload & Track"
        case .messaging: "Messaging"
        case .mapsLocation: "Maps & Location"
        case .marketplace: "Marketplace"
        case .profiles: "User Profiles"
        case .camera: "Camera & Photos"
        case .dashboard: "Dashboard & Stats"
        case .settings: "Settings"
        case .onboarding: "Onboarding Flow"
        case .lists: "Lists & Collections"
        }
    }

    var subtitle: String {
        switch self {
        case .socialFeed: "Scrollable content feed with likes & comments"
        case .itemDiscovery: "Browse, search, and filter items"
        case .uploadTrack: "Log entries, track progress over time"
        case .messaging: "Chat, DMs, real-time conversations"
        case .mapsLocation: "Map views, pins, nearby discovery"
        case .marketplace: "Buy, sell, or list items with pricing"
        case .profiles: "User accounts, avatars, bios"
        case .camera: "Capture, upload, edit photos"
        case .dashboard: "Charts, metrics, summaries"
        case .settings: "Preferences, toggles, account"
        case .onboarding: "Welcome screens, sign-up flow"
        case .lists: "Saved items, bookmarks, collections"
        }
    }

    var examples: [String] {
        switch self {
        case .socialFeed: ["Instagram", "TikTok", "Strava"]
        case .itemDiscovery: ["DoorDash", "Airbnb", "Yelp"]
        case .uploadTrack: ["Cal AI", "MyFitnessPal", "Streaks"]
        case .messaging: ["iMessage", "WhatsApp", "Slack"]
        case .mapsLocation: ["Uber", "Google Maps", "AllTrails"]
        case .marketplace: ["Depop", "OfferUp", "StockX"]
        case .profiles: ["LinkedIn", "Twitter", "Hinge"]
        case .camera: ["Snapchat", "VSCO", "BeReal"]
        case .dashboard: ["Fitbit", "Robinhood", "Screen Time"]
        case .settings: ["iOS Settings", "Spotify", "Notion"]
        case .onboarding: ["Duolingo", "Headspace", "Opal"]
        case .lists: ["Pinterest", "Pocket", "Goodreads"]
        }
    }

    var iconName: String {
        switch self {
        case .socialFeed: "rectangle.stack.fill"
        case .itemDiscovery: "magnifyingglass"
        case .uploadTrack: "chart.line.uptrend.xyaxis"
        case .messaging: "bubble.left.and.bubble.right.fill"
        case .mapsLocation: "map.fill"
        case .marketplace: "cart.fill"
        case .profiles: "person.crop.circle.fill"
        case .camera: "camera.fill"
        case .dashboard: "chart.bar.fill"
        case .settings: "gearshape.fill"
        case .onboarding: "hand.wave.fill"
        case .lists: "list.star"
        }
    }

}

// MARK: - Design Styles (trimmed to 6)

public enum DesignStyle: String, CaseIterable, Identifiable, Codable {
    case playful
    case clean
    case glassy
    case bold
    case dark
    case soft
    case minimal
    case neon
    case brutalist

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .playful: "Playful"
        case .clean: "Clean"
        case .glassy: "Glassy"
        case .bold: "Bold"
        case .dark: "Dark"
        case .soft: "Soft"
        case .minimal: "Minimal"
        case .neon: "Neon"
        case .brutalist: "Brutalist"
        }
    }

    public var subtitle: String {
        switch self {
        case .playful: "Bright colors, rounded shapes, fun energy"
        case .clean: "Whitespace, simple typography, restrained color"
        case .glassy: "Translucent layers, frosted glass, depth"
        case .bold: "Image-heavy, vibrant, strong grid layouts"
        case .dark: "Dark backgrounds, sharp type, content-forward"
        case .soft: "Rounded shapes, warm tones, gentle feel"
        case .minimal: "Extreme simplicity, monochrome, lots of space"
        case .neon: "Dark canvas with vivid glowing accents"
        case .brutalist: "Raw, blocky, high contrast, no decoration"
        }
    }

    public var examples: [String] {
        switch self {
        case .playful: ["Duolingo", "Streaks", "Goblin Tools"]
        case .clean: ["Uber", "Notion", "Things 3"]
        case .glassy: ["Opal", "Apple Weather", "Arc"]
        case .bold: ["Pinterest", "VSCO", "Depop"]
        case .dark: ["Spotify", "Letterboxd", "Apollo"]
        case .soft: ["Headspace", "Balance", "Gentler Streak"]
        case .minimal: ["iA Writer", "Bear", "Calm"]
        case .neon: ["Halide", "NightCafe", "Widgetsmith"]
        case .brutalist: ["Bloomberg", "Craigslist", "The Verge"]
        }
    }

    public var iconName: String {
        switch self {
        case .playful: "sparkles"
        case .clean: "square.split.2x1.fill"
        case .glassy: "drop.fill"
        case .bold: "photo.fill"
        case .dark: "moon.stars.fill"
        case .soft: "leaf.fill"
        case .minimal: "minus"
        case .neon: "bolt.fill"
        case .brutalist: "square.fill"
        }
    }
}

// MARK: - Target Audience

// MARK: - Onboarding Draft (persisted when user exits onboarding early)

struct OnboardingDraft: Codable {
    let appDescription: String
    let data: OnboardingData
}

// MARK: - Target Audience

public enum TargetAudience: String, CaseIterable, Identifiable, Codable {
    case everyone, teens, professionals, students, parents, seniors, creators, developers

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .everyone: "Everyone"
        case .teens: "Teens & Young Adults"
        case .professionals: "Professionals"
        case .students: "Students"
        case .parents: "Parents & Families"
        case .seniors: "Seniors"
        case .creators: "Creators"
        case .developers: "Developers"
        }
    }

    public var iconName: String {
        switch self {
        case .everyone: "globe"
        case .teens: "sparkles"
        case .professionals: "briefcase.fill"
        case .students: "graduationcap.fill"
        case .parents: "figure.2.and.child.holdinghands"
        case .seniors: "figure.stand"
        case .creators: "paintbrush.fill"
        case .developers: "chevron.left.forwardslash.chevron.right"
        }
    }
}
