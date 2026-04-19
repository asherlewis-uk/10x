import SwiftUI

/// Compact project file browser for the Development page.
/// Searchable tree only, with a lightweight transparent container.
struct ProjectBrowserView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @State private var rootNode: FileNode?
    @State private var selectedFilePath: URL?
    @State private var expandedFolders: Set<URL> = []
    @State private var hoveredItem: URL?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: Theme.spacingMD) {
            controlsBar
            content
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.top, Theme.spacingMD)
        .padding(.bottom, Theme.spacingLG)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .task(id: viewModel.localProjectPath) {
            await loadFileTree()
        }
        .task(id: viewModel.fileTreeRevision) {
            if viewModel.localProjectPath != nil {
                await loadFileTree()
            }
        }
        .onChange(of: viewModel.selectedFile) { _, _ in
            applyExternalSelectionIfNeeded()
        }
    }

    private var controlsBar: some View {
        HStack(spacing: Theme.spacingSM) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)

                TextField("Search files", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.geistMono(11))
                    .foregroundStyle(Theme.textSecondary)

                if !viewModel.fileTree.isEmpty {
                    Text("\(viewModel.fileTree.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(searchText.isEmpty ? Theme.textTertiary : Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    searchText.isEmpty
                                        ? Theme.surface
                                        : Theme.accent.opacity(0.10)
                                )
                        )
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(
                        searchText.isEmpty
                            ? Color.primary.opacity(0.06)
                            : Theme.accent.opacity(0.28),
                        lineWidth: 1
                    )
            )

            controlButton(icon: "folder", help: "Reveal in Finder") {
                if let path = viewModel.localProjectPath {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                }
            }
            .disabled(viewModel.localProjectPath == nil)
        }
    }

    private var content: some View {
        Group {
            if rootNode != nil {
                fileTreePane
            } else if !browserRootExists {
                emptyState
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var fileTreePane: some View {
        Group {
            if filteredNodes.isEmpty, !trimmedSearchText.isEmpty {
                VStack(spacing: Theme.spacingSM) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No matching files")
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.spacingLG)
                .fileBrowserCard()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredNodes, id: \.id) { node in
                            nodeRow(node, depth: 0)
                        }
                    }
                    .padding(.vertical, Theme.spacingSM)
                    .padding(.horizontal, Theme.spacingSM)
                }
                .fileBrowserCard()
            }
        }
    }

    @ViewBuilder
    private func nodeRow(_ node: FileNode, depth: Int) -> some View {
        let isDirectoryExpanded = trimmedSearchText.isEmpty
            ? expandedFolders.contains(node.url)
            : true
        let isSelected = selectedFilePath == node.url
        let isHovered = hoveredItem == node.url

        HStack(spacing: 0) {
            Color.clear
                .frame(width: CGFloat(depth) * 14)

            if node.isDirectory {
                Image(systemName: isDirectoryExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16, height: 16)
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }

            HStack(spacing: Theme.spacingSM) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.accent.opacity(0.14) : Theme.surface.opacity(0.82))

                    Image(systemName: node.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(node.isDirectory ? Theme.textSecondary : node.iconColor)
                }
                .frame(width: 20, height: 20)

                Text(node.name)
                    .font(Theme.geistMono(11, weight: node.isDirectory ? .medium : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: Theme.spacingSM)
            }
            .padding(.leading, 2)
        }
        .frame(height: 30)
        .padding(.horizontal, Theme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .fill(
                    isSelected
                        ? Color(hex: "2A2A2A")
                        : (isHovered ? Theme.surface.opacity(0.75) : .clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke(
                    isSelected
                        ? Theme.accent.opacity(0.32)
                        : Color.primary.opacity(0.04),
                    lineWidth: isSelected ? 1 : 0
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory {
                withAnimation(.easeOut(duration: 0.15)) {
                    if expandedFolders.contains(node.url) {
                        expandedFolders.remove(node.url)
                    } else {
                        expandedFolders.insert(node.url)
                    }
                }
            } else {
                selectedFilePath = node.url
                viewModel.selectedFile = relativePathString(for: node.url)
            }
        }
        .onHover { hovering in
            hoveredItem = hovering ? node.url : nil
        }

        if node.isDirectory, isDirectoryExpanded, let children = node.children {
            let visibleChildren = filterNodes(children)
            ForEach(visibleChildren, id: \.id) { child in
                AnyView(nodeRow(child, depth: depth + 1))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingSM) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)

            Text("No project files yet")
                .font(Theme.geist(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text("Build your app to browse files here")
                .font(Theme.geist(11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.spacingLG)
        .fileBrowserCard()
    }

    private var filteredNodes: [FileNode] {
        guard let rootNode else { return [] }
        return filterNodes(rootNode.children ?? [])
    }

    private var browserRootURL: URL? {
        guard let localProjectPath = viewModel.localProjectPath,
              let descriptor = viewModel.activeWorkspaceDescriptor else {
            return nil
        }
        return descriptor.workspaceRootURL(projectRoot: localProjectPath)
    }

    private var browserRootExists: Bool {
        guard let browserRootURL else { return false }
        return FileManager.default.fileExists(atPath: browserRootURL.path)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filterNodes(_ nodes: [FileNode]) -> [FileNode] {
        guard !trimmedSearchText.isEmpty else { return nodes }

        let query = trimmedSearchText.lowercased()
        return nodes.compactMap { node -> FileNode? in
            if node.isDirectory {
                let filteredChildren = filterNodes(node.children ?? [])
                guard !filteredChildren.isEmpty else { return nil }

                var copy = node
                copy.children = filteredChildren
                return copy
            }

            let filePath = relativePathString(for: node.url).lowercased()
            return filePath.contains(query) ? node : nil
        }
    }

    private func loadFileTree() async {
        guard let rootURL = browserRootURL,
              FileManager.default.fileExists(atPath: rootURL.path) else {
            rootNode = nil
            selectedFilePath = nil
            return
        }

        if rootNode?.url != rootURL {
            expandedFolders.removeAll()
            hoveredItem = nil
            selectedFilePath = nil
        }

        let tree = await Task.detached {
            FileNode.buildTree(at: rootURL)
        }.value

        rootNode = tree

        if expandedFolders.isEmpty, let children = tree.children {
            for child in children where child.isDirectory {
                expandedFolders.insert(child.url)
            }
        }

        if let selectedFilePath,
           !FileManager.default.fileExists(atPath: selectedFilePath.path) {
            self.selectedFilePath = nil
        }

        applyExternalSelectionIfNeeded()
    }

    private func relativePathString(for url: URL) -> String {
        guard let root = browserRootURL else { return url.lastPathComponent }
        let rootPath = root.path
        let filePath = url.path
        if filePath.hasPrefix(rootPath) {
            let relative = String(filePath.dropFirst(rootPath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return url.lastPathComponent
    }

    private func applyExternalSelectionIfNeeded() {
        guard let rootURL = browserRootURL,
              let relativePath = viewModel.selectedFile?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !relativePath.isEmpty
        else {
            return
        }

        let targetURL = rootURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return }

        selectedFilePath = targetURL

        var current = targetURL.deletingLastPathComponent()
        while current.path != rootURL.path, current.path.hasPrefix(rootURL.path) {
            expandedFolders.insert(current)
            current = current.deletingLastPathComponent()
        }
    }
}

private extension View {
    func fileBrowserCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusLG, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusLG, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct FileBrowserControlButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .fill(isHovered ? Theme.surfaceElevated : Theme.surface)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isEnabled ? Theme.textSecondary : Theme.textTertiary)
            }
            .frame(width: 36, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovered = $0 }
    }
}

private extension ProjectBrowserView {
    func controlButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        FileBrowserControlButton(icon: icon, help: help, action: action)
    }
}

// MARK: - File Node Model

struct FileNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int
    var children: [FileNode]?

    var icon: String {
        if isDirectory {
            return folderIcon
        }
        return Self.iconForExtension(url.pathExtension)
    }

    var iconColor: Color {
        if isDirectory { return .white }
        return Self.colorForExtension(url.pathExtension)
    }

    private var folderIcon: String {
        switch name.lowercased() {
        case "views": return "rectangle.on.rectangle.angled"
        case "models": return "cylinder"
        case "components": return "square.stack.3d.up"
        case "viewmodels": return "gearshape.2"
        case "ios": return "iphone"
        case "deriveddata", "build": return "hammer"
        case ".tenx": return "gear"
        case "assets", "assets.xcassets": return "photo.on.rectangle"
        case "planning": return "list.bullet.clipboard"
        default: return "folder.fill"
        }
    }

    static func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "json": return "curlybraces"
        case "plist", "xml": return "text.badge.xmark"
        case "md", "txt": return "doc.text"
        case "pbxproj", "xcodeproj", "xcworkspace": return "hammer"
        case "xcscheme": return "play.rectangle"
        case "entitlements": return "lock.shield"
        case "png", "jpg", "jpeg", "svg", "pdf": return "photo"
        case "xcassets": return "photo.on.rectangle"
        default: return "doc"
        }
    }

    static func colorForExtension(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "swift": return .orange
        case "json": return .yellow
        case "plist", "xml": return .gray
        case "md", "txt": return .secondary
        case "pbxproj", "xcodeproj": return .blue
        case "png", "jpg", "jpeg", "svg": return .pink
        default: return .secondary
        }
    }

    var sizeLabel: String {
        if fileSize < 1024 { return "\(fileSize) B" }
        if fileSize < 1024 * 1024 { return "\(fileSize / 1024) KB" }
        return String(format: "%.1f MB", Double(fileSize) / (1024 * 1024))
    }

    /// Recursively build a file tree from a directory URL.
    static func buildTree(at url: URL) -> FileNode {
        let fm = FileManager.default
        let name = url.lastPathComponent
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            // Skip DerivedData and build artifacts
            let filtered = contents.filter { item in
                let n = item.lastPathComponent
                return n != "DerivedData" && n != "build" && n != ".build"
            }

            let children = filtered
                .map { buildTree(at: $0) }
                .sorted { a, b in
                    // Folders first, then alphabetical
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }

            return FileNode(
                id: url, url: url, name: name,
                isDirectory: true, fileSize: 0,
                children: children.isEmpty ? nil : children
            )
        } else {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return FileNode(
                id: url, url: url, name: name,
                isDirectory: false, fileSize: size,
                children: nil
            )
        }
    }
}
