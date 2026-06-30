import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let inlineSkillEditorFont = NSFont(name: "Geist-Regular", size: 13) ?? .systemFont(ofSize: 13)
private let inlineSkillTagFont = NSFont(name: "Geist-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
private let inlineSkillEditorMinHeight: CGFloat = 104
private let inlineSkillEditorMaxHeight: CGFloat = 156
private let inlineSkillEditorVerticalInset: CGFloat = 6
private let composerAttachmentPreviewMaxWidth: CGFloat = 112
private let composerAttachmentPreviewMaxHeight: CGFloat = 72

private func composerAttachmentPreviewSize(for image: NSImage) -> CGSize {
    let originalSize = image.pixelDimensions
    guard originalSize.width > 0, originalSize.height > 0 else {
        return CGSize(width: composerAttachmentPreviewMaxWidth, height: composerAttachmentPreviewMaxHeight)
    }

    let widthScale = composerAttachmentPreviewMaxWidth / originalSize.width
    let heightScale = composerAttachmentPreviewMaxHeight / originalSize.height
    let scale = min(widthScale, heightScale, 1)

    return CGSize(
        width: max(56, floor(originalSize.width * scale)),
        height: max(40, floor(originalSize.height * scale))
    )
}

struct ChatSkillPickerPresentation {
    var isPresented = false
    var suggestions: [SkillRegistryEntry] = []
    var isLoading = false

    static let hidden = ChatSkillPickerPresentation()
}

struct ChatViewPickerPresentation {
    var isPresented = false
    var suggestions: [PreviewScreenCapture] = []

    static let hidden = ChatViewPickerPresentation()
}

struct ChatInputView: View {
    @Binding var skillPickerPresentation: ChatSkillPickerPresentation
    @Binding var viewPickerPresentation: ChatViewPickerPresentation
    @Binding var pendingSkillSelection: String?
    @Binding var pendingViewSelectionID: String?
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth
    @State private var input = ""
    @State private var attachments: [BuilderMessageAttachment] = []
    @State private var composerError: String?
    @State private var expandedQueueItem: UUID?
    @State private var isFocused = false
    @State private var editorHeight: CGFloat = inlineSkillEditorMinHeight
    @State private var pendingSelectionLocation: Int?
    @State private var pendingMessageAction: BuilderMessageAction?
    @State private var pendingMessageActionInputSnapshot: String?
    @State private var isDropTargeted = false

    private struct PreparedDraft {
        let text: String
        let requiredSkillNames: [String]
    }

    private struct TokenSearchContext {
        let tokenRange: Range<String.Index>
        let query: String
    }

    private var preparedDraft: PreparedDraft {
        prepareDraft(from: input)
    }

    private var isEmpty: Bool {
        preparedDraft.text.isEmpty && attachments.isEmpty
    }

    private var canAttachMoreFiles: Bool {
        !viewModel.hasPendingUserResponse
            && attachments.count < BuilderAttachmentPolicy.maxItemCount
            && BuilderAttachmentPolicy.payloadBytes(for: attachments) < BuilderAttachmentPolicy.maxTotalBytes
    }

    private var validationError: String? {
        isEmpty ? nil : viewModel.validateDraft(text: preparedDraft.text, attachments: attachments)
    }

    private var displayedComposerError: String? {
        composerError ?? validationError
    }

    private var canSend: Bool {
        !viewModel.hasPendingUserResponse && !isEmpty && displayedComposerError == nil
    }

    private var skillSearchContext: TokenSearchContext? {
        Self.skillSearchContext(in: input)
    }

    private var viewSearchContext: TokenSearchContext? {
        Self.viewSearchContext(in: input)
    }

    private var skillNameSet: Set<String> {
        Set(viewModel.availableSkills.map(\.name))
    }

    private var previewViewNameSet: Set<String> {
        Set(viewModel.developmentScreenLibrary.map { Self.normalizedPreviewViewMentionName($0.displayName) })
    }

    private var selectedSkillNames: [String] {
        Self.recognizedInlineSkillNames(in: input, availableSkillNames: skillNameSet)
    }

    private var selectedPreviewViewNames: [String] {
        Self.recognizedInlinePreviewViewNames(
            in: input,
            availablePreviewViewNames: previewViewNameSet
        )
    }

    private var filteredSkillSuggestions: [SkillRegistryEntry] {
        guard let skillSearchContext else { return [] }

        let selectedSet = Set(selectedSkillNames.map { $0.lowercased() })
        let remainingSkills = viewModel.availableSkills.filter { !selectedSet.contains($0.name.lowercased()) }
        let query = skillSearchContext.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else { return remainingSkills }

        let normalizedQuery = query.lowercased()
        return remainingSkills
            .filter { skill in
                skill.name.lowercased().contains(normalizedQuery)
                    || skill.displayTitle.lowercased().contains(normalizedQuery)
                    || skill.userFacingDescription.lowercased().contains(normalizedQuery)
                    || skill.description.lowercased().contains(normalizedQuery)
                    || skill.tags.contains(where: { $0.lowercased().contains(normalizedQuery) })
            }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.name.lowercased().hasPrefix(normalizedQuery)
                let rhsPrefix = rhs.name.lowercased().hasPrefix(normalizedQuery)
                if lhsPrefix != rhsPrefix {
                    return lhsPrefix && !rhsPrefix
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var filteredViewSuggestions: [PreviewScreenCapture] {
        guard let viewSearchContext else { return [] }

        let selectedSet = Set(selectedPreviewViewNames)
        let remainingViews = viewModel.developmentScreenLibrary.filter { capture in
            !selectedSet.contains(Self.normalizedPreviewViewMentionName(capture.displayName))
        }
        let query = viewSearchContext.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return remainingViews.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        let normalizedQuery = query.lowercased()
        return remainingViews
            .filter { capture in
                capture.displayName.lowercased().contains(normalizedQuery)
                    || (capture.viewName?.lowercased().contains(normalizedQuery) ?? false)
            }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.displayName.lowercased().hasPrefix(normalizedQuery)
                let rhsPrefix = rhs.displayName.lowercased().hasPrefix(normalizedQuery)
                if lhsPrefix != rhsPrefix {
                    return lhsPrefix && !rhsPrefix
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var showsSkillPicker: Bool {
        skillSearchContext != nil
    }

    private var showsViewPicker: Bool {
        viewSearchContext != nil
    }

    private var placeholderText: String {
        if viewModel.isGenerating {
            return "Queue your next message..."
        }
        switch viewModel.mode {
        case .plan: return "Describe your app idea or ask a question..."
        case .build: return "Describe what to build or change..."
        }
    }

    private var showsPlaceholder: Bool {
        input.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message queue (shown above input when non-empty)
            if !viewModel.messageQueue.isEmpty {
                queueSection
            }

            VStack(spacing: 4) {
                if !attachments.isEmpty {
                    attachmentTray
                }

                editorArea

                if let displayedComposerError, !displayedComposerError.isEmpty {
                    HStack(alignment: .center, spacing: Theme.spacingSM) {
                        Text(displayedComposerError)
                            .font(Theme.geist(11))
                            .foregroundStyle(Theme.error)

                        Spacer()

                        EmptyView()
                    }
                }

                // Bottom row: mode picker (left) + send/stop (right)
                HStack(spacing: Theme.spacingSM) {
                    attachButton
                    modePicker
                    Spacer()
                    if viewModel.isGenerating && isEmpty {
                        Button {
                            viewModel.stopGeneration()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            send()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(canSend ? Theme.accent : Theme.textTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                    }
                }
            }
            .padding(Theme.spacingMD)
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusSM)
                        .strokeBorder(
                            isDropTargeted ? Theme.accent : (isFocused ? Color.white.opacity(0.3) : Color.primary.opacity(0.15)),
                            lineWidth: isDropTargeted ? 1.5 : 1
                        )
                }
        }
        .padding(Theme.spacingMD)
        .onAppear {
            syncPickerPresentations()
        }
        .task(id: auth.accessToken) {
            guard let token = await auth.validAccessToken() else { return }
            await viewModel.loadAvailableSkills(accessToken: token)
            syncPickerPresentations()
        }
        .onChange(of: viewModel.pendingInputPrefill) { _, newValue in
            guard let text = newValue else { return }
            input = Self.composerInputText(
                text: text,
                requiredSkillNames: viewModel.pendingRequiredSkillPrefill ?? []
            )
            restorePendingMessageAction(viewModel.pendingMessageActionPrefill)
            viewModel.pendingInputPrefill = nil
            viewModel.pendingRequiredSkillPrefill = nil
            viewModel.pendingMessageActionPrefill = nil
            composerError = nil
            isFocused = true
        }
        .onChange(of: viewModel.pendingAttachmentPrefill) { _, newValue in
            guard let newValue else { return }
            attachments = newValue
            viewModel.pendingAttachmentPrefill = nil
            composerError = nil
            isFocused = true
        }
        .onChange(of: viewModel.pendingRequiredSkillPrefill) { _, newValue in
            guard let newValue, viewModel.pendingInputPrefill == nil else { return }
            input = Self.composerInputText(text: preparedDraft.text, requiredSkillNames: newValue)
            viewModel.pendingRequiredSkillPrefill = nil
            composerError = nil
            isFocused = true
        }
        .onChange(of: pendingSkillSelection) { _, newValue in
            guard let skillName = newValue else { return }
            defer { pendingSkillSelection = nil }
            guard let skill = viewModel.availableSkills.first(where: {
                $0.name.caseInsensitiveCompare(skillName) == .orderedSame
            }) else { return }
            selectSkill(skill)
        }
        .onChange(of: pendingViewSelectionID) { _, newValue in
            guard let viewID = newValue else { return }
            defer { pendingViewSelectionID = nil }
            guard let capture = viewModel.developmentScreenLibrary.first(where: { $0.id == viewID }) else { return }
            selectPreviewView(capture)
        }
        .onChange(of: viewModel.pendingAttachmentAppend) { _, newValue in
            guard let newValue else { return }
            let mergedAttachments = mergedAttachments(adding: newValue)
            if let error = viewModel.validateDraft(text: preparedDraft.text, attachments: mergedAttachments) {
                composerError = error
            } else {
                attachments = mergedAttachments
                clearPendingMessageAction()
                composerError = nil
            }
            viewModel.pendingAttachmentAppend = nil
            isFocused = true
        }
        .onChange(of: viewModel.pendingPreviewViewMentionAppend) { _, newValue in
            guard let newValue else { return }
            appendPreviewViewMentions(newValue)
            viewModel.pendingPreviewViewMentionAppend = nil
        }
        .onChange(of: input) { _, _ in
            if let snapshot = pendingMessageActionInputSnapshot, input != snapshot {
                clearPendingMessageAction()
            } else if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearPendingMessageAction()
            }
            if composerError != nil {
                composerError = nil
            }
            syncPickerPresentations()
        }
        .onChange(of: viewModel.isLoadingSkills) { _, _ in
            syncPickerPresentations()
        }
        .onChange(of: viewModel.developmentScreenLibrary.map(\.id)) { _, _ in
            syncPickerPresentations()
        }
        .onDisappear {
            skillPickerPresentation = .hidden
            viewPickerPresentation = .hidden
        }
    }

    // MARK: - Attachments

    private var attachButton: some View {
        Button {
            pickAttachments()
        } label: {
            Image(systemName: "paperclip.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(viewModel.hasPendingUserResponse ? Theme.textTertiary : Theme.textSecondary)
        }
        .buttonStyle(.borderless)
        .disabled(!canAttachMoreFiles)
        .help("Attach up to 5 PDF, image, or text/code files, 5 MB total")
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacingSM) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func attachmentChip(_ attachment: BuilderMessageAttachment) -> some View {
        if attachment.kind == .image {
            imageAttachmentChip(attachment)
        } else {
            fileAttachmentChip(attachment)
        }
    }

    private func imageAttachmentChip(_ attachment: BuilderMessageAttachment) -> some View {
        let imagePreview = attachment.imageData.flatMap(NSImage.init(data:))
        let previewSize = imagePreview.map(composerAttachmentPreviewSize(for:)) ?? CGSize(
            width: composerAttachmentPreviewMaxWidth,
            height: composerAttachmentPreviewMaxHeight
        )

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .fill(Theme.accent.opacity(0.08))
                    .frame(width: previewSize.width, height: previewSize.height)
                    .overlay {
                        Group {
                            if let imagePreview {
                                Image(nsImage: imagePreview)
                                    .resizable()
                                    .interpolation(.high)
                                    .antialiased(true)
                                    .scaledToFit()
                                    .padding(4)
                            } else {
                                Image(systemName: attachment.systemImageName)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(width: previewSize.width, height: previewSize.height)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08))
                    }

                Button {
                    attachments.removeAll { $0.id == attachment.id }
                    clearPendingMessageAction()
                    composerError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.95), Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(6)
            }

            Text(attachment.previewViewMentionTag ?? "Image")
                .font(Theme.geist(11, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(attachment.sizeDescription)
                .font(Theme.geistMono(10))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(width: previewSize.width, alignment: .leading)
        .help(attachment.filename)
    }

    private func fileAttachmentChip(_ attachment: BuilderMessageAttachment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.systemImageName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.previewViewMentionTag ?? attachment.filename)
                    .font(Theme.geist(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text("\(attachment.displayKind) • \(attachment.sizeDescription)")
                    .font(Theme.geistMono(10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Button {
                attachments.removeAll { $0.id == attachment.id }
                clearPendingMessageAction()
                composerError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Theme.accent.opacity(0.08))
        )
    }

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            if showsPlaceholder {
                Text(placeholderText)
                    .foregroundStyle(Theme.textTertiary)
                    .font(Theme.geist(13))
                    .padding(.leading, 4)
                    .padding(.top, inlineSkillEditorVerticalInset)
                    .allowsHitTesting(false)
            }

            InlineSkillTextEditor(
                text: $input,
                highlightedSkillNames: skillNameSet,
                highlightedPreviewViewNames: previewViewNameSet,
                isFocused: $isFocused,
                height: $editorHeight,
                pendingSelectionLocation: $pendingSelectionLocation,
                isEditable: !viewModel.hasPendingUserResponse,
                minHeight: inlineSkillEditorMinHeight,
                maxHeight: inlineSkillEditorMaxHeight,
                onPastePasteboard: importPasteboardAttachments(_:),
                onDropPasteboard: importPasteboardAttachments(_:),
                onDropTargetChange: { isDropTargeted = $0 },
                onSubmit: {
                    if let firstView = filteredViewSuggestions.first {
                        selectPreviewView(firstView)
                    } else if let firstSkill = filteredSkillSuggestions.first {
                        selectSkill(firstSkill)
                    } else {
                        send()
                    }
                }
            )
            .frame(height: editorHeight)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(ProjectMode.allCases, id: \.self) { m in
                let isActive = viewModel.mode == m
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.mode = m
                    }
                } label: {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: m.icon)
                            .font(.system(size: 11, weight: .medium))
                            .frame(height: 13)
                        Text(m.label)
                            .font(Theme.geist(12, weight: isActive ? .semibold : .regular))
                            .baselineOffset(-0.5)
                    }
                    .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .fill(Theme.textPrimary.opacity(0.08))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating || viewModel.hasPendingUserResponse)
            }
            .opacity((viewModel.isGenerating || viewModel.hasPendingUserResponse) ? 0.4 : 1.0)
        }
    }

    // MARK: - Queue Section

    private var queueSection: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)

            HStack {
                Text("Queued")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.top, 6)
            .padding(.bottom, 2)

            ForEach(Array(viewModel.messageQueue.enumerated()), id: \.element.id) { index, msg in
                queueItemRow(msg: msg, index: index, total: viewModel.messageQueue.count)
            }
            .padding(.bottom, 4)
        }
    }

    private func queueItemRow(msg: BuilderViewModel.QueuedMessage, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.spacingXS) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)

                HStack(spacing: 2) {
                    Image(systemName: msg.mode.icon)
                        .font(.system(size: 8))
                    Text(msg.mode.label)
                        .font(Theme.geist(9, weight: .medium))
                }
                .foregroundStyle(Theme.accent.opacity(0.8))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent.opacity(0.1)))

                Text(queuePreviewText(for: msg))
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(expandedQueueItem == msg.id ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            expandedQueueItem = expandedQueueItem == msg.id ? nil : msg.id
                        }
                    }

                // Edit — load into input field
                Button {
                    input = Self.composerInputText(text: msg.text, requiredSkillNames: msg.requiredSkillNames)
                    attachments = msg.attachments
                    restorePendingMessageAction(msg.action)
                    composerError = nil
                    withAnimation {
                        viewModel.removeQueuedMessage(at: index)
                    }
                    isFocused = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Edit message")

                if index > 0 {
                    Button {
                        withAnimation {
                            viewModel.messageQueue.move(
                                fromOffsets: IndexSet(integer: index),
                                toOffset: index - 1
                            )
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if index < total - 1 {
                    Button {
                        withAnimation {
                            viewModel.messageQueue.move(
                                fromOffsets: IndexSet(integer: index),
                                toOffset: index + 2
                            )
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation {
                        viewModel.removeQueuedMessage(at: index)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingXS)
    }

    private func queuePreviewText(for message: BuilderViewModel.QueuedMessage) -> String {
        let skillsSummary = message.requiredSkillNames.isEmpty
            ? nil
            : "Skills: \(message.requiredSkillNames.map { "/\($0)" }.joined(separator: ", "))"
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if message.attachments.isEmpty {
                if let skillsSummary {
                    return "\(skillsSummary)\n\(trimmed)"
                }
                return trimmed
            }
            let attachmentSummary = message.attachments.prefix(2).map(\.queueSummary).joined(separator: ", ")
            let extraCount = max(message.attachments.count - 2, 0)
            let suffix = extraCount > 0 ? ", +\(extraCount) more" : ""
            var sections: [String] = []
            if let skillsSummary {
                sections.append(skillsSummary)
            }
            sections.append(trimmed)
            sections.append("Attachments: \(attachmentSummary)\(suffix)")
            return sections.joined(separator: "\n")
        }

        if message.attachments.isEmpty {
            return skillsSummary ?? ""
        }

        let attachmentSummary = message.attachments.prefix(3).map(\.queueSummary).joined(separator: ", ")
        let extraCount = max(message.attachments.count - 3, 0)
        let suffix = extraCount > 0 ? ", +\(extraCount) more" : ""
        if let skillsSummary {
            return "\(skillsSummary)\nAttachments: \(attachmentSummary)\(suffix)"
        }
        return "Attachments: \(attachmentSummary)\(suffix)"
    }

    // MARK: - Send

    private func send() {
        if let composerError, !composerError.isEmpty {
            return
        }
        // Credits are unlimited in 11x local cockpit — no gating
        if let validationError {
            composerError = validationError
            return
        }

        Task { @MainActor in
            guard let token = await auth.validAccessToken() else { return }
            let draftText = preparedDraft.text

            if let error = viewModel.sendMessage(
                draftText,
                attachments: attachments,
                accessToken: token,
                requiredSkillNames: preparedDraft.requiredSkillNames,
                action: pendingMessageAction
            ) {
                composerError = error
                if ProjectEnvironmentSecurity.secretPasteWarning(in: draftText) != nil {
                    input = ""
                    attachments = []
                    clearPendingMessageAction()
                }
                return
            }

            input = ""
            attachments = []
            clearPendingMessageAction()
            composerError = nil
        }
    }

    private func selectSkill(_ skill: SkillRegistryEntry) {
        guard let skillSearchContext else { return }
        let replacementBase = "/\(skill.name)"
        let trailingText = input[skillSearchContext.tokenRange.upperBound...]
        let needsTrailingSpace = trailingText.first.map { !$0.isWhitespace } ?? true
        let replacement = needsTrailingSpace ? "\(replacementBase) " : replacementBase
        let cursorLocation = input.distance(from: input.startIndex, to: skillSearchContext.tokenRange.lowerBound)
            + (replacement as NSString).length
        input.replaceSubrange(skillSearchContext.tokenRange, with: replacement)
        pendingSelectionLocation = cursorLocation
        composerError = nil
        isFocused = true
    }

    private func selectPreviewView(_ capture: PreviewScreenCapture) {
        guard let viewSearchContext,
              let attachment = viewModel.previewScreenAttachment(for: capture)
        else { return }

        let nextAttachments = mergedAttachments(adding: [attachment])
        if let error = viewModel.validateDraft(text: preparedDraft.text, attachments: nextAttachments) {
            composerError = error
            return
        }

        let replacementBase = capture.chatMentionTag
        let trailingText = input[viewSearchContext.tokenRange.upperBound...]
        let needsTrailingSpace = trailingText.first.map { !$0.isWhitespace } ?? true
        let replacement = needsTrailingSpace ? "\(replacementBase) " : replacementBase
        let cursorLocation = input.distance(from: input.startIndex, to: viewSearchContext.tokenRange.lowerBound)
            + (replacement as NSString).length

        input.replaceSubrange(viewSearchContext.tokenRange, with: replacement)
        attachments = nextAttachments
        clearPendingMessageAction()
        pendingSelectionLocation = cursorLocation
        composerError = nil
        isFocused = true
    }

    private func appendPreviewViewMentions(_ viewNames: [String]) {
        var existing = Set(selectedPreviewViewNames)
        let tags = viewNames.compactMap { rawName -> String? in
            let normalized = Self.normalizedPreviewViewMentionName(rawName)
            guard !normalized.isEmpty, existing.insert(normalized).inserted else { return nil }
            return BuilderMessageAttachment.previewViewMentionTag(for: rawName)
        }

        guard !tags.isEmpty else {
            isFocused = true
            return
        }

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let appendedTags = tags.joined(separator: " ")
        if trimmedInput.isEmpty {
            input = appendedTags
        } else if input.last?.isWhitespace == true {
            input += appendedTags
        } else {
            input += " " + appendedTags
        }

        if input.last?.isWhitespace != true {
            input += " "
        }

        pendingSelectionLocation = (input as NSString).length
        composerError = nil
        isFocused = true
    }

    private func mergedAttachments(adding incoming: [BuilderMessageAttachment]) -> [BuilderMessageAttachment] {
        var merged = attachments

        for attachment in incoming {
            if let previewViewName = attachment.previewViewName,
               merged.contains(where: {
                   $0.previewViewName?.caseInsensitiveCompare(previewViewName) == .orderedSame
               }) {
                continue
            }

            if merged.contains(where: { $0.id == attachment.id }) {
                continue
            }

            merged.append(attachment)
        }

        return merged
    }

    private func prepareDraft(from rawText: String) -> PreparedDraft {
        var sanitizedText = rawText
        if let skillSearchContext = Self.skillSearchContext(in: sanitizedText) {
            sanitizedText.removeSubrange(skillSearchContext.tokenRange)
        }
        if let viewSearchContext = Self.viewSearchContext(in: sanitizedText) {
            sanitizedText.removeSubrange(viewSearchContext.tokenRange)
        }

        let inlineSkillNames = Self.recognizedInlineSkillNames(in: sanitizedText, availableSkillNames: skillNameSet)
        sanitizedText = Self.removingRecognizedInlineSkillTags(
            from: sanitizedText,
            availableSkillNames: skillNameSet
        )

        return PreparedDraft(
            text: sanitizedText.trimmingCharacters(in: .whitespacesAndNewlines),
            requiredSkillNames: inlineSkillNames
        )
    }

    private static func skillSearchContext(in text: String) -> TokenSearchContext? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?:(?<=^)|(?<=\s))/([a-z0-9-]*)$"#,
                options: [.caseInsensitive]
            )
        else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: nsRange),
            let tokenRange = Range(match.range, in: text),
            let queryRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return TokenSearchContext(
            tokenRange: tokenRange,
            query: String(text[queryRange])
        )
    }

    private static func viewSearchContext(in text: String) -> TokenSearchContext? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?:(?<=^)|(?<=\s))@([A-Za-z0-9_]*)$"#,
                options: [.caseInsensitive]
            )
        else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: nsRange),
            let tokenRange = Range(match.range, in: text),
            let queryRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return TokenSearchContext(
            tokenRange: tokenRange,
            query: String(text[queryRange])
        )
    }

    private static func recognizedInlineSkillNames(
        in text: String,
        availableSkillNames: Set<String>
    ) -> [String] {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?:(?<=^)|(?<=\s))/([a-z0-9][a-z0-9-]*)"#,
                options: [.caseInsensitive]
            )
        else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        let names = regex.matches(in: text, range: nsRange).compactMap { match -> String? in
            let rawName = nsText.substring(with: match.range(at: 1)).lowercased()
            return availableSkillNames.contains(rawName) ? rawName : nil
        }
        return orderedUniqueSkillNames(names)
    }

    private static func recognizedInlinePreviewViewNames(
        in text: String,
        availablePreviewViewNames: Set<String>
    ) -> [String] {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?:(?<=^)|(?<=\s))@([A-Za-z0-9_]+)"#,
                options: [.caseInsensitive]
            )
        else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        let names = regex.matches(in: text, range: nsRange).compactMap { match -> String? in
            let rawName = nsText.substring(with: match.range(at: 1))
            let normalized = normalizedPreviewViewMentionName(rawName)
            return availablePreviewViewNames.contains(normalized) ? normalized : nil
        }
        return orderedUniqueNormalizedNames(names)
    }

    private static func removingRecognizedInlineSkillTags(
        from text: String,
        availableSkillNames: Set<String>
    ) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?:(?<=^)|(?<=\s))/([a-z0-9][a-z0-9-]*)"#,
                options: [.caseInsensitive]
            )
        else {
            return text
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: nsRange)

        for match in matches.reversed() {
            let rawName = nsText.substring(with: match.range(at: 1)).lowercased()
            guard availableSkillNames.contains(rawName) else { continue }
            mutable.replaceCharacters(in: match.range, with: "")
        }

        return mutable as String
    }

    private static func orderedUniqueSkillNames(_ skillNames: [String]) -> [String] {
        orderedUniqueNormalizedNames(skillNames)
    }

    private static func orderedUniqueNormalizedNames(_ rawNames: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for rawName in rawNames {
            let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    fileprivate static func normalizedPreviewViewMentionName(_ rawName: String) -> String {
        BuilderMessageAttachment.normalizedPreviewViewMentionName(rawName)
    }

    private static func composerInputText(text: String, requiredSkillNames: [String]) -> String {
        let tags = orderedUniqueSkillNames(requiredSkillNames).map { "/\($0)" }.joined(separator: " ")
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (tags.isEmpty, trimmedText.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return tags
        case (true, false):
            return trimmedText
        case (false, false):
            return "\(tags) \(trimmedText)"
        }
    }

    private func syncPickerPresentations() {
        skillPickerPresentation = ChatSkillPickerPresentation(
            isPresented: showsSkillPicker,
            suggestions: showsSkillPicker ? filteredSkillSuggestions : [],
            isLoading: viewModel.isLoadingSkills && viewModel.availableSkills.isEmpty
        )

        viewPickerPresentation = ChatViewPickerPresentation(
            isPresented: showsViewPicker,
            suggestions: showsViewPicker ? filteredViewSuggestions : []
        )
    }

    private func pickAttachments() {
        if let error = BuilderAttachmentPolicy.validationError(for: attachments) {
            composerError = error
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = BuilderAttachmentImporter.allowedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        let nextCount = attachments.count + panel.urls.count
        if nextCount > BuilderAttachmentPolicy.maxItemCount {
            composerError = "You can attach up to \(BuilderAttachmentPolicy.maxItemCount) files per message."
            return
        }

        let (imported, errors) = BuilderAttachmentPasteboardSupport.importedAttachments(from: panel.urls)
        applyImportedAttachments(imported, errors: errors)
    }

    private func importPasteboardAttachments(_ pasteboard: NSPasteboard) -> Bool {
        var imported: [BuilderMessageAttachment] = []
        var errors: [String] = []
        var handled = false

        for data in droppedPreviewAttachmentPayloads(from: pasteboard) {
            handled = true
            if let attachment = droppedPreviewAttachment(from: data) {
                imported.append(attachment)
            }
        }

        let urls = BuilderAttachmentPasteboardSupport.fileURLs(from: pasteboard)
        if !urls.isEmpty {
            handled = true
            for url in urls {
                if let attachment = droppedPreviewAttachment(from: url) {
                    imported.append(attachment)
                    continue
                }

                let result = BuilderAttachmentPasteboardSupport.importedAttachments(from: [url])
                imported.append(contentsOf: result.attachments)
                errors.append(contentsOf: result.errors)
            }
        }

        guard handled else { return false }
        if imported.isEmpty, errors.isEmpty {
            errors.append("Couldn’t attach dropped item.")
        }
        applyImportedAttachments(imported, errors: errors)
        return true
    }

    private func droppedPreviewAttachment(from data: Data) -> BuilderMessageAttachment? {
        if let attachment = try? JSONDecoder().decode(BuilderMessageAttachment.self, from: data) {
            return attachment
        }
        guard let id = String(data: data, encoding: .utf8),
              let capture = viewModel.previewScreenCapture(withID: id) else {
            return nil
        }
        return viewModel.previewScreenAttachment(for: capture)
    }

    private func droppedPreviewAttachmentPayloads(from pasteboard: NSPasteboard) -> [Data] {
        let type = NSPasteboard.PasteboardType(UTType.tenXPreviewScreen.identifier)
        var orderedPayloads: [Data] = []
        var seenPayloads = Set<Data>()

        func append(_ data: Data?) {
            guard let data, seenPayloads.insert(data).inserted else { return }
            orderedPayloads.append(data)
        }

        func append(_ string: String?) {
            guard let string else { return }
            append(string.data(using: .utf8))
        }

        append(pasteboard.data(forType: type))
        append(pasteboard.string(forType: type))
        pasteboard.pasteboardItems?.forEach {
            append($0.data(forType: type))
            append($0.string(forType: type))
        }
        return orderedPayloads
    }

    private func droppedPreviewAttachment(from url: URL) -> BuilderMessageAttachment? {
        let resolvedURL = url.standardizedFileURL
        guard let capture = viewModel.developmentScreenLibrary.first(where: { capture in
            guard let captureURL = viewModel.previewScreenImageURL(for: capture) else { return false }
            return captureURL.standardizedFileURL == resolvedURL
        }) else {
            return nil
        }
        return viewModel.previewScreenAttachment(for: capture)
    }

    private func applyImportedAttachments(_ imported: [BuilderMessageAttachment], errors: [String]) {
        guard !imported.isEmpty || !errors.isEmpty else { return }

        let nextAttachments = mergedAttachments(adding: imported)
        var nextErrors = errors
        if nextErrors.isEmpty, let error = BuilderAttachmentPolicy.validationError(for: nextAttachments) {
            nextErrors.append(error)
        }

        if nextErrors.isEmpty, !imported.isEmpty {
            attachments = nextAttachments
            clearPendingMessageAction()
            composerError = nil
        } else {
            composerError = nextErrors.first
        }
        isFocused = true
    }

    private func clearPendingMessageAction() {
        pendingMessageAction = nil
        pendingMessageActionInputSnapshot = nil
    }

    private func restorePendingMessageAction(_ action: BuilderMessageAction?) {
        pendingMessageAction = action
        pendingMessageActionInputSnapshot = action == nil ? nil : input
    }
}

private struct InlineSkillTextEditor: NSViewRepresentable {
    @Binding var text: String
    let highlightedSkillNames: Set<String>
    let highlightedPreviewViewNames: Set<String>
    @Binding var isFocused: Bool
    @Binding var height: CGFloat
    @Binding var pendingSelectionLocation: Int?
    let isEditable: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onPastePasteboard: (NSPasteboard) -> Bool
    let onDropPasteboard: (NSPasteboard) -> Bool
    let onDropTargetChange: (Bool) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InlineSkillNSTextView()
        textView.delegate = context.coordinator
        textView.submitHandler = onSubmit
        textView.pasteHandler = onPastePasteboard
        textView.dropHandler = onDropPasteboard
        textView.dropTargetChanged = onDropTargetChange
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = inlineSkillEditorFont
        textView.textColor = .textColor
        textView.insertionPointColor = .white
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: inlineSkillEditorVerticalInset)
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: 10_000, height: 10_000)
        textView.autoresizingMask = [.width]
        textView.registerForDraggedTypes([
            NSPasteboard.PasteboardType(UTType.tenXPreviewScreen.identifier),
            .fileURL,
            .URL,
        ])

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
        guard let textView = scrollView.documentView as? InlineSkillNSTextView else { return }
        textView.submitHandler = onSubmit
        textView.pasteHandler = onPastePasteboard
        textView.dropHandler = onDropPasteboard
        textView.dropTargetChanged = onDropTargetChange
        textView.isEditable = isEditable
        context.coordinator.sync(textView: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineSkillTextEditor
        private var isApplyingUpdate = false
        private var renderedHighlightedSkillNames: Set<String> = []
        private var renderedHighlightedPreviewViewNames: Set<String> = []

        init(parent: InlineSkillTextEditor) {
            self.parent = parent
        }

        func sync(textView: InlineSkillNSTextView) {
            if textView.string != parent.text
                || renderedHighlightedSkillNames != parent.highlightedSkillNames
                || renderedHighlightedPreviewViewNames != parent.highlightedPreviewViewNames
                || parent.pendingSelectionLocation != nil
            {
                applyContent(to: textView)
            } else {
                updateHeight(for: textView)
            }

            syncFocus(for: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard !isApplyingUpdate else { return }
            if !parent.isFocused {
                DispatchQueue.main.async {
                    self.parent.isFocused = true
                }
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            guard !isApplyingUpdate else { return }
            if parent.isFocused {
                DispatchQueue.main.async {
                    self.parent.isFocused = false
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                  let textView = notification.object as? InlineSkillNSTextView else { return }

            if parent.text != textView.string {
                parent.text = textView.string
            }

            applyContent(to: textView)
        }

        private func applyContent(to textView: InlineSkillNSTextView) {
            let selectedRange = textView.selectedRange()
            let attributed = NSMutableAttributedString(
                string: parent.text,
                attributes: [
                    .font: inlineSkillEditorFont,
                    .foregroundColor: NSColor.textColor,
                ]
            )

            if let regex = try? NSRegularExpression(
                pattern: #"(?:(?<=^)|(?<=\s))/([a-z0-9][a-z0-9-]*)"#,
                options: [.caseInsensitive]
            ) {
                let nsRange = NSRange(parent.text.startIndex..<parent.text.endIndex, in: parent.text)
                let nsText = parent.text as NSString
                for match in regex.matches(in: parent.text, range: nsRange) {
                    let rawName = nsText.substring(with: match.range(at: 1)).lowercased()
                    guard parent.highlightedSkillNames.contains(rawName) else { continue }
                    attributed.addAttributes(
                        [
                            .font: inlineSkillTagFont,
                            .foregroundColor: NSColor.systemOrange,
                        ],
                        range: match.range
                    )
                }
            }

            if let regex = try? NSRegularExpression(
                pattern: #"(?:(?<=^)|(?<=\s))@([A-Za-z0-9_]+)"#,
                options: [.caseInsensitive]
            ) {
                let nsRange = NSRange(parent.text.startIndex..<parent.text.endIndex, in: parent.text)
                let nsText = parent.text as NSString
                for match in regex.matches(in: parent.text, range: nsRange) {
                    let rawName = nsText.substring(with: match.range(at: 1))
                    let normalized = ChatInputView.normalizedPreviewViewMentionName(rawName)
                    guard parent.highlightedPreviewViewNames.contains(normalized) else { continue }
                    attributed.addAttributes(
                        [
                            .font: inlineSkillTagFont,
                            .foregroundColor: NSColor.systemBlue,
                        ],
                        range: match.range
                    )
                }
            }

            isApplyingUpdate = true
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = [
                .font: inlineSkillEditorFont,
                .foregroundColor: NSColor.textColor,
            ]
            renderedHighlightedSkillNames = parent.highlightedSkillNames
            renderedHighlightedPreviewViewNames = parent.highlightedPreviewViewNames

            let preferredLocation = parent.pendingSelectionLocation ?? selectedRange.location
            let clampedLocation = min(preferredLocation, attributed.length)
            let clampedLength = min(selectedRange.length, max(0, attributed.length - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            isApplyingUpdate = false

            if parent.pendingSelectionLocation != nil {
                DispatchQueue.main.async {
                    self.parent.pendingSelectionLocation = nil
                }
            }

            updateHeight(for: textView)
        }

        private func syncFocus(for textView: InlineSkillNSTextView) {
            guard let window = textView.window else { return }
            if parent.isFocused {
                if window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            } else if window.firstResponder === textView {
                window.makeFirstResponder(nil)
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

private final class InlineSkillNSTextView: NSTextView {
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
        let previewType = NSPasteboard.PasteboardType(UTType.tenXPreviewScreen.identifier)
        if pasteboard.types?.contains(previewType) == true {
            return true
        }
        if pasteboard.pasteboardItems?.contains(where: { $0.types.contains(previewType) }) == true {
            return true
        }
        if pasteboard.canReadItem(withDataConformingToTypes: [previewType.rawValue]) {
            return true
        }
        if pasteboard.pasteboardItems?.contains(where: { $0.availableType(from: [previewType]) != nil }) == true {
            return true
        }

        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: fileOptions) {
            return true
        }
        if BuilderAttachmentPasteboardSupport.hasImportableFileURLs(on: pasteboard) {
            return true
        }

        return false
    }
}
