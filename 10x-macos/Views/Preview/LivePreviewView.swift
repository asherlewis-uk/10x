import SwiftUI

struct LivePreviewView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @State private var captureNameDraft = ""
    @State private var captureFeedback: String?
    @State private var captureFeedbackToken = UUID()
    @State private var isRenamingCapture = false
    @State private var isManagingScreens = false
    private let previewBannerSlotHeight: CGFloat = 48
    private let developmentLibraryHeight: CGFloat = 404
    private let previewPlaceholderAspectRatio: CGFloat = 390.0 / 844.0
    private var developmentModeOptions: [PreviewModeSwitcherOption<BuilderViewModel.DevelopmentPreviewMode>] {
        BuilderViewModel.DevelopmentPreviewMode.allCases.map { mode in
            PreviewModeSwitcherOption(
                value: mode,
                title: mode.label,
                iconName: mode == .live ? "dot.radiowaves.left.and.right" : "photo.on.rectangle"
            )
        }
    }

    private var displayedScreenshot: NSImage? {
        if viewModel.developmentPreviewMode == .live {
            return viewModel.livePreviewScreenshot ?? viewModel.previewScreenshot
        }
        if let selected = viewModel.selectedDevelopmentScreen,
           let image = viewModel.previewScreenImage(for: selected) {
            return image
        }
        return viewModel.previewScreenshot
    }

    private var selectedEditableCapture: PreviewScreenCapture? {
        viewModel.developmentPreviewMode == .saved ? viewModel.selectedCapturedScreen : nil
    }

    private var selectedDraggableCapture: PreviewScreenCapture? {
        guard viewModel.developmentPreviewMode == .saved else { return nil }
        return viewModel.selectedDevelopmentScreen
    }

    private var previewTitle: String {
        if let capture = selectedEditableCapture {
            return viewModel.capturedScreenName(for: capture)
        }
        if let capture = viewModel.selectedPreviewScreen {
            return capture.displayName
        }
        let liveName = viewModel.lastTrackedViewName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return liveName.isEmpty ? (viewModel.developmentPreviewMode == .live ? "Live Simulator" : "Latest Preview") : liveName
    }

    var body: some View {
        HSplitView {
            previewWorkspace
                .frame(minWidth: 420, maxWidth: .infinity)
                .layoutPriority(1)

            ProjectBrowserView()
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: syncCaptureNameDraft)
        .onChange(of: viewModel.selectedCapturedScreenID) { oldValue, _ in
            commitCaptureNameDraft(for: oldValue)
            syncCaptureNameDraft()
        }
        .onChange(of: viewModel.developmentPreviewMode) { oldValue, _ in
            if oldValue == .saved {
                commitCaptureNameDraft(for: viewModel.selectedCapturedScreenID)
            }
            syncCaptureNameDraft()
        }
        .onDisappear {
            commitCaptureNameDraft(for: viewModel.selectedCapturedScreenID)
        }
        .sheet(isPresented: $isManagingScreens) {
            manageScreensSheet
        }
    }

    private var previewWorkspace: some View {
        VStack(spacing: 0) {
            if !viewModel.fileTree.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview is view-only right now.")
                        .font(Theme.geist(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Theme.spacingMD) {
                        developmentModePicker
                        if let captureFeedback {
                            Label(captureFeedback, systemImage: "checkmark.circle.fill")
                                .font(Theme.geist(11, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Theme.spacingLG)
                .padding(.horizontal, Theme.spacingXL)
            }

            ZStack {
                if viewModel.isPreviewLoading {
                    previewRefreshingBanner
                }
            }
            .frame(height: previewBannerSlotHeight)

            ZStack {
                if viewModel.fileTree.isEmpty {
                    emptyState
                } else if let screenshot = displayedScreenshot {
                    simulatorPreview(screenshot)
                } else if viewModel.isPreviewLoading {
                    loadingPreviewState
                } else {
                    filesReadyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "iphone")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)

            Text("No preview yet")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)

            Text("Send a message to start building your iOS app")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Simulator Preview

    private func simulatorPreview(_ screenshot: NSImage) -> some View {
        GeometryReader { geo in
            previewCanvas(in: geo) { metrics in
                let previewImage = Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusXL))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusXL)
                            .stroke(
                                viewModel.developmentPreviewMode == .live
                                    ? Theme.accent
                                    : Color(nsColor: .separatorColor).opacity(0.22),
                                lineWidth: viewModel.developmentPreviewMode == .live ? 3 : 1
                            )
                    )
                    .shadow(
                        color: viewModel.developmentPreviewMode == .live
                            ? Theme.accent.opacity(0.18)
                            : .black.opacity(0.15),
                        radius: 22,
                        y: 8
                    )
                    .frame(
                        maxWidth: metrics.maxPreviewWidth,
                        maxHeight: metrics.maxPreviewHeight,
                        alignment: .center
                    )

                if let capture = selectedDraggableCapture {
                    previewImage.onDrag {
                        viewModel.previewScreenItemProvider(for: capture)
                    }
                } else {
                    previewImage
                }
            } footer: {
                previewTitleView
            }
        }
    }

    private var loadingPreviewState: some View {
        GeometryReader { geo in
            previewCanvas(in: geo) { metrics in
                RoundedRectangle(cornerRadius: Theme.radiusXL)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        VStack(spacing: Theme.spacingMD) {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(Theme.textTertiary)

                            Text(viewModel.previewStatus ?? "Refreshing preview...")
                                .font(Theme.geist(14, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(Theme.spacingXL)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusXL)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
                    .aspectRatio(previewPlaceholderAspectRatio, contentMode: .fit)
                    .frame(
                        maxWidth: metrics.maxPreviewWidth,
                        maxHeight: metrics.maxPreviewHeight,
                        alignment: .center
                    )
            } footer: {
                Text("Refreshing simulator preview")
                    .font(Theme.geist(14, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Files Ready (no preview yet)

    private var filesReadyState: some View {
        VStack(spacing: Theme.spacingXL) {
            Spacer()

            Image(systemName: "iphone.gen3")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary)

            Text("\(viewModel.fileTree.count) files generated")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)

            Button {
                Task { await viewModel.runSimulatorPreview() }
            } label: {
                Label("Preview on Simulator", systemImage: "play.fill")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isPreviewLoading)

            HStack(spacing: Theme.spacingSM) {
                Button {
                    Task { await viewModel.openInXcode() }
                } label: {
                    Label("Open in Xcode", systemImage: "arrow.up.forward.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let path = viewModel.localProjectPath {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Local path indicator
            if let path = viewModel.localProjectPath {
                Text(path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            // File list
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                ForEach(viewModel.fileTree.keys.sorted(), id: \.self) { path in
                    HStack(spacing: 6) {
                        Image(systemName: path.hasSuffix(".swift") ? "swift" : "doc.text")
                            .font(.caption2)
                            .foregroundStyle(path.hasSuffix(".swift") ? Theme.accent : .secondary)
                        Text(fileName(from: path))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 280)

            if !viewModel.developmentScreenLibrary.isEmpty {
                developmentScreensSection
                    .frame(maxWidth: 720)
            }

            Spacer()
        }
    }

    private var developmentScreensSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            screenSection(
                title: "Views",
                icon: "rectangle.on.rectangle.angled",
                captures: viewModel.previewScreenLibrary,
                selectedID: viewModel.selectedPreviewScreenID,
                emptyText: "Views appear here as you navigate the simulator.",
                onSelect: viewModel.selectPreviewScreen
            )

            screenSection(
                title: "Captured",
                icon: "camera.viewfinder",
                captures: viewModel.capturedScreenLibrary,
                selectedID: viewModel.selectedCapturedScreenID,
                emptyText: "Save screenshots here for reuse in App Store and chat.",
                buttonTitle: "Manage",
                buttonIcon: "slider.horizontal.3",
                buttonAction: { isManagingScreens = true },
                onSelect: viewModel.selectCapturedScreen
            )
        }
        .padding(.bottom, Theme.spacingSM)
    }

    private struct PreviewCanvasMetrics {
        let showsDevelopmentLibrary: Bool
        let libraryHeight: CGFloat
        let horizontalInset: CGFloat
        let previewVerticalPadding: CGFloat
        let topBottomSpacing: CGFloat
        let maxPreviewWidth: CGFloat
        let maxPreviewHeight: CGFloat
    }

    private func previewCanvasMetrics(for size: CGSize) -> PreviewCanvasMetrics {
        let showsDevelopmentLibrary = viewModel.developmentPreviewMode == .saved
        let libraryHeight = showsDevelopmentLibrary ? developmentLibraryHeight : 0
        let horizontalInset: CGFloat = showsDevelopmentLibrary ? 22 : 28
        let previewVerticalPadding: CGFloat = showsDevelopmentLibrary ? 4 : 14
        let topBottomSpacing: CGFloat = showsDevelopmentLibrary ? 4 : 18
        let availableWidth = max(320, size.width - (horizontalInset * 2))
        let availableHeight = max(
            240,
            size.height - libraryHeight - (previewVerticalPadding * 2) - (topBottomSpacing * 2)
        )

        return PreviewCanvasMetrics(
            showsDevelopmentLibrary: showsDevelopmentLibrary,
            libraryHeight: libraryHeight,
            horizontalInset: horizontalInset,
            previewVerticalPadding: previewVerticalPadding,
            topBottomSpacing: topBottomSpacing,
            maxPreviewWidth: min(availableWidth, showsDevelopmentLibrary ? 620 : 660),
            maxPreviewHeight: availableHeight
        )
    }

    private func previewCanvas<PreviewContent: View, FooterContent: View>(
        in geo: GeometryProxy,
        @ViewBuilder preview: (PreviewCanvasMetrics) -> PreviewContent,
        @ViewBuilder footer: () -> FooterContent
    ) -> some View {
        let metrics = previewCanvasMetrics(for: geo.size)

        return VStack(spacing: 0) {
            Spacer(minLength: metrics.topBottomSpacing)

            VStack(spacing: Theme.spacingMD) {
                preview(metrics)
                footer()
            }
            .padding(.horizontal, metrics.horizontalInset)
            .padding(.vertical, metrics.previewVerticalPadding)

            if metrics.showsDevelopmentLibrary {
                Spacer(minLength: metrics.topBottomSpacing)

                developmentScreensSection
                    .padding(.horizontal, Theme.spacingXL)
                    .padding(.top, 4)
                    .padding(.bottom, Theme.spacingXL)
                    .frame(height: metrics.libraryHeight, alignment: .top)
            } else {
                Spacer(minLength: Theme.spacingXL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var manageScreensSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Screens")
                    .font(Theme.geist(18, weight: .semibold))
                Spacer()
                Button("Done") { isManagingScreens = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.spacingXL)
            .padding(.top, Theme.spacingXL)

            List {
                managementSection(
                    title: "Views",
                    emptyText: "No saved views yet.",
                    captures: viewModel.previewScreenLibrary,
                    name: \.displayName,
                    delete: viewModel.deletePreviewScreen
                )
                managementSection(
                    title: "Captured",
                    emptyText: "No captured screenshots yet.",
                    captures: viewModel.capturedScreenLibrary,
                    name: viewModel.capturedScreenName(for:),
                    delete: viewModel.deleteCapturedScreen
                )
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    @ViewBuilder
    private func managementSection(
        title: String,
        emptyText: String,
        captures: [PreviewScreenCapture],
        name: @escaping (PreviewScreenCapture) -> String,
        delete: @escaping (PreviewScreenCapture) async -> Void
    ) -> some View {
        Section(title) {
            if captures.isEmpty {
                Text(emptyText)
                    .font(Theme.geist(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(captures) { capture in
                    HStack(spacing: Theme.spacingMD) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(capture))
                                .font(Theme.geist(13, weight: .medium))
                                .lineLimit(1)
                            Text("\(capture.pixelWidth)×\(capture.pixelHeight)")
                                .font(Theme.geist(11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await delete(capture) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var developmentModePicker: some View {
        PreviewModeSwitcher(
            selection: Binding(
                get: { viewModel.developmentPreviewMode },
                set: { viewModel.setDevelopmentPreviewMode($0) }
            ),
            options: developmentModeOptions
        )
    }

    @ViewBuilder
    private var previewTitleView: some View {
        if let capture = selectedEditableCapture, isRenamingCapture {
            HStack(spacing: Theme.spacingSM) {
                TextField("Capture name", text: $captureNameDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.geist(14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(width: 240)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.28))
                            .frame(height: 1)
                    }
                    .onSubmit {
                        saveCaptureRename(capture.id)
                    }

                Button("Save") {
                    saveCaptureRename(capture.id)
                }
                .buttonStyle(.plain)
                .font(Theme.geist(13, weight: .semibold))

                Button("Cancel") {
                    cancelCaptureRename()
                }
                .buttonStyle(.plain)
                .font(Theme.geist(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            }
        } else {
            HStack(spacing: Theme.spacingSM) {
                Text(previewTitle)
                    .font(Theme.geist(14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                if selectedEditableCapture != nil {
                    Button("Rename") {
                        beginCaptureRename()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.geist(13, weight: .semibold))
                }

                if viewModel.developmentPreviewMode == .live {
                    Button {
                        Task { await captureCurrentPreview() }
                    } label: {
                        Label("Capture", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
    }

    private func screenSection(
        title: String,
        icon: String,
        captures: [PreviewScreenCapture],
        selectedID: String?,
        emptyText: String,
        buttonTitle: String? = nil,
        buttonIcon: String? = nil,
        buttonAction: (() -> Void)? = nil,
        onSelect: @escaping (PreviewScreenCapture) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(captures.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.12)))
                Spacer()
                if let buttonTitle, let buttonAction {
                    Button(action: buttonAction) {
                        Label(buttonTitle, systemImage: buttonIcon ?? "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if captures.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(.horizontal, Theme.spacingMD)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.spacingMD) {
                        ForEach(captures) { capture in
                            PreviewScreenCaptureCard(
                                capture: capture,
                                image: viewModel.previewScreenImage(for: capture),
                                isSelected: selectedID == capture.id,
                                onSelect: { onSelect(capture) }
                            )
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, Theme.spacingMD)
                }
                .frame(minHeight: 172)
            }
        }
    }

    private var previewRefreshingBanner: some View {
        HStack(spacing: Theme.spacingSM) {
            ProgressView()
                .controlSize(.small)
            Text(viewModel.previewStatus ?? "Refreshing preview...")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.spacingLG)
        .padding(.vertical, Theme.spacingSM)
        .tenXGlassCapsule()
    }
    private func fileName(from path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func syncCaptureNameDraft() {
        isRenamingCapture = false
        captureNameDraft = selectedEditableCapture.map(viewModel.capturedScreenName(for:)) ?? ""
    }

    @MainActor
    private func captureCurrentPreview() async {
        let preserveMode = viewModel.developmentPreviewMode == .live
        let previousCount = viewModel.capturedScreenLibrary.count
        await viewModel.captureSavedScreen(preserveMode: preserveMode)
        let didCapture = viewModel.capturedScreenLibrary.count > previousCount
        guard didCapture,
              let capture = viewModel.capturedScreenLibrary.first else { return }
        showCaptureFeedback("Saved \(viewModel.capturedScreenName(for: capture))")
    }

    private func commitCaptureNameDraft(for captureID: String?) {
        guard let captureID,
              let capture = viewModel.capturedScreenLibrary.first(where: { $0.id == captureID }) else {
            return
        }
        let trimmed = captureNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != viewModel.capturedScreenName(for: capture) else { return }
        viewModel.renameCapturedScreen(capture, to: trimmed)
        captureNameDraft = viewModel.capturedScreenLibrary
            .first(where: { $0.id == captureID })
            .map(viewModel.capturedScreenName(for:)) ?? trimmed
    }

    private func beginCaptureRename() {
        guard selectedEditableCapture != nil else { return }
        captureNameDraft = previewTitle
        isRenamingCapture = true
    }

    private func cancelCaptureRename() {
        isRenamingCapture = false
        syncCaptureNameDraft()
    }

    private func saveCaptureRename(_ captureID: String) {
        commitCaptureNameDraft(for: captureID)
        isRenamingCapture = false
    }

    private func showCaptureFeedback(_ message: String) {
        let token = UUID()
        captureFeedbackToken = token
        captureFeedback = message
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard captureFeedbackToken == token else { return }
            captureFeedback = nil
        }
    }
}

struct PreviewModeSwitcherOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let iconName: String

    var id: Value { value }
}

struct PreviewModeSwitcher<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [PreviewModeSwitcherOption<Value>]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.iconName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(option.title)
                            .font(Theme.geist(13, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusMD)
                            .fill(isSelected ? Theme.textPrimary.opacity(0.08) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLG)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct PreviewScreenCaptureCard: View {
    @Environment(BuilderViewModel.self) private var viewModel
    let capture: PreviewScreenCapture
    let image: NSImage?
    let isSelected: Bool
    let onSelect: () -> Void

    private var previewSize: CGSize {
        let maxHeight: CGFloat = 104
        let width = max(CGFloat(capture.pixelWidth), 1)
        let height = max(CGFloat(capture.pixelHeight), 1)
        let aspectRatio = width / height
        return CGSize(width: maxHeight * aspectRatio, height: maxHeight)
    }

    private var displayName: String {
        if viewModel.capturedScreenLibrary.contains(where: { $0.id == capture.id }) {
            return viewModel.capturedScreenName(for: capture)
        }
        return capture.displayName
    }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Button(action: onSelect) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .fill(Color(nsColor: .controlBackgroundColor))

                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD))
                    } else {
                        Color(nsColor: .controlBackgroundColor)
                    }
                }
                .frame(width: previewSize.width, height: previewSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(isSelected ? Theme.accent : Color(nsColor: .separatorColor).opacity(0.18), lineWidth: isSelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)

            Text(displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                .lineLimit(1)
                .frame(width: previewSize.width)
        }
        .padding(.horizontal, Theme.spacingSM)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .stroke(isSelected ? Theme.accent.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
                )
        )
        .onDrag {
            viewModel.previewScreenItemProvider(for: capture)
        }
    }
}
