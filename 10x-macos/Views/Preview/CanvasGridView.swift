import SwiftUI
import Combine

// MARK: - Canvas Node Model

struct CanvasNode: Identifiable, Equatable {
    let id: String
    let kind: Kind
    var position: CGPoint
    var size: CGSize

    enum Kind: String, CaseIterable {
        case roadmap, design, development, environment
    }
}

// MARK: - Shared Canvas State

@Observable
@MainActor
final class CanvasState {
    var offsetX: CGFloat = -40
    var offsetY: CGFloat = -40
    var zoom: CGFloat = 1.0

    func worldToScreen(_ world: CGPoint) -> CGPoint {
        CGPoint(x: (world.x - offsetX) * zoom, y: (world.y - offsetY) * zoom)
    }
    func screenToWorld(_ screen: CGPoint) -> CGPoint {
        CGPoint(x: offsetX + screen.x / zoom, y: offsetY + screen.y / zoom)
    }
    func pan(dx: CGFloat, dy: CGFloat) { offsetX -= dx / zoom; offsetY -= dy / zoom }
    func zoomAt(delta: CGFloat, location: CGPoint) {
        let oldZoom = zoom
        let newZoom = min(max(zoom * (1 + delta), 0.15), 3.0)
        let wx = offsetX + location.x / oldZoom, wy = offsetY + location.y / oldZoom
        zoom = newZoom; offsetX = wx - location.x / newZoom; offsetY = wy - location.y / newZoom
    }
    func reset() { offsetX = -40; offsetY = -40; zoom = 1.0 }
    func fitAll(nodes: [CanvasNode], viewportSize: CGSize) {
        guard !nodes.isEmpty else { return }
        let minX = nodes.map(\.position.x).min()!, minY = nodes.map(\.position.y).min()!
        let maxX = nodes.map { $0.position.x + $0.size.width }.max()!, maxY = nodes.map { $0.position.y + $0.size.height }.max()!
        let w = maxX - minX, h = maxY - minY; guard w > 0, h > 0 else { return }
        let pad: CGFloat = 80
        zoom = min(max(min((viewportSize.width - pad * 2) / w, (viewportSize.height - pad * 2) / h), 0.15), 3.0)
        offsetX = minX - pad / zoom; offsetY = minY - pad / zoom
    }
}

// MARK: - Top-Level View

struct CanvasGridView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var canvasState = CanvasState()
    @State private var nodes: [CanvasNode] = []
    @State private var didLayout = false
    @State private var viewportSize: CGSize = .zero
    @State private var hostRefreshID = UUID()

    var body: some View {
        CanvasHostView(state: canvasState, refreshID: hostRefreshID) {
            ZStack { dotGrid; nodeLayer }
        }
        .overlay(alignment: .bottomTrailing) { canvasHUD }
        .onAppear {
            layoutNodesIfNeeded()
            refreshCanvasHost()
        }
        .onChange(of: viewModel.fileTree.count) { _, _ in relayoutNodes() }
        .onChange(of: viewModel.projectPlan) { _, _ in relayoutNodes() }
        .onChange(of: viewModel.projectTasks) { _, _ in relayoutNodes() }
        .onChange(of: viewModel.previewScreenshot) { _, _ in relayoutNodes() }
        .onChange(of: viewportSize) { oldSize, newSize in
            guard newSize.width > 1, newSize.height > 1 else { return }
            guard oldSize.width <= 1 || oldSize.height <= 1 else { return }
            refreshCanvasHost()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshCanvasHost()
        }
        .background(GeometryReader { geo in
            Color.clear.onAppear { viewportSize = geo.size }
                .onChange(of: geo.size) { _, s in viewportSize = s }
        })
    }

    // MARK: - Dot Grid

    private var dotGrid: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                ctx.fill(Rectangle().path(in: CGRect(origin: .zero, size: size)), with: .color(Theme.surfaceInset))
                let sp: CGFloat = 36, sc = sp * canvasState.zoom; guard sc > 3 else { return }
                let ox = (-canvasState.offsetX * canvasState.zoom).truncatingRemainder(dividingBy: sc)
                let oy = (-canvasState.offsetY * canvasState.zoom).truncatingRemainder(dividingBy: sc)
                let r = max(0.5, 1.5 * canvasState.zoom); var p = Path()
                var x = ox; while x < size.width + sc { var y = oy; while y < size.height + sc {
                    if x > -sc && y > -sc { p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }; y += sc }; x += sc }
                ctx.fill(p, with: .color(Color(nsColor: .separatorColor).opacity(0.35)))
            }
        }
    }

    // MARK: - Node Layer

    private var nodeLayer: some View {
        ZStack {
            ForEach($nodes) { $node in
                CanvasSectionView(
                    node: $node,
                    canvasState: canvasState,
                    onDoubleTap: { navigateToTab(node.kind) },
                    onDragEnd: {}
                ) {
                    switch node.kind {
                    case .roadmap: roadmapContent
                    case .design: designContent
                    case .development: developmentContent
                    case .environment: environmentContent
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func navigateToTab(_ kind: CanvasNode.Kind) {
        withAnimation(.easeOut(duration: 0.15)) {
            switch kind {
            case .roadmap: viewModel.viewMode = .roadmap
            case .design: viewModel.viewMode = .design
            case .development: viewModel.viewMode = .development
            case .environment: viewModel.viewMode = .environment
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - DESIGN (Brand, Colors, Style)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var designContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // App identity
            HStack(spacing: 10) {
                if let icon = viewModel.projectIcon {
                    Image(nsImage: icon).resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.activeProject?.name ?? "Untitled")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    if let desc = viewModel.activeProject?.description, !desc.isEmpty {
                        Text(desc).font(.system(size: 9)).foregroundStyle(Theme.textTertiary).lineLimit(2)
                    }
                }
            }

            // Design style
            if let style = viewModel.designStyle {
                overviewRow(label: "DESIGN STYLE", icon: style.iconName, iconColor: .purple) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(style.subtitle).font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            // Color palette
            if !extractedColors.isEmpty {
                overviewRow(label: "COLOR PALETTE", icon: "paintpalette.fill", iconColor: .pink) {
                    HStack(spacing: 8) {
                        ForEach(extractedColors, id: \.name) { c in
                            VStack(spacing: 3) {
                                Circle().fill(c.color).frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                                Text(c.name).font(.system(size: 7, weight: .medium)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }

            // Target audience
            if let data = viewModel.onboardingData, !data.targetAudience.isEmpty {
                overviewRow(label: "TARGET AUDIENCE", icon: "person.3.fill", iconColor: .blue) {
                    HStack(spacing: 4) {
                        ForEach(data.targetAudience) { audience in
                            HStack(spacing: 3) {
                                Image(systemName: audience.iconName).font(.system(size: 7))
                                Text(audience.label).font(.system(size: 9, weight: .medium))
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.surface))
                        }
                    }
                }
            }

            if viewModel.designStyle == nil && extractedColors.isEmpty && viewModel.onboardingData == nil {
                emptyState(icon: "paintbrush", title: "Design", subtitle: "Brand colors, fonts, and design style will appear here")
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - ROADMAP (Milestones + Plan)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var milestones: [CanvasMilestone] {
        let source = viewModel.projectTasks ?? viewModel.projectPlan
        guard let source else { return [] }
        var result: [CanvasMilestone] = []; var idx = 0
        for line in source.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { continue }
            if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") {
                result.append(CanvasMilestone(id: idx, text: String(t.dropFirst(6)), isChecked: true, isHeading: false)); idx += 1
            } else if t.hasPrefix("- [ ]") {
                result.append(CanvasMilestone(id: idx, text: String(t.dropFirst(6)), isChecked: false, isHeading: false)); idx += 1
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                result.append(CanvasMilestone(id: idx, text: String(t.dropFirst(2)), isChecked: false, isHeading: false)); idx += 1
            } else if t.hasPrefix("#") {
                let cleaned = String(t.drop(while: { $0 == "#" || $0 == " " }))
                result.append(CanvasMilestone(id: idx, text: cleaned, isChecked: false, isHeading: true)); idx += 1
            }
        }
        return result
    }

    private var roadmapContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            let items = milestones.filter { !$0.isHeading }
            let done = items.filter(\.isChecked)
            let todo = items.filter { !$0.isChecked }
            let total = items.count
            let doneCount = done.count

            // Progress bar
            if total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Progress")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(doneCount)/\(total)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(nsColor: .separatorColor).opacity(0.1)).frame(height: 6)
                            Capsule().fill(Theme.success).frame(width: total > 0 ? geo.size.width * CGFloat(doneCount) / CGFloat(total) : 0, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.bottom, 4)
            }

            // Milestone list (compact)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.success).frame(width: 6, height: 6)
                        Text("Done").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        Text("\(doneCount)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(done.prefix(6)) { m in milestoneCard(m, isDone: true) }
                    if done.count > 6 { Text("+ \(done.count - 6) more").font(.system(size: 8)).foregroundStyle(Theme.textTertiary) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("To Do").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        Text("\(todo.count)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(todo.prefix(6)) { m in milestoneCard(m, isDone: false) }
                    if todo.count > 6 { Text("+ \(todo.count - 6) more").font(.system(size: 8)).foregroundStyle(Theme.textTertiary) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if milestones.isEmpty {
                emptyState(icon: "map", title: "Roadmap", subtitle: "Generate a plan to see milestones")
            }
        }
    }

    private func milestoneCard(_ m: CanvasMilestone, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(isDone ? Theme.success : Color.orange)
            Text(m.text)
                .font(.system(size: 10, weight: isDone ? .regular : .medium))
                .foregroundStyle(isDone ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(isDone, color: Theme.textTertiary.opacity(0.5))
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(isDone ? Theme.success.opacity(0.04) : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isDone ? Theme.success.opacity(0.1) : Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - DEVELOPMENT (Screenshot + Build Status)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var developmentContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let ss = viewModel.previewScreenshot {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: ss).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                        .frame(maxWidth: 160)
                    VStack(alignment: .leading, spacing: 8) { buildStats; buildStatus }
                }
            } else {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Image(systemName: "iphone.gen3").font(.system(size: 28)).foregroundStyle(Theme.textTertiary.opacity(0.3))
                        Text("No preview").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                    }.frame(width: 80)
                    VStack(alignment: .leading, spacing: 8) { buildStats; buildStatus }
                }
            }

            if let e = viewModel.buildError {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(Theme.error)
                    Text(e).font(.system(size: 9)).foregroundStyle(Theme.error).lineLimit(2)
                }.padding(6).background(RoundedRectangle(cornerRadius: 4).fill(Theme.error.opacity(0.06)))
            }

            if !folderStructure.isEmpty {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(folderStructure.prefix(10)) { folder in
                        let depth = folder.path.split(separator: "/").count - 1
                        HStack(spacing: 5) {
                            Image(systemName: folder.icon).font(.system(size: 9)).foregroundStyle(folder.color).frame(width: 12).padding(.leading, CGFloat(depth) * 8)
                            Text(folder.name).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(folder.fileCount)").font(.system(size: 8, weight: .medium, design: .rounded)).foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 4).padding(.vertical, 1).background(Capsule().fill(Color(nsColor: .separatorColor).opacity(0.08)))
                        }.padding(.vertical, 2)
                    }
                    if folderStructure.count > 10 {
                        Text("+ \(folderStructure.count - 10) more folders")
                            .font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            if let p = viewModel.localProjectPath {
                Text(p.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var buildStats: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) { miniStat("\(viewModel.fileTree.count)", "Files", .blue); miniStat("\(swiftFileCount)", "Swift", .orange) }
            HStack(spacing: 10) { miniStat("\(assetFiles.count)", "Assets", .pink); miniStat("\(folderStructure.count)", "Folders", .indigo) }
        }
    }
    private var buildStatus: some View {
        let ok = viewModel.buildError == nil
        return HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(ok ? Theme.success : Theme.error)
            Text(ok ? "Healthy" : "Build Error").font(.system(size: 9, weight: .medium)).foregroundStyle(ok ? Theme.success : Theme.error)
        }.padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill((ok ? Theme.success : Theme.error).opacity(0.08)))
    }
    private func miniStat(_ v: String, _ l: String, _ c: Color) -> some View {
        HStack(spacing: 3) { Text(v).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(c); Text(l).font(.system(size: 8)).foregroundStyle(Theme.textTertiary) }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - ENVIRONMENT (Keys summary)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var environmentContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            let envVars = viewModel.environmentVariables.filter { !$0.key.isEmpty }
            if envVars.isEmpty {
                emptyState(icon: "key", title: "Environment", subtitle: "API keys and secrets will appear here")
            } else {
                ForEach(envVars) { v in
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow.opacity(0.7))
                        Text(v.key)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5)
                    )
                }
                Text("\(envVars.count) variable\(envVars.count == 1 ? "" : "s") configured")
                    .font(.system(size: 8)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private func overviewRow<Content: View>(label: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8)).foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1)
            }
            content()
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(Theme.textTertiary.opacity(0.25))
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
            Text(subtitle).font(.system(size: 9)).foregroundStyle(Theme.textTertiary.opacity(0.7))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - HUD

    private var canvasHUD: some View {
        HStack(spacing: 6) {
                Button { withAnimation(.easeOut(duration: 0.2)) { canvasState.zoom = min(max(canvasState.zoom - 0.2, 0.15), 3.0) } } label: {
                    Image(systemName: "minus").font(.system(size: 11, weight: .medium)).frame(width: 26, height: 26) }.buttonStyle(.plain)
                Text("\(Int(canvasState.zoom * 100))%").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.textSecondary).frame(width: 40)
                Button { withAnimation(.easeOut(duration: 0.2)) { canvasState.zoom = min(max(canvasState.zoom + 0.2, 0.15), 3.0) } } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium)).frame(width: 26, height: 26) }.buttonStyle(.plain)
                Divider().frame(height: 16)
                Button { withAnimation(.easeOut(duration: 0.3)) { canvasState.fitAll(nodes: nodes, viewportSize: viewportSize) } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .medium)).frame(width: 26, height: 26) }.buttonStyle(.plain).help("Fit all")
                Button { withAnimation(.easeOut(duration: 0.3)) { canvasState.reset() } } label: {
                    Image(systemName: "house").font(.system(size: 11, weight: .medium)).frame(width: 26, height: 26) }.buttonStyle(.plain).help("Reset view")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.radiusMD).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMD).stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2).padding(Theme.spacingLG)
    }

    // MARK: - Layout

    private func relayoutNodes() {
        let existing = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        didLayout = false; layoutNodesIfNeeded(existingPositions: existing)
    }

    private func refreshCanvasHost() {
        // The AppKit host can miss its first paint while hidden/zero-sized; force a fresh SwiftUI subtree.
        DispatchQueue.main.async {
            hostRefreshID = UUID()
        }
    }

    private func layoutNodesIfNeeded(existingPositions: [String: CGPoint]? = nil) {
        guard !didLayout || nodes.isEmpty else { return }; didLayout = true
        let saved = existingPositions ?? [:]; let gap: CGFloat = 60

        // 2x2 grid layout:
        // Roadmap (top-left)       | Design (top-right)
        // Development (bottom-left) | Environment (bottom-right)
        let roadmapW: CGFloat = 520, roadmapH: CGFloat = 500
        let designW: CGFloat = 420, designH: CGFloat = 400
        let devW: CGFloat = 420, devH: CGFloat = 480
        let envW: CGFloat = 360, envH: CGFloat = 350

        nodes = [
            CanvasNode(id: "roadmap", kind: .roadmap, position: saved["roadmap"] ?? CGPoint(x: 0, y: 0), size: CGSize(width: roadmapW, height: roadmapH)),
            CanvasNode(id: "design", kind: .design, position: saved["design"] ?? CGPoint(x: roadmapW + gap, y: 0), size: CGSize(width: designW, height: designH)),
            CanvasNode(id: "development", kind: .development, position: saved["development"] ?? CGPoint(x: 0, y: roadmapH + gap), size: CGSize(width: devW, height: devH)),
            CanvasNode(id: "environment", kind: .environment, position: saved["environment"] ?? CGPoint(x: devW + gap, y: roadmapH + gap), size: CGSize(width: envW, height: envH)),
        ]
    }

    // MARK: - Data Helpers

    private var swiftFileCount: Int { viewModel.fileTree.keys.filter { $0.hasSuffix(".swift") }.count }
    private var assetFiles: [(path: String, ext: String)] {
        let exts: Set<String> = ["png","jpg","jpeg","gif","svg","webp","ico","bmp","tiff","pdf"]
        return viewModel.fileTree.keys.compactMap { p in let e = (p as NSString).pathExtension.lowercased(); return exts.contains(e) ? (p,e) : nil }.sorted { $0.path < $1.path }
    }
    private var folderStructure: [FolderInfo] {
        var f: [String:Int] = [:]
        for p in viewModel.fileTree.keys { let c = p.split(separator:"/"); f[c.count>1 ? c.dropLast().joined(separator:"/") : "/", default:0] += 1 }
        return f.map { FolderInfo(path:$0.key, fileCount:$0.value) }.sorted { $0.path < $1.path }
    }

    /// Extract color references from the project plan text.
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

    private struct FolderInfo: Identifiable {
        let path: String; let fileCount: Int; var id: String { path }
        var name: String { path == "/" ? "Root" : String(path.split(separator:"/").last ?? "") }
        var icon: String { switch name.lowercased() { case "views":"rectangle.on.rectangle.angled"; case "models":"cylinder"; case "components":"square.stack.3d.up"; case "viewmodels":"gearshape.2"; case "ios":"iphone"; case "services":"server.rack"; case "assets","assets.xcassets":"photo.on.rectangle"; case "planning":"list.bullet.clipboard"; case "extensions":"puzzlepiece.extension"; default:"folder.fill" } }
        var color: Color { switch name.lowercased() { case "views":.blue; case "models":.purple; case "components":.indigo; case "viewmodels":.teal; case "ios":.orange; case "services":.green; case "assets","assets.xcassets":.pink; default:.secondary } }
    }
}

private struct CanvasMilestone: Identifiable {
    let id: Int
    let text: String
    let isChecked: Bool
    let isHeading: Bool
}

// MARK: - Canvas Section View (Figma-style dashed border)

private struct CanvasSectionView<Content: View>: View {
    @Binding var node: CanvasNode
    let canvasState: CanvasState
    let onDoubleTap: () -> Void
    let onDragEnd: () -> Void
    @ViewBuilder let content: Content

    @GestureState private var dragScreenOffset: CGSize = .zero
    @State private var isHovered = false

    private var sectionColor: Color { .white }
    private var sectionTitle: String {
        switch node.kind {
        case .roadmap: "Roadmap"
        case .design: "Design"
        case .development: "Development"
        case .environment: "Environment"
        }
    }
    private var sectionIcon: String {
        switch node.kind {
        case .roadmap: "map"
        case .design: "paintbrush"
        case .development: "hammer"
        case .environment: "key"
        }
    }

    var body: some View {
        let sp = canvasState.worldToScreen(node.position)
        let sw = node.size.width * canvasState.zoom, sh = node.size.height * canvasState.zoom
        let isDragging = dragScreenOffset != .zero
        sectionBody
            .frame(width: node.size.width, height: node.size.height)
            .scaleEffect(canvasState.zoom, anchor: .topLeading)
            .frame(width: sw, height: sh, alignment: .topLeading)
            .offset(x: sp.x, y: sp.y).offset(dragScreenOffset)
            .zIndex(isDragging ? 1000 : 0)
            .gesture(DragGesture(minimumDistance: 3)
                .updating($dragScreenOffset) { v, s, _ in s = v.translation }
                .onEnded { v in node.position = CGPoint(x: node.position.x + v.translation.width / canvasState.zoom, y: node.position.y + v.translation.height / canvasState.zoom); onDragEnd() })
    }

    private var sectionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: sectionIcon).font(.system(size: 10, weight: .medium)).foregroundStyle(sectionColor)
                Text(sectionTitle.uppercased()).font(Theme.geistMono(11)).foregroundStyle(isHovered ? sectionColor : Theme.textSecondary)
            }.padding(.bottom, 6)

            content
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: isHovered ? 1.5 : 1, dash: [6, 4])).foregroundStyle(isHovered ? sectionColor.opacity(0.6) : sectionColor.opacity(0.3)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contentShape(Rectangle())
        .onHover { h in isHovered = h }
        .onTapGesture(count: 2) { onDoubleTap() }
    }
}

// MARK: - Canvas Host

struct CanvasHostView<Content: View>: NSViewRepresentable {
    let state: CanvasState
    let refreshID: UUID
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> CanvasHostNSView {
        let v = CanvasHostNSView()
        v.canvasState = state
        v.clipsToBounds = true
        v.refreshID = refreshID

        let h = NSHostingView(rootView: AnyView(content.id(refreshID)))
        h.translatesAutoresizingMaskIntoConstraints = false
        h.clipsToBounds = true
        h.sizingOptions = []
        v.hostingView = h
        v.addSubview(h)

        NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: v.leadingAnchor), h.trailingAnchor.constraint(equalTo: v.trailingAnchor), h.topAnchor.constraint(equalTo: v.topAnchor), h.bottomAnchor.constraint(equalTo: v.bottomAnchor)])
        return v
    }
    func updateNSView(_ v: CanvasHostNSView, context: Context) {
        v.canvasState = state
        v.refreshID = refreshID
        v.hostingView?.rootView = AnyView(content.id(refreshID))
    }
}

final class CanvasHostNSView: NSView {
    var canvasState: CanvasState?
    var hostingView: NSHostingView<AnyView>?
    var refreshID: UUID = UUID() {
        didSet {
            guard refreshID != oldValue else { return }
            scheduleDisplayRefresh()
        }
    }
    private var pendingDisplayRefresh: DispatchWorkItem?
    private var windowObservers: [NSObjectProtocol] = []
    override var acceptsFirstResponder: Bool { true }; override var isFlipped: Bool { true }
    deinit {
        pendingDisplayRefresh?.cancel()
        removeWindowObservers()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow !== window {
            removeWindowObservers()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservers()
        scheduleDisplayRefresh()
    }
    override func viewDidUnhide() {
        super.viewDidUnhide()
        scheduleDisplayRefresh()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleDisplayRefresh()
    }
    override func scrollWheel(with event: NSEvent) {
        guard let s = canvasState else { super.scrollWheel(with: event); return }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let loc = convert(event.locationInWindow, from: nil); Task { @MainActor in s.zoomAt(delta: -event.scrollingDeltaY * 0.008, location: loc) }
        } else { Task { @MainActor in s.pan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY) } }
    }
    override func magnify(with event: NSEvent) {
        guard let s = canvasState else { super.magnify(with: event); return }
        let loc = convert(event.locationInWindow, from: nil)
        Task { @MainActor in s.zoomAt(delta: event.magnification, location: loc) }
    }
    override func smartMagnify(with event: NSEvent) {
        // Consume to prevent system smart-zoom on double-tap
    }

    private func installWindowObservers() {
        guard let window, windowObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didExposeNotification,
            NSWindow.didResizeNotification,
        ]

        windowObservers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.scheduleDisplayRefresh()
            }
        }
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
    }

    private func scheduleDisplayRefresh() {
        pendingDisplayRefresh?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            needsLayout = true
            needsDisplay = true
            subviews.forEach { subview in
                subview.needsLayout = true
                subview.needsDisplay = true
            }
            layoutSubtreeIfNeeded()
            displayIfNeeded()
        }

        pendingDisplayRefresh = workItem
        DispatchQueue.main.async(execute: workItem)
    }
}
