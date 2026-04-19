import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreviewPanelView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth

    private var panelBackground: Color {
        Theme.surfaceInset
    }

    private var buildIssueFixAction: (() -> Void)? {
        guard auth.isAuthenticated else { return nil }
        return {
            Task { @MainActor in
                guard let token = await auth.validAccessToken() else { return }
                viewModel.fixBuildError(accessToken: token)
            }
        }
    }

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Tab bar + actions row
            ChromeTabStrip(
                selection: $vm.viewMode,
                showsEnvironmentSetupWarning: viewModel.resolvedProjectDependencies.contains {
                    $0.requirement.integrationID != nil && !$0.isResolved
                },
                showsBackendSetupWarning: viewModel.resolvedProjectDependencies.contains {
                    $0.requirement.setupSurface == .backend && !$0.isResolved
                }
            ) {
                // Preview + dropdown pill
                HStack(spacing: 0) {
                    Button {
                        Task { await viewModel.runSimulatorPreview() }
                    } label: {
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "eye")
                                .font(.system(size: 12, weight: .medium))
                                .frame(height: 14)
                            Text("Preview")
                                .font(Theme.geist(12, weight: .regular))
                                .baselineOffset(-0.5)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.fileTree.isEmpty || viewModel.isPreviewLoading)

                    // Vertical divider
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 14)

                    Menu {
                        Button {
                            Task { await viewModel.openInXcode() }
                        } label: {
                            Label("Open in Xcode", systemImage: "hammer")
                        }
                        .disabled(viewModel.fileTree.isEmpty)

                        Button {
                            if let path = viewModel.localProjectPath {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                            }
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                        }
                        .disabled(viewModel.localProjectPath == nil)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 24)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .tint(.white)
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))

                if let project = viewModel.activeProject {
                    Button {
                        viewModel.showProjectSettings = true
                    } label: {
                        ProjectIconArtwork(
                            image: viewModel.projectIcon,
                            projectName: project.name,
                            size: 24
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Project Settings")
                    .fixedSize()
                }
            }

            // Content
            ZStack(alignment: .top) {
                switch viewModel.viewMode {
                case .roadmap:
                    RoadmapView()
                case .canvas:
                    CanvasGridView()
                case .design:
                    DesignView()
                case .development:
                    LivePreviewView()
                case .environment:
                    EnvironmentVariablesView()
                case .backend:
                    BackendView()
                case .review:
                    ReviewView()
                case .production:
                    ProductionView()
                }
            }
        }
        .background(panelBackground)
        .overlay(alignment: .bottom) {
            if let buildIssue = viewModel.activeBuildIssue {
                ProjectBuildIssueBar(
                    buildIssue: buildIssue,
                    fixAction: buildIssueFixAction
                )
                .padding(.horizontal, Theme.spacingLG)
                .padding(.bottom, Theme.spacingLG)
            }
        }
        .sheet(isPresented: Bindable(vm).showProjectSettings) {
            if let project = viewModel.activeProject {
                ProjectSettingsSheet(project: project, currentIcon: viewModel.projectIcon)
                    .environment(viewModel)
            }
        }
    }
}

private struct ProjectBuildIssueBar: View {
    let buildIssue: BuilderViewModel.BuildIssueDisplayState
    let fixAction: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.spacingMD) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.error)

            VStack(alignment: .leading, spacing: 2) {
                Text(buildIssue.isFixing ? "Fixing build error" : "Build error")
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.error)

                Text(buildIssue.error)
                    .font(Theme.geistMono(11))
                    .foregroundStyle(Theme.error.opacity(0.92))
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            if buildIssue.isFixing {
                HStack(spacing: 6) {
                    TypingDotsView(color: Theme.error, dotSize: 4)
                    Text("Fixing…")
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(Theme.error)
                }
            } else if let fixAction {
                Button("Fix with AI") {
                    fixAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Theme.error)
            }
        }
        .padding(Theme.spacingMD)
        .tenXGlassRect(cornerRadius: Theme.radiusMD, tint: Theme.error.opacity(0.16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

// MARK: - Chrome/Figma Tab Strip

/// A tab bar that mimics Chrome/Figma: gray strip background, active tab is white
/// with rounded top corners and bleeds into the content area below (no border under it).
private struct ChromeTabStrip<Actions: View>: View {
    @Binding var selection: BuilderViewModel.ViewMode
    let showsEnvironmentSetupWarning: Bool
    let showsBackendSetupWarning: Bool
    @ViewBuilder let actions: () -> Actions

    private static var barColor: Color {
        Color(nsColor: .separatorColor).opacity(0.12)
    }

    private var tabs: [(mode: BuilderViewModel.ViewMode, title: String, icon: String)] {
        [
            (.canvas, "Canvas", "square.grid.2x2"),
            (.roadmap, "Roadmap", "map"),
            (.design, "Design", "paintbrush"),
            (.development, "Development", "hammer"),
            (.environment, "Integrations", "link"),
            (.backend, "Backend", "server.rack"),
            (.review, "App Store", "sparkles.rectangle.stack"),
            (.production, "Production", "shippingbox"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs, id: \.mode) { tab in
                            tabButton(tab.mode, title: tab.title, icon: tab.icon)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, Theme.spacingMD)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Actions area
                HStack(alignment: .center, spacing: Theme.spacingSM) {
                    actions()
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Theme.spacingMD)
                .layoutPriority(1)
            }
            .frame(height: 40)
            .background(Self.barColor)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    private func tabButton(_ mode: BuilderViewModel.ViewMode, title: String, icon: String) -> some View {
        let isActive = selection == mode

        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selection = mode
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(height: 14)

                ZStack(alignment: .leading) {
                    Text(title)
                        .font(Theme.geist(12, weight: .medium))
                        .baselineOffset(-0.5)
                        .lineLimit(1)
                        .hidden()

                    Text(title)
                        .font(Theme.geist(12, weight: isActive ? .medium : .regular))
                        .baselineOffset(-0.5)
                        .lineLimit(1)
                }

                if mode == .environment, showsEnvironmentSetupWarning {
                    Circle()
                        .fill(Theme.warning)
                        .frame(width: 7, height: 7)
                        .help("Finish required integration setup")
                }

                if mode == .backend, showsBackendSetupWarning {
                    Circle()
                        .fill(Theme.warning)
                        .frame(width: 7, height: 7)
                        .help("Finish required backend setup")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? Color(nsColor: NSColor(name: nil) { appearance in
                        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                            ? NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)  // #2A2A2A
                            : NSColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)     // #E0E0E0
                    }) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectIconArtwork: View {
    let image: NSImage?
    let projectName: String
    var size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .accessibilityLabel("\(projectName) icon")
    }
}

private struct ProjectSettingsSheet: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let project: BuilderProject

    @State private var draftName: String
    @State private var draftIcon: NSImage?
    @State private var isSaving = false

    init(project: BuilderProject, currentIcon: NSImage?) {
        self.project = project
        _draftName = State(initialValue: project.name)
        _draftIcon = State(initialValue: currentIcon)
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                ProjectIconArtwork(image: draftIcon, projectName: trimmedName.isEmpty ? project.name : trimmedName, size: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Settings")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Update the project name and choose a custom icon.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Project Name")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("Project name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Icon")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 10) {
                    Button("Choose Image") {
                        pickIcon()
                    }

                    if draftIcon != nil {
                        Button("Remove Icon", role: .destructive) {
                            draftIcon = nil
                        }
                    }
                }
                .buttonStyle(.bordered)

                Text("PNG, JPEG, and other standard image formats are supported.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 440, height: 320)
    }

    private func pickIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }

        draftIcon = image
    }

    private func save() {
        let icon = draftIcon
        let name = trimmedName

        isSaving = true
        Task {
            await viewModel.updateProjectDetails(project, newName: name, customIcon: icon)
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}
