import AppKit
import SwiftUI

private let homePromptEditorMinHeight: CGFloat = 36
private let homePromptEditorMaxHeight: CGFloat = 100
private let homePromptEditorVerticalInset: CGFloat = 8

/// Home screen — create a new project or open a recent one.
struct HomeView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth
    @State private var prompt = ""
    @State private var projectToRename: BuilderProject?
    @State private var renameText = ""
    @State private var pendingProjectAction: PendingProjectAction?
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var thumbnailColors: [String: (Color, Color)] = [:]
    @State private var showOnboarding = false
    @State private var showPromptChoice = false
    @State private var showingArchivedProjects = false
    @State private var pendingPrompt = ""
    @State private var pendingAttachments: [BuilderMessageAttachment] = []
    @State private var promptComposerError: String?
    @State private var promptEditorHeight: CGFloat = homePromptEditorMinHeight
    @State private var isPromptDropTargeted = false
    @State private var isImportingProject = false
    @State private var resumingDraftProject: BuilderProject?
    @State private var resumingDraft: OnboardingDraft?
    let onOpenProject: (BuilderProject, _ initialMessage: String?, _ designStyle: DesignStyle?, _ onboardingData: OnboardingData?, _ attachments: [BuilderMessageAttachment]) -> Void
    var onArchiveProject: ((BuilderProject) -> Void)?
    var onUnarchiveProject: ((BuilderProject) -> Void)?
    var onDeleteProject: ((BuilderProject) -> Void)?

    private let localStore = LocalProjectStore()
    @State private var suggestions: [String] = []

    private struct ThumbnailLoadRequest {
        let id: String
        let projectName: String
    }

    private struct LoadedProjectAsset {
        let id: String
        let thumbnail: NSImage
        let colors: (Color, Color)
    }

    private static let allIdeas = [
        // Productivity
        "Pomodoro timer with analytics",
        "Habit tracker with streaks",
        "AI daily planner",
        "Voice note organizer",
        "Focus session tracker",
        "Smart to-do list with AI priorities",
        "Weekly review journal",
        // Health & Fitness
        "AI calorie tracker from photos",
        "Workout recommendation engine",
        "Gym PR tracker",
        "Stretching routine builder",
        "Sleep score tracker",
        "Meditation timer with breathing",
        "Running log with splits",
        "Meal prep planner",
        // Finance
        "Expense splitter for friend groups",
        "Subscription cost tracker",
        "Side hustle income dashboard",
        "Savings goal visualizer",
        "Freelancer invoice maker",
        "Crypto portfolio tracker",
        // Social
        "Find athletes near you",
        "Local pickup sports app",
        "Book club organizer",
        "Roommate chore tracker",
        "Study group finder",
        "Neighborhood event board",
        // Food & Drink
        "Cocktail recipe book",
        "Coffee brewing guide",
        "Restaurant wishlist with ratings",
        "Fridge inventory with expiry alerts",
        "Meal plan with grocery list",
        // Learning
        "Flashcard app with spaced repetition",
        "Coding challenge tracker",
        "Language learning journal",
        "Music practice logger",
        "Speed reading trainer",
        // Travel
        "Trip packing list generator",
        "Travel itinerary builder",
        "National parks checklist",
        "Bucket list with photos",
        // Creative
        "Movie watchlist with ratings",
        "Photography spot finder",
        "Mood board creator",
        "Podcast tracker",
        "Drawing prompt generator",
        // Lifestyle
        "Plant care reminder",
        "Closet organizer",
        "Gift idea tracker by person",
        "Pet care log",
        "Morning routine builder",
    ]

    private var displayedProjectLoadKey: String {
        let scope = showingArchivedProjects ? "archived" : "active"
        let projectKey = displayedProjects
            .map { "\($0.id):\($0.name)" }
            .joined(separator: "|")
        return "\(scope)|\(projectKey)"
    }

    private var shouldShowProjectsSection: Bool {
        true
    }

    private var shouldShowSubscriptionPrompt: Bool {
        !showingArchivedProjects
            && viewModel.hasLoadedProjects
            && !viewModel.isLoadingProjects
            && viewModel.projects.isEmpty
    }

    private var canAttachMoreFiles: Bool {
        pendingAttachments.count < BuilderAttachmentPolicy.maxItemCount
            && BuilderAttachmentPolicy.payloadBytes(for: pendingAttachments) < BuilderAttachmentPolicy.maxTotalBytes
    }

    var body: some View {
        ZStack {
            Theme.surfaceInset
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.spacingXL) {
                    Spacer(minLength: 40)

                    // Hero
                    Image("10XbuilderLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 70)
                        .foregroundStyle(Theme.textPrimary)

                    Text("What would you like to build?")
                        .font(Theme.geist(22, weight: .semibold))

                    // Input area
                    VStack(spacing: Theme.spacingXS) {
                        HomePromptTextEditor(
                            text: $prompt,
                            height: $promptEditorHeight,
                            isDropTargeted: $isPromptDropTargeted,
                            minHeight: homePromptEditorMinHeight,
                            maxHeight: homePromptEditorMaxHeight,
                            onPastePasteboard: importPromptPasteboard(_:),
                            onDropPasteboard: importPromptPasteboard(_:),
                            onSubmit: createProject
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: promptEditorHeight)
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.top, Theme.spacingSM)

                        if !pendingAttachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.spacingXS) {
                                    ForEach(pendingAttachments) { attachment in
                                        HStack(spacing: 4) {
                                            Image(systemName: attachment.systemImageName)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(Theme.accent)
                                            Text(attachment.filename)
                                                .font(Theme.geist(10, weight: .medium))
                                                .foregroundStyle(Theme.textSecondary)
                                                .lineLimit(1)
                                            Button {
                                                pendingAttachments.removeAll { $0.id == attachment.id }
                                                promptComposerError = nil
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(Theme.textTertiary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Theme.accent.opacity(0.08)))
                                    }
                                }
                                .padding(.horizontal, Theme.spacingMD)
                            }
                        }

                        if let promptComposerError, !promptComposerError.isEmpty {
                            HStack {
                                Text(promptComposerError)
                                    .font(Theme.geist(11))
                                    .foregroundStyle(Theme.error)
                                Spacer()
                            }
                            .padding(.horizontal, Theme.spacingMD)
                        }

                        HStack {
                            Text("iOS App")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)

                            Button { pickAttachment() } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 11))
                                    Text("Attach")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAttachMoreFiles)

                            Button { importExistingProject() } label: {
                                HStack(spacing: 3) {
                                    if isImportingProject {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "folder.badge.plus")
                                            .font(.system(size: 11))
                                    }
                                    Text(isImportingProject ? "Importing" : "Import")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isImportingProject)

                            Spacer()

                            Button {
                                createProject()
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        prompt.trimmingCharacters(in: .whitespaces).isEmpty
                                            ? Theme.textTertiary
                                            : Theme.accent
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.bottom, Theme.spacingSM)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusSM)
                                    .strokeBorder(
                                        isPromptDropTargeted ? Theme.accent : Color.primary.opacity(0.1),
                                        lineWidth: isPromptDropTargeted ? 1.5 : 1
                                    )
                            )
                    }
                    .frame(maxWidth: 500)

                    // Suggestion chips — 5 random ideas
                    if !suggestions.isEmpty {
                        FlowLayout(spacing: Theme.spacingSM, alignment: .center) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    prompt = suggestion
                                } label: {
                                    Text(suggestion)
                                        .font(Theme.geist(12))
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal, Theme.spacingMD)
                                        .padding(.vertical, 6)
                                        .background {
                                            Capsule()
                                                .fill(Theme.surface)
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                                                )
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    suggestions = Array(Self.allIdeas.shuffled().prefix(5))
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(6)
                                    .background {
                                        Circle()
                                            .fill(Theme.surface)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .help("Refresh suggestions")
                        }
                        .frame(maxWidth: 500, alignment: .center)
                    }

                    if shouldShowProjectsSection {
                        VStack(alignment: .leading, spacing: Theme.spacingMD) {
                            projectTabsHeader

                            if displayedProjects.isEmpty {
                                if shouldShowSubscriptionPrompt {
                                    emptyProjectsInfoCard
                                } else {
                                    Text(showingArchivedProjects ? "No archived projects yet." : "No recent projects yet.")
                                        .font(Theme.geist(12))
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(Theme.spacingMD)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                                .fill(Theme.surface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                                )
                                        )
                                }
                            } else {
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: Theme.spacingMD),
                                    GridItem(.flexible(), spacing: Theme.spacingMD),
                                ], spacing: Theme.spacingMD) {
                                    ForEach(displayedProjects) { project in
                                        projectCard(project, mode: showingArchivedProjects ? .archived : .active)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 700)
                        .padding(.top, Theme.spacingXL)
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if suggestions.isEmpty {
                suggestions = Array(Self.allIdeas.shuffled().prefix(5))
            }
        }
        .task(id: displayedProjectLoadKey) {
            await preloadDisplayedProjectAssets(for: displayedProjectLoadKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tenxProjectThumbnailDidChange)) { notification in
            guard let projectId = notification.object as? String,
                  let projectName = notification.userInfo?["projectName"] as? String else {
                return
            }

            Task {
                await refreshProjectThumbnail(projectId: projectId, projectName: projectName)
            }
        }
        .alert("Rename Project", isPresented: Binding(
            get: { projectToRename != nil },
            set: { if !$0 { projectToRename = nil } }
        )) {
            TextField("Project name", text: $renameText)
            Button("Cancel", role: .cancel) { projectToRename = nil }
            Button("Rename") {
                guard let project = projectToRename else { return }
                let name = renameText
                projectToRename = nil
                Task { await viewModel.renameProject(project, newName: name) }
            }
        }
        .alert(item: $pendingProjectAction) { action in
            Alert(
                title: Text(action.kind == .archive ? "Archive Project?" : "Delete Project Permanently?"),
                message: Text(
                    action.kind == .archive
                        ? "\"\(action.project.name)\" will be removed from your active project list. Generated files and conversation history will stay on disk."
                        : "\"\(action.project.name)\" will be permanently deleted from the archive, and its local files and conversation history will be removed from disk."
                ),
                primaryButton: .cancel(Text("Cancel")),
                secondaryButton: action.kind == .archive
                    ? .default(Text("Archive")) { runProjectAction(action) }
                    : .destructive(Text("Delete Permanently")) { runProjectAction(action) }
            )
        }
        .overlay {
            if showPromptChoice {
                promptChoiceOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showPromptChoice)
        .overlay {
            if showOnboarding {
                OnboardingView(
                    appDescription: pendingPrompt,
                    initialDraft: resumingDraft,
                    onComplete: { data in
                        completeOnboarding(data: data)
                    },
                    onSkip: {
                        skipOnboarding()
                    },
                    onQuit: { draft in
                        saveDraftAndClose(draft)
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showOnboarding)
    }

    // MARK: - Project Card (iPhone Case Style)

    private static let phoneWidth: CGFloat = 140
    private static let phoneHeight: CGFloat = 280
    private static let phoneCornerRadius: CGFloat = 28
    private static let phoneBorderWidth: CGFloat = 4
    private static let phoneNotchWidth: CGFloat = 50
    private static let phoneNotchHeight: CGFloat = 8
    private static let cardPreviewHeight: CGFloat = 180

    private enum ProjectCardMode {
        case active
        case archived
    }

    private struct PendingProjectAction: Identifiable {
        enum Kind: String {
            case archive
            case delete
        }

        let kind: Kind
        let project: BuilderProject

        var id: String { "\(kind.rawValue)-\(project.id)" }
    }

    private var displayedProjects: [BuilderProject] {
        showingArchivedProjects ? viewModel.archivedProjects : viewModel.projects
    }

    private var projectTabsHeader: some View {
        HStack {
            projectTabButton(
                title: "Recent Projects",
                count: viewModel.projects.count,
                isSelected: !showingArchivedProjects
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingArchivedProjects = false
                }
            }

            Spacer()

            projectTabButton(
                title: "Archived",
                count: viewModel.archivedProjects.count,
                isSelected: showingArchivedProjects
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingArchivedProjects = true
                }
            }
        }
    }

    private var emptyProjectsInfoCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .top, spacing: Theme.spacingMD) {
                Image(systemName: "app.badge")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Create your first project")
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("11x is an unlimited single-user local cockpit. Start a new project to begin building.")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func projectTabButton(
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.spacingSM) {
                Text(title)
                    .font(Theme.geist(13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Theme.textTertiary)

                Text("\(count)")
                    .font(Theme.geist(11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Theme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isSelected ? Theme.accent.opacity(0.9) : Color.primary.opacity(0.06))
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func projectCard(_ project: BuilderProject, mode: ProjectCardMode) -> some View {
        let colors = thumbnailColors[project.id] ?? projectGradientColors(for: project.name)
        let isArchived = mode == .archived
        let subtitle = isArchived ? "Archived iOS App" : "iOS App"
        let primaryActionIcon = isArchived ? "tray.and.arrow.up" : "archivebox"
        let primaryActionLabel = isArchived ? "Unarchive" : "Archive"
        let handlePrimaryAction = {
            if isArchived {
                Task {
                    await viewModel.unarchiveProject(project)
                    onUnarchiveProject?(project)
                }
            } else {
                pendingProjectAction = PendingProjectAction(kind: .archive, project: project)
            }
        }

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Preview area with iPhone in gradient
                ZStack {
                    Theme.surface

                    // Subtle radial glow behind the phone
                    RadialGradient(
                        colors: [colors.0.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 120
                    )

                    phoneFrame(project: project, gradientColors: colors)
                        .padding(.top, Theme.spacingMD)
                }
                .frame(height: Self.cardPreviewHeight, alignment: .top)
                .clipped()

                // Label bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(Theme.geist(12, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitle)
                            .font(Theme.geist(10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, Theme.spacingSM)
            }
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(Theme.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .opacity(isArchived ? 0.9 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            .onTapGesture {
                if let draft = localStore.loadOnboardingDraft(projectName: project.name, projectId: project.id) {
                    // Resume onboarding for this draft project
                    resumingDraftProject = project
                    resumingDraft = draft
                    pendingPrompt = draft.appDescription
                    showOnboarding = true
                } else {
                    onOpenProject(project, nil, nil, nil, [])
                }
            }

            VStack(spacing: 8) {
                projectActionButton(
                    systemName: primaryActionIcon,
                    foregroundColor: Theme.textSecondary,
                    help: "\(primaryActionLabel) Project",
                    action: handlePrimaryAction
                )

                if isArchived {
                    projectActionButton(
                        systemName: "trash",
                        foregroundColor: Color.red.opacity(0.9),
                        help: "Delete Project Permanently"
                    ) {
                        pendingProjectAction = PendingProjectAction(kind: .delete, project: project)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(Theme.spacingSM)
        }
        .contextMenu {
            Button {
                if let draft = localStore.loadOnboardingDraft(projectName: project.name, projectId: project.id) {
                    resumingDraftProject = project
                    resumingDraft = draft
                    pendingPrompt = draft.appDescription
                    showOnboarding = true
                } else {
                    onOpenProject(project, nil, nil, nil, [])
                }
            } label: {
                Label("Open", systemImage: "arrow.right.circle")
            }

            Button {
                renameText = project.name
                projectToRename = project
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(action: handlePrimaryAction) {
                Label(primaryActionLabel, systemImage: primaryActionIcon)
            }

            if isArchived {
                Divider()

                Button(role: .destructive) {
                    pendingProjectAction = PendingProjectAction(kind: .delete, project: project)
                } label: {
                    Label("Delete Permanently", systemImage: "trash")
                }
            }
        }
    }

    private func projectActionButton(
        systemName: String,
        foregroundColor: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
        }
        .help(help)
    }

    private func runProjectAction(_ action: PendingProjectAction) {
        pendingProjectAction = nil
        Task {
            switch action.kind {
            case .archive:
                await viewModel.archiveProject(action.project)
                onArchiveProject?(action.project)
            case .delete:
                await viewModel.deleteProject(action.project)
                onDeleteProject?(action.project)
            }
        }
    }

    /// iPhone-shaped frame containing the project preview
    private func phoneFrame(project: BuilderProject, gradientColors: (Color, Color)) -> some View {
        let screenWidth = Self.phoneWidth - Self.phoneBorderWidth * 2
        let screenHeight = Self.phoneHeight - Self.phoneBorderWidth * 2
        let screenRadius = Self.phoneCornerRadius - Self.phoneBorderWidth
        let hasThumb = thumbnails[project.id] != nil

        return ZStack {
            // Bezel
            RoundedRectangle(cornerRadius: Self.phoneCornerRadius)
                .fill(Color(white: 0.15))
                .frame(width: Self.phoneWidth, height: Self.phoneHeight)

            // Screen content — fill width, clip to screen bounds
            if let thumb = thumbnails[project.id] {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: screenWidth, height: screenHeight, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: screenRadius))
            } else {
                LinearGradient(
                    colors: [gradientColors.0, gradientColors.1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(project.name.prefix(12))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .frame(width: screenWidth, height: screenHeight)
                .clipShape(RoundedRectangle(cornerRadius: screenRadius))
            }

            // Dynamic Island — only show on placeholder, not on real screenshots
            if !hasThumb {
                Capsule()
                    .fill(Color(white: 0.15))
                    .frame(width: Self.phoneNotchWidth, height: Self.phoneNotchHeight)
                    .offset(y: -(Self.phoneHeight / 2 - 16))
            }
        }
    }

    /// Find the most common color in a thumbnail, then return a lighter and darker
    /// version for the ambient gradient.
    private static func dominantColors(from image: NSImage) -> (Color, Color) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return (.gray, .gray)
        }

        let w = bitmap.pixelsWide
        let h = bitmap.pixelsHigh
        guard w > 4, h > 4 else { return (.gray, .gray) }

        // Quantize ALL pixels into buckets to find the most common background color
        var buckets: [Int: (count: Int, rSum: CGFloat, gSum: CGFloat, bSum: CGFloat)] = [:]
        let step = 6 // sample every 6th pixel
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                let ri = Int(r * 7), gi = Int(g * 7), bi = Int(b * 7)
                let key = ri * 64 + gi * 8 + bi
                let existing = buckets[key] ?? (0, 0, 0, 0)
                buckets[key] = (existing.count + 1, existing.rSum + r, existing.gSum + g, existing.bSum + b)
            }
        }

        // Find the bucket with the most pixels — this IS the background color
        guard let best = buckets.max(by: { $0.value.count < $1.value.count }) else {
            return (.gray, .gray)
        }

        let count = CGFloat(best.value.count)
        let r = best.value.rSum / count
        let g = best.value.gSum / count
        let b = best.value.bSum / count

        // Convert to HSB so we can adjust brightness without losing hue
        let nsColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)

        // For very desaturated colors, boost saturation so the tint is visible in the gradient
        let boostedSat = max(sat, 0.15)

        let lighter = Color(hue: hue, saturation: boostedSat * 0.7, brightness: min(1, bri * 1.05))
        let darker = Color(hue: hue, saturation: boostedSat * 1.1, brightness: bri * 0.90)

        return (lighter, darker)
    }

    /// Curated gradient palettes for projects without thumbnails.
    /// Stable selection via djb2 hash so colors don't change across launches.
    private static let curatedPalettes: [(Color, Color, Color)] = [
        // Blue
        (Color(red: 0.90, green: 0.93, blue: 0.97), Color(red: 0.84, green: 0.88, blue: 0.94), Color(red: 0.78, green: 0.84, blue: 0.90)),
        // Green
        (Color(red: 0.90, green: 0.95, blue: 0.90), Color(red: 0.84, green: 0.90, blue: 0.84), Color(red: 0.78, green: 0.86, blue: 0.78)),
        // Orange
        (Color(red: 0.97, green: 0.93, blue: 0.88), Color(red: 0.94, green: 0.88, blue: 0.82), Color(red: 0.90, green: 0.84, blue: 0.76)),
        // Yellow
        (Color(red: 0.97, green: 0.96, blue: 0.88), Color(red: 0.94, green: 0.92, blue: 0.82), Color(red: 0.90, green: 0.88, blue: 0.76)),
    ]

    /// Gradient directions for visual variety
    private static let gradientDirections: [(UnitPoint, UnitPoint)] = [
        (.topLeading, .bottomTrailing),
        (.top, .bottom),
        (.topTrailing, .bottomLeading),
        (.leading, .trailing),
    ]

    private func projectGradientColors(for name: String) -> (Color, Color) {
        var hash: UInt64 = 5381
        for char in name.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(char)
        }
        let palette = Self.curatedPalettes[Int(hash % UInt64(Self.curatedPalettes.count))]
        // Use first and last color for the ambient gradient; middle is used in the card
        return (palette.0, palette.2)
    }

    private func projectGradientTriple(for name: String) -> (Color, Color, Color) {
        var hash: UInt64 = 5381
        for char in name.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(char)
        }
        return Self.curatedPalettes[Int(hash % UInt64(Self.curatedPalettes.count))]
    }

    private func projectGradientDirection(for name: String) -> (UnitPoint, UnitPoint) {
        var hash: UInt64 = 5381
        for char in name.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(char)
        }
        return Self.gradientDirections[Int((hash / 8) % UInt64(Self.gradientDirections.count))]
    }

    private func preloadDisplayedProjectAssets(for loadKey: String) async {
        let requests = displayedProjects.compactMap { project in
            thumbnails[project.id] == nil
                ? ThumbnailLoadRequest(id: project.id, projectName: project.name)
                : nil
        }

        guard !requests.isEmpty else { return }

        let loadedAssets = await loadProjectAssets(requests)
        guard !Task.isCancelled, loadKey == displayedProjectLoadKey, !loadedAssets.isEmpty else { return }

        var nextThumbnails = thumbnails
        var nextThumbnailColors = thumbnailColors

        for asset in loadedAssets {
            if nextThumbnails[asset.id] == nil {
                nextThumbnails[asset.id] = asset.thumbnail
                nextThumbnailColors[asset.id] = asset.colors
            }
        }

        thumbnails = nextThumbnails
        thumbnailColors = nextThumbnailColors
    }

    private func loadProjectAssets(_ requests: [ThumbnailLoadRequest]) async -> [LoadedProjectAsset] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let loadedAssets = requests.compactMap { request in
                    autoreleasepool { () -> LoadedProjectAsset? in
                        guard let thumbnail = localStore.loadThumbnail(
                            projectName: request.projectName,
                            projectId: request.id
                        ) else {
                            return nil
                        }

                        return LoadedProjectAsset(
                            id: request.id,
                            thumbnail: thumbnail,
                            colors: Self.dominantColors(from: thumbnail)
                        )
                    }
                }

                continuation.resume(returning: loadedAssets)
            }
        }
    }

    private func refreshProjectThumbnail(projectId: String, projectName: String) async {
        let asset = await loadProjectAssets([
            ThumbnailLoadRequest(id: projectId, projectName: projectName)
        ]).first

        guard !Task.isCancelled else { return }

        if let asset {
            thumbnails[projectId] = asset.thumbnail
            thumbnailColors[projectId] = asset.colors
        } else {
            thumbnails.removeValue(forKey: projectId)
            thumbnailColors.removeValue(forKey: projectId)
        }
    }

    private func createProject() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pendingPrompt = text
        showPromptChoice = true
        promptComposerError = nil
    }

    private func pickAttachment() {
        if let error = BuilderAttachmentPolicy.validationError(for: pendingAttachments) {
            promptComposerError = error
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Attach files"
        panel.allowedContentTypes = BuilderAttachmentImporter.allowedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        let (imported, errors) = BuilderAttachmentPasteboardSupport.importedAttachments(from: panel.urls)
        applyImportedAttachments(imported, errors: errors)
    }

    private func importExistingProject() {
        guard !isImportingProject else { return }

        let panel = NSOpenPanel()
        panel.title = "Import SwiftUI Project"
        panel.message = "Choose a project folder, `.xcodeproj`, or `.xcworkspace`."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let selectionURL = panel.url else { return }

        promptComposerError = nil
        isImportingProject = true

        Task {
            guard let token = await auth.validAccessToken() else {
                await MainActor.run {
                    isImportingProject = false
                    promptComposerError = "Sign in before importing an existing project."
                }
                return
            }

            do {
                let project = try await viewModel.importExistingProject(
                    from: selectionURL,
                    accessToken: token
                )
                await MainActor.run {
                    isImportingProject = false
                    onOpenProject(project, nil, nil, nil, [])
                }
            } catch {
                await MainActor.run {
                    isImportingProject = false
                    promptComposerError = error.localizedDescription
                }
            }
        }
    }

    private func importPromptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let urls = BuilderAttachmentPasteboardSupport.fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }

        let (imported, errors) = BuilderAttachmentPasteboardSupport.importedAttachments(from: urls)
        if imported.isEmpty, errors.isEmpty {
            applyImportedAttachments([], errors: ["Couldn’t attach pasted item."])
        } else {
            applyImportedAttachments(imported, errors: errors)
        }
        return true
    }

    private func applyImportedAttachments(_ imported: [BuilderMessageAttachment], errors: [String]) {
        guard !imported.isEmpty || !errors.isEmpty else { return }

        let nextAttachments = pendingAttachments + imported
        var nextErrors = errors
        if nextErrors.isEmpty, let error = BuilderAttachmentPolicy.validationError(for: nextAttachments) {
            nextErrors.append(error)
        }

        if nextErrors.isEmpty {
            pendingAttachments = nextAttachments
            promptComposerError = nil
        } else {
            promptComposerError = nextErrors.first
        }
    }

    // MARK: - Prompt Choice Overlay

    private var promptChoiceOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture {
                withAnimation {
                    showPromptChoice = false
                    pendingPrompt = ""
                }
            }

            VStack(spacing: 16) {
                // App concept
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                    Text(pendingPrompt)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.04))
                )

                Text("How would you like to start?")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                // Two options
                VStack(spacing: 8) {
                    // Add Details (recommended)
                    Button {
                        withAnimation {
                            showPromptChoice = false
                            showOnboarding = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.accent.opacity(0.1))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.accent)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text("Select Your Style")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Recommended")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.accent.opacity(0.1)))
                                }
                                Text("Choose design inspiration, colors, audience, and more")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Begin Immediately
                    Button {
                        withAnimation {
                            showPromptChoice = false
                        }
                        skipOnboarding()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Begin Immediately")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Skip customization — let AI decide everything")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            )
        }
    }

    private func completeOnboarding(data: OnboardingData) {
        showOnboarding = false

        var fullPrompt = pendingPrompt
        if let context = data.contextString() {
            fullPrompt += context
        }

        let name = String(pendingPrompt.prefix(50))
        let selectedStyle = data.designStyle
        let attachments = pendingAttachments
        let draftProject = resumingDraftProject
        pendingPrompt = ""
        pendingAttachments = []
        resumingDraftProject = nil
        resumingDraft = nil

        Task {
            guard let token = await auth.validAccessToken() else { return }
            if let project = draftProject {
                // Resuming from a draft — clean up draft file and use existing project
                await localStore.deleteOnboardingDraft(projectName: project.name, projectId: project.id)
                onOpenProject(project, fullPrompt, selectedStyle, data, attachments)
            } else {
                await viewModel.createProject(name: name, accessToken: token)
                if let project = viewModel.activeProject {
                    onOpenProject(project, fullPrompt, selectedStyle, data, attachments)
                }
            }
        }
    }

    private func skipOnboarding() {
        showOnboarding = false
        let text = pendingPrompt
        let name = String(text.prefix(50))
        let attachments = pendingAttachments
        let draftProject = resumingDraftProject
        pendingPrompt = ""
        pendingAttachments = []
        resumingDraftProject = nil
        resumingDraft = nil

        Task {
            guard let token = await auth.validAccessToken() else { return }
            if let project = draftProject {
                await localStore.deleteOnboardingDraft(projectName: project.name, projectId: project.id)
                onOpenProject(project, text, nil, nil, attachments)
            } else {
                await viewModel.createProject(name: name, accessToken: token)
                if let project = viewModel.activeProject {
                    onOpenProject(project, text, nil, nil, attachments)
                }
            }
        }
    }

    private func saveDraftAndClose(_ draft: OnboardingDraft) {
        showOnboarding = false

        let description = pendingPrompt
        let name = String(description.prefix(50))

        if let project = resumingDraftProject {
            // Already have a project — just update the draft
            Task {
                await localStore.saveOnboardingDraft(draft, projectName: project.name, projectId: project.id)
            }
            prompt = description
            pendingPrompt = ""
            resumingDraftProject = nil
            resumingDraft = nil
        } else {
            // First time quitting — create project, then save draft
            pendingPrompt = ""
            prompt = description
            Task {
                guard let token = await auth.validAccessToken() else { return }
                await viewModel.createProject(name: name, accessToken: token)
                if let project = viewModel.activeProject {
                    await localStore.saveOnboardingDraft(draft, projectName: project.name, projectId: project.id)
                }
            }
        }
    }
}

private struct HomePromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isDropTargeted: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onPastePasteboard: (NSPasteboard) -> Bool
    let onDropPasteboard: (NSPasteboard) -> Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = HomePromptNSTextView()
        textView.delegate = context.coordinator
        textView.submitHandler = onSubmit
        textView.pasteHandler = onPastePasteboard
        textView.dropHandler = onDropPasteboard
        textView.dropTargetChanged = { context.coordinator.updateDropTargetState($0) }
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont(name: "Geist-Regular", size: 13) ?? .systemFont(ofSize: 13)
        textView.textColor = .textColor
        textView.insertionPointColor = .white
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: homePromptEditorVerticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: 10_000, height: 10_000)
        textView.autoresizingMask = [.width]
        textView.registerForDraggedTypes([.fileURL, .URL])

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.sync(textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? HomePromptNSTextView else { return }
        textView.submitHandler = onSubmit
        textView.pasteHandler = onPastePasteboard
        textView.dropHandler = onDropPasteboard
        textView.dropTargetChanged = { context.coordinator.updateDropTargetState($0) }
        context.coordinator.sync(textView: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HomePromptTextEditor
        private var isApplyingUpdate = false

        init(parent: HomePromptTextEditor) {
            self.parent = parent
        }

        func sync(textView: HomePromptNSTextView) {
            if textView.string != parent.text {
                isApplyingUpdate = true
                textView.string = parent.text
                textView.typingAttributes = [
                    .font: NSFont(name: "Geist-Regular", size: 13) ?? .systemFont(ofSize: 13),
                    .foregroundColor: NSColor.textColor,
                ]
                isApplyingUpdate = false
            }

            updateHeight(for: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? HomePromptNSTextView else { return }

            if parent.text != textView.string {
                parent.text = textView.string
            }

            updateHeight(for: textView)
        }

        func updateDropTargetState(_ isTargeted: Bool) {
            guard parent.isDropTargeted != isTargeted else { return }
            DispatchQueue.main.async {
                self.parent.isDropTargeted = isTargeted
            }
        }

        private func updateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let contentHeight = ceil(usedRect.height + (textView.textContainerInset.height * 2) + 2)
            let clamped = max(parent.minHeight, min(parent.maxHeight, contentHeight))

            if abs(parent.height - clamped) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.height = clamped
                }
            }
        }
    }
}

private final class HomePromptNSTextView: NSTextView {
    var submitHandler: (() -> Void)?
    var pasteHandler: ((NSPasteboard) -> Bool)?
    var dropHandler: ((NSPasteboard) -> Bool)?
    var dropTargetChanged: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76) && !event.modifierFlags.contains(.shift) {
            submitHandler?()
            return
        }

        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if pasteHandler?(NSPasteboard.general) == true {
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canHandleDrop(sender.draggingPasteboard) else {
            return super.draggingEntered(sender)
        }
        dropTargetChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canHandleDrop(sender.draggingPasteboard) else {
            return super.draggingUpdated(sender)
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTargetChanged?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canHandleDrop(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTargetChanged?(false)
        guard canHandleDrop(sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        return dropHandler?(sender.draggingPasteboard) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dropTargetChanged?(false)
        super.concludeDragOperation(sender)
    }

    private func canHandleDrop(_ pasteboard: NSPasteboard) -> Bool {
        BuilderAttachmentPasteboardSupport.hasImportableFileURLs(on: pasteboard)
    }
}
