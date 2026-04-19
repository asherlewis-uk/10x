import Foundation

enum AppStoreReviewAssetKind: String, Codable, CaseIterable, Sendable {
    case icon
    case description
    case screenshots

    var label: String {
        switch self {
        case .icon:
            return "Icon"
        case .description:
            return "Description"
        case .screenshots:
            return "Screenshots"
        }
    }
}

enum AppStoreReviewTextPlacement: String, Codable, Sendable {
    case top
    case bottom
}

enum AppStoreReviewTextAlignment: String, Codable, Sendable {
    case leading
    case center
    case trailing
}

enum AppStoreReviewHeadlineWeight: String, Codable, Sendable {
    case regular
    case medium
    case semibold
    case bold
    case black
}

enum AppStoreReviewFontFamily: String, Codable, Sendable {
    case system
    case rounded
    case serif
    case condensed
    case monospaced
}

struct OpenAIImageProxyRequest: Codable, Sendable {
    let prompt: String
    let model: String?
    let size: String
    let quality: String
    let background: String
    let outputFormat: String
    let n: Int
    let projectId: String?
    let sessionId: String?
    let idempotencyKey: String?
    let billingGroupId: String?
    let billingMessagePreview: String?
}

enum AppStoreReviewScreenshotAction: String, Codable, Sendable {
    case remove
    case move
}

struct AppStoreReviewToolInput: Sendable {
    let assets: [String]
    let brief: String?
    let sourceViewNames: [String]
    let applyIconToProject: Bool
    let screenshotAction: AppStoreReviewScreenshotAction?
    let screenshotPosition: Int?
    let moveToPosition: Int?

    nonisolated init(
        assets: [String] = [],
        brief: String? = nil,
        sourceViewNames: [String] = [],
        applyIconToProject: Bool = true,
        screenshotAction: AppStoreReviewScreenshotAction? = nil,
        screenshotPosition: Int? = nil,
        moveToPosition: Int? = nil
    ) {
        self.assets = assets
        self.brief = brief
        self.sourceViewNames = sourceViewNames
        self.applyIconToProject = applyIconToProject
        self.screenshotAction = screenshotAction
        self.screenshotPosition = screenshotPosition
        self.moveToPosition = moveToPosition
    }
}

struct AppStoreReviewDescriptionSpec: Codable, Equatable, Sendable {
    let headline: String
    let subtitle: String
    let shortBlurb: String
    let fullDescription: String
    let featureBullets: [String]
}

struct AppStoreReviewScreenshotSpec: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let sourceCaptureID: String?
    let sourceViewName: String
    let headline: String
    let subheadline: String
    let backgroundColors: [String]
    let accentColor: String?
    let deviceScale: Double
    let rotationDegrees: Double
    let textPlacement: AppStoreReviewTextPlacement
    let textAlignment: AppStoreReviewTextAlignment
    let headlineFontFamily: AppStoreReviewFontFamily
    let headlineWeight: AppStoreReviewHeadlineWeight
    let headlineItalic: Bool
    let headlineAllCaps: Bool
    let headlineScale: Double
    let headlineTracking: Double
    let headlineWidthRatio: Double
    let subheadlineFontFamily: AppStoreReviewFontFamily
    let subheadlineWeight: AppStoreReviewHeadlineWeight
    let subheadlineItalic: Bool
    let subheadlineScale: Double
    let textToDeviceSpacing: Double
    let screenZoom: Double
    let screenFocusX: Double
    let screenFocusY: Double

    init(
        id: String = UUID().uuidString,
        sourceCaptureID: String? = nil,
        sourceViewName: String,
        headline: String,
        subheadline: String,
        backgroundColors: [String],
        accentColor: String? = nil,
        deviceScale: Double,
        rotationDegrees: Double,
        textPlacement: AppStoreReviewTextPlacement,
        textAlignment: AppStoreReviewTextAlignment,
        headlineFontFamily: AppStoreReviewFontFamily = .system,
        headlineWeight: AppStoreReviewHeadlineWeight = .bold,
        headlineItalic: Bool = false,
        headlineAllCaps: Bool = false,
        headlineScale: Double = 1.0,
        headlineTracking: Double = -1.0,
        headlineWidthRatio: Double = 0.92,
        subheadlineFontFamily: AppStoreReviewFontFamily = .system,
        subheadlineWeight: AppStoreReviewHeadlineWeight = .medium,
        subheadlineItalic: Bool = false,
        subheadlineScale: Double = 1.0,
        textToDeviceSpacing: Double = 88,
        screenZoom: Double = 1.0,
        screenFocusX: Double = 0.5,
        screenFocusY: Double = 0.5
    ) {
        self.id = id
        self.sourceCaptureID = sourceCaptureID
        self.sourceViewName = sourceViewName
        self.headline = headline
        self.subheadline = subheadline
        self.backgroundColors = backgroundColors
        self.accentColor = accentColor
        self.deviceScale = deviceScale
        self.rotationDegrees = rotationDegrees
        self.textPlacement = textPlacement
        self.textAlignment = textAlignment
        self.headlineFontFamily = headlineFontFamily
        self.headlineWeight = headlineWeight
        self.headlineItalic = headlineItalic
        self.headlineAllCaps = headlineAllCaps
        self.headlineScale = headlineScale
        self.headlineTracking = headlineTracking
        self.headlineWidthRatio = headlineWidthRatio
        self.subheadlineFontFamily = subheadlineFontFamily
        self.subheadlineWeight = subheadlineWeight
        self.subheadlineItalic = subheadlineItalic
        self.subheadlineScale = subheadlineScale
        self.textToDeviceSpacing = textToDeviceSpacing
        self.screenZoom = screenZoom
        self.screenFocusX = screenFocusX
        self.screenFocusY = screenFocusY
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceCaptureID
        case sourceViewName
        case headline
        case subheadline
        case backgroundColors
        case accentColor
        case deviceScale
        case rotationDegrees
        case textPlacement
        case textAlignment
        case headlineFontFamily
        case headlineWeight
        case headlineItalic
        case headlineAllCaps
        case headlineScale
        case headlineTracking
        case headlineWidthRatio
        case subheadlineFontFamily
        case subheadlineWeight
        case subheadlineItalic
        case subheadlineScale
        case textToDeviceSpacing
        case screenZoom
        case screenFocusX
        case screenFocusY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sourceCaptureID = try container.decodeIfPresent(String.self, forKey: .sourceCaptureID)
        sourceViewName = try container.decode(String.self, forKey: .sourceViewName)
        headline = try container.decode(String.self, forKey: .headline)
        subheadline = try container.decodeIfPresent(String.self, forKey: .subheadline) ?? ""
        backgroundColors = try container.decode([String].self, forKey: .backgroundColors)
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor)
        deviceScale = try container.decode(Double.self, forKey: .deviceScale)
        rotationDegrees = try container.decode(Double.self, forKey: .rotationDegrees)
        textPlacement = try container.decodeIfPresent(AppStoreReviewTextPlacement.self, forKey: .textPlacement) ?? .top
        textAlignment = try container.decodeIfPresent(AppStoreReviewTextAlignment.self, forKey: .textAlignment) ?? .leading
        headlineFontFamily = try container.decodeIfPresent(AppStoreReviewFontFamily.self, forKey: .headlineFontFamily) ?? .system
        headlineWeight = try container.decodeIfPresent(AppStoreReviewHeadlineWeight.self, forKey: .headlineWeight) ?? .bold
        headlineItalic = try container.decodeIfPresent(Bool.self, forKey: .headlineItalic) ?? false
        headlineAllCaps = try container.decodeIfPresent(Bool.self, forKey: .headlineAllCaps) ?? false
        headlineScale = try container.decodeIfPresent(Double.self, forKey: .headlineScale) ?? 1.0
        headlineTracking = try container.decodeIfPresent(Double.self, forKey: .headlineTracking) ?? -1.0
        headlineWidthRatio = try container.decodeIfPresent(Double.self, forKey: .headlineWidthRatio) ?? 0.92
        subheadlineFontFamily = try container.decodeIfPresent(AppStoreReviewFontFamily.self, forKey: .subheadlineFontFamily) ?? headlineFontFamily
        subheadlineWeight = try container.decodeIfPresent(AppStoreReviewHeadlineWeight.self, forKey: .subheadlineWeight) ?? .medium
        subheadlineItalic = try container.decodeIfPresent(Bool.self, forKey: .subheadlineItalic) ?? false
        subheadlineScale = try container.decodeIfPresent(Double.self, forKey: .subheadlineScale) ?? 1.0
        textToDeviceSpacing = try container.decodeIfPresent(Double.self, forKey: .textToDeviceSpacing) ?? 88
        screenZoom = try container.decodeIfPresent(Double.self, forKey: .screenZoom) ?? 1.0
        screenFocusX = try container.decodeIfPresent(Double.self, forKey: .screenFocusX) ?? 0.5
        screenFocusY = try container.decodeIfPresent(Double.self, forKey: .screenFocusY) ?? 0.5
    }
}

struct ReviewAgentScreenshotDraft: Codable, Sendable {
    let id: String?
    let sourceCaptureID: String
    let sourceViewName: String
    let headline: String
    let subheadline: String
    let backgroundColors: [String]
    let accentColor: String?
    let deviceScale: Double
    let rotationDegrees: Double
    let textPlacement: AppStoreReviewTextPlacement
    let textAlignment: AppStoreReviewTextAlignment
    let headlineFontFamily: AppStoreReviewFontFamily
    let headlineWeight: AppStoreReviewHeadlineWeight
    let headlineItalic: Bool
    let headlineAllCaps: Bool
    let headlineScale: Double
    let headlineTracking: Double
    let headlineWidthRatio: Double
    let subheadlineFontFamily: AppStoreReviewFontFamily
    let subheadlineWeight: AppStoreReviewHeadlineWeight
    let subheadlineItalic: Bool
    let subheadlineScale: Double
    let textToDeviceSpacing: Double
    let screenZoom: Double
    let screenFocusX: Double
    let screenFocusY: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceCaptureID
        case sourceViewName
        case headline
        case subheadline
        case backgroundColors
        case accentColor
        case deviceScale
        case rotationDegrees
        case textPlacement
        case textAlignment
        case headlineFontFamily
        case headlineWeight
        case headlineItalic
        case headlineAllCaps
        case headlineScale
        case headlineTracking
        case headlineWidthRatio
        case subheadlineFontFamily
        case subheadlineWeight
        case subheadlineItalic
        case subheadlineScale
        case textToDeviceSpacing
        case screenZoom
        case screenFocusX
        case screenFocusY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        sourceCaptureID = try container.decode(String.self, forKey: .sourceCaptureID)
        sourceViewName = try container.decodeIfPresent(String.self, forKey: .sourceViewName) ?? ""
        headline = try container.decode(String.self, forKey: .headline)
        subheadline = try container.decodeIfPresent(String.self, forKey: .subheadline) ?? ""
        backgroundColors = try container.decodeIfPresent([String].self, forKey: .backgroundColors) ?? []
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor)
        deviceScale = try container.decodeIfPresent(Double.self, forKey: .deviceScale) ?? 1.0
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        textPlacement = try container.decodeIfPresent(AppStoreReviewTextPlacement.self, forKey: .textPlacement) ?? .top
        textAlignment = try container.decodeIfPresent(AppStoreReviewTextAlignment.self, forKey: .textAlignment) ?? .leading
        headlineFontFamily = try container.decodeIfPresent(AppStoreReviewFontFamily.self, forKey: .headlineFontFamily) ?? .system
        headlineWeight = try container.decodeIfPresent(AppStoreReviewHeadlineWeight.self, forKey: .headlineWeight) ?? .bold
        headlineItalic = try container.decodeIfPresent(Bool.self, forKey: .headlineItalic) ?? false
        headlineAllCaps = try container.decodeIfPresent(Bool.self, forKey: .headlineAllCaps) ?? false
        headlineScale = try container.decodeIfPresent(Double.self, forKey: .headlineScale) ?? 1.0
        headlineTracking = try container.decodeIfPresent(Double.self, forKey: .headlineTracking) ?? -1.0
        headlineWidthRatio = try container.decodeIfPresent(Double.self, forKey: .headlineWidthRatio) ?? 0.92
        subheadlineFontFamily = try container.decodeIfPresent(AppStoreReviewFontFamily.self, forKey: .subheadlineFontFamily) ?? headlineFontFamily
        subheadlineWeight = try container.decodeIfPresent(AppStoreReviewHeadlineWeight.self, forKey: .subheadlineWeight) ?? .medium
        subheadlineItalic = try container.decodeIfPresent(Bool.self, forKey: .subheadlineItalic) ?? false
        subheadlineScale = try container.decodeIfPresent(Double.self, forKey: .subheadlineScale) ?? 1.0
        textToDeviceSpacing = try container.decodeIfPresent(Double.self, forKey: .textToDeviceSpacing) ?? 88
        screenZoom = try container.decodeIfPresent(Double.self, forKey: .screenZoom) ?? 1.0
        screenFocusX = try container.decodeIfPresent(Double.self, forKey: .screenFocusX) ?? 0.5
        screenFocusY = try container.decodeIfPresent(Double.self, forKey: .screenFocusY) ?? 0.5
    }

    func screenshotSpec() -> AppStoreReviewScreenshotSpec {
        AppStoreReviewScreenshotSpec(
            id: id ?? UUID().uuidString,
            sourceCaptureID: sourceCaptureID,
            sourceViewName: sourceViewName,
            headline: headline,
            subheadline: subheadline,
            backgroundColors: backgroundColors,
            accentColor: accentColor,
            deviceScale: deviceScale,
            rotationDegrees: rotationDegrees,
            textPlacement: textPlacement,
            textAlignment: textAlignment,
            headlineFontFamily: headlineFontFamily,
            headlineWeight: headlineWeight,
            headlineItalic: headlineItalic,
            headlineAllCaps: headlineAllCaps,
            headlineScale: headlineScale,
            headlineTracking: headlineTracking,
            headlineWidthRatio: headlineWidthRatio,
            subheadlineFontFamily: subheadlineFontFamily,
            subheadlineWeight: subheadlineWeight,
            subheadlineItalic: subheadlineItalic,
            subheadlineScale: subheadlineScale,
            textToDeviceSpacing: textToDeviceSpacing,
            screenZoom: screenZoom,
            screenFocusX: screenFocusX,
            screenFocusY: screenFocusY
        )
    }
}

struct AppStoreDetailsUpdateInput: Codable, Sendable {
    let description: AppStoreReviewDescriptionSpec?
    let screenshots: [ReviewAgentScreenshotDraft]?
}

struct OpenAIImageProxyImage: Codable, Sendable {
    let base64Data: String?
    let revisedPrompt: String?
}

struct OpenAIImageProxyResponse: Codable, Sendable {
    let images: [OpenAIImageProxyImage]
    let mimeType: String
    let model: String
    let outputFormat: String
}

struct AppStoreReviewIconAsset: Codable, Equatable, Sendable {
    let relativeImagePath: String
    let updatedAt: String
}

struct AppStoreReviewDescriptionAsset: Codable, Equatable, Sendable {
    let spec: AppStoreReviewDescriptionSpec
    let updatedAt: String
}

struct AppStoreReviewScreenshotAsset: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let relativeImagePath: String
    let spec: AppStoreReviewScreenshotSpec
    let updatedAt: String

    var displayTitle: String {
        spec.headline
    }
}

struct AppStoreReviewState: Codable, Equatable, Sendable {
    var creativeDirection: String?
    var icon: AppStoreReviewIconAsset?
    var description: AppStoreReviewDescriptionAsset?
    var screenshots: [AppStoreReviewScreenshotAsset]

    init(
        creativeDirection: String? = nil,
        icon: AppStoreReviewIconAsset? = nil,
        description: AppStoreReviewDescriptionAsset? = nil,
        screenshots: [AppStoreReviewScreenshotAsset] = []
    ) {
        self.creativeDirection = creativeDirection
        self.icon = icon
        self.description = description
        self.screenshots = screenshots
    }

    static let empty = AppStoreReviewState()

    var hasContent: Bool {
        icon != nil || description != nil || !screenshots.isEmpty
    }

    var referencedImagePaths: Set<String> {
        var paths: Set<String> = []
        if let iconPath = icon?.relativeImagePath {
            paths.insert(iconPath)
        }
        for screenshot in screenshots {
            paths.insert(screenshot.relativeImagePath)
        }
        return paths
    }
}
