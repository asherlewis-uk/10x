import AppKit
import SwiftUI

struct ChatPanelView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth
    @State private var isNearBottom = true
    @State private var shouldFollowLive = true
    @State private var skillPickerPresentation = ChatSkillPickerPresentation.hidden
    @State private var viewPickerPresentation = ChatViewPickerPresentation.hidden
    @State private var pendingSkillSelection: String?
    @State private var pendingViewSelectionID: String?
    @State private var composerHeight: CGFloat = 0
    @State private var pendingScrollTask: Task<Void, Never>?
    private let chatHeaderContentInset: CGFloat = 44
    private let chatHeaderFadeHeight: CGFloat = 64
    private let composerHeightChangeThreshold: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                chatItemsList
                                if viewModel.hasStreamingAssistant {
                                    HStack(spacing: 0) {
                                        StreamingAssistantBubble(text: viewModel.pendingAssistantContent) { _ in
                                            guard shouldFollowLive else { return }
                                            scheduleScrollToBottom(with: proxy)
                                        }
                                        .padding(.leading, 8)

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.bottom, Theme.spacingMD)
                                }

                                confirmPlanSection
                                activeGenerationSection
                                liveBuildFixSection
                                questionSection
                                resumeSection
                                dependencyReminderSection

                                // Bottom anchor
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.spacingLG)
                            .padding(.bottom, Theme.spacingLG)
                            .padding(.top, chatHeaderContentInset)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                            .background {
                                UserScrollIntentTracker(shouldStickToBottom: shouldFollowLive) { nearBottom in
                                    isNearBottom = nearBottom
                                    shouldFollowLive = nearBottom
                                }
                            }
                        }
                        .overlay(alignment: .top) {
                            chatHeader
                        }
                        .onChange(of: viewModel.chatItems.count) {
                            guard shouldFollowLive else { return }
                            scheduleScrollToBottom(with: proxy, animated: true)
                        }
                        .onChange(of: viewModel.pendingAssistantContent) { _, _ in
                            guard shouldFollowLive, viewModel.hasStreamingAssistant else { return }
                            scheduleScrollToBottom(with: proxy)
                        }
                        .onChange(of: viewModel.activeSteps.count) {
                            guard shouldFollowLive else { return }
                            scheduleScrollToBottom(with: proxy)
                        }
                        .onChange(of: viewModel.questionQueue?.currentIndex) {
                            proxy.scrollTo("question", anchor: .bottom)
                        }
                        .onChange(of: viewModel.isGenerating) { _, generating in
                            if generating {
                                shouldFollowLive = true
                                scheduleScrollToBottom(with: proxy)
                            } else {
                                pendingScrollTask?.cancel()
                                if isNearBottom {
                                    shouldFollowLive = true
                                }
                            }
                        }
                        .onChange(of: viewModel.activeChat?.id) {
                            shouldFollowLive = true
                            isNearBottom = true
                            scheduleScrollToBottom(with: proxy)
                        }

                        if !shouldFollowLive {
                            scrollToBottomButton(proxy: proxy)
                                .padding(.trailing, Theme.spacingLG)
                                .padding(.bottom, Theme.spacingLG)
                        }
                    }
                }

                VStack(spacing: 0) {
                    if let approval = viewModel.integrationApproval {
                        IntegrationApprovalView(approval: approval)
                            .padding(.horizontal, Theme.spacingMD)
                            .padding(.top, Theme.spacingSM)
                    }

                    ChatInputView(
                        skillPickerPresentation: $skillPickerPresentation,
                        viewPickerPresentation: $viewPickerPresentation,
                        pendingSkillSelection: $pendingSkillSelection,
                        pendingViewSelectionID: $pendingViewSelectionID
                    )
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                updateComposerHeight(proxy.size.height)
                            }
                            .onChange(of: proxy.size.height) { _, newValue in
                                updateComposerHeight(newValue)
                            }
                    }
                }
            }
        }
        .background(Theme.surfaceInset)
        .overlay(alignment: .bottom) {
            if viewPickerPresentation.isPresented {
                ViewSuggestionsOverlay(
                    presentation: viewPickerPresentation,
                    onSelect: { capture in
                        pendingViewSelectionID = capture.id
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.bottom, composerHeight + Theme.spacingSM)
                .zIndex(1000)
                .compositingGroup()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if skillPickerPresentation.isPresented {
                SkillSuggestionsOverlay(
                    presentation: skillPickerPresentation,
                    onSelect: { skill in
                        pendingSkillSelection = skill.name
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.bottom, composerHeight + Theme.spacingSM)
                .zIndex(1000)
                .compositingGroup()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDisappear {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
        }
    }

    private var chatHeader: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Theme.surface.opacity(0.95), location: 0),
                    .init(color: Theme.surface.opacity(0.72), location: 0.28),
                    .init(color: Theme.surface.opacity(0.22), location: 0.7),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: chatHeaderFadeHeight)
            .allowsHitTesting(false)

            HStack(alignment: .center, spacing: Theme.spacingSM) {
                Button {
                    viewModel.showChatSidebar.toggle()
                } label: {
                    Label("Chats", systemImage: "bubble.left.and.text.bubble.right")
                        .font(Theme.geistMono(12, weight: .semibold))
                        .foregroundStyle(viewModel.showChatSidebar ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Browse chats")
                .popover(
                    isPresented: Binding(
                        get: { viewModel.showChatSidebar },
                        set: { viewModel.showChatSidebar = $0 }
                    ),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) {
                    ProjectChatSidebarView()
                }

                Spacer()

                if viewModel.isGenerating {
                    TypingDotsView(color: Theme.textSecondary, dotSize: 5)
                }

                Button {
                    viewModel.createChat()
                } label: {
                    Label("New", systemImage: "square.and.pencil")
                        .font(Theme.geistMono(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canManageChats)
            }
            .padding(.horizontal, Theme.spacingLG)
            .padding(.top, Theme.spacingSM)
            .padding(.bottom, 6)
        }
        .frame(height: chatHeaderFadeHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.clear)
        .frame(maxWidth: .infinity)
    }

    private func shouldShowAssistantFooter(for message: BuilderMessage, at index: Int) -> Bool {
        guard message.role == "assistant" else { return true }
        if viewModel.isGenerating || !viewModel.activeSteps.isEmpty || viewModel.hasStreamingAssistant {
            return false
        }

        let nextIndex = index + 1
        let items = viewModel.chatItems
        guard nextIndex < items.count else { return true }
        switch items[nextIndex] {
        case .message(let nextMessage):
            return nextMessage.role != "assistant"
        case .toolSteps:
            return false
        default:
            return true
        }
    }

    // MARK: - Chat Items

    @ViewBuilder
    private var chatItemsList: some View {
        ForEach(Array(viewModel.chatItems.enumerated()), id: \.element.id) { index, item in
            chatItemView(for: item, at: index)
        }
    }

    @ViewBuilder
    private func chatItemView(for item: BuilderViewModel.ChatItem, at index: Int) -> some View {
        switch item {
        case .message(let msg):
            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                MessageBubbleView(
                    message: msg,
                    showAssistantFooter: shouldShowAssistantFooter(for: msg, at: index),
                    assistantCopyText: msg.role == "assistant" ? assistantCopyText(for: index) : nil
                )

                if shouldShowDependencyChecklist(after: msg) {
                    dependencyChecklistCard
                        .id("dependency-checklist-card")
                }
            }
            .padding(.bottom, Theme.spacingMD)
        case .systemEvent(let event):
            if event.kind != .dependencyChecklist {
                SystemEventRowView(event: event)
                    .padding(.bottom, Theme.spacingMD)
            }
        case .toolSteps(_, let steps):
            ToolStepsView(steps: steps)
                .padding(.bottom, Theme.spacingSM)
        case .error(_, let message):
            errorView(message: message)
                .padding(.bottom, Theme.spacingMD)
        case .buildFix(let id, let error, let resolved):
            BuildFixItemView(error: error, isActive: isActiveBuildFix(id: id), resolved: resolved)
                .padding(.bottom, Theme.spacingMD)
        }
    }

    private func shouldShowDependencyChecklist(after message: BuilderMessage) -> Bool {
        viewModel.hasDependencyChecklist && viewModel.dependencyChecklistAnchorMessageId == message.id
    }

    private var unresolvedDependencyRows: [ProjectDependencyResolution] {
        viewModel.dependencyChecklistRows.filter { !$0.isResolved }
    }

    private var dependencyReminderRows: [ProjectDependencyResolution] {
        viewModel.dependencyChecklistRows
    }

    private var shouldShowDependencyReminderInChat: Bool {
        !unresolvedDependencyRows.isEmpty
    }

    @ViewBuilder
    private var dependencyChecklistCard: some View {
        let rows = viewModel.dependencyChecklistRows

        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            HStack(alignment: .center, spacing: Theme.spacingSM) {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text(rows.isEmpty ? "No setup required for this plan" : "Setup required by the plan")
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()
            }

            if rows.isEmpty {
                Text("Dependency analysis is complete. No integrations, backend setup, or secrets are required for the current plan.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    ForEach(rows, id: \.requirement.id) { resolution in
                        dependencyChecklistRow(resolution)
                    }
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(Theme.separator, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var dependencyReminderSection: some View {
        if shouldShowDependencyReminderInChat {
            dependencyReminderCard
                .padding(.bottom, Theme.spacingMD)
        }
    }

    @ViewBuilder
    private var dependencyReminderCard: some View {
        let rows = dependencyReminderRows
        let primaryRequirement = rows.count == 1 ? rows.first?.requirement : nil

        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.requirement.id) { resolution in
                    dependencyReminderRow(resolution)
                }
            }

            HStack(spacing: Theme.spacingSM) {
                Button {
                    openDependencySurface(for: primaryRequirement ?? unresolvedDependencyRows.first?.requirement ?? rows.first?.requirement)
                } label: {
                    Text(dependencyActionTitle(for: unresolvedDependencyRows.count == 1 ? unresolvedDependencyRows.first?.requirement : unresolvedDependencyRows.first?.requirement ?? primaryRequirement))
                        .font(Theme.geist(10, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.warning.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(Theme.warning.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private func dependencyReminderRow(_ resolution: ProjectDependencyResolution) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: resolution.isResolved ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(resolution.isResolved ? Theme.success : Theme.warning.opacity(0.9))
                .padding(.top, 2)

            Text(dependencyReminderActionLine(for: resolution))
                .font(Theme.geist(11, weight: .medium))
                .foregroundStyle(resolution.isResolved ? Theme.textTertiary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(resolution.isResolved, color: Theme.textTertiary.opacity(0.7))

            Spacer(minLength: 0)
        }
    }

    private func dependencyReminderActionLine(for resolution: ProjectDependencyResolution) -> String {
        switch resolution.requirement.setupSurface {
        case .backend:
            return "Open Backend and configure \(resolution.requirement.title)."
        case .integration:
            return "Open Integrations and configure \(resolution.requirement.title)."
        case .external:
            if !resolution.missingKeys.isEmpty {
                let keys = resolution.missingKeys.map { "`\($0)`" }.joined(separator: ", ")
                return "Add \(keys) to finish \(resolution.requirement.title)."
            }
            return "Finish external setup for \(resolution.requirement.title)."
        }
    }

    private func dependencyChecklistRow(_ resolution: ProjectDependencyResolution) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: Theme.spacingSM) {
                Image(systemName: resolution.isResolved ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(resolution.isResolved ? Theme.success : Theme.textTertiary)

                Text(resolution.requirement.title)
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                dependencySafetyBadge(resolution.requirement.safety)

                Spacer(minLength: 0)

                if resolution.requirement.setupSurface == .backend {
                    Button {
                        viewModel.focusBackend()
                    } label: {
                        Text(resolution.isResolved ? "View" : "Open Backend")
                            .font(Theme.geist(11, weight: .semibold))
                            .foregroundStyle(resolution.isResolved ? Theme.textSecondary : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(resolution.isResolved ? Theme.surfaceInset : Theme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                } else if let integrationID = resolution.requirement.integrationID {
                    Button {
                        viewModel.focusEnvironmentIntegration(integrationID)
                    } label: {
                        Text(resolution.isResolved ? "View" : "Configure")
                            .font(Theme.geist(11, weight: .semibold))
                            .foregroundStyle(resolution.isResolved ? Theme.textSecondary : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(resolution.isResolved ? Theme.surfaceInset : Theme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(resolution.requirement.summary)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(resolution.detail)
                .font(Theme.geist(11))
                .foregroundStyle(resolution.isResolved ? Theme.success : Theme.textTertiary)

            if resolution.requirement.allowsMockDataUntilConfigured && !resolution.isResolved {
                Text("The agent should use dummy/mock data until this is configured.")
                    .font(Theme.geist(11, weight: .medium))
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.vertical, 2)
    }

    private func dependencyActionTitle(for requirement: ProjectDependencyRequirement?) -> String {
        switch requirement?.setupSurface {
        case .backend:
            return "Open Backend"
        case .integration:
            return requirement?.integrationID == nil ? "Open" : "Configure"
        case .external:
            return "Open"
        case nil:
            return "Open"
        }
    }

    private func openDependencySurface(for requirement: ProjectDependencyRequirement?) {
        switch requirement?.setupSurface {
        case .backend:
            viewModel.focusBackend()
        case .integration:
            viewModel.focusEnvironmentIntegration(requirement?.integrationID)
        case .external, nil:
            viewModel.focusEnvironmentIntegration(requirement?.integrationID)
        }
    }

    private func dependencySafetyBadge(_ safety: ProjectDependencySafety) -> some View {
        Text(safety.title)
            .font(Theme.geist(10, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Theme.surfaceInset)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
            .help(safety.detail)
    }

    private func isActiveBuildFix(id: String) -> Bool {
        guard let activeBuildIssue = viewModel.activeBuildIssue else { return false }
        return activeBuildIssue.isFixing && activeBuildIssue.id == id
    }

    private func assistantCopyText(for index: Int) -> String? {
        guard index < viewModel.chatItems.count else { return nil }

        var collectedSegments: [String] = []
        var currentIndex = index

        while currentIndex >= 0 {
            let item = viewModel.chatItems[currentIndex]
            switch item {
            case .message(let msg) where msg.role == "assistant":
                let content = msg.displayableContent
                if !content.isEmpty {
                    collectedSegments.append(content)
                }
                currentIndex -= 1
            case .toolSteps:
                currentIndex -= 1
            default:
                currentIndex = -1
            }
        }

        guard !collectedSegments.isEmpty else { return nil }
        let combined = collectedSegments.reversed().joined(separator: "\n\n")
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            shouldFollowLive = true
            scheduleScrollToBottom(with: proxy, animated: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .semibold))
                Text("Jump to live")
                    .font(Theme.geist(12, weight: .semibold))
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .background(.ultraThickMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll to latest message")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func scheduleScrollToBottom(with proxy: ScrollViewProxy, animated: Bool = false) {
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func updateComposerHeight(_ newValue: CGFloat) {
        let sanitized = max(0, ceil(newValue))
        guard abs(composerHeight - sanitized) >= composerHeightChangeThreshold else { return }
        composerHeight = sanitized
    }

    // MARK: - Confirm Plan

    @ViewBuilder
    private var confirmPlanSection: some View {
        if viewModel.projectPlan != nil,
           viewModel.fileTree.isEmpty,
           !viewModel.isGenerating,
           !viewModel.hasRequestedPlanExecution {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.body)

                Text("Plan ready")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                if auth.isAuthenticated {
                    Button {
                        Task { @MainActor in
                            guard let token = await auth.validAccessToken() else { return }
                            _ = viewModel.sendMessage("I'd like to refine the plan. Let me give you some feedback.", accessToken: token)
                        }
                    } label: {
                        Text("Refine")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.spacingMD)
                            .padding(.vertical, Theme.spacingXS)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .separatorColor).opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { @MainActor in
                            guard let token = await auth.validAccessToken() else { return }
                            _ = viewModel.sendMessage(
                                "The plan looks great. Start building the app now.",
                                accessToken: token,
                                action: .executePlan
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hammer.fill")
                                .font(.caption)
                            Text("Start Building")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.vertical, Theme.spacingXS)
                        .background(
                            Capsule()
                                .fill(Theme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .fill(Theme.accent.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSM)
                            .stroke(Theme.accent.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.bottom, Theme.spacingMD)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Active Generation

    @ViewBuilder
    private var activeGenerationSection: some View {
        if viewModel.isGenerating || !viewModel.activeSteps.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                if !viewModel.activeSteps.isEmpty {
                    ToolStepsView(steps: viewModel.activeSteps)
                }
                generationStatusView
            }
            .padding(.bottom, Theme.spacingMD)
        }
    }

    @ViewBuilder
    private var liveBuildFixSection: some View {
        if !viewModel.isPreviewLoading,
           let activeBuildIssue = viewModel.activeBuildIssue,
           !hasInlineBuildFix(for: activeBuildIssue) {
            BuildFixItemView(
                error: activeBuildIssue.error,
                isActive: activeBuildIssue.isFixing,
                resolved: false
            )
            .padding(.bottom, Theme.spacingMD)
        }
    }

    private func hasInlineBuildFix(for activeBuildIssue: BuilderViewModel.BuildIssueDisplayState) -> Bool {
        viewModel.chatItems.contains {
            if case .buildFix(let id, _, _) = $0 { return id == activeBuildIssue.id }
            return false
        }
    }

    @ViewBuilder
    private var generationStatusView: some View {
        if viewModel.isGenerating, let status = viewModel.currentGenerationStatus {
            HStack(spacing: 6) {
                TypingDotsView(color: Theme.textSecondary, dotSize: 4)
                Text(status.title)
                    .font(Theme.geist(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Question

    @ViewBuilder
    private var questionSection: some View {
        if let queue = viewModel.questionQueue, let current = queue.currentQuestion {
            InlineQuestionView(
                question: current,
                questionIndex: queue.currentIndex + 1,
                totalQuestions: queue.totalCount,
                currentAnswer: queue.answers[current.question],
                canGoBack: queue.currentIndex > 0
            )
            .padding(.bottom, Theme.spacingSM)
            .id("question")
        }
    }

    // MARK: - Resume

    @ViewBuilder
    private var resumeSection: some View {
        if viewModel.showResumePrompt && !viewModel.isGenerating && !viewModel.hasPendingUserResponse {
            resumeView
                .padding(.bottom, Theme.spacingMD)
        }
    }

    private var resumeView: some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: "arrow.forward.circle.fill")
                .foregroundStyle(Theme.accent)
                .font(.body)

            Text("Pick up where you left off?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            if auth.isAuthenticated {
                Button {
                    Task { @MainActor in
                        guard let token = await auth.validAccessToken() else { return }
                        _ = viewModel.sendMessage("Continue", accessToken: token)
                    }
                } label: {
                    Text("Continue")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.vertical, Theme.spacingXS)
                        .background(
                            Capsule()
                                .fill(Theme.accent.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.accent.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(Theme.accent.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Error view with retry

    private func errorView(message: String) -> some View {
        let isConnectionIssue = BuilderGenerationRequestPlanner.isConnectionFailureMessage(message)
        let lower = message.lowercased()
        let isProviderIssue = lower.contains("provider") || lower.contains("api key") || lower.contains("apikey")

        return HStack(spacing: Theme.spacingSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.error)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(isConnectionIssue ? "Connection issue" : "Generation failed")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.error)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.error.opacity(0.9))
                    .lineLimit(3)

                if isProviderIssue {
                    Text("Check Settings > Provider")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer()

            if viewModel.lastFailedRequest != nil, auth.isAuthenticated {
                Button {
                    Task { @MainActor in
                        guard let token = await auth.validAccessToken() else { return }
                        viewModel.retryLastMessage(accessToken: token)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                        Text("Retry")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.error.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(Theme.error.opacity(0.2), lineWidth: 1)
                )
        )
    }

}

private struct SkillSuggestionsOverlay: View {
    let presentation: ChatSkillPickerPresentation
    let onSelect: (SkillRegistryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Skills")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if presentation.isLoading {
                HStack(spacing: Theme.spacingSM) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading skills...")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            } else if presentation.suggestions.isEmpty {
                Text("No matching skills")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(presentation.suggestions, id: \.name) { skill in
                            Button {
                                onSelect(skill)
                            } label: {
                                HStack(alignment: .top, spacing: Theme.spacingSM) {
                                    Image(systemName: skill.iconName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 14, alignment: .center)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(skill.displayTitle)
                                            .font(Theme.geist(12, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(skill.userFacingDescription)
                                            .font(Theme.geist(12))
                                            .foregroundStyle(Theme.textSecondary)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text("/\(skill.name)")
                                            .font(Theme.geistMono(10))
                                            .foregroundStyle(Theme.textTertiary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if skill.name != presentation.suggestions.last?.name {
                                Divider()
                                    .opacity(0.35)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.surfaceElevated.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .fill(Color.white.opacity(0.03))
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
    }
}

private struct ViewSuggestionsOverlay: View {
    @Environment(BuilderViewModel.self) private var viewModel
    let presentation: ChatViewPickerPresentation
    let onSelect: (PreviewScreenCapture) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Views")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if presentation.suggestions.isEmpty {
                Text(viewModel.developmentScreenLibrary.isEmpty ? "No app views available yet" : "No matching views")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(presentation.suggestions) { capture in
                            Button {
                                onSelect(capture)
                            } label: {
                                HStack(alignment: .top, spacing: Theme.spacingSM) {
                                    Group {
                                        if let image = viewModel.previewScreenImage(for: capture) {
                                            Image(nsImage: image)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Theme.surface)
                                                .overlay(
                                                    Image(systemName: "rectangle.on.rectangle.angled")
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(Theme.accent)
                                                )
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(capture.displayName)
                                            .font(Theme.geist(12, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(capture.chatMentionTag)
                                            .font(Theme.geistMono(10))
                                            .foregroundStyle(Theme.accent)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if capture.id != presentation.suggestions.last?.id {
                                Divider()
                                    .opacity(0.35)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.surfaceElevated.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .fill(Color.white.opacity(0.03))
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
    }
}

private struct UserScrollIntentTracker: NSViewRepresentable {
    let shouldStickToBottom: Bool
    let onUserScroll: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldStickToBottom: shouldStickToBottom, onUserScroll: onUserScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shouldStickToBottom = shouldStickToBottom
        context.coordinator.onUserScroll = onUserScroll
        context.coordinator.attach(to: nsView)
        context.coordinator.pinToBottomIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var shouldStickToBottom: Bool
        var onUserScroll: (Bool) -> Void
        private weak var scrollView: NSScrollView?
        private weak var documentView: NSView?
        private var observers: [NSObjectProtocol] = []

        init(shouldStickToBottom: Bool, onUserScroll: @escaping (Bool) -> Void) {
            self.shouldStickToBottom = shouldStickToBottom
            self.onUserScroll = onUserScroll
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, let enclosing = view.enclosingScrollView else { return }
                guard enclosing !== self.scrollView else { return }
                self.observe(enclosing)
            }
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            scrollView = nil
            documentView = nil
        }

        private func observe(_ scrollView: NSScrollView) {
            detach()
            self.scrollView = scrollView
            let contentView = scrollView.contentView
            contentView.postsFrameChangedNotifications = true
            if let documentView = scrollView.documentView {
                self.documentView = documentView
                documentView.postsFrameChangedNotifications = true
            }

            let center = NotificationCenter.default
            var nextObservers: [NSObjectProtocol] = [
                center.addObserver(
                    forName: NSScrollView.didLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    self?.notifyScrollPosition()
                },
                center.addObserver(
                    forName: NSScrollView.didEndLiveScrollNotification,
                    object: scrollView,
                    queue: .main
                ) { [weak self] _ in
                    self?.notifyScrollPosition()
                },
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: contentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.pinToBottomIfNeeded()
                },
            ]
            if let documentView {
                nextObservers.append(
                    center.addObserver(
                        forName: NSView.frameDidChangeNotification,
                        object: documentView,
                        queue: .main
                    ) { [weak self] _ in
                        self?.pinToBottomIfNeeded()
                    }
                )
            }
            observers = nextObservers

            notifyScrollPosition()
            pinToBottomIfNeeded()
        }

        private func notifyScrollPosition() {
            guard let scrollView else { return }
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let visibleMaxY = scrollView.contentView.bounds.maxY
            let nearBottom = (documentHeight - visibleMaxY) < 80
            onUserScroll(nearBottom)
        }

        func pinToBottomIfNeeded() {
            guard shouldStickToBottom else { return }
            pinToBottom()
        }

        private func pinToBottom() {
            guard let scrollView, let documentView else { return }
            let contentView = scrollView.contentView
            let targetY = max(0, documentView.frame.height - contentView.bounds.height)
            guard abs(contentView.bounds.origin.y - targetY) > 0.5 else { return }
            contentView.setBoundsOrigin(NSPoint(x: contentView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(contentView)
            notifyScrollPosition()
        }

        deinit {
            detach()
        }
    }
}

// MARK: - Build Fix Item

private struct BuildFixItemView: View {
    let error: String
    let isActive: Bool
    let resolved: Bool
    @State private var isExpanded = false

    private var accentColor: Color { resolved ? Color.green : Theme.error }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: resolved ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill")
                        .font(.caption)
                        .foregroundStyle(accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(resolved ? "Build errors fixed" : "Fixing build errors")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(accentColor)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(accentColor.opacity(0.7))
                    }

                    Spacer()

                    if isActive {
                        TypingDotsView(color: accentColor, dotSize: 3)
                            .padding(.trailing, 4)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(accentColor.opacity(0.5))
                }
                .padding(Theme.spacingMD)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(accentColor.opacity(0.15))

                ScrollView {
                    Text(error)
                        .font(Theme.geistMono(10))
                        .foregroundStyle(accentColor.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacingMD)
                }
                .frame(maxHeight: 180)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
    }

    private var subtitle: String {
        if isActive { return "AI is repairing compile errors..." }
        if resolved { return "Project compiles successfully · tap to see what was fixed" }
        return "Repair attempted · tap to see errors"
    }
}

// MARK: - Pulsing Typing Dots

struct TypingDotsView: View {
    var color: Color = Theme.textSecondary
    var dotSize: CGFloat = 4
    private let cycleDuration: TimeInterval = 0.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: dotSize * 0.75) {
                ForEach(0..<3, id: \.self) { index in
                    let intensity = intensityFor(index, at: time)

                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .opacity(opacityFor(intensity))
                        .scaleEffect(scaleFor(intensity))
                }
            }
        }
    }

    private func intensityFor(_ index: Int, at time: TimeInterval) -> Double {
        let progress = (time / cycleDuration - Double(index) / 3.0)
            .truncatingRemainder(dividingBy: 1.0)
        return 0.5 + 0.5 * sin(progress * 2 * .pi)
    }

    private func opacityFor(_ intensity: Double) -> Double {
        0.3 + 0.7 * intensity
    }

    private func scaleFor(_ intensity: Double) -> CGFloat {
        0.7 + 0.3 * CGFloat(intensity)
    }
}
