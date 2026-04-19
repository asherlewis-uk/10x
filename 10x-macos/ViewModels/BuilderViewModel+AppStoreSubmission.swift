import Foundation

extension BuilderViewModel {
    private static let appStoreSubmissionModel = "claude-sonnet-4-6"

    var appStoreSubmissionPublishBlockers: [String] {
        let projectName = activeProject?.name ?? appStoreSubmissionDraft.facts.appName
        return appStoreSubmissionDraft.normalized(projectName: projectName).publishBlockers()
    }

    func saveAppStoreSubmissionDraft(
        _ draft: AppStoreSubmissionDraft,
        allowSlugChange: Bool = false
    ) async {
        guard let project = activeProject else { return }

        let current = appStoreSubmissionDraft.normalized(projectName: project.name)
        var next = draft.normalized(projectName: project.name)
        if !allowSlugChange, let frozenSlug = current.publish.lastPublishedSlug, !frozenSlug.isEmpty {
            next.publish.publicSlug = frozenSlug
        }

        appStoreSubmissionDraft = next

        var mergedSettings = project.settings ?? [:]
        if let encoded = AnyCodableValue.encode(next) {
            mergedSettings[BuilderProject.appStoreSubmissionSettingsKey] = encoded
        } else {
            mergedSettings.removeValue(forKey: BuilderProject.appStoreSubmissionSettingsKey)
        }

        do {
            let updatedProject = try await supabase.updateProject(
                id: project.id,
                data: UpdateProjectData(settings: mergedSettings.isEmpty ? nil : mergedSettings)
            )
            if let idx = projects.firstIndex(where: { $0.id == updatedProject.id }) {
                projects[idx] = updatedProject
            }
            if let idx = archivedProjects.firstIndex(where: { $0.id == updatedProject.id }) {
                archivedProjects[idx] = updatedProject
            }
            if activeProject?.id == updatedProject.id {
                activeProject = updatedProject
            }
        } catch {
            appStoreSubmissionError = "Failed to save the App Store submission draft: \(error.localizedDescription)"
        }

        await saveLocally(touchChat: false)
    }

    func collectAppStoreSubmissionFacts() -> AppStoreSubmissionFacts {
        guard let project = activeProject else { return .empty }
        let snapshot = AppStoreSubmissionProjectSnapshot(
            projectName: project.name,
            projectDescription: project.description,
            projectPlan: projectPlan,
            workspaceDescriptor: project.workspaceDescriptor,
            fileTree: appStoreInspectionFileTree(),
            environmentValuesByKey: environmentValuesByKey,
            dependencyManifest: projectDependencyManifest,
            backendState: projectBackendState
        )
        let inferred = AppStoreSubmissionFactCollector.collect(from: snapshot)
        return mergedSubmissionFacts(
            existing: appStoreSubmissionDraft.facts,
            inferred: inferred,
            confirmations: appStoreSubmissionDraft.confirmations
        )
    }

    func generateAppStoreSubmissionDrafts() async {
        guard let project = activeProject else {
            appStoreSubmissionError = "No active project."
            appStoreSubmissionStatus = nil
            return
        }
        guard let accessToken = sessionAccessToken else {
            appStoreSubmissionError = "No active session. Open the project again before generating App Store legal drafts."
            appStoreSubmissionStatus = nil
            return
        }

        isGeneratingAppStoreSubmission = true
        appStoreSubmissionError = nil
        appStoreSubmissionStatus = "Collecting project facts..."
        defer { isGeneratingAppStoreSubmission = false }

        var nextDraft = appStoreSubmissionDraft.normalized(projectName: project.name)
        nextDraft.facts = collectAppStoreSubmissionFacts()
        await saveAppStoreSubmissionDraft(nextDraft)

        do {
            appStoreSubmissionStatus = "Generating privacy, terms, support, and submission drafts..."
            let generated = try await requestAppStoreSubmissionGeneration(
                accessToken: accessToken,
                project: project,
                draft: nextDraft
            )
            nextDraft.generated = generated
            if nextDraft.publish.publicSlug.isEmpty {
                nextDraft.publish.publicSlug = AppStoreSubmissionDraft.normalizedSlug(project.name)
            }
            await saveAppStoreSubmissionDraft(nextDraft)
            appStoreSubmissionStatus = "App Store legal and submission drafts updated."
        } catch {
            appStoreSubmissionError = error.localizedDescription
            appStoreSubmissionStatus = nil
        }
    }

    func publishAppStoreSubmission() async {
        guard let project = activeProject else {
            appStoreSubmissionError = "No active project."
            return
        }

        let blockers = appStoreSubmissionPublishBlockers
        guard blockers.isEmpty else {
            appStoreSubmissionError = blockers.joined(separator: " ")
            appStoreSubmissionStatus = nil
            return
        }

        isPublishingAppStoreSubmission = true
        appStoreSubmissionError = nil
        appStoreSubmissionStatus = "Publishing hosted legal pages..."
        defer { isPublishingAppStoreSubmission = false }

        let updatedAtLabel = appStoreUpdatedAtLabel(for: Date())

        do {
            let normalized = appStoreSubmissionDraft.normalized(projectName: project.name)
            let payload = normalized.publishedPayload(projectId: project.id, updatedAtLabel: updatedAtLabel)
            let published = try await supabase.savePublishedAppStorePage(payload)

            var nextDraft = normalized
            nextDraft.publish.isPublished = true
            nextDraft.publish.lastPublishedAt = published.publishedAt
            nextDraft.publish.lastPublishedSlug = published.publicSlug
            nextDraft.publish.publicSlug = published.publicSlug
            nextDraft.publish.updatedAt = published.updatedAt
            await saveAppStoreSubmissionDraft(nextDraft)

            appStoreSubmissionStatus = "Published hosted legal pages."
        } catch {
            appStoreSubmissionError = "Failed to publish hosted legal pages: \(error.localizedDescription)"
            appStoreSubmissionStatus = nil
        }
    }

    func unpublishAppStoreSubmission() async {
        guard let project = activeProject else {
            appStoreSubmissionError = "No active project."
            return
        }

        isPublishingAppStoreSubmission = true
        appStoreSubmissionError = nil
        appStoreSubmissionStatus = "Unpublishing hosted legal pages..."
        defer { isPublishingAppStoreSubmission = false }

        do {
            try await supabase.unpublishAppStorePage(projectId: project.id)
            var nextDraft = appStoreSubmissionDraft.normalized(projectName: project.name)
            nextDraft.publish.isPublished = false
            nextDraft.publish.updatedAt = BuilderChat.timestamp()
            await saveAppStoreSubmissionDraft(nextDraft)
            appStoreSubmissionStatus = "Unpublished hosted legal pages."
        } catch {
            appStoreSubmissionError = "Failed to unpublish hosted legal pages: \(error.localizedDescription)"
            appStoreSubmissionStatus = nil
        }
    }

    func exportAppStoreSubmissionPacket() async {
        guard let project = activeProject else {
            appStoreSubmissionError = "No active project."
            return
        }

        do {
            let rootURL = appStoreSubmissionExportDirectory(for: project)
                .appendingPathComponent("submission", isDirectory: true)
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let normalized = appStoreSubmissionDraft.normalized(projectName: project.name)
            try normalized.generated.privacy.markdown().write(
                to: rootURL.appendingPathComponent("privacy.md"),
                atomically: true,
                encoding: .utf8
            )
            try normalized.generated.terms.markdown().write(
                to: rootURL.appendingPathComponent("terms.md"),
                atomically: true,
                encoding: .utf8
            )
            try normalized.generated.support.markdown().write(
                to: rootURL.appendingPathComponent("support.md"),
                atomically: true,
                encoding: .utf8
            )

            let metadata = normalized.generated.metadata.normalized
            try metadata.appStoreDescription.write(
                to: rootURL.appendingPathComponent("description.txt"),
                atomically: true,
                encoding: .utf8
            )
            try metadata.promotionalText.write(
                to: rootURL.appendingPathComponent("promotional_text.txt"),
                atomically: true,
                encoding: .utf8
            )
            try metadata.keywordString.write(
                to: rootURL.appendingPathComponent("keywords.txt"),
                atomically: true,
                encoding: .utf8
            )
            try metadata.reviewNotes.joined(separator: "\n").write(
                to: rootURL.appendingPathComponent("review_notes.txt"),
                atomically: true,
                encoding: .utf8
            )

            let overviewData = try JSONEncoder().encode(normalized)
            try overviewData.write(to: rootURL.appendingPathComponent("submission.json"), options: .atomic)

            appStoreSubmissionStatus = "Exported the App Store submission packet to \(rootURL.path)."
        } catch {
            appStoreSubmissionError = "Failed to export the App Store submission packet: \(error.localizedDescription)"
            appStoreSubmissionStatus = nil
        }
    }

    func hostedAppStoreURL(kind: String) -> URL? {
        let projectName = activeProject?.name ?? appStoreSubmissionDraft.facts.appName
        return appStoreSubmissionDraft
            .normalized(projectName: projectName)
            .hostedURL(baseURL: Config.hostedAppsBaseURL, kind: kind)
    }

    private func requestAppStoreSubmissionGeneration(
        accessToken: String,
        project: BuilderProject,
        draft: AppStoreSubmissionDraft
    ) async throws -> AppStoreSubmissionGenerated {
        let billingGroupId = UUID().uuidString
        let billingMessagePreview = "Generate App Store legal drafts"
        var body: [String: Any] = [
            "system": appStoreSubmissionSystemPrompt(),
            "messages": [[
                "role": "user",
                "content": [[
                    "type": "text",
                    "text": try appStoreSubmissionPromptText(project: project, draft: draft),
                ]],
            ]],
            "tools": [],
            "max_tokens": 7200,
            "model": Self.appStoreSubmissionModel,
            "idempotency_key": UUID().uuidString,
            "billing_group_id": billingGroupId,
            "billing_message_preview": billingMessagePreview,
            "project_id": project.id,
        ]
        if let sessionId = activeChat?.id {
            body["session_id"] = sessionId
        }

        do {
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
                if type == "error" {
                    throw APIError.serverError(
                        statusCode: 502,
                        message: (json["message"] as? String) ?? "App Store legal generation failed."
                    )
                }
            }

            await billingRefreshHandler?(true)

            let response = try parseAppStoreSubmissionResponse(text)
            return normalizedGeneratedResponse(from: response)
        } catch {
            await billingRefreshHandler?(true)
            throw error
        }
    }

    private func appStoreSubmissionSystemPrompt() -> String {
        """
        You generate App Store legal and submission copy inside the 10x macOS client.

        Rules:
        - Return only one valid JSON object. No markdown fences. No prose before or after the JSON.
        - Treat the structured facts JSON as authoritative. Do not infer product capabilities or legal facts that contradict those fields.
        - Use the provided section titles and keep the section order exactly as supplied.
        - Do not invent company names, support emails, jurisdictions, URLs, pricing, tracking claims, or legal commitments that are missing from the facts.
        - If important details are missing, write neutral product-safe copy and add a warning.
        - All strings must be valid JSON strings with escaped quotes and escaped newlines when needed.
        - Privacy, terms, and support documents should read like polished public-facing pages.
        - App Store description must be plain text, not markdown.
        - Promotional text must be 170 characters or fewer.
        - Keep the comma-joined keywords string at or under 100 characters total when possible.
        - The warnings array is only for unresolved publication blockers, compliance risks, or materially uncertain facts. Do not include success confirmations, passed limit checks, or generic reminders.
        - Do not warn about account deletion unless facts.usesAccounts is true.
        """
    }

    private func appStoreSubmissionPromptText(
        project: BuilderProject,
        draft: AppStoreSubmissionDraft
    ) throws -> String {
        let facts = draft.facts.normalized
        let blueprints = [
            "privacy": privacyBlueprint(for: facts),
            "terms": termsBlueprint(for: facts),
            "support": supportBlueprint(for: facts),
        ]

        struct PromptPayload: Encodable {
            let projectName: String
            let projectDescription: String?
            let currentAppStoreDescription: String?
            let facts: AppStoreSubmissionFacts
            let confirmations: AppStoreSubmissionConfirmations
            let blueprints: [String: [String]]
        }

        let payload = PromptPayload(
            projectName: project.name,
            projectDescription: project.description,
            currentAppStoreDescription: appStoreReviewState.description?.spec.fullDescription,
            facts: facts,
            confirmations: draft.confirmations,
            blueprints: blueprints
        )

        let data = try JSONEncoder().encode(payload)
        let jsonText = String(decoding: data, as: UTF8.self)

        return """
        Generate privacy, terms, support, and App Store submission copy for the following app.

        Facts JSON:
        \(jsonText)

        Required response JSON shape:
        {
          "privacy": { "title": "...", "intro": ["..."], "sections": [{ "title": "...", "paragraphs": ["..."], "bullets": ["..."] }] },
          "terms": { "title": "...", "intro": ["..."], "sections": [{ "title": "...", "paragraphs": ["..."], "bullets": ["..."] }] },
          "support": { "title": "...", "intro": ["..."], "sections": [{ "title": "...", "paragraphs": ["..."], "bullets": ["..."] }] },
          "metadata": {
            "appStoreDescription": "...",
            "promotionalText": "...",
            "keywords": ["..."],
            "reviewNotes": ["..."],
            "categorySuggestions": ["..."],
            "demoAccountChecklist": ["..."],
            "reviewerContactChecklist": ["..."],
            "appPrivacyAnswers": ["..."],
            "ageRatingHints": ["..."],
            "accessibilityHints": ["..."]
          },
          "warnings": ["..."]
        }
        """
    }

    private func parseAppStoreSubmissionResponse(_ text: String) throws -> AppStoreSubmissionModelResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let extracted = extractFirstJSONObject(from: trimmed) {
            jsonText = extracted
        } else {
            throw APIError.serverError(
                statusCode: 502,
                message: "App Store legal generation did not return valid JSON."
            )
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw APIError.serverError(
                statusCode: 502,
                message: "App Store legal generation returned invalid UTF-8."
            )
        }

        do {
            return try JSONDecoder().decode(AppStoreSubmissionModelResponse.self, from: data)
        } catch {
            throw APIError.serverError(
                statusCode: 502,
                message: "App Store legal generation returned JSON that did not match the required schema: \(error.localizedDescription)"
            )
        }
    }

    private func normalizedGeneratedResponse(
        from response: AppStoreSubmissionModelResponse
    ) -> AppStoreSubmissionGenerated {
        let metadata = response.metadata.normalized
        let joinedKeywords = metadata.keywords.joined(separator: ",")
        let limitedKeywords: [String]
        if joinedKeywords.count <= 100 {
            limitedKeywords = metadata.keywords
        } else {
            var running: [String] = []
            var total = 0
            for keyword in metadata.keywords {
                let addition = running.isEmpty ? keyword.count : keyword.count + 1
                guard total + addition <= 100 else { break }
                running.append(keyword)
                total += addition
            }
            limitedKeywords = running
        }

        return AppStoreSubmissionGenerated(
            privacy: response.privacy.normalized,
            terms: response.terms.normalized,
            support: response.support.normalized,
            metadata: AppStoreSubmissionMetadataDraft(
                appStoreDescription: String(metadata.appStoreDescription.prefix(4000)),
                promotionalText: String(metadata.promotionalText.prefix(170)),
                keywords: limitedKeywords,
                reviewNotes: metadata.reviewNotes,
                categorySuggestions: metadata.categorySuggestions,
                demoAccountChecklist: metadata.demoAccountChecklist,
                reviewerContactChecklist: metadata.reviewerContactChecklist,
                appPrivacyAnswers: metadata.appPrivacyAnswers,
                ageRatingHints: metadata.ageRatingHints,
                accessibilityHints: metadata.accessibilityHints
            ),
            lastGeneratedAt: BuilderChat.timestamp(),
            model: Self.appStoreSubmissionModel,
            warnings: response.warnings
        ).normalized
    }

    private func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private func mergedSubmissionFacts(
        existing: AppStoreSubmissionFacts,
        inferred: AppStoreSubmissionFacts,
        confirmations: AppStoreSubmissionConfirmations
    ) -> AppStoreSubmissionFacts {
        var next = existing.normalized

        func preferExistingString(_ current: String, _ incoming: String) -> String {
            current.isEmpty ? incoming : current
        }

        next.appName = preferExistingString(next.appName, inferred.appName)
        next.projectSummary = preferExistingString(next.projectSummary, inferred.projectSummary)
        next.companyName = preferExistingString(next.companyName, inferred.companyName)
        next.legalEntityName = preferExistingString(next.legalEntityName, inferred.legalEntityName)
        next.supportName = preferExistingString(next.supportName, inferred.supportName)
        next.supportEmail = preferExistingString(next.supportEmail, inferred.supportEmail)
        next.contactEmail = preferExistingString(next.contactEmail, inferred.contactEmail)
        next.websiteURL = preferExistingString(next.websiteURL, inferred.websiteURL)
        next.marketingURL = preferExistingString(next.marketingURL, inferred.marketingURL)
        next.accessibilityURL = preferExistingString(next.accessibilityURL, inferred.accessibilityURL)
        next.jurisdiction = preferExistingString(next.jurisdiction, inferred.jurisdiction)
        next.bundleIdentifier = preferExistingString(next.bundleIdentifier, inferred.bundleIdentifier)
        next.backendProvider = preferExistingString(next.backendProvider, inferred.backendProvider)
        next.authProvider = preferExistingString(next.authProvider, inferred.authProvider)

        let privacyLocked = confirmations.isConfirmed("privacy_claims")
        let trackingLocked = confirmations.isConfirmed("tracking_claims")

        next.usesAccounts = privacyLocked ? next.usesAccounts : (next.usesAccounts || inferred.usesAccounts)
        next.supportsAccountDeletion = privacyLocked ? next.supportsAccountDeletion : (next.supportsAccountDeletion || inferred.supportsAccountDeletion)
        next.usesSubscriptions = privacyLocked ? next.usesSubscriptions : (next.usesSubscriptions || inferred.usesSubscriptions)
        next.usesAnalytics = privacyLocked ? next.usesAnalytics : (next.usesAnalytics || inferred.usesAnalytics)
        next.usesAds = trackingLocked ? next.usesAds : (next.usesAds || inferred.usesAds)
        next.usesTracking = trackingLocked ? next.usesTracking : (next.usesTracking || inferred.usesTracking)
        next.collectsCameraData = privacyLocked ? next.collectsCameraData : (next.collectsCameraData || inferred.collectsCameraData)
        next.collectsMicrophoneData = privacyLocked ? next.collectsMicrophoneData : (next.collectsMicrophoneData || inferred.collectsMicrophoneData)
        next.collectsPhotoLibraryData = privacyLocked ? next.collectsPhotoLibraryData : (next.collectsPhotoLibraryData || inferred.collectsPhotoLibraryData)
        next.collectsLocationData = privacyLocked ? next.collectsLocationData : (next.collectsLocationData || inferred.collectsLocationData)
        next.collectsContactsData = privacyLocked ? next.collectsContactsData : (next.collectsContactsData || inferred.collectsContactsData)
        next.collectsHealthData = privacyLocked ? next.collectsHealthData : (next.collectsHealthData || inferred.collectsHealthData)

        next.kidFocused = next.kidFocused || inferred.kidFocused
        next.servesEUUsers = next.servesEUUsers || inferred.servesEUUsers
        next.hasUserGeneratedContent = next.hasUserGeneratedContent || inferred.hasUserGeneratedContent

        next.permissionUsageDescriptions = inferred.permissionUsageDescriptions
        next.entitlementKeys = inferred.entitlementKeys
        next.privacyTrackingEnabled = trackingLocked ? next.privacyTrackingEnabled : inferred.privacyTrackingEnabled
        next.privacyTrackingDomains = inferred.privacyTrackingDomains
        next.requiredReasonAPIs = inferred.requiredReasonAPIs
        next.integratedServices = inferred.integratedServices
        next.inferenceNotes = inferred.inferenceNotes

        return next.normalized
    }

    private func appStoreInspectionFileTree() -> [String: String] {
        var combined = fileTree
        guard let root = localProjectPath else {
            return combined
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return combined
        }

        for case let url as URL in enumerator {
            let path = url.path
            let lower = path.lowercased()
            guard lower.hasSuffix("info.plist")
                    || lower.hasSuffix(".entitlements")
                    || lower.hasSuffix("privacyinfo.xcprivacy")
                    || lower.hasSuffix(".pbxproj")
            else {
                continue
            }

            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            let relativePath = path.replacingOccurrences(of: root.path + "/", with: "")
            combined[relativePath] = content
        }

        return combined
    }

    private func appStoreUpdatedAtLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }

    private func appStoreSubmissionExportDirectory(for project: BuilderProject) -> URL {
        let root = localProjectPath ?? LocalProjectStore.projectRootDirectory(
            projectName: project.name,
            projectId: project.id
        )
        return root
            .appendingPathComponent("dist", isDirectory: true)
            .appendingPathComponent("app-store", isDirectory: true)
    }

    private func privacyBlueprint(for facts: AppStoreSubmissionFacts) -> [String] {
        [
            "Information We Collect",
            "How We Use Information",
            facts.collectsCameraData || facts.collectsMicrophoneData || facts.collectsPhotoLibraryData || facts.collectsLocationData || facts.collectsContactsData || facts.collectsHealthData
                ? "Device Permissions And Sensitive Data"
                : "Product And Technical Data",
            "How We Share Information",
            "Data Retention",
            "Your Choices",
            "Children's Privacy",
            "Contact",
        ]
    }

    private func termsBlueprint(for facts: AppStoreSubmissionFacts) -> [String] {
        var sections = [
            "Use Of The Service",
            "Accounts And Eligibility",
        ]
        if facts.usesSubscriptions {
            sections.append("Subscriptions And Billing")
        }
        sections.append(contentsOf: [
            "Acceptable Use",
            "Intellectual Property",
            "Disclaimers",
            "Limitation Of Liability",
            "Termination",
            "Changes To These Terms",
            "Contact",
        ])
        return sections
    }

    private func supportBlueprint(for facts: AppStoreSubmissionFacts) -> [String] {
        var sections = [
            "How To Reach Support",
            "What To Include In Your Request",
        ]
        if facts.usesAccounts {
            sections.append("Account And Access Issues")
        }
        if facts.usesSubscriptions {
            sections.append("Billing And Subscription Help")
        }
        sections.append(contentsOf: [
            "Privacy And Data Requests",
            "Response Expectations",
        ])
        return sections
    }
}

private struct AppStoreSubmissionModelResponse: Decodable {
    let privacy: AppStoreGeneratedDocument
    let terms: AppStoreGeneratedDocument
    let support: AppStoreGeneratedDocument
    let metadata: AppStoreSubmissionMetadataDraft
    let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case privacy, terms, support, metadata, warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        privacy = try container.decode(AppStoreGeneratedDocument.self, forKey: .privacy)
        terms = try container.decode(AppStoreGeneratedDocument.self, forKey: .terms)
        support = try container.decode(AppStoreGeneratedDocument.self, forKey: .support)
        metadata = try container.decode(AppStoreSubmissionMetadataDraft.self, forKey: .metadata)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}
