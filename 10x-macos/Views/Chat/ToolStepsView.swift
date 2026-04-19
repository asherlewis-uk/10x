import SwiftUI

/// Claude Code-style collapsible tool steps indicator.
/// Shows each tool call with a specific icon, spinner/checkmark, and duration.
/// Individual steps are expandable to show input/output details.
struct ToolStepsView: View {
    let steps: [BuilderToolStep]

    @State private var isExpanded = true
    @State private var expandedStepIds: Set<UUID> = []

    private var isAllDone: Bool {
        !steps.isEmpty && steps.allSatisfy { $0.status != .running }
    }

    private var totalDuration: Int {
        steps
            .filter { $0.name != "read_files" }
            .compactMap(\.durationMs)
            .reduce(0, +)
    }

    private var groupedSections: [BuilderToolStepGroup] {
        steps.contiguousToolGroups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary header (clickable to expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 12)

                    if isAllDone {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 11, height: 11)
                    }

                    Text(summaryText)
                        .font(Theme.geistMono(12, weight: .medium))
                        .baselineOffset(-0.5)
                        .foregroundStyle(Theme.textSecondary)

                    if isAllDone && totalDuration > 0 {
                        Text(formatDuration(totalDuration))
                            .font(Theme.geistMono(11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Expanded step list
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groupedSections) { section in
                        sectionView(section)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private var summaryText: String {
        if isAllDone {
            let parts = groupedSections.map { section in
                "\(section.steps.count) \(BuilderToolPresentation.summaryLabel(name: section.name, count: section.steps.count))"
            }
            if parts.isEmpty { return "Used \(steps.count) tool\(steps.count == 1 ? "" : "s")" }
            return parts.joined(separator: ", ")
        } else {
            if let running = steps.last(where: { $0.status == .running }) {
                return displayLabel(for: running)
            }
            return "Working..."
        }
    }

    private func sectionView(_ section: BuilderToolStepGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let representativeStep = section.steps.first {
                    toolIcon(for: representativeStep)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 12, height: 12)
                }

                Text(BuilderToolPresentation.groupTitle(name: section.name))
                    .font(Theme.geistMono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)

                Text("\(section.steps.count)")
                    .font(Theme.geistMono(10))
                    .foregroundStyle(Theme.textTertiary.opacity(0.8))

                Spacer()
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(section.steps) { step in
                    stepRow(step)
                }
            }
            .padding(.leading, 14)
        }
    }

    private func stepRow(_ step: BuilderToolStep) -> some View {
        let hasDetail = step.inputPreview != nil || step.outputPreview != nil
        let isStepExpanded = expandedStepIds.contains(step.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                if hasDetail {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        if isStepExpanded {
                            expandedStepIds.remove(step.id)
                        } else {
                            expandedStepIds.insert(step.id)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // Tool-specific icon
                    toolIcon(for: step)
                        .font(.system(size: 10))
                        .foregroundStyle(iconColor(for: step))
                        .frame(width: 14, height: 14)

                    // Status indicator
                    Group {
                        switch step.status {
                        case .running:
                            ProgressView()
                                .controlSize(.mini)
                        case .success:
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                        case .error:
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.error)
                        }
                    }
                    .frame(width: 10, height: 10)

                    Text(displayLabel(for: step))
                        .font(Theme.geist(11))
                        .foregroundStyle(step.status == .running ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)

                    if let ms = step.durationMs, step.name != "read_files" {
                        Text(formatDuration(ms))
                            .font(Theme.geistMono(10))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    // Expand indicator for steps with detail
                    if hasDetail && step.status != .running {
                        Image(systemName: isStepExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
            .opacity(isReadOp(step.name) && !isStepExpanded ? 0.6 : 1.0)

            // Expanded detail view
            if isStepExpanded, hasDetail {
                detailView(for: step)
                    .padding(.leading, 24)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
            }
        }
    }

    private func detailView(for step: BuilderToolStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let input = step.inputPreview, !input.isEmpty {
                detailSection(title: "Input", content: input)
            }
            if let output = step.outputPreview, !output.isEmpty {
                detailSection(title: "Output", content: output)
            }
        }
    }

    private func displayLabel(for step: BuilderToolStep) -> String {
        if step.name == "update_project_dependencies",
           step.inputPreview?.contains("dependencies: none") == true {
            return "Confirming no setup requirements"
        }
        return step.label
    }

    private func detailSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.geistMono(9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)

            Text(content.prefix(1500))
                .font(Theme.geistMono(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(12)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }

    @ViewBuilder
    private func toolIcon(for step: BuilderToolStep) -> some View {
        switch step.name {
        case "write_file":
            Image(systemName: "doc.badge.plus")
        case "read_files":
            Image(systemName: "doc.text")
        case "delete_file":
            Image(systemName: "trash")
        case "list_files":
            Image(systemName: "folder")
        case "search_files":
            Image(systemName: "magnifyingglass")
        case "web_search":
            Image(systemName: "globe")
        case "scrape_url":
            Image(systemName: "doc.text.magnifyingglass")
        case "update_project_status":
            Image(systemName: "list.bullet.clipboard")
        case "update_project_dependencies":
            Image(systemName: "checklist")
        case "update_app_store_assets", "update_app_store_review_assets":
            Image(systemName: "sparkles.rectangle.stack")
        case "set_project_identity":
            Image(systemName: "app.badge")
        case "change_mode":
            Image(systemName: "arrow.triangle.2.circlepath")
        case "ask_user":
            Image(systemName: "questionmark.bubble")
        case "run_command":
            Image(systemName: "terminal")
        case "edit_file":
            Image(systemName: "pencil")
        case "list_skills":
            Image(systemName: "books.vertical")
        case "use_skill":
            Image(systemName: "graduationcap")
        default:
            Image(systemName: "wrench")
        }
    }

    private func iconColor(for step: BuilderToolStep) -> Color {
        switch step.name {
        case "write_file": .green
        case "edit_file": Theme.accent
        case "delete_file": Theme.error
        case "web_search", "scrape_url": .blue
        case "search_files": .purple
        case "run_command": .cyan
        case "list_skills", "use_skill": .orange
        case "update_project_status", "update_project_dependencies", "set_project_identity", "change_mode", "update_app_store_assets", "update_app_store_review_assets": Theme.accent
        case "read_files", "list_files": Theme.textTertiary
        default: Theme.textSecondary
        }
    }

    private func isReadOp(_ name: String) -> Bool {
        ["read_files", "list_files", "search_files", "scrape_url"].contains(name)
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }
}
