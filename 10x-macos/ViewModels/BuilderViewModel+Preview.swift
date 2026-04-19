import AppKit
import Foundation
import UniformTypeIdentifiers

extension Notification.Name {
    static let tenxProjectThumbnailDidChange = Notification.Name("TenXProjectThumbnailDidChange")
}

extension BuilderViewModel {
    var developmentScreenLibrary: [PreviewScreenCapture] {
        previewScreenLibrary + capturedScreenLibrary
    }

    private func normalizedPreviewViewName(_ viewName: String?) -> String? {
        let trimmed = viewName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func knownPreviewViewNames() -> Set<String> {
        XcodePreviewService.trackedViewNames(in: fileTree)
    }

    private func validatedPreviewViewName(_ viewName: String?, knownViewNames: Set<String>) -> String? {
        guard let normalizedName = normalizedPreviewViewName(viewName),
              knownViewNames.contains(normalizedName) else {
            return nil
        }
        return normalizedName
    }

    private func matchingPreviewScreenIndex(
        for viewName: String,
        pixelWidth: Int,
        pixelHeight: Int,
        in captures: [PreviewScreenCapture]
    ) -> Int? {
        let normalizedName = BuilderMessageAttachment.normalizedPreviewViewMentionName(viewName)
        return captures.firstIndex { capture in
            guard let captureViewName = normalizedPreviewViewName(capture.viewName),
                  capture.pixelWidth == pixelWidth,
                  capture.pixelHeight == pixelHeight else {
                return false
            }

            return BuilderMessageAttachment.normalizedPreviewViewMentionName(captureViewName) == normalizedName
        }
    }

    private func hasDuplicatePreviewScreen(
        perceptualHash: UInt64,
        pixelWidth: Int,
        pixelHeight: Int,
        in captures: [PreviewScreenCapture],
        excludingID: String? = nil
    ) -> Bool {
        captures.contains { capture in
            guard capture.id != excludingID,
                  capture.pixelWidth == pixelWidth,
                  capture.pixelHeight == pixelHeight else {
                return false
            }

            return PreviewScreenFingerprint.hammingDistance(capture.perceptualHash, perceptualHash)
                <= PreviewScreenFingerprint.duplicateHammingThreshold
        }
    }

    private func normalizedPreviewCapture(
        from capture: PreviewScreenCapture,
        knownViewNames: Set<String>
    ) -> PreviewScreenCapture? {
        let viewName: String?
        if let normalizedName = normalizedPreviewViewName(capture.viewName) {
            guard knownViewNames.isEmpty || knownViewNames.contains(normalizedName) else {
                return nil
            }
            viewName = normalizedName
        } else {
            viewName = nil
        }

        return PreviewScreenCapture(
            id: capture.id,
            relativeImagePath: capture.relativeImagePath,
            perceptualHash: capture.perceptualHash,
            pixelWidth: capture.pixelWidth,
            pixelHeight: capture.pixelHeight,
            viewName: viewName
        )
    }

    private func persistPreviewCapture(
        _ capture: PreviewScreenCapture,
        image: NSImage,
        project: BuilderProject
    ) async {
        previewScreenImageCache[capture.id] = image
        previewScreenshot = image
        lastPreviewedFileTreeRevision = fileTreeRevision

        let preferredSelectionID = selectedPreviewScreenID == nil ? capture.id : nil
        syncPreviewScreenSelection(preferredID: preferredSelectionID)

        await localStore.savePreviewScreenImage(
            image,
            capture: capture,
            projectName: project.name,
            projectId: project.id
        )
        await localStore.saveThumbnail(image, projectName: project.name, projectId: project.id)
        NotificationCenter.default.post(
            name: .tenxProjectThumbnailDidChange,
            object: project.id,
            userInfo: ["projectName": project.name]
        )
        await savePreviewScreens()
    }

    private func syncPreviewScreenSelection(preferredID: String? = nil) {
        if previewScreenLibrary.count > Self.maxPreviewScreenLibraryCount {
            previewScreenLibrary = Array(previewScreenLibrary.prefix(Self.maxPreviewScreenLibraryCount))
        }

        if let preferredID,
           previewScreenLibrary.contains(where: { $0.id == preferredID }) {
            selectedPreviewScreenID = preferredID
            return
        }

        guard let selectedPreviewScreenID,
              previewScreenLibrary.contains(where: { $0.id == selectedPreviewScreenID }) else {
            self.selectedPreviewScreenID = previewScreenLibrary.first?.id
            return
        }
    }

    private func upsertPreviewScreen(
        perceptualHash: UInt64,
        pixelWidth: Int,
        pixelHeight: Int,
        viewName: String
    ) -> PreviewScreenCapture? {
        if let existingIndex = matchingPreviewScreenIndex(
            for: viewName,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            in: previewScreenLibrary
        ) {
            let existing = previewScreenLibrary[existingIndex]
            guard !hasDuplicatePreviewScreen(
                perceptualHash: perceptualHash,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                in: previewScreenLibrary,
                excludingID: existing.id
            ) else {
                return nil
            }

            let capture = PreviewScreenCapture(
                id: existing.id,
                relativeImagePath: existing.relativeImagePath,
                perceptualHash: perceptualHash,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                viewName: viewName
            )
            previewScreenLibrary[existingIndex] = capture
            return capture
        }

        guard !hasDuplicatePreviewScreen(
            perceptualHash: perceptualHash,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            in: previewScreenLibrary
        ) else {
            return nil
        }

        let capture = PreviewScreenCapture(
            relativeImagePath: "preview-screens/\(UUID().uuidString).png",
            perceptualHash: perceptualHash,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            viewName: viewName
        )
        previewScreenLibrary.append(capture)
        return capture
    }

    private func recordInitialPreview(_ initialPreview: PreviewLaunchResult) async {
        let knownViewNames = knownPreviewViewNames()
        if let image = NSImage(contentsOf: initialPreview.screenshotURL) {
            previewScreenshot = image
            if let validatedViewName = validatedPreviewViewName(
                initialPreview.initialView?.viewName,
                knownViewNames: knownViewNames
            ) {
                pendingInitialPreviewImage = nil
                _ = await ingestPreviewScreen(image, viewName: validatedViewName)
            } else {
                pendingInitialPreviewImage = image
            }
        }

        guard let entry = initialPreview.initialView,
              let validatedViewName = validatedPreviewViewName(
                entry.viewName,
                knownViewNames: knownViewNames
              ) else {
            return
        }
        lastTrackedViewName = validatedViewName
        lastTrackedTimestamp = entry.timestamp
        lastPreviewedFileTreeRevision = fileTreeRevision
    }

    func cancelPreviewWork() {
        activePreviewRunID = UUID()
        stopLivePreview()
        livePreviewScreenshot = nil
        cancelPreviewScreenCaptureLoop()
        isPreviewLoading = false
        previewStatus = nil
        pendingInitialPreviewImage = nil
        Task { await simulatorService.cancelActiveCommands() }
    }

    private func isCurrentPreviewRun(_ runID: UUID) -> Bool {
        activePreviewRunID == runID
    }

    func previewScreenAttachment(for capture: PreviewScreenCapture) -> BuilderMessageAttachment? {
        guard let url = previewScreenImageURL(for: capture),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        let baseName = capture.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = (baseName.isEmpty ? "View" : baseName) + ".png"
        return BuilderMessageAttachment(
            filename: filename,
            kind: .image,
            mediaType: "image/png",
            sizeBytes: data.count,
            base64Data: data.base64EncodedString(),
            previewViewName: capture.displayName
        )
    }

    func previewScreenImageURL(for capture: PreviewScreenCapture) -> URL? {
        guard let project = activeProject else { return nil }
        return LocalProjectStore.previewScreenImageURL(
            projectName: project.name,
            projectId: project.id,
            relativePath: capture.relativeImagePath
        )
    }

    func previewScreenImage(for capture: PreviewScreenCapture) -> NSImage? {
        if let cached = previewScreenImageCache[capture.id] {
            return cached
        }

        guard let url = previewScreenImageURL(for: capture),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        previewScreenImageCache[capture.id] = image
        return image
    }

    var selectedPreviewScreen: PreviewScreenCapture? {
        guard let selectedPreviewScreenID else { return nil }
        return previewScreenLibrary.first(where: { $0.id == selectedPreviewScreenID })
    }

    var selectedCapturedScreen: PreviewScreenCapture? {
        guard let selectedCapturedScreenID else { return nil }
        return capturedScreenLibrary.first(where: { $0.id == selectedCapturedScreenID })
    }

    var selectedDevelopmentScreen: PreviewScreenCapture? {
        selectedCapturedScreen ?? selectedPreviewScreen
    }

    func capturedScreenName(for capture: PreviewScreenCapture) -> String {
        guard let index = capturedScreenLibrary.firstIndex(where: { $0.id == capture.id }) else {
            return capture.displayName
        }
        let trimmed = capture.viewName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, !trimmed.hasPrefix("Captured ") {
            return trimmed
        }
        return "Capture #\(captureNumber(for: capture, index: index))"
    }

    func renameCapturedScreen(_ capture: PreviewScreenCapture, to name: String) {
        guard let index = capturedScreenLibrary.firstIndex(where: { $0.id == capture.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty
            ? "Capture #\(captureNumber(for: capturedScreenLibrary[index], index: index))"
            : trimmed
        guard capturedScreenLibrary[index].viewName != resolvedName else { return }
        capturedScreenLibrary[index].viewName = resolvedName
        Task { await saveCapturedScreens() }
    }

    private func syncDevelopmentSelectionAfterScreenMutation() {
        let capture = selectedCapturedScreen
            ?? selectedPreviewScreen
            ?? capturedScreenLibrary.first
            ?? previewScreenLibrary.first
        selectedCapturedScreenID = capture.flatMap { capturedScreenLibrary.contains($0) ? $0.id : nil }
        selectedPreviewScreenID = capture.flatMap { previewScreenLibrary.contains($0) ? $0.id : nil }
        previewScreenshot = capture.flatMap(previewScreenImage(for:))
    }

    private func deleteScreen(
        _ capture: PreviewScreenCapture,
        from captures: inout [PreviewScreenCapture]
    ) -> Bool {
        guard let index = captures.firstIndex(where: { $0.id == capture.id }) else { return false }
        captures.remove(at: index)
        previewScreenImageCache.removeValue(forKey: capture.id)
        return true
    }

    func deletePreviewScreen(_ capture: PreviewScreenCapture) async {
        guard deleteScreen(capture, from: &previewScreenLibrary) else { return }
        syncDevelopmentSelectionAfterScreenMutation()
        await savePreviewScreens()
    }

    func deleteCapturedScreen(_ capture: PreviewScreenCapture) async {
        guard deleteScreen(capture, from: &capturedScreenLibrary) else { return }
        syncDevelopmentSelectionAfterScreenMutation()
        await saveCapturedScreens()
    }

    func previewScreenCapture(withID id: String) -> PreviewScreenCapture? {
        developmentScreenLibrary.first { $0.id == id }
    }

    func selectPreviewScreen(_ capture: PreviewScreenCapture) {
        selectedPreviewScreenID = capture.id
        selectedCapturedScreenID = nil
        if let image = previewScreenImage(for: capture) {
            previewScreenshot = image
        }
        setDevelopmentPreviewMode(.saved)
        livePreviewScreenshot = nil
        viewMode = .development
    }

    func selectCapturedScreen(_ capture: PreviewScreenCapture) {
        selectedCapturedScreenID = capture.id
        selectedPreviewScreenID = nil
        if let image = previewScreenImage(for: capture) {
            previewScreenshot = image
        }
        setDevelopmentPreviewMode(.saved)
        livePreviewScreenshot = nil
        viewMode = .development
    }

    func previewScreenItemProvider(for capture: PreviewScreenCapture) -> NSItemProvider {
        let provider = previewScreenImageURL(for: capture)
            .map { NSItemProvider(object: $0 as NSURL) }
            ?? NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.tenXPreviewScreen.identifier,
            visibility: .all
        ) { completion in
            completion(capture.id.data(using: .utf8), nil)
            return nil
        }
        provider.suggestedName = "\(capture.displayName).png"
        return provider
    }

    func setDevelopmentPreviewMode(_ mode: DevelopmentPreviewMode) {
        developmentPreviewMode = mode
        switch mode {
        case .saved:
            stopLivePreview()
        case .live:
            startLivePreviewIfNeeded()
        }
    }

    func openInXcode() async {
        guard !fileTree.isEmpty,
              let project = activeProject else {
            return
        }

        let workspaceDescriptor = project.workspaceDescriptor
        if workspaceDescriptor.isImported {
            guard let containerURL = xcodeContainerURL() else {
                buildError = "This imported project is missing its Xcode workspace path."
                lastPreviewCompileError = nil
                return
            }
            await MainActor.run {
                NSWorkspace.shared.open(
                    [containerURL],
                    withApplicationAt: URL(fileURLWithPath: "/Applications/Xcode.app"),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
            fileWatcher?.updateBaseline(fileTree: fileTree)
            return
        }

        do {
            try await previewService.openInXcode(
                fileTree: fileTree,
                projectName: project.name,
                projectId: project.id,
                customIcon: projectIcon,
                environmentVariables: environmentVariables
            )
            fileWatcher?.updateBaseline(fileTree: fileTree)
        } catch {
            buildError = "Failed to open in Xcode: \(error.localizedDescription)"
            lastPreviewCompileError = nil
        }
    }

    func runSimulatorPreview(
        autoFixIfNeeded: Bool = true,
        buildFixMessageId: String? = nil
    ) async {
        guard !isGenerating else {
            print("[billing-debug] builder.preview.skip reason=is_generating")
            return
        }
        guard !fileTree.isEmpty,
              let project = activeProject else {
            return
        }
        let name = project.name
        let workspaceDescriptor = project.workspaceDescriptor
        print(
            "[billing-debug] builder.preview.start billingGroupId=\(currentBillingGroupId ?? "nil") autoFixIfNeeded=\(autoFixIfNeeded) projectId=\(activeProject?.id ?? "nil")"
        )
        let previewRunID = UUID()
        activePreviewRunID = previewRunID
        viewMode = .development
        stopLivePreview()
        livePreviewScreenshot = nil
        await stopPreviewScreenCaptureLoop()
        await resetPreviewScreenLibrary()
        previewTrackingMinimumTimestamp = Date().timeIntervalSince1970
        guard isCurrentPreviewRun(previewRunID) else { return }

        isPreviewLoading = true
        previewStatus = "Preparing project..."
        buildError = nil
        lastPreviewCompileError = nil

        do {
            let targetName = XcodePreviewService.targetName(from: name)
            let rootDir: URL
            let containerURL: URL
            let containerKind: XcodeContainerKind
            let scheme: String
            let derivedDataURL: URL
            if let existing = localProjectPath {
                rootDir = existing
                if workspaceDescriptor.isImported {
                    guard let importedContainerURL = workspaceDescriptor.xcodeContainerURL(projectRoot: existing),
                          let importedScheme = workspaceDescriptor.scheme,
                          let importedContainerKind = workspaceDescriptor.xcodeContainerKind else {
                        throw ExistingProjectImportError.invalidSelection(
                            "This imported project is missing its Xcode workspace metadata."
                        )
                    }
                    containerURL = importedContainerURL
                    containerKind = importedContainerKind
                    scheme = importedScheme
                    derivedDataURL = existing.appendingPathComponent("DerivedData", isDirectory: true)
                } else {
                    let sourcesDir = existing
                        .appendingPathComponent("ios", isDirectory: true)
                        .appendingPathComponent(targetName, isDirectory: true)
                    if FileManager.default.fileExists(atPath: sourcesDir.path) {
                        try await previewService.regenerateXcodeProject(
                            projectName: name,
                            projectId: project.id,
                            fileTree: fileTree,
                            customIcon: projectIcon,
                            environmentVariables: environmentVariables
                        )
                    } else {
                        _ = try await previewService.writeProjectToDisk(
                            fileTree: fileTree,
                            projectName: name,
                            projectId: project.id,
                            customIcon: projectIcon,
                            environmentVariables: environmentVariables
                        )
                    }
                    containerURL = existing
                        .appendingPathComponent("ios", isDirectory: true)
                        .appendingPathComponent("\(targetName).xcodeproj")
                    containerKind = .project
                    scheme = targetName
                    derivedDataURL = existing
                        .appendingPathComponent("ios", isDirectory: true)
                        .appendingPathComponent("DerivedData", isDirectory: true)
                }
            } else {
                rootDir = try await previewService.writeProjectToDisk(
                    fileTree: fileTree,
                    projectName: name,
                    projectId: project.id,
                    customIcon: projectIcon,
                    environmentVariables: environmentVariables
                )
                guard isCurrentPreviewRun(previewRunID) else { return }
                localProjectPath = rootDir
                containerURL = rootDir
                    .appendingPathComponent("ios", isDirectory: true)
                    .appendingPathComponent("\(targetName).xcodeproj")
                containerKind = .project
                scheme = targetName
                derivedDataURL = rootDir
                    .appendingPathComponent("ios", isDirectory: true)
                    .appendingPathComponent("DerivedData", isDirectory: true)
            }

            guard isCurrentPreviewRun(previewRunID) else { return }
            fileWatcher?.updateBaseline(fileTree: fileTree)

            previewStatus = "Building app..."
            let buildCheckErrors = try await simulatorService.checkBuild(
                containerURL: containerURL,
                containerKind: containerKind,
                scheme: scheme,
                derivedDataURL: derivedDataURL
            )
            guard isCurrentPreviewRun(previewRunID) else { return }
            if let errors = buildCheckErrors {
                print(
                    "[billing-debug] builder.preview.build_failed billingGroupId=\(currentBillingGroupId ?? "nil") autoFixIfNeeded=\(autoFixIfNeeded)"
                )
                buildError = errors
                lastPreviewCompileError = errors
                latestBuildFixError = errors
                if isAutoFixingBuild, let buildFixMessageId {
                    updateBuildFixState(messageId: buildFixMessageId, error: errors, resolved: false)
                }
                previewStatus = nil
                isPreviewLoading = false
                await stopPreviewScreenCaptureLoop()
                if autoFixIfNeeded && !isAutoFixingBuild {
                    continueAutomaticBuildFixIfPossible()
                }
                return
            }

            let initialPreview = try await simulatorService.runPreview(
                containerURL: containerURL,
                containerKind: containerKind,
                scheme: scheme,
                derivedDataURL: derivedDataURL,
                bundleId: workspaceDescriptor.bundleIdentifier,
                environment: clientEnvironmentValuesByKey,
                skipBuild: true,
                onStatus: { status in
                    await MainActor.run {
                        guard self.isCurrentPreviewRun(previewRunID) else { return }
                        self.previewStatus = status
                    }
                }
            )
            guard isCurrentPreviewRun(previewRunID) else { return }

            buildError = nil
            lastPreviewCompileError = nil
            latestBuildFixError = nil
            resolveLatestStoredBuildIssueIfNeeded()
            await recordInitialPreview(initialPreview)

            previewStatus = nil
            consecutiveAutomaticBuildFixFailures = 0
            lastAutomaticBuildFixSignature = nil
            lastAutomaticBuildFixRevision = nil
            startPreviewScreenCaptureLoopIfNeeded()
            if developmentPreviewMode == .live {
                startLivePreviewIfNeeded()
            }
        } catch is CancellationError {
            guard isCurrentPreviewRun(previewRunID) else { return }
            previewStatus = nil
            isPreviewLoading = false
            await stopPreviewScreenCaptureLoop()
            return
        } catch {
            guard isCurrentPreviewRun(previewRunID) else { return }
            print(
                "[billing-debug] builder.preview.error billingGroupId=\(currentBillingGroupId ?? "nil") autoFixIfNeeded=\(autoFixIfNeeded) error=\(error.localizedDescription)"
            )
            buildError = error.localizedDescription
            lastPreviewCompileError = BuilderBuildFixSupport.automaticBuildFixErrorMessage(from: error)
            latestBuildFixError = lastPreviewCompileError
            if isAutoFixingBuild, let latestBuildFixError, let buildFixMessageId {
                updateBuildFixState(messageId: buildFixMessageId, error: latestBuildFixError, resolved: false)
            }
            previewStatus = nil
            await stopPreviewScreenCaptureLoop()
            if autoFixIfNeeded && !isAutoFixingBuild && lastPreviewCompileError != nil {
                continueAutomaticBuildFixIfPossible()
            }
        }

        guard isCurrentPreviewRun(previewRunID) else { return }
        isPreviewLoading = false
    }

    func savePreviewScreens() async {
        guard let project = activeProject else { return }
        await localStore.savePreviewScreens(previewScreenLibrary, projectName: project.name, projectId: project.id)
    }

    func saveCapturedScreens() async {
        guard let project = activeProject else { return }
        await localStore.saveCapturedScreens(capturedScreenLibrary, projectName: project.name, projectId: project.id)
    }

    func resetPreviewScreenLibrary() async {
        previewScreenLibrary = []
        selectedPreviewScreenID = nil
        previewTrackingMinimumTimestamp = 0
        lastTrackedViewName = nil
        lastTrackedTimestamp = 0
        previewScreenImageCache = [:]
        pendingInitialPreviewImage = nil
        await savePreviewScreens()
    }

    func captureSavedScreen(preserveMode: Bool = false) async {
        guard let project = activeProject else { return }

        let image: NSImage?
        if let screenshotURL = try? await simulatorService.captureCurrentScreen() {
            image = NSImage(contentsOf: screenshotURL)
        } else {
            image = livePreviewScreenshot ?? previewScreenshot
        }

        guard let image,
              let perceptualHash = PreviewScreenFingerprint.hash(for: image),
              !PreviewScreenHeuristics.shouldIgnore(image)
        else {
            return
        }

        let pixelSize = image.pixelDimensions
        let pixelWidth = Int(pixelSize.width)
        let pixelHeight = Int(pixelSize.height)
        guard !hasDuplicatePreviewScreen(
            perceptualHash: perceptualHash,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            in: capturedScreenLibrary
        ) else {
            return
        }

        let capture = PreviewScreenCapture(
            relativeImagePath: "captured-screens/\(UUID().uuidString).png",
            perceptualHash: perceptualHash,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            viewName: nextCapturedScreenName()
        )
        capturedScreenLibrary.insert(capture, at: 0)
        previewScreenImageCache[capture.id] = image
        selectedCapturedScreenID = capture.id
        selectedPreviewScreenID = nil
        previewScreenshot = image
        if !preserveMode {
            setDevelopmentPreviewMode(.saved)
        }
        await localStore.savePreviewScreenImage(
            image,
            capture: capture,
            projectName: project.name,
            projectId: project.id
        )
        await saveCapturedScreens()
    }

    func startPreviewScreenCaptureLoopIfNeeded() {
        guard activeProject != nil, previewScreenCaptureTask == nil else {
            return
        }

        let sessionID = UUID()
        previewScreenCaptureSessionID = sessionID
        previewScreenCaptureTask = Task { [weak self] in
            await self?.runViewTrackingLoop(sessionID: sessionID)
        }
    }

    func cancelPreviewScreenCaptureLoop() {
        previewScreenCaptureSessionID = UUID()
        previewScreenCaptureTask?.cancel()
        previewScreenCaptureTask = nil
        previewTrackingMinimumTimestamp = 0
    }

    func stopPreviewScreenCaptureLoop() async {
        let task = previewScreenCaptureTask
        cancelPreviewScreenCaptureLoop()
        await task?.value
    }

    func startLivePreviewIfNeeded() {
        guard livePreviewTask == nil else { return }
        let sessionID = UUID()
        livePreviewSessionID = sessionID
        livePreviewTask = Task { [weak self] in
            await self?.runLivePreviewLoop(sessionID: sessionID)
        }
    }

    func stopLivePreview() {
        livePreviewSessionID = UUID()
        livePreviewTask?.cancel()
        livePreviewTask = nil
    }

    func runLivePreviewLoop(sessionID: UUID) async {
        while !Task.isCancelled {
            guard sessionID == livePreviewSessionID else { return }
            if let screenshotURL = try? await simulatorService.captureCurrentScreen(),
               let image = NSImage(contentsOf: screenshotURL) {
                livePreviewScreenshot = image
                if selectedDevelopmentScreen == nil {
                    previewScreenshot = image
                }
            }
            try? await Task.sleep(for: .seconds(Self.livePreviewPollIntervalSeconds))
        }
    }

    func runViewTrackingLoop(sessionID: UUID) async {
        guard let project = activeProject else { return }
        let bundleId = XcodePreviewService.bundleId(from: project.name)

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.viewTrackingPollIntervalSeconds))
            guard !Task.isCancelled, sessionID == previewScreenCaptureSessionID else { return }

            let minimumTimestamp = max(previewTrackingMinimumTimestamp, lastTrackedTimestamp)
            guard let entry = await simulatorService.readCurrentViewName(
                bundleId: bundleId,
                minimumTimestamp: minimumTimestamp
            ) else {
                continue
            }

            let isNewView = entry.viewName != lastTrackedViewName
            let isNewTimestamp = entry.timestamp > lastTrackedTimestamp
            guard isNewView || isNewTimestamp else { continue }

            let viewName = entry.viewName
            lastTrackedViewName = viewName
            lastTrackedTimestamp = entry.timestamp

            try? await Task.sleep(for: .seconds(Self.viewSettleDelaySeconds))
            guard !Task.isCancelled, sessionID == previewScreenCaptureSessionID else { return }

            await captureViewScreen(viewName: viewName, sessionID: sessionID)
        }
    }

    func captureViewScreen(viewName: String, sessionID: UUID) async {
        let knownViewNames = knownPreviewViewNames()
        guard let validatedViewName = validatedPreviewViewName(viewName, knownViewNames: knownViewNames) else {
            return
        }

        if let pendingInitialPreviewImage {
            self.pendingInitialPreviewImage = nil
            _ = await ingestPreviewScreen(pendingInitialPreviewImage, viewName: validatedViewName)
            return
        }

        do {
            let screenshotURL = try await simulatorService.captureCurrentScreen()
            guard let image = NSImage(contentsOf: screenshotURL) else { return }
            guard sessionID == previewScreenCaptureSessionID else { return }
            _ = await ingestPreviewScreen(image, viewName: validatedViewName)
        } catch {
        }
    }

    @discardableResult
    func ingestPreviewScreen(_ image: NSImage, viewName: String? = nil) async -> Bool {
        let knownViewNames = knownPreviewViewNames()
        guard let project = activeProject,
              let resolvedViewName = validatedPreviewViewName(viewName, knownViewNames: knownViewNames),
              let perceptualHash = PreviewScreenFingerprint.hash(for: image) else {
            return false
        }

        guard !PreviewScreenHeuristics.shouldIgnore(image) else { return false }

        let pixelSize = image.pixelDimensions
        let pixelWidth = Int(pixelSize.width)
        let pixelHeight = Int(pixelSize.height)

        guard let capture = upsertPreviewScreen(
            perceptualHash: perceptualHash,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            viewName: resolvedViewName
        ) else {
            return false
        }

        await persistPreviewCapture(capture, image: image, project: project)
        return true
    }

    func sanitizePreviewScreenLibrary() async {
        guard !previewScreenLibrary.isEmpty else { return }

        let knownViewNames = knownPreviewViewNames()
        var sanitized: [PreviewScreenCapture] = []
        for capture in previewScreenLibrary {
            guard let image = previewScreenImage(for: capture),
                  !PreviewScreenHeuristics.shouldIgnore(image),
                  let normalizedCapture = normalizedPreviewCapture(from: capture, knownViewNames: knownViewNames)
            else {
                previewScreenImageCache.removeValue(forKey: capture.id)
                continue
            }

            if let viewName = normalizedCapture.viewName,
               let existingIndex = matchingPreviewScreenIndex(
                for: viewName,
                pixelWidth: normalizedCapture.pixelWidth,
                pixelHeight: normalizedCapture.pixelHeight,
                in: sanitized
               ) {
                let existing = sanitized[existingIndex]
                guard !hasDuplicatePreviewScreen(
                    perceptualHash: normalizedCapture.perceptualHash,
                    pixelWidth: normalizedCapture.pixelWidth,
                    pixelHeight: normalizedCapture.pixelHeight,
                    in: sanitized,
                    excludingID: existing.id
                ) else {
                    previewScreenImageCache.removeValue(forKey: capture.id)
                    continue
                }

                previewScreenImageCache.removeValue(forKey: existing.id)
                sanitized[existingIndex] = normalizedCapture
                continue
            }

            guard !hasDuplicatePreviewScreen(
                perceptualHash: normalizedCapture.perceptualHash,
                pixelWidth: normalizedCapture.pixelWidth,
                pixelHeight: normalizedCapture.pixelHeight,
                in: sanitized
            ) else {
                previewScreenImageCache.removeValue(forKey: capture.id)
                continue
            }

            sanitized.append(normalizedCapture)
        }

        guard sanitized != previewScreenLibrary else { return }
        previewScreenLibrary = sanitized
        syncPreviewScreenSelection()
        await savePreviewScreens()
    }

    private func nextCapturedScreenName() -> String {
        "Capture #\(capturedScreenLibrary.count + 1)"
    }

    private func captureNumber(for capture: PreviewScreenCapture, index: Int) -> Int {
        let trimmed = capture.viewName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let number = Int(trimmed.replacingOccurrences(of: "Capture #", with: "")), number > 0 {
            return number
        }
        if trimmed.hasPrefix("Captured ") {
            let digits = trimmed.dropFirst("Captured ".count).prefix { $0.isNumber }
            if let number = Int(digits), number > 0 {
                return number
            }
        }
        return index + 1
    }
}
