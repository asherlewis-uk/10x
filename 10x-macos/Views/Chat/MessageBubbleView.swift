import AppKit
import SwiftUI

private let previewAttachmentMaxWidth: CGFloat = 220
private let previewAttachmentMaxHeight: CGFloat = 180

private func previewAttachmentDisplaySize(for image: NSImage) -> CGSize {
    let originalSize = image.pixelDimensions
    guard originalSize.width > 0, originalSize.height > 0 else {
        return CGSize(width: previewAttachmentMaxWidth, height: previewAttachmentMaxHeight)
    }

    let widthScale = previewAttachmentMaxWidth / originalSize.width
    let heightScale = previewAttachmentMaxHeight / originalSize.height
    let scale = min(widthScale, heightScale, 1)

    return CGSize(
        width: max(80, floor(originalSize.width * scale)),
        height: max(80, floor(originalSize.height * scale))
    )
}

struct MessageBubbleView: View {
    let message: BuilderMessage
    var showAssistantFooter: Bool = true
    var assistantCopyText: String? = nil
    @Environment(BuilderViewModel.self) private var viewModel
    @State private var showRevertConfirmation = false
    @State private var isAssistantCopied = false

    private var isUser: Bool { message.role == "user" }
    private var isLive: Bool { message.id == "streaming" }

    /// Strip internal tool-history blocks from display text if they are present.
    private var displayContent: String { message.displayableContent }
    private static let skillTagPalette: [Color] = [
        Color(hex: "FF9F43"),
        Color(hex: "56CCF2"),
        Color(hex: "6FCF97"),
        Color(hex: "BB6BD9"),
        Color(hex: "F2994A"),
        Color(hex: "EB5757"),
    ]
    private var previewViewAttachments: [BuilderMessageAttachment] {
        message.attachments.filter(\.isPreviewViewAttachment)
    }
    private var fileAttachments: [BuilderMessageAttachment] {
        message.attachments.filter { !$0.isPreviewViewAttachment }
    }

    private static func skillTagColor(for skillName: String) -> Color {
        let value = skillName.lowercased().unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return skillTagPalette[value % skillTagPalette.count]
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if isUser {
                HStack(spacing: 0) {
                    Spacer(minLength: 40)
                    userBubble
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 0) {
                    assistantBubble
                    Spacer(minLength: 0)
                }
            }

            if isUser {
                userFooter
            } else if showAssistantFooter && !isLive {
                assistantFooter
            }
        }
    }

    // MARK: - Assistant footer (copy only)

    private var assistantFooter: some View {
        HStack(spacing: 8) {
            Button {
                copyAssistantMessage()
            } label: {
                labelIcon(isCopied: isAssistantCopied)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Copy message")
        }
        .padding(.top, Theme.spacingXS)
    }

    // MARK: - User bubble

    private var userBubble: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            if !message.attachments.isEmpty {
                attachmentListView
            }

            if !message.requiredSkillNames.isEmpty {
                userSkillTagsView
            }

            if !displayContent.isEmpty {
                MarkdownTextView(text: displayContent, animateTransitions: false)
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Color.primary.opacity(0.06))
        )
        .textSelection(.enabled)
    }

    private var userSkillTagsView: some View {
        FlowLayout(spacing: Theme.spacingXS) {
            ForEach(Array(message.requiredSkillNames.enumerated()), id: \.offset) { _, skillName in
                Text("/\(skillName)")
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Self.skillTagColor(for: skillName))
                    .padding(.horizontal, Theme.spacingSM)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Self.skillTagColor(for: skillName).opacity(0.12))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attachmentListView: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            if !previewViewAttachments.isEmpty {
                FlowLayout(spacing: Theme.spacingSM) {
                    ForEach(previewViewAttachments) { attachment in
                        previewAttachmentCard(attachment)
                    }
                }
                .frame(maxWidth: 460, alignment: .leading)
            }

            if !fileAttachments.isEmpty {
                ForEach(fileAttachments) { attachment in
                    attachmentCard(attachment)
                }
            }
        }
    }

    private func previewAttachmentCard(_ attachment: BuilderMessageAttachment) -> some View {
        let imagePreview = attachment.imageData.flatMap(NSImage.init(data:))
        let previewSize = imagePreview.map(previewAttachmentDisplaySize(for:)) ?? .zero

        return VStack(alignment: .leading, spacing: 6) {
            if let imagePreview {
                Image(nsImage: imagePreview)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: previewSize.width, height: previewSize.height, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            }

            if let previewViewName = attachment.previewViewName {
                Text(previewViewName)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: previewSize.width, alignment: .leading)
    }

    private func attachmentCard(_ attachment: BuilderMessageAttachment) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            if let imagePreview = attachment.imageData.flatMap(NSImage.init(data:)) {
                Image(nsImage: imagePreview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 180, maxHeight: 140, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            }

            HStack(spacing: Theme.spacingSM) {
                Image(systemName: attachment.systemImageName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename)
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    Text("\(attachment.displayKind) • \(attachment.sizeDescription)")
                        .font(Theme.geistMono(11))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 0)

                Button {
                    viewModel.revealAttachment(attachment, in: message.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Show in Finder")
                            .font(Theme.geist(11, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.spacingSM)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Theme.textPrimary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Show attached file in Finder")
            }
        }
        .padding(.horizontal, Theme.spacingSM)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(Theme.accent.opacity(0.08))
        )
    }

    // MARK: - Assistant bubble (markdown)

    private var assistantBubble: some View {
        MarkdownTextView(text: displayContent, animateTransitions: false)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .textSelection(.enabled)
    }

    // MARK: - User message footer

    private var userFooter: some View {
        HStack(spacing: 8) {
            if viewModel.isReverting {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.textTertiary)
            } else {
                Button {
                    showRevertConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                        Text("Revert")
                            .font(Theme.geist(12, weight: .medium))
                    }
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingXS)
                    .background(
                        Capsule().fill(Theme.textTertiary.opacity(0.12))
                    )
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Revert project to before this message")
                .disabled(viewModel.isGenerating || viewModel.isReverting)
                .confirmationDialog(
                    "Revert to before this message?",
                    isPresented: $showRevertConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Revert", role: .destructive) {
                        Task { await viewModel.revertToMessage(message.id) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your message will be returned to the input bar and your project files will be restored to the state before it was sent.")
                }
            }
        }
    }

    // MARK: - Mode badge

    private func modeBadge(_ mode: ProjectMode) -> some View {
        HStack(spacing: 4) {
            Image(systemName: mode.icon)
                .font(.system(size: 11, weight: .medium))
            Text(mode.label)
                .font(Theme.geist(11, weight: .medium))
        }
        .foregroundStyle(mode == .plan ? Color.orange.opacity(0.9) : Theme.accent)
        .padding(.horizontal, Theme.spacingSM)
        .padding(.vertical, Theme.spacingXS)
        .background(
            Capsule().fill(mode == .plan ? Color.orange.opacity(0.15) : Theme.accent.opacity(0.15))
        )
    }

    private func copyAssistantMessage() {
        let text = assistantCopyText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? assistantCopyText!
            : displayContent
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        isAssistantCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isAssistantCopied = false }
    }

    private func labelIcon(isCopied: Bool) -> Image {
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
    }
}
