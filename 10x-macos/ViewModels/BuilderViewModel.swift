import AppKit
import Foundation
import SwiftUI

/// JSON payload stored in a BuilderMessage with role "build_fix".
struct BuildFixContent: Codable {
    var error: String
    var resolved: Bool
}

struct BuilderGenerationStatus: Equatable, Sendable {
    let title: String
    let detail: String?

    static let gettingReady = Self(
        title: "Getting ready",
        detail: "Reviewing your request and the current project."
    )
    static let pickingBackUp = Self(
        title: "Picking back up",
        detail: "Working from your latest answer and the current state of the project."
    )
    static let reviewingRecentWork = Self(
        title: "Reviewing recent work",
        detail: "Looking through the latest files, messages, and changes that matter here."
    )
    static let workingFromLatestResults = Self(
        title: "Working from the latest results",
        detail: "Using what I just found to decide the next step."
    )
    static let choosingNextStep = Self(
        title: "Choosing the next step",
        detail: "Deciding whether to inspect code, make changes, or answer directly."
    )
    static let needPermissionToContinue = Self(
        title: "Need permission",
        detail: "Waiting for approval before changing the connected integration."
    )
    static let workingThroughRequest = Self(
        title: "Working through the request",
        detail: "I have the context I need and I am deciding what to do first."
    )
    static let workingFallback = Self(
        title: "Working on it",
        detail: nil
    )

    var normalized: Self? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedDetail, !trimmedDetail.isEmpty {
            return Self(title: trimmedTitle, detail: trimmedDetail)
        }

        return Self(title: trimmedTitle, detail: nil)
    }
}

/// Core UI-facing state container for the 10x App Builder.
/// Behavior is split across focused extensions by domain.
@Observable
@MainActor
final class BuilderViewModel {
    // MARK: - Projects
    var projects: [BuilderProject] = []
    var archivedProjects: [BuilderProject] = []
    var activeProject: BuilderProject?
    var isLoadingProjects = false
    var hasLoadedProjects = false

    // MARK: - Versions
    var versions: [BuilderVersion] = []
    var activeVersion: BuilderVersion?

    // MARK: - File Tree
    var fileTree: [String: String] = [:]
    var fileTreeRevision: Int = 0

    // MARK: - Chat
    var chats: [BuilderChat] = []
    var activeChat: BuilderChat?
    var messages: [BuilderMessage] = []
    var chatItems: [ChatItem] = []
    var dependencyChecklistAnchorMessageId: String?
    var pendingDependencyChecklistAnchor = false
    var pendingAssistantContent = ""
    var isGenerating = false
    var generationStatus: BuilderGenerationStatus?

    var hasStreamingAssistant: Bool {
        isGenerating
            && !pendingAssistantContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentGenerationStatus: BuilderGenerationStatus? {
        if let status = generationStatus?.normalized {
            return status
        }

        if isGenerating && activeSteps.isEmpty && !hasStreamingAssistant {
            return .workingFallback
        }

        return nil
    }

    // MARK: - Tool Steps
    var activeSteps: [BuilderToolStep] = []

    // MARK: - UI State
    var viewMode: ViewMode = .canvas
    var selectedFile: String?
    var buildError: String?
    var pendingEnvironmentIntegrationFocus: ProjectIntegrationID?
    var pendingBackendFocus = false

    // MARK: - Build Fix
    var isAutoFixingBuild = false

    struct BuildIssueDisplayState: Identifiable, Equatable {
        let id: String
        let error: String
        let isFixing: Bool
    }

    // MARK: - Revert
    var isReverting = false
    var pendingInputPrefill: String?
    var pendingAttachmentPrefill: [BuilderMessageAttachment]?
    var pendingRequiredSkillPrefill: [String]?
    var pendingMessageActionPrefill: BuilderMessageAction?
    var pendingAttachmentAppend: [BuilderMessageAttachment]?
    var pendingPreviewViewMentionAppend: [String]?

    // MARK: - Retry
    var lastFailedRequest: QueuedMessage?

    // MARK: - Resume
    var showResumePrompt = false

    // MARK: - Mode
    var mode: ProjectMode = .build

    // MARK: - Plan & Tasks
    var projectPlan: String?
    var projectTasks: String?
    var projectWarnings: [BuilderProjectWarning] = []
    var projectDependencyManifest: ProjectDependencyManifest?
    var projectBackendState: ProjectBackendState = .empty
    var projectSuperwallState: ProjectSuperwallState = .empty

    var hasSupabaseRuntimeIntegration: Bool {
        SupabaseManagementService.projectRef(from: environmentValuesByKey["SUPABASE_URL"]) != nil
    }

    var hasSuperwallRuntimeIntegration: Bool {
        !(environmentValuesByKey["SUPERWALL_PUBLIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || projectSuperwallState.isConfigured
    }

    var hasManagedSupabaseBackend: Bool {
        projectBackendState.providerID == .supabase && projectBackendState.isConfigured
    }

    var activeRoadmapWarnings: [BuilderProjectWarning] {
        BuilderProjectWarning.normalized(
            projectWarnings,
            supportsManagedSupabaseBackend: hasSupabaseRuntimeIntegration || hasManagedSupabaseBackend
        )
    }

    var hasProjectStatusContent: Bool {
        if let projectPlan, !projectPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let projectTasks, !projectTasks.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !activeRoadmapWarnings.isEmpty {
            return true
        }
        return projectDependencyManifest != nil
    }

    var projectStatusState: BuilderProjectStatusState {
        BuilderProjectStatusState(
            plan: projectPlan,
            tasks: projectTasks,
            warnings: activeRoadmapWarnings,
            dependencyManifest: projectDependencyManifest
        )
    }

    var resolvedProjectDependencies: [ProjectDependencyResolution] {
        (projectDependencyManifest?.dependencies ?? []).map {
            $0.resolve(using: environmentVariables, backendState: projectBackendState)
        }
    }

    var dependencyChecklistRows: [ProjectDependencyResolution] {
        resolvedProjectDependencies
    }

    var hasDependencyChecklist: Bool {
        !(projectDependencyManifest?.isEmpty ?? true)
    }

    var requiredIntegrationIDs: Set<ProjectIntegrationID> {
        Set(resolvedProjectDependencies.compactMap(\.requirement.integrationID))
    }

    // MARK: - Design Style & Onboarding
    var designStyle: DesignStyle?
    var onboardingData: OnboardingData?

    // MARK: - Ask User
    var questionQueue: QuestionQueue?
    var integrationApproval: IntegrationApprovalState?

    var hasPendingUserResponse: Bool {
        questionQueue != nil || integrationApproval != nil
    }

    // MARK: - Message Queue
    var messageQueue: [QueuedMessage] = []
    var availableSkills: [SkillRegistryEntry] = []
    var isLoadingSkills = false

    var canManageChats: Bool {
        activeProject != nil && !isGenerating && !hasPendingUserResponse
    }

    /// The latest build/compile issue that should stay visible in the UI, even while
    /// the agent is actively attempting a repair and `buildError` has already been cleared.
    var activeBuildIssue: BuildIssueDisplayState? {
        guard let error = firstNonEmpty([
            buildError,
            latestBuildFixError,
            lastPreviewCompileError,
            latestStoredBuildIssueText,
        ]) else { return nil }

        return BuildIssueDisplayState(
            id: latestBuildFixMessageId(in: messages) ?? "active-build-issue",
            error: error,
            isFixing: isAutoFixingBuild && isGenerating
        )
    }

    var hasRequestedPlanExecution: Bool {
        messages.contains { Self.isUserAuthoredMessage($0) && $0.action == .executePlan }
    }

    // MARK: - Local Project
    var localProjectPath: URL?
    var environmentVariables: [ProjectEnvironmentVariable] = []
    var productionChecklistState: ProductionChecklistState = .empty

    // MARK: - File Explorer
    var showFileExplorer = false
    var showChatSidebar = false
    var showProjectSettings = false

    // MARK: - Simulator Preview
    var previewScreenshot: NSImage?
    var livePreviewScreenshot: NSImage?
    var isPreviewLoading = false
    var previewStatus: String?
    var projectIcon: NSImage?
    var developmentPreviewMode: DevelopmentPreviewMode = .saved
    var previewScreenLibrary: [PreviewScreenCapture] = []
    var capturedScreenLibrary: [PreviewScreenCapture] = []
    var selectedPreviewScreenID: String?
    var selectedCapturedScreenID: String?
    var lastPreviewedFileTreeRevision: Int?
    var appStoreReviewState: AppStoreReviewState = .empty
    var isGeneratingAppStoreReviewAssets = false
    var appStoreReviewStatus: String?
    var appStoreReviewError: String?
    var appStoreSubmissionDraft: AppStoreSubmissionDraft = .empty
    var isGeneratingAppStoreSubmission = false
    var isPublishingAppStoreSubmission = false
    var appStoreSubmissionStatus: String?
    var appStoreSubmissionError: String?

    // MARK: - Persisted Session State
    var generationSnapshots: [ProjectSnapshot] = []
    var contextState: BuilderContextState = .empty

    // MARK: - Collaborators
    var streamTask: Task<Void, Never>?
    let supabase = SupabaseService.shared
    let apiClient = APIClient()
    let contextManager = BuilderContextManager()
    let generationService = GenerationService()
    let skillsManager = SkillsManager()
    let localStore = LocalProjectStore()
    let previewService = XcodePreviewService()
    let simulatorService = SimulatorPreviewService.shared
    let projectImporter = ExistingProjectImporter()

    // MARK: - Ephemeral Runtime State
    var fileWatcher: FileSystemWatcher?
    var sessionAccessToken: String?
    var titleRequestsInFlight: Set<String> = []
    var consecutiveAutomaticBuildFixFailures = 0
    var lastPreviewCompileError: String?
    var latestBuildFixError: String?
    var lastAutomaticBuildFixSignature: String?
    var lastAutomaticBuildFixRevision: Int?
    var activeGenerationRunID = UUID()
    var activePreviewRunID = UUID()
    var suppressIntermediateAssistantText = false
    var persistCurrentRunToolSteps = true
    var cachedReadFiles: [String: String] = [:]
    var cachedReadFileOrder: [String] = []
    var previewScreenCaptureTask: Task<Void, Never>?
    var livePreviewTask: Task<Void, Never>?
    // Runtime-only cache; views read and fill this during rendering.
    @ObservationIgnored var previewScreenImageCache: [String: NSImage] = [:]
    @ObservationIgnored var reviewAssetImageCache: [String: NSImage] = [:]
    @ObservationIgnored var pendingInitialPreviewImage: NSImage?
    var previewScreenCaptureSessionID = UUID()
    var livePreviewSessionID = UUID()
    var previewTrackingMinimumTimestamp: Double = 0
    var lastTrackedViewName: String?
    var lastTrackedTimestamp: Double = 0
    var billingRefreshHandler: (@MainActor (Bool) async -> Void)?
    var currentBillingGroupId: String?
    var currentBillingMessagePreview: String?

    static let automaticBuildFixFailureLimit = 3
    static let maxInlineTextAttachmentTokens = 80_000
    static let viewTrackingPollIntervalSeconds = 1.0
    static let viewSettleDelaySeconds = 0.5
    static let maxPreviewScreenLibraryCount = 50
    static let livePreviewPollIntervalSeconds = 0.8

    enum ViewMode: String {
        case canvas
        case roadmap
        case design
        case development
        case environment
        case backend
        case review
        case production
    }

    enum DevelopmentPreviewMode: String, CaseIterable {
        case saved
        case live

        var label: String {
            switch self {
            case .saved: return "Saved"
            case .live: return "Live"
            }
        }
    }

    enum ChatItem: Identifiable {
        case message(BuilderMessage)
        case systemEvent(BuilderSystemEvent)
        case toolSteps(id: String, steps: [BuilderToolStep])
        case error(id: String, message: String)
        case buildFix(id: String, error: String, resolved: Bool)

        var id: String {
            switch self {
            case .message(let message):
                return message.id
            case .systemEvent(let event):
                return event.id
            case .toolSteps(let id, _):
                return id
            case .error(let id, _):
                return id
            case .buildFix(let id, _, _):
                return id
            }
        }
    }

    struct QuestionQueue: Identifiable {
        let id = UUID()
        let questions: [AskUserQuestion]
        let toolUseId: String
        var currentIndex = 0
        var answers: [String: String] = [:]

        init(
            questions: [AskUserQuestion],
            toolUseId: String,
            currentIndex: Int = 0,
            answers: [String: String] = [:]
        ) {
            self.questions = questions
            self.toolUseId = toolUseId
            self.currentIndex = currentIndex
            self.answers = answers
        }

        var currentQuestion: AskUserQuestion? {
            currentIndex < questions.count ? questions[currentIndex] : nil
        }

        var isComplete: Bool { currentIndex >= questions.count }
        var totalCount: Int { questions.count }

        init(persisted state: PersistedQuestionQueue) {
            self.init(
                questions: state.questions,
                toolUseId: state.toolUseId,
                currentIndex: state.currentIndex,
                answers: state.answers
            )
        }

        var persistedState: PersistedQuestionQueue {
            PersistedQuestionQueue(
                questions: questions,
                toolUseId: toolUseId,
                currentIndex: currentIndex,
                answers: answers
            )
        }
    }

    struct IntegrationApprovalState: Identifiable {
        let request: IntegrationApprovalRequest
        let toolUseId: String

        var id: String {
            "\(toolUseId)-\(request.integration)-\(request.scope)"
        }

        init(request: IntegrationApprovalRequest, toolUseId: String) {
            self.request = request
            self.toolUseId = toolUseId
        }

        init(persisted state: PersistedIntegrationApproval) {
            self.init(request: state.request, toolUseId: state.toolUseId)
        }

        var persistedState: PersistedIntegrationApproval {
            PersistedIntegrationApproval(
                request: request,
                toolUseId: toolUseId
            )
        }
    }

    struct RestartContinuation {
        let note: String
        let event: BuilderSystemEvent
    }

    struct QueuedMessage: Identifiable {
        let id = UUID()
        var text: String
        var attachments: [BuilderMessageAttachment]
        var requiredSkillNames: [String]
        var action: BuilderMessageAction?
        var mode: ProjectMode
    }

    struct ChatTitleResponse: Decodable {
        let title: String
    }
}

extension BuilderViewModel {
    var activeWorkspaceDescriptor: ProjectWorkspaceDescriptor? {
        activeProject.map { $0.workspaceDescriptor }
    }

    func workspaceRootURL(projectRoot: URL? = nil) -> URL? {
        guard let descriptor = activeWorkspaceDescriptor else { return nil }
        guard let root = projectRoot ?? localProjectPath else { return nil }
        return descriptor.workspaceRootURL(projectRoot: root)
    }

    func xcodeContainerURL(projectRoot: URL? = nil) -> URL? {
        guard let descriptor = activeWorkspaceDescriptor else { return nil }
        guard let root = projectRoot ?? localProjectPath else { return nil }
        return descriptor.xcodeContainerURL(projectRoot: root)
    }
}
