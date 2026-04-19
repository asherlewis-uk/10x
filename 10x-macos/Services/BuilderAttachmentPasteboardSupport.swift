import AppKit
import Foundation

enum BuilderAttachmentPasteboardSupport {
    static func hasImportableFileURLs(on pasteboard: NSPasteboard) -> Bool {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: fileOptions) {
            return true
        }
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [:]) {
            return true
        }

        return pasteboard.types?.contains(.fileURL) == true
            || pasteboard.types?.contains(.URL) == true
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return orderedUnique(urls)
        }

        let urls: [URL] = pasteboard.pasteboardItems?.compactMap { item in
            guard let rawURL = item.string(forType: .fileURL) ?? item.string(forType: .URL) else { return nil }
            return URL(string: rawURL)
        } ?? []
        return orderedUnique(urls)
    }

    static func importedAttachments(from urls: [URL]) -> (attachments: [BuilderMessageAttachment], errors: [String]) {
        var imported: [BuilderMessageAttachment] = []
        var errors: [String] = []

        for url in urls {
            do {
                imported.append(try BuilderAttachmentImporter.makeAttachment(from: url))
            } catch let error as BuilderAttachmentImportError {
                errors.append(error.localizedDescription)
            } catch {
                errors.append("Couldn’t attach \(url.lastPathComponent).")
            }
        }

        return (imported, errors)
    }

    private static func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for url in urls {
            let key = url.standardizedFileURL.absoluteString
            guard seen.insert(key).inserted else { continue }
            ordered.append(url)
        }

        return ordered
    }
}
