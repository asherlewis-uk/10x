import Combine
import SwiftUI
#if SWIFT_PACKAGE
@testable import TenXAppCore
#endif

enum SparklePromptStage: Equatable {
    case available
    case downloaded
    case installing
}

struct SparkleAvailableUpdatePrompt: Identifiable, Equatable {
    let versionString: String
    let displayVersionString: String
    let title: String
    let releaseNotesURL: URL?
    let stage: SparklePromptStage

    var id: String {
        versionString
    }

    var heading: String {
        switch stage {
        case .available:
            return "Update Available"
        case .downloaded:
            return "Update Ready"
        case .installing:
            return "Installing Update"
        }
    }

    var message: String {
        switch stage {
        case .available:
            return "A new 10x build is available. Update now to download and install the latest release."
        case .downloaded:
            return "The latest 10x build has already been downloaded. Update now to install it and relaunch."
        case .installing:
            return "10x is finishing an update in the background. Bringing the updater into focus will complete the install flow."
        }
    }

    var primaryActionTitle: String {
        switch stage {
        case .available:
            return "Update Now"
        case .downloaded:
            return "Install Now"
        case .installing:
            return "Open Updater"
        }
    }
}

#if canImport(Sparkle)
import AppKit
import Sparkle

@MainActor
@Observable
final class SparkleUpdaterCoordinator: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var availableUpdatePrompt: SparkleAvailableUpdatePrompt?

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController!
    @ObservationIgnored private var hasActivated = false
    @ObservationIgnored private var launchProbeInProgress = false
    @ObservationIgnored private var suppressedVersionThisLaunch: String?

    override init() {
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func activate() {
        guard !hasActivated else { return }
        hasActivated = true

        updaterController.startUpdater()

        guard updater.automaticallyChecksForUpdates else { return }

        launchProbeInProgress = true
        updater.checkForUpdateInformation()
    }

    func checkForUpdates() {
        activate()

        if let version = availableUpdatePrompt?.versionString {
            suppressedVersionThisLaunch = version
        }
        availableUpdatePrompt = nil

        DispatchQueue.main.async { [weak self] in
            self?.updater.checkForUpdates()
        }
    }

    func dismissPromptForLater() {
        if let version = availableUpdatePrompt?.versionString {
            suppressedVersionThisLaunch = version
        }
        availableUpdatePrompt = nil
    }

    func openReleaseNotes() {
        guard let url = availableUpdatePrompt?.releaseNotesURL else { return }
        NSWorkspace.shared.open(url)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        AppUpdateChannel.preferredChannel().sparkleAllowedChannels
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard launchProbeInProgress else { return }
        presentPrompt(for: item, state: nil)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard launchProbeInProgress else { return }
        launchProbeInProgress = false
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        guard launchProbeInProgress else { return }
        launchProbeInProgress = false
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if launchProbeInProgress {
            launchProbeInProgress = false
        }
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        presentPrompt(for: update, state: state)
    }

    private func presentPrompt(for item: SUAppcastItem, state: SPUUserUpdateState?) {
        let prompt = SparkleAvailableUpdatePrompt(
            versionString: item.versionString,
            displayVersionString: item.displayVersionString,
            title: item.title ?? "10x \(item.displayVersionString)",
            releaseNotesURL: browserReleaseNotesURL(from: item.releaseNotesURL ?? item.fullReleaseNotesURL),
            stage: promptStage(from: state)
        )

        guard suppressedVersionThisLaunch != prompt.versionString else { return }

        if let currentPrompt = availableUpdatePrompt, currentPrompt.versionString == prompt.versionString {
            if currentPrompt != prompt {
                availableUpdatePrompt = prompt
            }
            return
        }

        availableUpdatePrompt = prompt
    }

    private func promptStage(from state: SPUUserUpdateState?) -> SparklePromptStage {
        guard let state else { return .available }

        switch state.stage {
        case .downloaded:
            return .downloaded
        case .installing:
            return .installing
        default:
            return .available
        }
    }

    private func browserReleaseNotesURL(from url: URL?) -> URL? {
        AppUpdateChannel.browserReleaseNotesURL(from: url)
    }
}
#else
@MainActor
@Observable
final class SparkleUpdaterCoordinator {
    private(set) var availableUpdatePrompt: SparkleAvailableUpdatePrompt?

    func activate() {}
    func checkForUpdates() {}
    func dismissPromptForLater() {
        availableUpdatePrompt = nil
    }
    func openReleaseNotes() {}
}
#endif

struct CheckForUpdatesView: View {
    #if canImport(Sparkle)
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updaterCoordinator: SparkleUpdaterCoordinator

    init(updaterCoordinator: SparkleUpdaterCoordinator) {
        self.updaterCoordinator = updaterCoordinator
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updaterCoordinator.updater))
    }
    #endif

    var body: some View {
        #if canImport(Sparkle)
        Button("Check for Updates…") {
            updaterCoordinator.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
        #else
        EmptyView()
        #endif
    }
}

#if canImport(Sparkle)
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
}
#endif

struct SparkleUpdatePromptView: View {
    let prompt: SparkleAvailableUpdatePrompt
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
    let releaseNotesAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXL) {
            VStack(alignment: .leading, spacing: Theme.spacingMD) {
                Text(prompt.heading)
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)

                Text(prompt.message)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                Text(prompt.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text("Version \(prompt.displayVersionString)")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingSM)
                    .background(
                        Capsule()
                            .fill(Theme.accentLight)
                    )
            }

            HStack(spacing: Theme.spacingMD) {
                if let releaseNotesAction {
                    Button("Release Notes", action: releaseNotesAction)
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: Theme.spacingLG)

                Button("Later", action: secondaryAction)
                    .buttonStyle(.bordered)

                Button(prompt.primaryActionTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.spacingXXL)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXL, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
    }
}
