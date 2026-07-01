import SwiftUI

/// Design tokens for the 11x local cockpit.
enum Theme {
    // MARK: - Colors

    /// Calm green accent for the 11x local cockpit. Intentionally less saturated
    /// than the original 10x token so status and actions feel quiet, not toy-bright.
    static let accent = Color(hex: "2E9E3A")
    static let accentSecondary = accent.opacity(0.72)
    static let accentLight = accent.opacity(0.12)
    static let accentSubtle = accent.opacity(0.06)

    static let surface = Color(hex: "1C1C1C")           // bg.primary
    static let surfaceElevated = Color(hex: "202220")     // bg.secondary
    static let surfaceInset = Color(hex: "141414")        // bg.recessed — darker than surface
    static let separator = Color.primary.opacity(0.08)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.primary.opacity(0.3)

    static let success = Color.green
    static let error = Color.red
    static let warning = Color.orange

    // MARK: - Glass

    static let glassCornerRadius: CGFloat = 16
    static let glassCornerRadiusSmall: CGFloat = 10

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    // MARK: - Corner Radii

    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 16
    static let radiusXL: CGFloat = 20

    // MARK: - Typography

    static func geist(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .light: name = "Geist-Light"
        case .medium: name = "Geist-Medium"
        case .semibold: name = "Geist-SemiBold"
        case .bold: name = "Geist-Bold"
        case .black: name = "Geist-Black"
        default: name = "Geist-Regular"
        }
        return Font.custom(name, fixedSize: size)
    }

    static func geistMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .light: name = "GeistMono-Light"
        case .medium: name = "GeistMono-Medium"
        case .semibold: name = "GeistMono-SemiBold"
        case .bold: name = "GeistMono-Bold"
        default: name = "GeistMono-Regular"
        }
        return Font.custom(name, fixedSize: size)
    }

    // MARK: - Type Scale

    static let largeTitle = geist(28, weight: .bold)
    static let title = geist(20, weight: .semibold)
    static let title2 = geist(17, weight: .semibold)
    static let title3 = geist(15, weight: .semibold)
    static let headline = geist(14, weight: .semibold)
    static let body = geist(13)
    static let subheadline = geist(12, weight: .medium)
    static let caption = geist(11)
    static let caption2 = geist(10)

    // MARK: - Code

    static let codeFont = geistMono(14)
    static let codeFontSmall = geistMono(12)
    static let lineHeight: CGFloat = 20

    /// Generic status tint helper. Replaces the 10x-era `billingStatusTint`.
    static func statusTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "active", "completed", "paid", "configured", "ready", "ok", "success":
            accent
        case "trialing", "pending", "open", "running", "in_progress", "processing", "started", "streaming":
            .blue
        case "cancelled", "failed", "error", "missing":
            warning
        case "past_due", "uncollectible":
            error
        default:
            textSecondary
        }
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        if hex.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
