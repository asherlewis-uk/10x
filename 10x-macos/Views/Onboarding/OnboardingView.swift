import SwiftUI
import UniformTypeIdentifiers

/// Step-by-step onboarding: 3 screens guiding design choices.
struct OnboardingView: View {
    private static let targetAudienceListHeight: CGFloat = 232
    private static let detailsEditorHeight: CGFloat = 188

    let appDescription: String
    let initialDraft: OnboardingDraft?
    let onComplete: (OnboardingData) -> Void
    let onSkip: () -> Void
    let onQuit: (OnboardingDraft) -> Void

    @State private var data = OnboardingData()
    @State private var step: Int = 0
    @State private var selectedStyleId: String? = "clean-minimal"
    @State private var imageAttachments: [URL] = []

    private let totalSteps = 4

    init(
        appDescription: String,
        initialDraft: OnboardingDraft? = nil,
        onComplete: @escaping (OnboardingData) -> Void,
        onSkip: @escaping () -> Void,
        onQuit: @escaping (OnboardingDraft) -> Void
    ) {
        self.appDescription = appDescription
        self.initialDraft = initialDraft
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.onQuit = onQuit
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider().opacity(0.2)

                Group {
                    switch step {
                    case 0: centeredStepContent { localCockpitStep }
                    case 1: centeredStepContent { designStep }
                    case 2: centeredStepContent { targetAudienceStep }
                    default: centeredStepContent { detailsStep }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Divider().opacity(0.2)

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: 580, maxHeight: 560)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(40)
        }
        .onAppear {
            if let draft = initialDraft {
                data = draft.data
            }
        }
        .animation(.easeOut(duration: 0.25), value: step)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                let draft = OnboardingDraft(
                    appDescription: appDescription,
                    data: data
                )
                onQuit(draft)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)

            Spacer()

            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.accent : Color(nsColor: .separatorColor).opacity(0.15))
                        .frame(width: i == step ? 24 : 8, height: 4)
                }
            }

            Spacer()

            Button("Skip") { onSkip() }
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        Text("Back").font(Theme.geist(12, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Summary chips
            HStack(spacing: 6) {
                if let id = selectedStyleId, let style = Self.designStyles.first(where: { $0.id == id }) {
                    summaryChip(style.name, icon: style.icon)
                }
                if !data.targetAudience.isEmpty {
                    summaryChip("\(data.targetAudience.count) audiences", icon: "person.2")
                }
            }

            Spacer()

            Button {
                if step < totalSteps - 1 {
                    withAnimation { step += 1 }
                } else {
                    finishOnboarding()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(step < totalSteps - 1 ? "Next" : "Start Building")
                        .font(Theme.geist(12, weight: .semibold))
                    Image(systemName: step < totalSteps - 1 ? "chevron.right" : "hammer.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 7))
            Text(text).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.08)))
    }

    // MARK: - Finish

    private func finishOnboarding() {
        var finalData = data
        if let id = selectedStyleId, let style = Self.designStyles.first(where: { $0.id == id }) {
            finalData.designStyle = DesignStyle.allCases.first { $0.label == style.name } ?? finalData.designStyle
            finalData.colorOverrides = [
                "primary": style.primary,
                "secondary": style.secondary,
                "accent": style.accent,
                "background": style.background,
                "surface": style.surface,
            ]
            // Add style context to additional details
            let styleContext = """
            Design direction: \(style.name) — \(style.vibe). Inspired by apps like \(style.apps.joined(separator: ", ")).
            Typography: \(style.fontStyle). Corner radius: \(style.cornerRadius). Spacing: \(style.spacing). Shadows: \(style.shadows).
            """
            if finalData.additionalDetails.isEmpty {
                finalData.additionalDetails = styleContext
            } else {
                finalData.additionalDetails = styleContext + "\n" + finalData.additionalDetails
            }
        }
        onComplete(finalData)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - STEP 1: Local Cockpit
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var localCockpitStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Welcome to 11x",
                subtitle: "Your unlimited single-user local cockpit"
            )

            VStack(alignment: .leading, spacing: 12) {
                localCockpitBullet(
                    icon: "lock.fill",
                    title: "No login required",
                    detail: "A single local profile lives on your Mac. No vendor auth, no cloud account."
                )
                localCockpitBullet(
                    icon: "creditcard.fill",
                    title: "No billing or credits",
                    detail: "Generation and export are unlimited. There are no paywalls, subscriptions, or credit packs."
                )
                localCockpitBullet(
                    icon: "internaldrive.fill",
                    title: "Local storage",
                    detail: "Projects, generations, and assets are stored in your local Application Support folder."
                )
                localCockpitBullet(
                    icon: "network",
                    title: "Your own provider",
                    detail: "Connect an OpenAI-compatible endpoint in Settings > Provider. Your key is stored in the system keychain."
                )
            }
            .padding(.horizontal, 20)
        }
    }

    private func localCockpitBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - STEP 2: Design Style (merged inspiration + colors)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private struct AppDesignStyle: Identifiable {
        let id: String
        let name: String
        let vibe: String
        let icon: String
        let apps: [String]
        // Colors
        let primary: String
        let secondary: String
        let accent: String
        let background: String
        let surface: String
        // Typography & shape
        let fontStyle: String       // e.g. "SF Pro", "Rounded", "Serif", "Mono"
        let cornerRadius: String    // e.g. "Sharp (4pt)", "Rounded (12pt)", "Pill"
        let spacing: String         // e.g. "Tight", "Balanced", "Airy"
        let shadows: String         // e.g. "None", "Subtle", "Layered", "Glow"
    }

    private static let designStyles: [AppDesignStyle] = [
        AppDesignStyle(
            id: "clean-minimal", name: "Clean & Minimal", vibe: "Whitespace, restrained color, precise type",
            icon: "square.split.2x1", apps: ["Apple", "Things 3", "Bear"],
            primary: "#1D1D1F", secondary: "#6E6E73", accent: "#0071E3", background: "#FFFFFF", surface: "#F5F5F7",
            fontStyle: "SF Pro", cornerRadius: "Medium (10pt)", spacing: "Balanced", shadows: "Subtle"
        ),
        AppDesignStyle(
            id: "sharp-dark", name: "Sharp & Focused", vibe: "Developer-oriented, dense, monospaced labels",
            icon: "terminal", apps: ["Linear", "Cursor", "Warp"],
            primary: "#F7F8F8", secondary: "#8A8F98", accent: "#5E6AD2", background: "#08090A", surface: "#16171A",
            fontStyle: "Mono", cornerRadius: "Sharp (4pt)", spacing: "Tight", shadows: "None"
        ),
        AppDesignStyle(
            id: "warm-inviting", name: "Warm & Inviting", vibe: "Soft warm tones, friendly rounded cards",
            icon: "cup.and.saucer", apps: ["Airbnb", "Notion", "Calm"],
            primary: "#37352F", secondary: "#787774", accent: "#FF385C", background: "#FFFFFF", surface: "#F7F6F3",
            fontStyle: "Rounded", cornerRadius: "Rounded (12pt)", spacing: "Balanced", shadows: "Subtle"
        ),
        AppDesignStyle(
            id: "bold-dark", name: "Bold & Expressive", vibe: "Dark canvas, heavy type, vivid accents",
            icon: "flame", apps: ["Spotify", "VSCO", "Letterboxd"],
            primary: "#FFFFFF", secondary: "#B3B3B3", accent: "#1DB954", background: "#121212", surface: "#1E1E1E",
            fontStyle: "SF Pro Bold", cornerRadius: "Medium (8pt)", spacing: "Tight", shadows: "None"
        ),
        AppDesignStyle(
            id: "professional", name: "Professional", vibe: "Refined cards, layered depth, cool tones",
            icon: "briefcase", apps: ["Stripe", "Vercel", "Mercury"],
            primary: "#0A2540", secondary: "#425466", accent: "#635BFF", background: "#FFFFFF", surface: "#F6F9FC",
            fontStyle: "SF Pro", cornerRadius: "Medium (8pt)", spacing: "Balanced", shadows: "Layered"
        ),
        AppDesignStyle(
            id: "playful", name: "Playful & Fun", vibe: "Bouncy shapes, pill buttons, bright colors",
            icon: "sparkles", apps: ["Duolingo", "Streaks", "Widgetsmith"],
            primary: "#1B1B3A", secondary: "#6B5CA5", accent: "#58CC02", background: "#FFFFFF", surface: "#F7F7F7",
            fontStyle: "Rounded", cornerRadius: "Pill (20pt)", spacing: "Balanced", shadows: "Subtle"
        ),
        AppDesignStyle(
            id: "soft-pastel", name: "Soft & Pastel", vibe: "Muted tints, gentle shapes, calming feel",
            icon: "leaf", apps: ["Headspace", "Balance", "Flo"],
            primary: "#4A3F4B", secondary: "#8B7E8C", accent: "#E8A0B4", background: "#FFF5F7", surface: "#FFEAEF",
            fontStyle: "Rounded", cornerRadius: "Rounded (14pt)", spacing: "Balanced", shadows: "Soft"
        ),
        AppDesignStyle(
            id: "earth-natural", name: "Earth & Natural", vibe: "Grounded earth tones, organic feel",
            icon: "mountain.2", apps: ["AllTrails", "Strava", "Nike Run"],
            primary: "#1A2E1E", secondary: "#4D6A52", accent: "#5B8C5A", background: "#F5F9F5", surface: "#E8F0E8",
            fontStyle: "SF Pro", cornerRadius: "Rounded (12pt)", spacing: "Balanced", shadows: "Subtle"
        ),
        AppDesignStyle(
            id: "glass-depth", name: "Glass & Depth", vibe: "Translucent layers, blur, floating cards",
            icon: "drop", apps: ["Weather", "Arc", "Opal"],
            primary: "#E2E8F0", secondary: "#94A3B8", accent: "#38BDF8", background: "#0F172A", surface: "#1E293B",
            fontStyle: "SF Pro", cornerRadius: "Rounded (16pt)", spacing: "Balanced", shadows: "Layered"
        ),
        AppDesignStyle(
            id: "social-coral", name: "Social & Vibrant", vibe: "Feed-first, bold headers, punchy CTA",
            icon: "person.2", apps: ["Instagram", "TikTok", "BeReal"],
            primary: "#262626", secondary: "#8E8E8E", accent: "#FE2C55", background: "#FFFFFF", surface: "#FAFAFA",
            fontStyle: "SF Pro Bold", cornerRadius: "Medium (10pt)", spacing: "Tight", shadows: "None"
        ),
        AppDesignStyle(
            id: "neon-electric", name: "Neon & Electric", vibe: "OLED black, glowing accents, tech feel",
            icon: "bolt", apps: ["Halide", "Apollo", "NightCafe"],
            primary: "#E4E4E7", secondary: "#71717A", accent: "#22D3EE", background: "#09090B", surface: "#18181B",
            fontStyle: "Mono", cornerRadius: "Sharp (4pt)", spacing: "Tight", shadows: "Glow"
        ),
        AppDesignStyle(
            id: "editorial", name: "Editorial", vibe: "Serif headings, generous line height, longform",
            icon: "text.book.closed", apps: ["Medium", "Substack", "Apple News"],
            primary: "#292929", secondary: "#6B6B6B", accent: "#1A8917", background: "#FFFFFF", surface: "#FAFAFA",
            fontStyle: "Serif", cornerRadius: "Sharp (4pt)", spacing: "Balanced", shadows: "None"
        ),
    ]

    private var selectedStyle: AppDesignStyle? {
        guard let id = selectedStyleId else { return nil }
        return Self.designStyles.first { $0.id == id }
    }

    private var designStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(
                title: "Design Direction",
                subtitle: "Pick the style that best fits your app's personality"
            )

            // Live preview of selected style
            if let style = selectedStyle {
                stylePreview(style)
                    .padding(.horizontal, 20)
            }

            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.designStyles) { style in
                    styleCard(style)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // Derive numeric corner radius from the style string
    private func cardRadius(for style: AppDesignStyle) -> CGFloat {
        if style.cornerRadius.contains("Sharp") { return 2 }
        if style.cornerRadius.contains("Pill") { return 10 }
        if style.cornerRadius.contains("16") { return 8 }
        if style.cornerRadius.contains("14") { return 7 }
        if style.cornerRadius.contains("12") { return 6 }
        if style.cornerRadius.contains("10") { return 5 }
        return 4 // Medium (8pt)
    }

    // Derive font for the style
    private func previewFont(for style: AppDesignStyle, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch style.fontStyle {
        case "Rounded": return .system(size: size, weight: weight, design: .rounded)
        case "Mono": return .system(size: size, weight: weight, design: .monospaced)
        case "Serif": return .system(size: size, weight: weight, design: .serif)
        case "SF Pro Bold": return .system(size: size, weight: weight == .regular ? .semibold : weight)
        default: return .system(size: size, weight: weight)
        }
    }

    // Derive shadow for the style
    private func cardShadow(for style: AppDesignStyle) -> some ViewModifier {
        PreviewCardShadow(shadows: style.shadows, accent: style.accent)
    }

    /// Mini phone-style preview showing what the selected palette looks like as a real UI.
    private func stylePreview(_ style: AppDesignStyle) -> some View {
        let cr = cardRadius(for: style)

        return HStack(spacing: 12) {
            // Mini phone frame
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    Text("9:41")
                        .font(previewFont(for: style, size: 6, weight: .semibold))
                        .foregroundStyle(Color(hex: style.primary))
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "wifi").font(.system(size: 5))
                        Image(systemName: "battery.100").font(.system(size: 6))
                    }
                    .foregroundStyle(Color(hex: style.secondary))
                }
                .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 3)

                // Nav title
                HStack {
                    Text("Home")
                        .font(previewFont(for: style, size: 8, weight: .bold))
                        .foregroundStyle(Color(hex: style.primary))
                    Spacer()
                    Circle()
                        .fill(Color(hex: style.accent))
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 6).padding(.bottom, 4)

                // Card 1
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: style.primary))
                        .frame(width: 40, height: 4)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: style.secondary))
                        .frame(width: 55, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: style.secondary).opacity(0.5))
                        .frame(width: 35, height: 3)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: cr).fill(Color(hex: style.surface)))
                .modifier(cardShadow(for: style))
                .padding(.horizontal, 6)

                Spacer().frame(height: 4)

                // Card 2
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: style.primary))
                        .frame(width: 35, height: 4)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: style.secondary))
                        .frame(width: 50, height: 3)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: cr).fill(Color(hex: style.surface)))
                .modifier(cardShadow(for: style))
                .padding(.horizontal, 6)

                Spacer().frame(height: 5)

                // CTA button
                Text("Get Started")
                    .font(previewFont(for: style, size: 6, weight: .semibold))
                    .foregroundStyle(Color(hex: style.background))
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: style.cornerRadius.contains("Pill") ? 20 : cr)
                            .fill(Color(hex: style.accent))
                    )
                    .modifier(cardShadow(for: style))
                    .padding(.bottom, 6)

                // Tab bar
                HStack {
                    ForEach(["house.fill", "magnifyingglass", "plus.circle.fill", "bell", "person"], id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 6))
                            .foregroundStyle(icon == "house.fill" ? Color(hex: style.accent) : Color(hex: style.secondary))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 4)
                .background(Color(hex: style.surface))
            }
            .frame(width: 100, height: 140)
            .background(Color(hex: style.background))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)

            // Style info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: style.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: style.accent))
                    Text(style.name)
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }

                Text(style.vibe)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    ForEach(style.apps, id: \.self) { app in
                        Text(app)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.08)))
                    }
                }

                // Full palette
                HStack(spacing: 4) {
                    ForEach([
                        ("BG", style.background), ("Surface", style.surface),
                        ("Accent", style.accent), ("Text", style.primary), ("Muted", style.secondary)
                    ], id: \.0) { label, hex in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: hex))
                                .frame(width: 24, height: 16)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5))
                            Text(label)
                                .font(.system(size: 7))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                // Style properties
                HStack(spacing: 10) {
                    styleProperty(icon: "textformat", label: style.fontStyle)
                    styleProperty(icon: "square.on.square", label: style.cornerRadius)
                    styleProperty(icon: "arrow.up.and.down", label: style.spacing)
                    styleProperty(icon: "shadow", label: style.shadows)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: selectedStyleId)
    }

    private func styleCard(_ style: AppDesignStyle) -> some View {
        let isSelected = selectedStyleId == style.id

        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedStyleId = style.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Color swatches row
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: style.background))
                        .frame(maxWidth: .infinity, maxHeight: 24)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: style.surface))
                        .frame(maxWidth: .infinity, maxHeight: 24)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: style.accent))
                        .frame(maxWidth: .infinity, maxHeight: 24)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: style.primary))
                        .frame(maxWidth: .infinity, maxHeight: 24)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5))
                }

                // Name + icon
                HStack(spacing: 4) {
                    Image(systemName: style.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: style.accent))
                    Text(style.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                    }
                }

                // App examples
                Text(style.apps.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.accent.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.accent.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.1), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - STEP 2: Target Audience
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var targetAudienceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Target Audience",
                subtitle: "Who is this app for? Select all that apply."
            )

            ScrollView(.vertical, showsIndicators: false) {
                let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(TargetAudience.allCases) { audience in
                        let isSelected = data.targetAudience.contains(audience)
                        Button {
                            withAnimation(.easeOut(duration: 0.1)) {
                                if isSelected { data.targetAudience.removeAll { $0 == audience } }
                                else { data.targetAudience.append(audience) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: audience.iconName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                                    .frame(width: 20)

                                Text(audience.label)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Theme.accent.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Theme.accent.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.12), lineWidth: isSelected ? 1.5 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: Self.targetAudienceListHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - STEP 3: Details + Images
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: "Additional Details",
                subtitle: "Describe features, inspirations, or attach reference images"
            )

            TextEditor(text: $data.additionalDetails)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                .frame(height: Self.detailsEditorHeight)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.1), lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if data.additionalDetails.isEmpty {
                        Text("e.g. \"Include a social feed, dark mode toggle, and onboarding flow inspired by Duolingo...\"")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 16)
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 20)

            // Image attachments
            HStack(spacing: 8) {
                Button {
                    pickImages()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 11))
                        Text("Add Images")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                ForEach(imageAttachments, id: \.absoluteString) { url in
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.accent)
                        Text(url.lastPathComponent)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Button {
                            imageAttachments.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent.opacity(0.06)))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.title = "Attach reference images"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        imageAttachments.append(contentsOf: panel.urls)
    }

    // MARK: - Shared

    /// Shadow modifier that adapts to the style's shadow type.
    private struct PreviewCardShadow: ViewModifier {
        let shadows: String
        let accent: String

        func body(content: Content) -> some View {
            switch shadows {
            case "Subtle":
                content.shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            case "Soft":
                content.shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            case "Layered":
                content
                    .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            case "Glow":
                content.shadow(color: Color(hex: accent).opacity(0.3), radius: 3, y: 0)
            default:
                content
            }
        }
    }

    private func styleProperty(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundStyle(Theme.textTertiary)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.geist(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func centeredStepContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
