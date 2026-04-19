import SwiftUI

/// Full-tab design view showing brand identity, colors, fonts, design style,
/// and other onboarding selections. Replaces the old moodboard canvas section.
struct DesignView: View {
    @Environment(BuilderViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // App identity
                appIdentitySection

                // Design style
                if let style = viewModel.designStyle {
                    designStyleSection(style)
                }

                // Color palette
                if !extractedColors.isEmpty {
                    colorPaletteSection
                }

                // Target audience
                if let data = viewModel.onboardingData, !data.targetAudience.isEmpty {
                    targetAudienceSection(data)
                }

                // Additional details
                if let data = viewModel.onboardingData, !data.additionalDetails.isEmpty {
                    detailsSection(data)
                }

                // Design notes from plan
                if !designNotesMarkdown.isEmpty {
                    designNotesSection
                }

                // Asset gallery
                if !assetFiles.isEmpty {
                    assetGallerySection
                }

                // Empty state
                if viewModel.designStyle == nil && extractedColors.isEmpty && designNotesMarkdown.isEmpty && assetFiles.isEmpty && viewModel.onboardingData == nil {
                    emptyState
                }
            }
            .padding(Theme.spacingXL)
        }
        .background(Theme.surfaceInset)
    }

    // MARK: - Sections

    private var appIdentitySection: some View {
        HStack(spacing: 14) {
            if let icon = viewModel.projectIcon {
                Image(nsImage: icon).resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.activeProject?.name ?? "Untitled")
                    .font(Theme.geist(18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let desc = viewModel.activeProject?.description, !desc.isEmpty {
                    Text(desc)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(3)
                }
            }
        }
    }

    private func designStyleSection(_ style: DesignStyle) -> some View {
        sectionCard(label: "DESIGN STYLE", icon: style.iconName, iconColor: .purple) {
            VStack(alignment: .leading, spacing: 4) {
                Text(style.label)
                    .font(Theme.geist(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(style.subtitle)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
                Text(style.examples.joined(separator: ", "))
                    .font(Theme.geist(10))
                    .foregroundStyle(Theme.textTertiary)
                    .italic()
            }
        }
    }

    private var colorPaletteSection: some View {
        sectionCard(label: "COLOR PALETTE", icon: "paintpalette.fill", iconColor: .pink) {
            HStack(spacing: 12) {
                ForEach(extractedColors, id: \.name) { c in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(c.color)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                            .shadow(color: c.color.opacity(0.3), radius: 4, y: 1)
                        Text(c.name)
                            .font(Theme.geistMono(9, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    private func targetAudienceSection(_ data: OnboardingData) -> some View {
        sectionCard(label: "TARGET AUDIENCE", icon: "person.3.fill", iconColor: .blue) {
            HStack(spacing: 6) {
                ForEach(data.targetAudience) { audience in
                    HStack(spacing: 4) {
                        Image(systemName: audience.iconName).font(.system(size: 9))
                        Text(audience.label).font(Theme.geist(11, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.surface))
                }
            }
        }
    }

    private func detailsSection(_ data: OnboardingData) -> some View {
        sectionCard(label: "ADDITIONAL DETAILS", icon: "doc.text.fill", iconColor: .orange) {
            MarkdownTextView(text: data.additionalDetails, animateTransitions: false)
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var designNotesSection: some View {
        sectionCard(label: "DESIGN NOTES", icon: "paintbrush.pointed.fill", iconColor: .pink) {
            MarkdownTextView(text: designNotesMarkdown, animateTransitions: false)
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assetGallerySection: some View {
        sectionCard(label: "ASSETS (\(assetFiles.count))", icon: "photo.on.rectangle.angled", iconColor: .indigo) {
            let cols = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: Theme.spacingMD)]
            LazyVGrid(columns: cols, spacing: Theme.spacingMD) {
                ForEach(assetFiles.prefix(12), id: \.path) { file in
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .fill(Color(nsColor: .separatorColor).opacity(0.04))
                            if let pp = viewModel.localProjectPath {
                                AsyncImageFileView(url: pp.appendingPathComponent(file.path))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
                            }
                        }
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.1), lineWidth: 0.5)
                        )
                        Text((file.path as NSString).lastPathComponent)
                            .font(Theme.geistMono(9))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            if assetFiles.count > 12 {
                Text("+ \(assetFiles.count - 12) more")
                    .font(Theme.geist(10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "paintbrush")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textTertiary.opacity(0.25))
            Text("Design")
                .font(Theme.geist(13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("Brand colors, fonts, and design style will appear here after onboarding")
                .font(Theme.geist(11))
                .foregroundStyle(Theme.textTertiary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(label: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10)).foregroundStyle(iconColor)
                Text(label)
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.5)
            }
            content()
        }
        .padding(Theme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMD)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Data

    private var extractedColors: [(name: String, color: Color)] {
        let defaults: [(String, Color)] = [
            ("Primary", Theme.accent),
            ("Surface", Theme.surfaceElevated),
            ("Text", Theme.textPrimary),
            ("Success", Theme.success),
            ("Error", Theme.error),
        ]
        guard let plan = viewModel.projectPlan else { return defaults }
        let hexPattern = /#([0-9A-Fa-f]{6})\b/
        var found: [(String, Color)] = []
        for match in plan.matches(of: hexPattern).prefix(6) {
            let hex = String(match.output.1)
            found.append((hex, Color(hex: hex)))
        }
        return found.isEmpty ? defaults : found
    }

    private var designNotesMarkdown: String {
        guard let plan = viewModel.projectPlan else { return "" }

        let sectionKeywords = [
            "design",
            "visual",
            "brand",
            "style",
            "theme",
            "palette",
            "typography",
            "color",
            "colour",
            "layout",
            "icon",
            "logo",
        ]

        let extractedSections = extractMarkdownSections(from: plan, matching: sectionKeywords)
        if !extractedSections.isEmpty {
            return extractedSections
        }

        return extractMarkdownBlocks(from: plan, matching: sectionKeywords)
    }

    private func extractMarkdownSections(from markdown: String, matching keywords: [String]) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var sections: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let heading = markdownHeading(in: trimmed) else {
                index += 1
                continue
            }

            let title = heading.title.lowercased()
            guard keywords.contains(where: { title.contains($0) }) else {
                index += 1
                continue
            }

            var sectionLines = [lines[index]]
            index += 1

            while index < lines.count {
                let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if let nextHeading = markdownHeading(in: nextTrimmed), nextHeading.level <= heading.level {
                    break
                }
                sectionLines.append(lines[index])
                index += 1
            }

            let section = sectionLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !section.isEmpty {
                sections.append(section)
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private func extractMarkdownBlocks(from markdown: String, matching keywords: [String]) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [String] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            guard !trimmed.isEmpty, keywords.contains(where: { lower.contains($0) }) else {
                index += 1
                continue
            }

            var start = index
            while start > 0 {
                let previous = lines[start - 1].trimmingCharacters(in: .whitespaces)
                if previous.isEmpty {
                    break
                }
                if markdownHeading(in: previous) != nil {
                    start -= 1
                    break
                }
                start -= 1
            }

            var end = index
            while end + 1 < lines.count {
                let next = lines[end + 1].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || markdownHeading(in: next) != nil {
                    break
                }
                end += 1
            }

            let block = lines[start...end]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !block.isEmpty, !blocks.contains(block) {
                blocks.append(block)
            }

            index = end + 1
        }

        return blocks.prefix(3).joined(separator: "\n\n")
    }

    private func markdownHeading(in line: String) -> (level: Int, title: String)? {
        guard line.hasPrefix("#") else { return nil }

        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }

        let title = line
            .dropFirst(level)
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return (level, title)
    }

    private var assetFiles: [(path: String, ext: String)] {
        let exts: Set<String> = ["png","jpg","jpeg","gif","svg","webp","ico","bmp","tiff","pdf"]
        return viewModel.fileTree.keys.compactMap { p in
            let e = (p as NSString).pathExtension.lowercased()
            return exts.contains(e) ? (p, e) : nil
        }.sorted { $0.path < $1.path }
    }
}

// MARK: - Async Image File View

private struct AsyncImageFileView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            image = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }
}
