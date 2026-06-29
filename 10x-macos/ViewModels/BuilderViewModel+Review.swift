import AppKit
import Foundation
import UniformTypeIdentifiers

private enum ReviewScreenshotEditRequestSource {
    case explicitFields
    case parsedBrief
}

private enum ReviewScreenshotSlot {
    case absolute(Int)
    case last

    func resolve(count: Int) -> Int? {
        switch self {
        case .absolute(let position):
            guard (1...count).contains(position) else { return nil }
            return position
        case .last:
            guard count > 0 else { return nil }
            return count
        }
    }
}

private struct ReviewScreenshotEditRequest {
    let action: AppStoreReviewScreenshotAction
    let position: ReviewScreenshotSlot?
    let destination: ReviewScreenshotSlot?
    let source: ReviewScreenshotEditRequestSource
}

extension BuilderViewModel {
    private static let minimumReviewScreenshotCaptures = 3

    func requestAppStoreReviewGeneration() {
        guard activeProject != nil else {
            appStoreReviewStatus = nil
            appStoreReviewError = "No active project."
            return
        }
        guard let accessToken = sessionAccessToken else {
            appStoreReviewStatus = nil
            appStoreReviewError = "No active session. Open the project again before generating App Store assets."
            return
        }

        let prompt = "Create an icon, screenshots, and description for this app."
        let previousMode = mode
        let willQueue = isGenerating || hasPendingUserResponse
        mode = .build

        if let error = sendMessage(
            prompt,
            accessToken: accessToken,
            requiredSkillNames: ["app-store-assets"]
        ) {
            mode = previousMode
            appStoreReviewStatus = nil
            appStoreReviewError = error
            return
        }

        if willQueue {
            mode = previousMode
        }
        appStoreReviewError = nil
        appStoreReviewStatus = willQueue
            ? "Queued App Store generation request."
            : "Sent App Store generation request."
    }

    func handleAppStoreReviewTool(_ input: AppStoreReviewToolInput) async -> String {
        var requestedAssets = normalizedReviewAssetKinds(from: input.assets)
        var brief = input.brief?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceViewNames = input.sourceViewNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let applyIconToProject = input.applyIconToProject
        let screenshotEditRequest = reviewScreenshotEditRequest(from: input, brief: brief)

        if requestedAssets.isEmpty {
            requestedAssets = screenshotEditRequest == nil ? AppStoreReviewAssetKind.allCases : [.screenshots]
        }

        var localMessages: [String] = []
        var remainingAssets = deduplicated(requestedAssets)

        if remainingAssets.contains(.screenshots), let screenshotEditRequest {
            let result = await applyReviewScreenshotEdit(screenshotEditRequest)
            guard !result.hasPrefix("Error:") else {
                return result
            }
            localMessages.append(result)
            remainingAssets.removeAll { $0 == .screenshots }
            if screenshotEditRequest.source == .parsedBrief {
                brief = nil
            }
        }

        guard !remainingAssets.isEmpty else {
            return localMessages.joined(separator: " ")
        }

        guard let accessToken = sessionAccessToken else {
            return "Error: no active session. Open the project again before generating App Store assets."
        }

        let generationMessage = await generateAppStoreReviewAssets(
            accessToken: accessToken,
            requestedAssets: remainingAssets,
            brief: brief,
            sourceViewNames: sourceViewNames,
            applyIconToProject: applyIconToProject
        )
        if localMessages.isEmpty {
            return generationMessage
        }
        return (localMessages + [generationMessage]).joined(separator: " ")
    }

    @discardableResult
    func generateAppStoreReviewAssets(
        accessToken: String,
        requestedAssets: [AppStoreReviewAssetKind] = AppStoreReviewAssetKind.allCases,
        brief: String? = nil,
        sourceViewNames: [String] = [],
        applyIconToProject: Bool = true
    ) async -> String {
        guard let project = activeProject else {
            return "Error: no active project."
        }

        rememberAccessToken(accessToken)
        viewMode = .review
        appStoreReviewError = nil
        appStoreReviewStatus = "Preparing App Store assets..."
        isGeneratingAppStoreReviewAssets = true
        defer { isGeneratingAppStoreReviewAssets = false }

        var assets = deduplicated(requestedAssets)
        let startingState = appStoreReviewState
        let sourceCaptures = reviewSourceCaptures(sourceViewNames: sourceViewNames)
        var warnings: [String] = []

        if assets.contains(.screenshots),
           sourceCaptures.count < Self.minimumReviewScreenshotCaptures {
            let message = missingReviewScreenshotSourcesMessage()
            if assets.count == 1 {
                appStoreReviewError = message
                appStoreReviewStatus = nil
                return message
            }
            assets.removeAll { $0 == .screenshots }
            warnings.append(message)
        }

        var generatedIconImage: NSImage?

        if assets.contains(.description) || assets.contains(.screenshots) {
            let outcome = await generateReviewAssetsWithAgent(
                accessToken: accessToken,
                project: project,
                requestedAssets: assets,
                brief: brief,
                sourceCaptures: sourceCaptures
            )
            if case .failure(let message) = outcome {
                warnings.append(message)
            }
        }

        if assets.contains(.icon) {
            let iconResult = await generateReviewIconAsset(
                accessToken: accessToken,
                project: project,
                brief: brief,
                sourceCaptures: sourceCaptures
            )
            generatedIconImage = iconResult.image
            warnings.append(contentsOf: iconResult.warnings)
        }

        let finalState = appStoreReviewState
        let updatedAssets = changedReviewAssets(
            from: startingState,
            to: finalState,
            requestedAssets: assets
        )

        if updatedAssets.isEmpty {
            let detail = warnings.isEmpty
                ? "No App Store assets were updated."
                : warnings.joined(separator: " ")
            let message = "Error generating App Store assets: \(detail)"
            appStoreReviewError = message
            appStoreReviewStatus = nil
            return message
        }

        if applyIconToProject, let generatedIconImage {
            await updateProjectDetails(project, newName: project.name, customIcon: generatedIconImage)
        } else {
            await saveLocally(touchChat: false)
        }

        appStoreReviewStatus = warnings.isEmpty
            ? "App Store assets updated."
            : "App Store assets updated with warnings."
        appStoreReviewError = warnings.isEmpty ? nil : warnings.joined(separator: " ")

        return reviewSummary(
            assets: updatedAssets.map { $0.label.lowercased() },
            screenshotCount: updatedAssets.contains(.screenshots) ? finalState.screenshots.count : 0,
            project: project,
            warnings: warnings
        )
    }

    private func reviewScreenshotEditRequest(
        from input: AppStoreReviewToolInput,
        brief: String?
    ) -> ReviewScreenshotEditRequest? {
        let parsedBriefRequest = parsedReviewScreenshotEditRequest(from: brief)
        if let screenshotAction = input.screenshotAction {
            return ReviewScreenshotEditRequest(
                action: screenshotAction,
                position: input.screenshotPosition.map(ReviewScreenshotSlot.absolute) ?? parsedBriefRequest?.position,
                destination: input.moveToPosition.map(ReviewScreenshotSlot.absolute) ?? parsedBriefRequest?.destination,
                source: .explicitFields
            )
        }
        return parsedBriefRequest
    }

    private func parsedReviewScreenshotEditRequest(from brief: String?) -> ReviewScreenshotEditRequest? {
        guard let brief, !brief.isEmpty else { return nil }
        let normalized = normalizedReviewScreenshotInstruction(brief)

        if matchesOnlyReviewScreenshotMoveInstruction(normalized),
           let moveRange = normalized.range(of: " to "),
           let source = parsedReviewScreenshotSourceSlot(in: String(normalized[..<moveRange.lowerBound])),
           let destination = parsedReviewScreenshotDestinationSlot(in: String(normalized[moveRange.upperBound...])) {
            return ReviewScreenshotEditRequest(
                action: .move,
                position: source,
                destination: destination,
                source: .parsedBrief
            )
        }

        if matchesOnlyReviewScreenshotRemoveInstruction(normalized),
           let position = parsedReviewScreenshotSourceSlot(in: normalized) {
            return ReviewScreenshotEditRequest(
                action: .remove,
                position: position,
                destination: nil,
                source: .parsedBrief
            )
        }

        return nil
    }

    private func applyReviewScreenshotEdit(_ request: ReviewScreenshotEditRequest) async -> String {
        guard let project = activeProject else {
            return "Error: no active project."
        }
        let screenshotCount = appStoreReviewState.screenshots.count
        guard screenshotCount > 0 else {
            return "Error: no App Store screenshots are available yet."
        }
        guard let position = request.position?.resolve(count: screenshotCount) else {
            return "Error: screenshot_position must identify an existing 1-based screenshot."
        }

        var nextState = appStoreReviewState
        let message: String

        switch request.action {
        case .remove:
            nextState.screenshots.remove(at: position - 1)
            let remainingCount = nextState.screenshots.count
            let screenshotLabel = remainingCount == 1 ? "screenshot remains" : "screenshots remain"
            message = "Removed App Store screenshot \(position). \(remainingCount) \(screenshotLabel)."
        case .move:
            guard let destinationSlot = request.destination,
                  let destination = destinationSlot.resolve(count: screenshotCount) else {
                return "Error: move_to_position must identify an existing 1-based screenshot position."
            }
            if position == destination {
                return "App Store screenshot \(position) is already in that position."
            }
            let screenshot = nextState.screenshots.remove(at: position - 1)
            let destinationIndex = min(max(destination - 1, 0), nextState.screenshots.count)
            nextState.screenshots.insert(screenshot, at: destinationIndex)
            message = "Moved App Store screenshot \(position) to position \(destination)."
        }

        do {
            viewMode = .review
            try await persistReviewState(nextState, project: project)
            appStoreReviewError = nil
            appStoreReviewStatus = message
            return "\(message) Exported assets to \(reviewExportDirectory(for: project).path)."
        } catch {
            let errorMessage = "Error: failed to update App Store screenshots: \(error.localizedDescription)"
            appStoreReviewError = errorMessage
            appStoreReviewStatus = nil
            return errorMessage
        }
    }

    func appStoreReviewImage(for relativePath: String) -> NSImage? {
        if let cached = reviewAssetImageCache[relativePath] {
            return cached
        }

        guard let project = activeProject else { return nil }
        let url = LocalProjectStore.reviewAssetImageURL(
            projectName: project.name,
            projectId: project.id,
            relativePath: relativePath
        )
        guard let image = NSImage(contentsOf: url) else { return nil }
        reviewAssetImageCache[relativePath] = image
        return image
    }

    var hasExportedAppStoreReviewAssets: Bool {
        activeProject != nil && appStoreReviewState.hasContent
    }

    func revealAppStoreReviewAssetsInFinder() {
        guard let project = activeProject else {
            appStoreReviewError = "No active project."
            return
        }
        guard appStoreReviewState.hasContent else {
            appStoreReviewError = "No App Store assets are available to reveal yet."
            return
        }

        do {
            try exportReviewAssets(appStoreReviewState, project: project)
            appStoreReviewError = nil
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: reviewExportDirectory(for: project).path)
        } catch {
            appStoreReviewError = "Failed to prepare App Store assets for Finder: \(error.localizedDescription)"
        }
    }

    func exportAppStoreReviewAssetsZip() async {
        guard let project = activeProject else {
            appStoreReviewError = "No active project."
            return
        }
        guard appStoreReviewState.hasContent else {
            appStoreReviewError = "No App Store assets are available to export yet."
            return
        }

        do {
            try exportReviewAssets(appStoreReviewState, project: project)
        } catch {
            appStoreReviewStatus = nil
            appStoreReviewError = "Failed to prepare App Store assets for export: \(error.localizedDescription)"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export App Store Assets ZIP"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(safeSlug(from: project.name))-app-store-assets.zip"
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .data]

        guard panel.runModal() == .OK,
              let destinationURL = panel.url else {
            return
        }

        let exportDirectory = reviewExportDirectory(for: project)
        appStoreReviewError = nil
        appStoreReviewStatus = "Exporting App Store assets ZIP..."

        do {
            try createReviewAssetsZip(sourceURL: exportDirectory, destinationURL: destinationURL)
            appStoreReviewStatus = "Saved App Store assets ZIP."
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        } catch {
            appStoreReviewStatus = nil
            appStoreReviewError = "Failed to export App Store assets ZIP: \(error.localizedDescription)"
        }
    }

    private func normalizedReviewAssetKinds(from values: [String]) -> [AppStoreReviewAssetKind] {
        values.compactMap { AppStoreReviewAssetKind(rawValue: $0.lowercased()) }
    }

    private func reviewSourceCaptures(sourceViewNames: [String]) -> [PreviewScreenCapture] {
        let requestedNames = sourceViewNames.map {
            BuilderMessageAttachment.normalizedPreviewViewMentionName($0)
        }
        let available = developmentScreenLibrary
        guard !requestedNames.isEmpty else {
            return available
        }

        let requestedLookup = Set(requestedNames)
        return Array(available.enumerated())
            .sorted { lhs, rhs in
                let lhsName = BuilderMessageAttachment.normalizedPreviewViewMentionName(lhs.element.displayName)
                let rhsName = BuilderMessageAttachment.normalizedPreviewViewMentionName(rhs.element.displayName)
                let lhsRequested = requestedLookup.contains(lhsName)
                let rhsRequested = requestedLookup.contains(rhsName)
                if lhsRequested != rhsRequested {
                    return lhsRequested && !rhsRequested
                }
                if lhsRequested, rhsRequested {
                    let lhsIndex = requestedNames.firstIndex(of: lhsName) ?? Int.max
                    let rhsIndex = requestedNames.firstIndex(of: rhsName) ?? Int.max
                    if lhsIndex != rhsIndex {
                        return lhsIndex < rhsIndex
                    }
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func missingReviewScreenshotSourcesMessage() -> String {
        "Need at least \(Self.minimumReviewScreenshotCaptures) captured app screens before making App Store screenshots. Capture a few more screens in Development and try again."
    }

    private func generateReviewAssetsWithAgent(
        accessToken: String,
        project: BuilderProject,
        requestedAssets: [AppStoreReviewAssetKind],
        brief: String?,
        sourceCaptures: [PreviewScreenCapture]
    ) async -> ReviewAssetGenerationOutcome {
        let screenshotOrDescriptionAssets = requestedAssets.filter { $0 == .description || $0 == .screenshots }
        guard !screenshotOrDescriptionAssets.isEmpty else {
            return .success
        }

        let projectDir = localProjectPath ?? LocalProjectStore.projectRootDirectory(
            projectName: project.name,
            projectId: project.id
        )
        let toolExecutor = ToolExecutor(
            workspaceRoot: project.workspaceDescriptor.workspaceRootURL(projectRoot: projectDir),
            projectName: project.name,
            targetName: XcodePreviewService.targetName(from: project.name),
            currentMode: mode,
            fileTree: [:],
            appStoreDetailsUpdateHandler: { [weak self] update in
                guard let self else { return "Error: App Store details update failed." }
                return await self.updateAppStoreDetails(update, project: project)
            },
            screenCatalogHandler: { [weak self] in
                guard let self else { return "Error: screen listing failed." }
                return await self.reviewSourceCaptureCatalog(sourceCaptures)
            }
        )

        let billingGroupId = currentBillingGroupId ?? UUID().uuidString
        currentBillingGroupId = billingGroupId
        appStoreReviewStatus = "Reviewing available screens..."

        let outcome = await generationService.runGeneration(
            systemPrompt: reviewAgentSystemPrompt(requestedAssets: screenshotOrDescriptionAssets),
            claudeMessages: [[
                "role": "user",
                "content": reviewAgentContentBlocks(
                    project: project,
                    requestedAssets: screenshotOrDescriptionAssets,
                    brief: brief,
                    sourceCaptures: sourceCaptures
                ),
            ]],
            tools: reviewAgentTools(for: screenshotOrDescriptionAssets),
            toolExecutor: toolExecutor,
            accessToken: accessToken,
            projectId: project.id,
            sessionId: activeChat?.id,
            billingGroupId: billingGroupId,
            billingMessagePreview: "Generate App Store assets"
        ) { [weak self] event in
            guard let self else { return }
            switch event {
            case .status(let status):
                let detail = status.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.appStoreReviewStatus = detail.isEmpty
                    ? status.title
                    : "\(status.title): \(detail)"
            case .toolCallStart(_, let name):
                self.appStoreReviewStatus = BuilderToolPresentation.shortLabel(name: name)
            case .toolCallUpdate(_, let label, _):
                self.appStoreReviewStatus = label
            case .error(let message):
                self.appStoreReviewError = message
                self.appStoreReviewStatus = nil
            default:
                break
            }
        }

        switch outcome {
        case .completed:
            appStoreReviewError = nil
            return .success
        case .failed(let message):
            let errorMessage = "Error generating App Store assets: \(message)"
            appStoreReviewError = errorMessage
            appStoreReviewStatus = nil
            return .failure(errorMessage)
        }
    }

    private func generateReviewIconAsset(
        accessToken: String,
        project: BuilderProject,
        brief: String?,
        sourceCaptures: [PreviewScreenCapture]
    ) async -> (image: NSImage?, warnings: [String]) {
        let billingGroupId = currentBillingGroupId ?? UUID().uuidString
        currentBillingGroupId = billingGroupId
        let iconPlan: ReviewIconPlanner.Plan?
        do {
            appStoreReviewStatus = "Planning App Store icon..."
            iconPlan = try await generateReviewIconPlan(
                accessToken: accessToken,
                project: project,
                brief: brief,
                sourceCaptures: sourceCaptures,
                billingGroupId: billingGroupId
            )
        } catch {
            iconPlan = nil
        }
        let request = OpenAIImageProxyRequest(
            prompt: ReviewIconPlanner.imagePrompt(
                project: project,
                projectPlan: projectPlan,
                brief: brief,
                plan: iconPlan
            ),
            model: nil,
            size: "1024x1024",
            quality: "high",
            background: "opaque",
            outputFormat: "png",
            n: 1,
            projectId: project.id,
            sessionId: activeChat?.id,
            idempotencyKey: UUID().uuidString
        )

        do {
            appStoreReviewStatus = "Generating App Store icon..."
            let response: OpenAIImageProxyResponse = try await apiClient.post(
                APIClient.builder("openai/images/generate"),
                json: try request.jsonDictionary(),
                accessToken: accessToken,
                requestTimeout: 180
            )

            guard let imageBase64 = response.images.first?.base64Data,
                  let imageData = Data(base64Encoded: imageBase64),
                  let generatedIconImage = NSImage(data: imageData)?.normalizedAppIconCanvasIfNeeded() else {
                let warning = "App Store icon generation did not return a valid image."
                return (nil, warning.isEmpty ? [] : [warning])
            }

            let timestamp = BuilderChat.timestamp()
            var nextState = appStoreReviewState
            let relativePath = LocalAssetStorage.relativePath(
                projectId: project.id,
                kind: .export,
                filename: "icon-1024.png",
                subdirectories: ["app-store-review"]
            )
            await localStore.saveReviewAssetImage(
                generatedIconImage,
                relativePath: relativePath,
                projectName: project.name,
                projectId: project.id
            )
            nextState.icon = AppStoreReviewIconAsset(relativeImagePath: relativePath, updatedAt: timestamp)
            try await persistReviewState(nextState, project: project)
            return (generatedIconImage, [])
        } catch {
            return (nil, ["App Store icon generation failed: \(error.localizedDescription)"])
        }
    }

    private func generateReviewIconPlan(
        accessToken: String,
        project: BuilderProject,
        brief: String?,
        sourceCaptures: [PreviewScreenCapture],
        billingGroupId: String
    ) async throws -> ReviewIconPlanner.Plan {
        var body: [String: Any] = [
            "system": ReviewIconPlanner.systemPrompt,
            "messages": [[
                "role": "user",
                "content": reviewIconContentBlocks(project: project, brief: brief, sourceCaptures: sourceCaptures),
            ]],
            "tools": [],
            "max_tokens": 2600,
            "model": ReviewIconPlanner.model,
            "idempotency_key": UUID().uuidString,
            "billing_group_id": billingGroupId,
            "billing_message_preview": "Plan App Store icon",
            "project_id": project.id,
        ]
        if let sessionId = activeChat?.id {
            body["session_id"] = sessionId
        }

        let rawLines = try await apiClient.stream(
            APIClient.builder("claude/stream"),
            method: "POST",
            json: body,
            accessToken: accessToken
        )

        var text = ""
        for try await line in rawLines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let chunk = delta["text"] as? String {
                text += chunk
                continue
            }
            if type == "message_delta",
               let delta = json["delta"] as? [String: Any],
               delta["stop_reason"] as? String == "max_tokens" {
                throw APIError.serverError(
                    statusCode: 502,
                    message: "Review icon planning was cut off before it returned valid JSON."
                )
            }
            if type == "error" {
                throw APIError.serverError(
                    statusCode: 502,
                    message: (json["message"] as? String) ?? "Review icon planning failed."
                )
            }
        }

        return try ReviewIconPlanner.parsePlanResponse(
            text,
            project: project,
            projectPlan: projectPlan,
            brief: brief
        )
    }

    private func reviewIconContentBlocks(
        project: BuilderProject,
        brief: String?,
        sourceCaptures: [PreviewScreenCapture]
    ) -> [[String: Any]] {
        var blocks: [[String: Any]] = [[
            "type": "text",
            "text": ReviewIconPlanner.promptText(
                project: project,
                projectPlan: projectPlan,
                brief: brief,
                sourceCaptures: sourceCaptures,
                existingState: appStoreReviewState
            ),
        ]]

        for capture in sourceCaptures.prefix(6) {
            blocks.append([
                "type": "text",
                "text": "Preview screen: \(capture.displayName) (\(capture.pixelWidth)x\(capture.pixelHeight))",
            ])

            guard let image = previewScreenImage(for: capture) else {
                continue
            }

            let compactPNG = image.downsampledPNGData(maxDimension: 720)
            if let compactPNG {
                blocks.append(reviewAgentImageBlock(base64PNG: compactPNG.base64EncodedString()))
            }

            if let fullPNG = image.pngData, fullPNG != compactPNG {
                blocks.append([
                    "type": "text",
                    "text": "Full-resolution preview screen: \(capture.displayName)",
                ])
                blocks.append(reviewAgentImageBlock(base64PNG: fullPNG.base64EncodedString()))
            }
        }

        return blocks
    }

    private func updateAppStoreDetails(
        _ update: AppStoreDetailsUpdateInput,
        project: BuilderProject
    ) async -> String {
        let timestamp = BuilderChat.timestamp()
        var nextState = appStoreReviewState
        var updates: [String] = []

        if let description = update.description {
            let normalizedDescription = normalizedAppStoreDescriptionSpec(description)
            guard !normalizedDescription.headline.isEmpty,
                  !normalizedDescription.fullDescription.isEmpty else {
                return "Error: the App Store description must include a non-empty headline and fullDescription."
            }
            nextState.description = AppStoreReviewDescriptionAsset(
                spec: normalizedDescription,
                updatedAt: timestamp
            )
            updates.append("description")
        }

        if let drafts = update.screenshots {
            guard !drafts.isEmpty else {
                return "Error: screenshots must contain at least one item when provided."
            }
            guard drafts.count <= 5 else {
                return "Error: provide at most 5 screenshots."
            }
            let specs: [AppStoreReviewScreenshotSpec]
            do {
                specs = try appStoreScreenshotSpecs(from: drafts)
            } catch let error as ReviewAssetToolError {
                return "Error: \(error.message)"
            } catch {
                return "Error: failed to prepare the screenshot set: \(error.localizedDescription)"
            }

            let rendered = await renderReviewScreenshots(
                specs,
                project: project,
                timestamp: timestamp
            )
            guard rendered.count == specs.count else {
                return "Error: failed to render the full screenshot set. Only \(rendered.count) of \(specs.count) screenshots rendered successfully."
            }
            nextState.screenshots = rendered
            updates.append("\(rendered.count) screenshots")
        }

        guard !updates.isEmpty else {
            return "Error: provide a description, screenshots, or both."
        }

        do {
            try await persistReviewState(nextState, project: project)
            return "Saved App Store \(updates.joined(separator: " and "))."
        } catch {
            return "Error: failed to save the App Store details: \(error.localizedDescription)"
        }
    }

    private func normalizedAppStoreDescriptionSpec(
        _ spec: AppStoreReviewDescriptionSpec
    ) -> AppStoreReviewDescriptionSpec {
        let headline = spec.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = spec.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortBlurb = spec.shortBlurb.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullDescription = spec.fullDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let featureBullets = spec.featureBullets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return AppStoreReviewDescriptionSpec(
            headline: headline,
            subtitle: subtitle,
            shortBlurb: shortBlurb,
            fullDescription: fullDescription,
            featureBullets: featureBullets
        )
    }

    private func appStoreScreenshotSpecs(
        from drafts: [ReviewAgentScreenshotDraft]
    ) throws -> [AppStoreReviewScreenshotSpec] {
        var usedCaptureIDs: Set<String> = []
        return try drafts.map { draft in
            guard let capture = developmentScreenLibrary.first(where: { $0.id == draft.sourceCaptureID }) else {
                throw ReviewAssetToolError("Unknown sourceCaptureID '\(draft.sourceCaptureID)'. Use list_screens and choose an exact attached capture ID.")
            }
            guard usedCaptureIDs.insert(capture.id).inserted else {
                throw ReviewAssetToolError("Each App Store screenshot must use a distinct sourceCaptureID. Remove duplicates or return fewer screenshots.")
            }
            let headline = draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headline.isEmpty else {
                throw ReviewAssetToolError("Each screenshot needs a non-empty headline.")
            }
            let backgroundColors = draft.backgroundColors
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !backgroundColors.isEmpty else {
                throw ReviewAssetToolError("Each screenshot needs at least one background color.")
            }
            return AppStoreReviewScreenshotSpec(
                id: draft.id ?? UUID().uuidString,
                sourceCaptureID: capture.id,
                sourceViewName: capture.displayName,
                headline: headline,
                subheadline: draft.subheadline.trimmingCharacters(in: .whitespacesAndNewlines),
                backgroundColors: backgroundColors,
                accentColor: draft.accentColor?.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceScale: draft.deviceScale,
                rotationDegrees: draft.rotationDegrees,
                textPlacement: draft.textPlacement,
                textAlignment: draft.textAlignment,
                headlineFontFamily: draft.headlineFontFamily,
                headlineWeight: draft.headlineWeight,
                headlineItalic: draft.headlineItalic,
                headlineAllCaps: draft.headlineAllCaps,
                headlineScale: draft.headlineScale,
                headlineTracking: draft.headlineTracking,
                headlineWidthRatio: draft.headlineWidthRatio,
                subheadlineFontFamily: draft.subheadlineFontFamily,
                subheadlineWeight: draft.subheadlineWeight,
                subheadlineItalic: draft.subheadlineItalic,
                subheadlineScale: draft.subheadlineScale,
                textToDeviceSpacing: draft.textToDeviceSpacing,
                screenZoom: draft.screenZoom,
                screenFocusX: draft.screenFocusX,
                screenFocusY: draft.screenFocusY
            )
        }
    }

    private func persistReviewState(_ state: AppStoreReviewState, project: BuilderProject) async throws {
        appStoreReviewState = state
        reviewAssetImageCache = [:]
        await localStore.saveReviewState(state, projectName: project.name, projectId: project.id)
        try exportReviewAssets(state, project: project)
        await saveLocally(touchChat: false)
    }

    private func reviewAgentSystemPrompt(requestedAssets: [AppStoreReviewAssetKind]) -> String {
        var lines = [
            "You are preparing App Store assets inside the 10x App Store tab.",
            "The attached images are the source of truth for screen selection, screenshot copy, and screenshot colors.",
            "Use list_screens to get the exact sourceCaptureID values for the attached screens.",
            "Do not infer screen contents from names alone. Inspect the images.",
            "Never update an App Store asset that was not requested.",
            "Need at least 3 distinct source captures before making App Store screenshots. If there are fewer, tell the user more captures are needed and do not generate screenshots.",
            "Match screenshot copy and background colors to the paired screen unless a deliberate change is clearly justified.",
            "Use update_app_store_details to save the App Store description, screenshot set, or both together.",
        ]
        if requestedAssets.contains(.description) && requestedAssets.contains(.screenshots) {
            lines.append("When both are requested, prefer one update_app_store_details call containing both description and screenshots.")
        } else if requestedAssets.contains(.description) {
            lines.append("If only the description is requested, call update_app_store_details with just the description field.")
        } else if requestedAssets.contains(.screenshots) {
            lines.append("If only screenshots are requested, call update_app_store_details with just the screenshots field.")
        }
        if requestedAssets.contains(.description) {
            lines.append("When writing the description, make fullDescription markdown with short paragraphs, compact lists, and selective bold or italics. Do not use markdown headings.")
        }
        return lines.joined(separator: "\n")
    }

    private func reviewAgentContentBlocks(
        project: BuilderProject,
        requestedAssets: [AppStoreReviewAssetKind],
        brief: String?,
        sourceCaptures: [PreviewScreenCapture]
    ) -> [[String: Any]] {
        var blocks: [[String: Any]] = [[
            "type": "text",
            "text": reviewAgentPromptText(
                project: project,
                requestedAssets: requestedAssets,
                brief: brief,
                sourceCaptures: sourceCaptures
            ),
        ]]

        for capture in sourceCaptures {
            guard let image = previewScreenImage(for: capture),
                  let imageData = image.downsampledPNGData(maxDimension: 900) else {
                continue
            }
            blocks.append([
                "type": "text",
                "text": "Source capture attached below. sourceCaptureID: \(capture.id). sourceViewName: \(capture.displayName). size: \(capture.pixelWidth)x\(capture.pixelHeight).",
            ])
            blocks.append(reviewAgentImageBlock(base64PNG: imageData.base64EncodedString()))
        }

        if requestedAssets.contains(.screenshots) {
            for (index, screenshot) in appStoreReviewState.screenshots.enumerated() {
                guard let image = appStoreReviewImage(for: screenshot.relativeImagePath),
                      let imageData = image.downsampledPNGData(maxDimension: 900) else {
                    continue
                }
                let sourceCaptureID = screenshot.spec.sourceCaptureID ?? "none"
                blocks.append([
                    "type": "text",
                    "text": "Current rendered App Store screenshot output \(index + 1) attached below for diagnosis. headline: \(screenshot.spec.headline). sourceCaptureID: \(sourceCaptureID). sourceViewName: \(screenshot.spec.sourceViewName). This current output may be visually wrong.",
                ])
                blocks.append(reviewAgentImageBlock(base64PNG: imageData.base64EncodedString()))
            }
        }

        return blocks
    }

    private func reviewAgentPromptText(
        project: BuilderProject,
        requestedAssets: [AppStoreReviewAssetKind],
        brief: String?,
        sourceCaptures: [PreviewScreenCapture]
    ) -> String {
        var sections = [
            "Project name: \(project.name)",
            "Requested assets: \(requestedAssets.map { $0.label.lowercased() }.joined(separator: ", "))",
        ]
        if let description = project.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            sections.append("Project description: \(description)")
        }
        if let plan = projectPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !plan.isEmpty {
            sections.append("Project plan:\n\(String(plan.prefix(2500)))")
        }
        if let brief, !brief.isEmpty {
            sections.append("Creative brief:\n\(brief)")
        }
        if let description = appStoreReviewState.description?.spec.fullDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Current App Store description:\n\(description)")
        }
        if sourceCaptures.isEmpty {
            sections.append("No source captures are currently available.")
        } else {
            sections.append("Attached source capture catalog:\n\(reviewSourceCaptureCatalog(sourceCaptures))")
        }
        sections.append(
            """
            Requirements:
            - Match screenshot copy to the actual UI in the paired source capture.
            - Only update the requested App Store assets. Leave the others untouched.
            - App Store screenshots need at least 3 distinct sourceCaptureIDs. If there are fewer, tell the user more captures are needed.
            - Use exact sourceCaptureID values instead of fuzzy name matching.
            - Use each sourceCaptureID at most once. If there are fewer than 5 strong screens, return fewer screenshots.
            - Keep screenshot backgrounds visually coherent with the paired source capture.
            - If a description is requested, write fullDescription in markdown with no markdown headings.
            """
        )
        return sections.joined(separator: "\n\n")
    }

    private func reviewSourceCaptureCatalog(_ captures: [PreviewScreenCapture]) -> String {
        guard !captures.isEmpty else {
            return "No screens are available."
        }
        return captures.enumerated().map { index, capture in
            "\(index + 1). sourceCaptureID: \(capture.id) | sourceViewName: \(capture.displayName) | size: \(capture.pixelWidth)x\(capture.pixelHeight)"
        }
        .joined(separator: "\n")
    }

    private func reviewAgentImageBlock(base64PNG: String) -> [String: Any] {
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": "image/png",
                "data": base64PNG,
            ],
        ]
    }

    private func reviewAgentTools(for requestedAssets: [AppStoreReviewAssetKind]) -> [[String: Any]] {
        var tools: [[String: Any]] = [BuilderToolDefinitions.listScreensTool]
        if requestedAssets.contains(.description) || requestedAssets.contains(.screenshots) {
            tools.append(BuilderToolDefinitions.updateAppStoreDetailsTool)
        }
        return tools
    }

    private func renderReviewScreenshots(
        _ specs: [AppStoreReviewScreenshotSpec],
        project: BuilderProject,
        timestamp: String
    ) async -> [AppStoreReviewScreenshotAsset] {
        var rendered: [AppStoreReviewScreenshotAsset] = []
        for spec in specs {
            guard let capture = previewCapture(id: spec.sourceCaptureID, named: spec.sourceViewName),
                  let sourceImage = previewScreenImage(for: capture),
                  let image = AppStoreReviewRenderer.renderScreenshot(spec: spec, sourceImage: sourceImage)
            else {
                continue
            }

            let relativePath = LocalAssetStorage.relativePath(
                projectId: project.id,
                kind: .export,
                filename: "\(safeSlug(from: spec.id))-\(safeSlug(from: spec.headline)).png",
                subdirectories: ["app-store-review", "screenshots"]
            )
            await localStore.saveReviewAssetImage(
                image,
                relativePath: relativePath,
                projectName: project.name,
                projectId: project.id
            )
            rendered.append(
                AppStoreReviewScreenshotAsset(
                    id: spec.id,
                    relativeImagePath: relativePath,
                    spec: spec,
                    updatedAt: timestamp
                )
            )
        }
        return rendered
    }

    private func previewCapture(id: String?, named viewName: String) -> PreviewScreenCapture? {
        if let id, let exact = developmentScreenLibrary.first(where: { $0.id == id }) {
            return exact
        }
        let normalized = BuilderMessageAttachment.normalizedPreviewViewMentionName(viewName)
        return developmentScreenLibrary.first {
            BuilderMessageAttachment.normalizedPreviewViewMentionName($0.displayName) == normalized
        }
    }

    private func exportReviewAssets(_ state: AppStoreReviewState, project: BuilderProject) throws {
        let rootURL = reviewExportDirectory(for: project)
        let screenshotsURL = rootURL.appendingPathComponent("screenshots", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let iconURL = rootURL.appendingPathComponent("icon-1024.png")
        if let icon = state.icon, let image = appStoreReviewImage(for: icon.relativeImagePath), let data = image.pngData {
            try data.write(to: iconURL, options: .atomic)
        } else if fileManager.fileExists(atPath: iconURL.path) {
            try fileManager.removeItem(at: iconURL)
        }

        if let description = state.description {
            try description.spec.fullDescription.write(
                to: rootURL.appendingPathComponent("description.md"),
                atomically: true,
                encoding: .utf8
            )
        } else {
            let descriptionURL = rootURL.appendingPathComponent("description.md")
            if fileManager.fileExists(atPath: descriptionURL.path) {
                try fileManager.removeItem(at: descriptionURL)
            }
        }

        let legacyDescriptionURL = rootURL.appendingPathComponent("description.txt")
        if fileManager.fileExists(atPath: legacyDescriptionURL.path) {
            try fileManager.removeItem(at: legacyDescriptionURL)
        }

        if fileManager.fileExists(atPath: screenshotsURL.path) {
            try fileManager.removeItem(at: screenshotsURL)
        }
        try fileManager.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        for (index, screenshot) in state.screenshots.enumerated() {
            guard let image = appStoreReviewImage(for: screenshot.relativeImagePath),
                  let data = image.pngData else {
                continue
            }
            let filename = exportedReviewScreenshotFilename(for: screenshot, index: index)
            try data.write(to: screenshotsURL.appendingPathComponent(filename), options: .atomic)
        }

        struct ExportOverview: Encodable {
            struct Screenshot: Encodable {
                let filename: String
                let headline: String
                let subheadline: String
                let sourceCaptureID: String?
                let sourceViewName: String
            }

            let creativeDirection: String?
            let headline: String?
            let subtitle: String?
            let shortBlurb: String?
            let featureBullets: [String]
            let screenshots: [Screenshot]
        }

        let overview = ExportOverview(
            creativeDirection: state.creativeDirection,
            headline: state.description?.spec.headline,
            subtitle: state.description?.spec.subtitle,
            shortBlurb: state.description?.spec.shortBlurb,
            featureBullets: state.description?.spec.featureBullets ?? [],
            screenshots: state.screenshots.enumerated().map { index, screenshot in
                ExportOverview.Screenshot(
                    filename: exportedReviewScreenshotFilename(for: screenshot, index: index),
                    headline: screenshot.spec.headline,
                    subheadline: screenshot.spec.subheadline,
                    sourceCaptureID: screenshot.spec.sourceCaptureID,
                    sourceViewName: screenshot.spec.sourceViewName
                )
            }
        )

        let overviewData = try JSONEncoder().encode(overview)
        try overviewData.write(to: rootURL.appendingPathComponent("overview.json"), options: .atomic)
    }

    private func reviewExportDirectory(for project: BuilderProject) -> URL {
        let root = localProjectPath ?? LocalProjectStore.projectRootDirectory(
            projectName: project.name,
            projectId: project.id
        )
        return root
            .appendingPathComponent("dist", isDirectory: true)
            .appendingPathComponent("app-store", isDirectory: true)
    }

    private func safeSlug(from value: String) -> String {
        let lowered = value.lowercased()
        let replaced = lowered.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? UUID().uuidString.lowercased() : trimmed
    }

    private func exportedReviewScreenshotFilename(
        for screenshot: AppStoreReviewScreenshotAsset,
        index: Int
    ) -> String {
        "\(String(format: "%02d", index + 1))-\(safeSlug(from: screenshot.spec.headline)).png"
    }

    private func normalizedReviewScreenshotInstruction(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9#]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesOnlyReviewScreenshotRemoveInstruction(_ value: String) -> Bool {
        matchesReviewScreenshotPattern(
            #"^(?:please )?(?:remove|delete|drop|cut|get rid of) (?:the )?(?:(?:last|final|first|second|third|fourth|fifth) screenshot|screenshot (?:last|final|first|second|third|fourth|fifth)|screenshot (?:number )?#?\d+|slot \d+|position \d+)$"#,
            in: value
        )
    }

    private func matchesOnlyReviewScreenshotMoveInstruction(_ value: String) -> Bool {
        matchesReviewScreenshotPattern(
            #"^(?:please )?(?:move|reorder|shift) (?:the )?(?:(?:last|final|first|second|third|fourth|fifth) screenshot|screenshot (?:last|final|first|second|third|fourth|fifth)|screenshot (?:number )?#?\d+|slot \d+|position \d+) to (?:(?:last|final|first|second|third|fourth|fifth)|position \d+|slot \d+|\d+)$"#,
            in: value
        )
    }

    private func parsedReviewScreenshotSourceSlot(in value: String) -> ReviewScreenshotSlot? {
        if matchesReviewScreenshotPattern(#"\b(?:last|final) screenshot\b"#, in: value) ||
            matchesReviewScreenshotPattern(#"\bscreenshot (?:last|final)\b"#, in: value) {
            return .last
        }
        if let ordinal = firstReviewScreenshotCapture(
            in: value,
            patterns: [
                #"\b(first|second|third|fourth|fifth) screenshot\b"#,
                #"\bscreenshot (first|second|third|fourth|fifth)\b"#,
            ]
        ) {
            return reviewScreenshotOrdinalSlot(from: ordinal)
        }
        if let digits = firstReviewScreenshotCapture(
            in: value,
            patterns: [
                #"\bscreenshot (?:number )?#?(\d+)\b"#,
                #"\bslot (\d+)\b"#,
                #"\bposition (\d+)\b"#,
            ]
        ),
           let position = Int(digits) {
            return .absolute(position)
        }
        return nil
    }

    private func parsedReviewScreenshotDestinationSlot(in value: String) -> ReviewScreenshotSlot? {
        if matchesReviewScreenshotPattern(#"\b(?:last|final)\b"#, in: value) {
            return .last
        }
        if let ordinal = firstReviewScreenshotCapture(
            in: value,
            patterns: [
                #"\b(first|second|third|fourth|fifth)\b"#,
            ]
        ) {
            return reviewScreenshotOrdinalSlot(from: ordinal)
        }
        if let digits = firstReviewScreenshotCapture(
            in: value,
            patterns: [
                #"\bposition (\d+)\b"#,
                #"\bslot (\d+)\b"#,
                #"\b(\d+)\b"#,
            ]
        ),
           let position = Int(digits) {
            return .absolute(position)
        }
        return nil
    }

    private func reviewScreenshotOrdinalSlot(from value: String) -> ReviewScreenshotSlot? {
        switch value {
        case "first":
            return .absolute(1)
        case "second":
            return .absolute(2)
        case "third":
            return .absolute(3)
        case "fourth":
            return .absolute(4)
        case "fifth":
            return .absolute(5)
        default:
            return nil
        }
    }

    private func matchesReviewScreenshotPattern(_ pattern: String, in value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private func firstReviewScreenshotCapture(
        in value: String,
        patterns: [String]
    ) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(value.startIndex..., in: value)
            guard let match = regex.firstMatch(in: value, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: value) else {
                continue
            }
            return String(value[captureRange])
        }
        return nil
    }

    private func deduplicated(_ assets: [AppStoreReviewAssetKind]) -> [AppStoreReviewAssetKind] {
        var seen: Set<AppStoreReviewAssetKind> = []
        return assets.filter { seen.insert($0).inserted }
    }

    private func changedReviewAssets(
        from oldState: AppStoreReviewState,
        to newState: AppStoreReviewState,
        requestedAssets: [AppStoreReviewAssetKind]
    ) -> [AppStoreReviewAssetKind] {
        let requested = Set(requestedAssets)
        return AppStoreReviewAssetKind.allCases.filter { asset in
            guard requested.contains(asset) else { return false }
            switch asset {
            case .icon:
                return oldState.icon != newState.icon
            case .description:
                return oldState.description != newState.description
            case .screenshots:
                return oldState.screenshots != newState.screenshots
            }
        }
    }

    private func reviewSummary(
        assets: [String],
        screenshotCount: Int,
        project: BuilderProject,
        warnings: [String] = []
    ) -> String {
        let assetSummary = assets.isEmpty ? "review assets" : assets.joined(separator: ", ")
        let screenshotLine = screenshotCount > 0 ? " Generated \(screenshotCount) screenshots." : ""
        let warningLine = warnings.isEmpty ? "" : " Warning: \(warnings.joined(separator: " "))"
        return "Updated App Store \(assetSummary). Exported assets to \(reviewExportDirectory(for: project).path).\(screenshotLine)\(warningLine)"
    }
}

private func createReviewAssetsZip(sourceURL: URL, destinationURL: URL) throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.currentDirectoryURL = sourceURL.deletingLastPathComponent()
    process.arguments = [
        "-c",
        "-k",
        "--sequesterRsrc",
        "--keepParent",
        sourceURL.lastPathComponent,
        destinationURL.path,
    ]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let detail = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            throw ReviewAssetToolError(detail)
        }
        throw ReviewAssetToolError("The zip export command failed.")
    }
}

private struct ReviewAssetToolError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

extension ReviewAssetToolError: LocalizedError {
    var errorDescription: String? { message }
}

private enum ReviewAssetGenerationOutcome {
    case success
    case failure(String)
}

private extension Encodable {
    func jsonDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return dictionary
    }
}
