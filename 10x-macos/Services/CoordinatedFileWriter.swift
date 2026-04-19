import Foundation

/// Writes files using NSFileCoordinator so that Xcode (and other file presenters)
/// pick up changes automatically without prompting "Use version on disk?".
enum CoordinatedFileWriter {

    /// Write string content to a file with file coordination.
    static func write(_ content: String, to url: URL) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordinatedURL in
            try? content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
        }
        if let error {
            // Fall back to direct write if coordination fails
            print("[10x] File coordination failed for \(url.lastPathComponent): \(error.localizedDescription)")
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Write data to a file with file coordination.
    static func writeData(_ data: Data, to url: URL) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordinatedURL in
            try? data.write(to: coordinatedURL)
        }
        if let error {
            print("[10x] File coordination failed for \(url.lastPathComponent): \(error.localizedDescription)")
            try? data.write(to: url)
        }
    }

    /// Delete a file with file coordination.
    static func delete(_ url: URL) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &error) { coordinatedURL in
            try? FileManager.default.removeItem(at: coordinatedURL)
        }
        if let error {
            print("[10x] File coordination failed for delete \(url.lastPathComponent): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
        }
    }
}
