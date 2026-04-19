import CoreServices
import Foundation

/// Watches a directory recursively for external file changes using FSEvents.
/// When changes are detected, scans the directory and reports diffs via a callback.
///
/// Used to detect edits made by external tools (e.g. Claude Code, Xcode) so the
/// in-memory file tree stays in sync with disk.
final class FileSystemWatcher: @unchecked Sendable {

    struct Changes: Sendable {
        let created: [String: String]   // path → content
        let modified: [String: String]  // path → new content
        let deleted: Set<String>        // paths removed from disk
    }

    typealias ChangeHandler = @Sendable (Changes) -> Void

    private let sourcesDir: URL
    private let onChange: ChangeHandler
    private let queue = DispatchQueue(label: "com.tenx.file-watcher", qos: .utility)

    private var eventStream: FSEventStreamRef?

    /// Snapshot of relative-path → last-modified-date for diffing.
    private var knownModDates: [String: Date] = [:]

    init(sourcesDir: URL, onChange: @escaping ChangeHandler) {
        self.sourcesDir = sourcesDir
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Start watching. Takes the current in-memory file tree to establish baseline mod dates.
    func start(currentFileTree: [String: String]) {
        stop()

        // Build initial mod-date snapshot from disk
        knownModDates = snapshotModDates()
        // Also ensure every in-memory key is present (even if not yet on disk)
        for path in currentFileTree.keys {
            if knownModDates[path] == nil {
                knownModDates[path] = .distantPast
            }
        }

        guard FileManager.default.fileExists(atPath: sourcesDir.path) else {
            print("[10x][FileWatcher] Sources directory does not exist yet: \(sourcesDir.path)")
            return
        }

        let pathsToWatch = [sourcesDir.path] as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            FileSystemWatcher.fsEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency in seconds — coalesces rapid events
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            print("[10x][FileWatcher] Failed to create FSEvent stream for: \(sourcesDir.path)")
            return
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)

        print("[10x][FileWatcher] Watching \(sourcesDir.path)")
    }

    func stop() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    /// Update the baseline snapshot after the app itself writes files (e.g. after generation).
    func updateBaseline(fileTree: [String: String]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.knownModDates = self.snapshotModDates()
            for path in fileTree.keys {
                if self.knownModDates[path] == nil {
                    self.knownModDates[path] = .distantPast
                }
            }
        }
    }

    // MARK: - FSEvents Callback

    private static let fsEventCallback: FSEventStreamCallback = {
        (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
        guard let info = clientCallBackInfo else { return }
        let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.handleFSEvent()
    }

    // MARK: - Internal

    /// Debounce timer to coalesce rapid filesystem events.
    private var debounceWorkItem: DispatchWorkItem?

    private func handleFSEvent() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.scanForChanges()
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func scanForChanges() {
        let currentModDates = snapshotModDates()
        let allPaths = Set(knownModDates.keys).union(currentModDates.keys)

        var created: [String: String] = [:]
        var modified: [String: String] = [:]
        var deleted: Set<String> = []

        for path in allPaths {
            let wasKnown = knownModDates[path] != nil
            let existsNow = currentModDates[path] != nil

            if !wasKnown && existsNow {
                // New file on disk
                if let content = readFile(at: path) {
                    created[path] = content
                }
            } else if wasKnown && !existsNow {
                // File removed from disk
                deleted.insert(path)
            } else if wasKnown && existsNow {
                // Check if modified
                let oldDate = knownModDates[path] ?? .distantPast
                let newDate = currentModDates[path] ?? .distantPast
                if newDate > oldDate {
                    if let content = readFile(at: path) {
                        modified[path] = content
                    }
                }
            }
        }

        // Update baseline
        knownModDates = currentModDates

        let changes = Changes(created: created, modified: modified, deleted: deleted)
        guard !changes.created.isEmpty || !changes.modified.isEmpty || !changes.deleted.isEmpty else {
            return
        }

        print("[10x][FileWatcher] External changes detected — created: \(changes.created.count), modified: \(changes.modified.count), deleted: \(changes.deleted.count)")
        onChange(changes)
    }

    /// Build a snapshot of relative-path → modification-date for all files under sourcesDir.
    private func snapshotModDates() -> [String: Date] {
        var result: [String: Date] = [:]
        let fm = FileManager.default
        let sourcesDirPath = sourcesDir.path

        guard let enumerator = fm.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let modDate = values.contentModificationDate else { continue }

            // Relative path from sourcesDir
            let fullPath = fileURL.path
            guard fullPath.hasPrefix(sourcesDirPath) else { continue }
            var relative = String(fullPath.dropFirst(sourcesDirPath.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }

            // Skip non-source files (Assets.xcassets, etc. are managed by the app)
            if relative.hasPrefix("Assets.xcassets") { continue }

            result[relative] = modDate
        }

        return result
    }

    private func readFile(at relativePath: String) -> String? {
        let url = sourcesDir.appendingPathComponent(relativePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
