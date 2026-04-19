import SwiftUI

// MARK: - Roadmap Phase Model

private struct RoadmapPhase: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let icon: String
    let status: Status

    enum Status {
        case completed
        case active
        case upcoming
    }
}

// MARK: - View

/// Full-tab roadmap view showing standardized project lifecycle phases
/// and the detailed plan document side-by-side.
struct RoadmapView: View {
    @Environment(BuilderViewModel.self) private var viewModel

    private var warnings: [BuilderProjectWarning] {
        viewModel.activeRoadmapWarnings
    }

    var body: some View {
        VStack(spacing: 0) {
            if !warnings.isEmpty {
                roadmapWarnings
                    .padding(Theme.spacingXL)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.15))
                    .frame(height: 1)
            }

            HStack(alignment: .top, spacing: 0) {
                // Left: Visual phase tracker
                ScrollView {
                    phaseTracker
                        .padding(Theme.spacingXL)
                }
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 440)

                // Divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.15))
                    .frame(width: 1)

                // Right: Plan document
                ScrollView {
                    planDocument
                        .padding(Theme.spacingXL)
                }
            }
        }
        .background(Theme.surfaceInset)
    }

    private var roadmapWarnings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text("Roadmap Warnings")
                    .font(Theme.geist(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            ForEach(warnings) { warning in
                roadmapWarningCard(warning)
            }
        }
    }

    private func roadmapWarningCard(_ warning: BuilderProjectWarning) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(warning.title)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if let requestedCapability = warning.requestedCapability {
                Text("Requested: \(requestedCapability)")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(warning.message)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let fallback = warning.fallback {
                Text("Fallback: \(fallback)")
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.warning.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.warning.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Phase Computation

    private var phases: [RoadmapPhase] {
        let hasDesign = viewModel.designStyle != nil || viewModel.onboardingData != nil
        let hasPlan = viewModel.projectPlan != nil
        let hasFiles = !viewModel.fileTree.isEmpty
        let hasCleanBuild = hasFiles && viewModel.buildError == nil
        let hasPreview = viewModel.previewScreenshot != nil

        let taskProgress = computeTaskProgress()
        let coreFeaturesDone = taskProgress >= 0.5
        let refinementDone = taskProgress >= 0.9
        let launchReady = refinementDone && hasCleanBuild && hasPreview

        // Determine the current active phase index
        let completedCount: Int = {
            if launchReady { return 6 }
            if refinementDone { return 5 }
            if coreFeaturesDone { return 4 }
            if hasCleanBuild { return 3 }
            if hasPlan { return 2 }
            if hasDesign { return 1 }
            return 0
        }()

        return [
            RoadmapPhase(
                id: 0,
                title: "Design",
                subtitle: "Choose style, colors, and audience",
                icon: "paintbrush",
                status: phaseStatus(index: 0, completedCount: completedCount)
            ),
            RoadmapPhase(
                id: 1,
                title: "Plan",
                subtitle: "Generate the project plan and architecture",
                icon: "list.bullet.clipboard",
                status: phaseStatus(index: 1, completedCount: completedCount)
            ),
            RoadmapPhase(
                id: 2,
                title: "First Build",
                subtitle: "Initial code generation and successful compile",
                icon: "hammer",
                status: phaseStatus(index: 2, completedCount: completedCount)
            ),
            RoadmapPhase(
                id: 3,
                title: "Core Features",
                subtitle: "Build out the main app functionality",
                icon: "square.stack.3d.up",
                status: phaseStatus(index: 3, completedCount: completedCount)
            ),
            RoadmapPhase(
                id: 4,
                title: "Refinement",
                subtitle: "Polish UI, fix bugs, improve UX",
                icon: "wand.and.stars",
                status: phaseStatus(index: 4, completedCount: completedCount)
            ),
            RoadmapPhase(
                id: 5,
                title: "Launch Ready",
                subtitle: "All features complete, clean build, ready to ship",
                icon: "paperplane.fill",
                status: phaseStatus(index: 5, completedCount: completedCount)
            ),
        ]
    }

    private func phaseStatus(index: Int, completedCount: Int) -> RoadmapPhase.Status {
        if index < completedCount { return .completed }
        if index == completedCount { return .active }
        return .upcoming
    }

    private func computeTaskProgress() -> Double {
        let source = viewModel.projectTasks ?? viewModel.projectPlan
        guard let source else { return 0 }
        var total = 0
        var done = 0
        for line in source.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") {
                total += 1; done += 1
            } else if t.hasPrefix("- [ ]") {
                total += 1
            }
        }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    // MARK: - Phase Tracker

    private var phaseTracker: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Project Roadmap")
                    .font(Theme.geist(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                let progress = computeTaskProgress()
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(nsColor: .separatorColor).opacity(0.12))
                                .frame(height: 6)
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(progress * 100))%")
                        .font(Theme.geistMono(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(.bottom, 24)

            // Phase list with connecting line
            ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                HStack(alignment: .top, spacing: 14) {
                    // Timeline column
                    VStack(spacing: 0) {
                        phaseIndicator(phase.status)

                        if index < phases.count - 1 {
                            Rectangle()
                                .fill(phase.status == .completed ? Theme.accent.opacity(0.4) : Color(nsColor: .separatorColor).opacity(0.12))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 28)

                    // Content
                    phaseCard(phase)
                        .padding(.bottom, index < phases.count - 1 ? 8 : 0)
                }
            }

            // Task breakdown
            if !taskItems.isEmpty {
                taskBreakdown
                    .padding(.top, 24)
            }
        }
    }

    private func phaseIndicator(_ status: RoadmapPhase.Status) -> some View {
        ZStack {
            switch status {
            case .completed:
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )
            case .active:
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 12, height: 12)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.accent.opacity(0.4), lineWidth: 2)
                    )
            case .upcoming:
                Circle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.08))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1.5)
                    )
            }
        }
    }

    private func phaseCard(_ phase: RoadmapPhase) -> some View {
        HStack(spacing: 10) {
            Image(systemName: phase.icon)
                .font(.system(size: 14))
                .foregroundStyle(phaseColor(phase.status))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase.title)
                    .font(Theme.geist(13, weight: .semibold))
                    .foregroundStyle(phase.status == .upcoming ? Theme.textTertiary : Theme.textPrimary)
                Text(phase.subtitle)
                    .font(Theme.geist(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
            }

            Spacer()

            if phase.status == .completed {
                Text("Done")
                    .font(Theme.geistMono(9, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent.opacity(0.1)))
            } else if phase.status == .active {
                Text("In Progress")
                    .font(Theme.geistMono(9, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.08)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(phase.status == .active ? Theme.surface : Theme.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    phase.status == .active ? Theme.accent.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.1),
                    lineWidth: phase.status == .active ? 1.5 : 0.5
                )
        )
    }

    private func phaseColor(_ status: RoadmapPhase.Status) -> Color {
        switch status {
        case .completed: Theme.accent
        case .active: Theme.textPrimary
        case .upcoming: Theme.textTertiary.opacity(0.5)
        }
    }

    // MARK: - Task Breakdown

    private var taskItems: [(text: String, isDone: Bool)] {
        let source = viewModel.projectTasks ?? viewModel.projectPlan
        guard let source else { return [] }
        var result: [(String, Bool)] = []
        for line in source.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") {
                result.append((String(t.dropFirst(6)), true))
            } else if t.hasPrefix("- [ ]") {
                result.append((String(t.dropFirst(6)), false))
            }
        }
        return result
    }

    private var taskBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            let done = taskItems.filter(\.isDone)
            let todo = taskItems.filter { !$0.isDone }

            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                Text("TASKS")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.5)
                Spacer()
                Text("\(done.count)/\(taskItems.count)")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(todo.prefix(8).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 7) {
                        Image(systemName: "circle")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.orange)
                        Text(item.text)
                            .font(Theme.geist(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                if todo.count > 8 {
                    Text("+ \(todo.count - 8) more")
                        .font(Theme.geist(9))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 16)
                }

                if !done.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        Text("\(done.count) completed")
                            .font(Theme.geist(10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Plan Document

    private var planDocument: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let plan = viewModel.projectPlan {
                MarkdownTextView(text: plan, animateTransitions: false)
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.textTertiary.opacity(0.25))
                    Text("Plan")
                        .font(Theme.geist(13, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Text("The project plan will appear here after your first generation")
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textTertiary.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
