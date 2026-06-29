import SwiftUI
import AppKit

// MARK: - Traffic Light Positioner

/// Repositions the window's traffic light buttons (close/minimize/zoom)
/// so they vertically center within our custom tab bar.
private struct TrafficLightPositioner: NSViewRepresentable {
    let barHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.repositionButtons(in: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.repositionButtons(in: nsView.window) }
    }

    private func repositionButtons(in window: NSWindow?) {
        guard let window else { return }
        guard let close = window.standardWindowButton(.closeButton) else { return }
        let buttonHeight = close.frame.height
        // Center buttons vertically within the tab bar
        let targetY = (barHeight - buttonHeight) / 2.0

        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            // The buttons live in a titlebar container — adjust relative to their superview
            if let superview = button.superview {
                let superHeight = superview.frame.height
                let currentCenterY = button.frame.origin.y + buttonHeight / 2.0
                let wantedCenterY = superHeight - targetY - buttonHeight / 2.0
                let dy = wantedCenterY - currentCenterY
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: button.frame.origin.y + dy))
            }
        }
    }
}

private enum TabBarPalette {
    static let barBackground = Theme.surfaceInset
    static let tabInactive = Theme.surfaceInset
    static let tabActive = Theme.surface
    static let border = Theme.separator
    static let accent = Theme.accent
    static let textPrimary = Theme.textPrimary
    static let textSecondary = Theme.textSecondary
    static let iconInactive = Theme.textSecondary
    static let homeIcon = Theme.textSecondary
    static let segmentHeight: CGFloat = 36
    static let popoverOffset: CGFloat = 10
}

// MARK: - Helpers

extension ContentView {
    private func preloadPreview(for tab: AppTab, project: BuilderProject, viewModel: BuilderViewModel) {
        Task.detached(priority: .background) {
            let image = self.localStore.loadThumbnail(projectName: project.name, projectId: project.id)
            if let image {
                await MainActor.run {
                    viewModel.previewScreenshot = image
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct TabProjectIcon: View {
    let isActive: Bool
    let isBusy: Bool
    let icon: NSImage?

    var body: some View {
        Group {
            if isBusy {
                TabBusySpinner(isActive: isActive)
            } else if let icon {
                TabProjectImageIcon(image: icon, isActive: isActive)
            } else {
                TabSeedIcon(isActive: isActive)
            }
        }
        .frame(width: 14, height: 14)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isBusy)
    }
}

private struct TabProjectImageIcon: View {
    let image: NSImage
    let isActive: Bool

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(isActive ? TabBarPalette.accent.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

private struct TabSeedIcon: View {
    let isActive: Bool

    var body: some View {
        let color = isActive ? TabBarPalette.accent : TabBarPalette.iconInactive

        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color.opacity(isActive ? 0.12 : 0.08))
            .overlay(
                Image(systemName: "app.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 0.5)
            )
    }
}

private struct TabBusySpinner: View {
    let isActive: Bool
    @State private var rotation: Double = 0

    var body: some View {
        let color = isActive ? TabBarPalette.accent : TabBarPalette.iconInactive

        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            .onDisappear { rotation = 0 }
    }
}

struct ContentView: View {
    private static let openTabsPreferenceKey = "\(AppIdentity.preferencesNamespace).openTabs"
    private static let activeTabPreferenceKey = "\(AppIdentity.preferencesNamespace).activeTabId"

    @Environment(AuthManager.self) private var auth

    @State private var tabs: [AppTab] = []
    @State private var activeTabId: String?  // nil = home screen
    @State private var tabViewModels: [String: BuilderViewModel] = [:]
    @State private var homeViewModel = BuilderViewModel()
    @State private var selectedSettingsSection: SettingsSection = .general
    @State private var hasRestoredTabs = false
    private let localStore = LocalProjectStore()

    private var isHome: Bool { activeTabId == nil }

    var body: some View {
        VStack(spacing: 0) {
            topNavigationBar
                .zIndex(2)

            ZStack {
                HomeView(
                    onOpenProject: openProject,
                    onArchiveProject: archiveProject,
                    onUnarchiveProject: unarchiveProject,
                    onDeleteProject: permanentlyDeleteProject
                )
                    .environment(homeViewModel)
                    .opacity(isHome ? 1 : 0)
                    .allowsHitTesting(isHome)

                ForEach(tabs) { tab in
                    if tab.kind == .account || tabViewModels[tab.id] != nil {
                        tabContent(for: tab, vm: tabViewModels[tab.id])
                            .opacity(tab.id == activeTabId ? 1 : 0)
                            .allowsHitTesting(tab.id == activeTabId)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(TrafficLightPositioner(barHeight: TabBarPalette.segmentHeight))
        .task(id: auth.accessToken) {
            guard let token = await auth.validAccessToken() else {
                syncSessionAccessTokens(nil)
                tabs = []
                tabViewModels = [:]
                activeTabId = nil
                hasRestoredTabs = false
                return
            }

            syncSessionAccessTokens(token)

            Task.detached(priority: .utility) {
                await SimulatorPreviewService.shared.prewarmOnAppLaunchIfNeeded()
            }

            let needsTabRestore = !hasRestoredTabs
            if needsTabRestore {
                hasRestoredTabs = true
            }

            await homeViewModel.loadProjects(accessToken: token)

            if needsTabRestore {
                restoreTabs(accessToken: token)
            }


        }
        .onChange(of: tabs) {
            saveTabs()
        }
        .onChange(of: activeTabId) {
            saveTabs()
        }


    }

    // MARK: - Per-tab ViewModel (created eagerly, read-only during body)

    /// Creates a new VM for a tab. Call this when adding a tab, NOT during body.
    @discardableResult
    private func createViewModel(for tabId: String) -> BuilderViewModel {
        let vm = BuilderViewModel()
        vm.projects = homeViewModel.projects
        vm.archivedProjects = homeViewModel.archivedProjects
        vm.billingRefreshHandler = { _ in }
        tabViewModels[tabId] = vm
        return vm
    }

    private func syncSessionAccessTokens(_ accessToken: String?) {
        homeViewModel.syncSessionAccessToken(accessToken)
        for (_, vm) in tabViewModels {
            vm.syncSessionAccessToken(accessToken)
        }
    }

    private func syncProjectsToAll() {
        for (_, vm) in tabViewModels {
            vm.projects = homeViewModel.projects
            vm.archivedProjects = homeViewModel.archivedProjects
        }
    }

    // MARK: - Tab bar

    private var topNavigationBar: some View {
        ZStack(alignment: .leading) {
            TabBarPalette.barBackground

            HStack(spacing: 0) {
                // Spacer for traffic light buttons
                Color.clear
                    .frame(width: 82)

                tabStrip
                    .frame(maxWidth: .infinity, alignment: .leading)

                profileButton
            }
            .padding(.trailing, 16)
        }
        .frame(height: TabBarPalette.segmentHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1.0 / (NSScreen.main?.backingScaleFactor ?? 2.0))
        }
    }

    private var tabStrip: some View {
        HStack(spacing: -1) {
            homeTab
            ForEach(tabs.filter { $0.kind == .project }) { tab in
                appTab(tab, viewModel: tabViewModels[tab.id])
            }
        }
    }

    private var homeTab: some View {
        let isActive = activeTabId == nil

        return Button {
            activeTabId = nil
        } label: {
            Image("10XbuilderLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 16)
                .foregroundStyle(isActive ? TabBarPalette.accent : TabBarPalette.homeIcon)
                .frame(width: 26, height: 22)
                .padding(.horizontal, 11)
                .frame(height: TabBarPalette.segmentHeight)
                .background(isActive ? TabBarPalette.tabActive : TabBarPalette.tabInactive)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(TabBarPalette.border)
                        .frame(width: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func appTab(_ tab: AppTab, viewModel: BuilderViewModel?) -> some View {
        switch tab.kind {
        case .project:
            return AnyView(projectTab(tab, viewModel: viewModel))
        case .account:
            return AnyView(utilityTab(tab))
        }
    }

    private func projectTab(_ tab: AppTab, viewModel: BuilderViewModel?) -> some View {
        let isActive = tab.id == activeTabId
        let isBusy = viewModel?.isGenerating == true

        return HStack(spacing: 6) {
            Button {
                activeTabId = tab.id
            } label: {
                HStack(spacing: 8) {
                    TabProjectIcon(isActive: isActive, isBusy: isBusy, icon: viewModel?.projectIcon)

                    Text(tab.label)
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(isActive ? TabBarPalette.textPrimary : TabBarPalette.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            closeTabButton {
                closeTab(tab)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: TabBarPalette.segmentHeight)
        .background(isActive ? TabBarPalette.tabActive : TabBarPalette.tabInactive)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TabBarPalette.border)
                .frame(width: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TabBarPalette.border)
                .frame(width: 1)
        }
    }

    private func utilityTab(_ tab: AppTab) -> some View {
        let isActive = tab.id == activeTabId

        return HStack(spacing: 6) {
            Button {
                activeTabId = tab.id
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? TabBarPalette.accent : TabBarPalette.iconInactive)

                    Text(tab.label)
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(isActive ? TabBarPalette.textPrimary : TabBarPalette.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            closeTabButton {
                closeTab(tab)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: TabBarPalette.segmentHeight)
        .background(isActive ? TabBarPalette.tabActive : TabBarPalette.tabInactive)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(TabBarPalette.border)
                .frame(width: 1)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TabBarPalette.border)
                .frame(width: 1)
        }
    }

    private func closeTabButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(TabBarPalette.iconInactive)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var profileButton: some View {
        let isActive = tabs.first(where: { $0.kind == .account })?.id == activeTabId && activeTabId != nil

        return Button {
            openAccountTab()
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? TabBarPalette.accent : TabBarPalette.homeIcon)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
    }



    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(for tab: AppTab, vm: BuilderViewModel?) -> some View {
        Group {
            switch tab.kind {
            case .project:
                if let vm {
                    BuilderView()
                        .environment(vm)
                }
            case .account:
                SettingsView(selectedSection: $selectedSettingsSection)
            }
        }
        .onChange(of: vm?.activeProject?.name) { _, newName in
            guard tab.kind == .project,
                  let name = newName,
                  let idx = tabs.firstIndex(where: { $0.id == tab.id }),
                  let vm
            else { return }
            tabs[idx].label = name
            homeViewModel.projects = vm.projects
            homeViewModel.archivedProjects = vm.archivedProjects
            syncProjectsToAll()
        }
        .onChange(of: vm?.projects.count) { _, _ in
            guard tab.kind == .project, let vm else { return }
            homeViewModel.projects = vm.projects
            homeViewModel.archivedProjects = vm.archivedProjects
            syncProjectsToAll()
        }
        .onChange(of: vm?.archivedProjects.count) { _, _ in
            guard tab.kind == .project, let vm else { return }
            homeViewModel.projects = vm.projects
            homeViewModel.archivedProjects = vm.archivedProjects
            syncProjectsToAll()
        }
    }

    // MARK: - Actions

    private func openProject(
        _ project: BuilderProject,
        initialMessage: String? = nil,
        designStyle: DesignStyle? = nil,
        onboardingData: OnboardingData? = nil,
        attachments: [BuilderMessageAttachment] = []
    ) {
        if let existing = tabs.first(where: { $0.projectId == project.id }) {
            activeTabId = existing.id
            return
        }

        let tab = AppTab.project(name: project.name, projectId: project.id)
        let vm = createViewModel(for: tab.id)
        tabs.append(tab)
        activeTabId = tab.id

        vm.designStyle = designStyle
        vm.onboardingData = onboardingData
        preloadPreview(for: tab, project: project, viewModel: vm)

        Task { @MainActor in
            guard let token = await auth.validAccessToken() else { return }
            vm.selectProject(project, accessToken: token)

            if let message = initialMessage, !message.isEmpty || !attachments.isEmpty {
                vm.mode = .plan
                try? await Task.sleep(for: .milliseconds(300))
                _ = vm.sendMessage(message, attachments: attachments, accessToken: token)
            }
        }
    }

    private func openAccountTab(select section: SettingsSection? = nil) {
        if let section {
            selectedSettingsSection = section
        }
        if let existing = tabs.first(where: { $0.kind == .account }) {
            activeTabId = existing.id
            return
        }

        let tab = AppTab.account()
        tabs.append(tab)
        activeTabId = tab.id
    }

    // MARK: - Tab Persistence

    private func saveTabs() {
        guard hasRestoredTabs else { return }  // Don't save during initial restore
        let persistentTabs = tabs
        if let data = try? JSONEncoder().encode(persistentTabs) {
            UserDefaults.standard.set(data, forKey: Self.openTabsPreferenceKey)
        }
        UserDefaults.standard.set(activeTabId, forKey: Self.activeTabPreferenceKey)
    }

    private func restoreTabs(accessToken: String) {
        guard let data = UserDefaults.standard.data(forKey: Self.openTabsPreferenceKey),
              let savedTabs = try? JSONDecoder().decode([AppTab].self, from: data) else {
            return
        }

        for tab in savedTabs {
            guard !tabs.contains(where: { restoredTabMatches($0, tab) }) else {
                continue
            }

            switch tab.kind {
            case .project:
                guard let projectId = tab.projectId,
                      let project = homeViewModel.projects.first(where: { $0.id == projectId }) else {
                    continue
                }
                let vm = createViewModel(for: tab.id)
                tabs.append(tab)
                vm.selectProject(project, accessToken: accessToken)
                preloadPreview(for: tab, project: project, viewModel: vm)
            case .account:
                tabs.append(tab)
            }
        }

        // Always start on the home screen
        activeTabId = nil
    }

    private func restoredTabMatches(_ lhs: AppTab, _ rhs: AppTab) -> Bool {
        switch (lhs.kind, rhs.kind) {
        case (.project, .project):
            guard let lhsProjectId = lhs.projectId, let rhsProjectId = rhs.projectId else {
                return false
            }
            return lhsProjectId == rhsProjectId
        case (.account, .account):
            return true
        default:
            return false
        }
    }

    private func archiveProject(_ project: BuilderProject) {
        removeTabs(for: project)
        syncProjectsToAll()
    }

    private func unarchiveProject(_ project: BuilderProject) {
        if let restoredProject = homeViewModel.projects.first(where: { $0.id == project.id }) {
            for (_, vm) in tabViewModels where vm.activeProject?.id == restoredProject.id {
                vm.activeProject = restoredProject
            }
        }
        syncProjectsToAll()
    }

    private func permanentlyDeleteProject(_ project: BuilderProject) {
        removeTabs(for: project)
        syncProjectsToAll()
    }

    private func removeTabs(for project: BuilderProject) {
        for tab in tabs where tab.projectId == project.id {
            closeTab(tab)
        }
    }

    private func closeTab(_ tab: AppTab) {
        if let idx = tabs.firstIndex(of: tab) {
            tabViewModels.removeValue(forKey: tab.id)
            tabs.remove(at: idx)
            if activeTabId == tab.id {
                if tabs.isEmpty {
                    activeTabId = nil
                } else {
                    let newIdx = min(idx, tabs.count - 1)
                    activeTabId = tabs[newIdx].id
                }
            }
        }
    }
}
