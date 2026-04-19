import Foundation
import UniformTypeIdentifiers

enum BuilderAttachmentImportError: LocalizedError {
    case unsupportedType(filename: String)
    case fileTooLarge(filename: String)
    case unreadableText(filename: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let filename):
            return "\(filename) isn’t a supported attachment type."
        case .fileTooLarge(let filename):
            return "\(filename) is larger than the 5 MB attachment limit."
        case .unreadableText(let filename):
            return "\(filename) couldn’t be read as a text/code file."
        }
    }
}

enum BuilderAttachmentImporter {
    static let allowedContentTypes: [UTType] = {
        let extensions = Array(supportedTextExtensions) + Array(imageMediaTypes.keys) + ["pdf"]
        var seen: Set<String> = []
        return extensions.compactMap { UTType(filenameExtension: $0) }.filter { type in
            seen.insert(type.identifier).inserted
        }
    }()

    static func makeAttachment(from url: URL) throws -> BuilderMessageAttachment {
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .nameKey])
        let filename = values.name ?? url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let contentType = values.contentType ?? UTType(filenameExtension: ext)
        let fileSize = values.fileSize ?? 0

        if fileSize > BuilderAttachmentPolicy.maxTotalBytes {
            throw BuilderAttachmentImportError.fileTooLarge(filename: filename)
        }

        if let mediaType = imageMediaTypes[ext] {
            let data = try loadAttachmentData(from: url, filename: filename)
            return BuilderMessageAttachment(
                filename: filename,
                kind: .image,
                mediaType: mediaType,
                sizeBytes: data.count,
                base64Data: data.base64EncodedString()
            )
        }

        if ext == "pdf" || contentType?.conforms(to: .pdf) == true {
            let data = try loadAttachmentData(from: url, filename: filename)
            return BuilderMessageAttachment(
                filename: filename,
                kind: .pdf,
                mediaType: "application/pdf",
                sizeBytes: data.count,
                base64Data: data.base64EncodedString()
            )
        }

        if isSupportedTextType(contentType, ext: ext) {
            let data = try loadAttachmentData(from: url, filename: filename)
            var encoding = String.Encoding.utf8.rawValue
            do {
                let text = try NSString(contentsOf: url, usedEncoding: &encoding) as String
                let sizeBytes = fileSize > 0 ? fileSize : data.count
                if sizeBytes > BuilderAttachmentPolicy.maxTotalBytes {
                    throw BuilderAttachmentImportError.fileTooLarge(filename: filename)
                }
                return BuilderMessageAttachment(
                    filename: filename,
                    kind: .text,
                    mediaType: textMediaType(for: ext),
                    sizeBytes: sizeBytes,
                    textContent: text,
                    base64Data: data.base64EncodedString()
                )
            } catch {
                if let importError = error as? BuilderAttachmentImportError {
                    throw importError
                }
                throw BuilderAttachmentImportError.unreadableText(filename: filename)
            }
        }

        throw BuilderAttachmentImportError.unsupportedType(filename: filename)
    }

    private static func loadAttachmentData(from url: URL, filename: String) throws -> Data {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if data.count > BuilderAttachmentPolicy.maxTotalBytes {
            throw BuilderAttachmentImportError.fileTooLarge(filename: filename)
        }
        return data
    }

    private static func isSupportedTextType(_ contentType: UTType?, ext: String) -> Bool {
        if supportedTextExtensions.contains(ext) {
            return true
        }

        guard let contentType else { return false }
        return contentType.conforms(to: .text)
            || contentType.conforms(to: .plainText)
            || contentType.conforms(to: .sourceCode)
            || contentType.conforms(to: .xml)
            || contentType.conforms(to: .json)
    }

    private static func textMediaType(for ext: String) -> String {
        supportedTextMediaTypes[ext] ?? "text/plain"
    }

    private static let imageMediaTypes: [String: String] = [
        "gif": "image/gif",
        "jpeg": "image/jpeg",
        "jpg": "image/jpeg",
        "png": "image/png",
        "webp": "image/webp",
    ]

    private static let supportedTextExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "csv", "docx", "h", "hpp", "html", "java", "js", "json",
        "jsx", "kt", "log", "m", "md", "mm", "py", "rb", "rs", "sh", "sql",
        "swift", "ts", "tsx", "txt", "xml", "yaml", "yml",
    ]

    private static let supportedTextMediaTypes: [String: String] = [
        "css": "text/css",
        "csv": "text/csv",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "html": "text/html",
        "java": "text/x-java-source",
        "js": "text/javascript",
        "json": "application/json",
        "jsx": "text/jsx",
        "kt": "text/x-kotlin",
        "log": "text/plain",
        "md": "text/markdown",
        "py": "text/x-python",
        "rb": "text/x-ruby",
        "rs": "text/rust",
        "sh": "text/x-shellscript",
        "sql": "application/sql",
        "swift": "text/x-swift",
        "ts": "text/typescript",
        "tsx": "text/tsx",
        "txt": "text/plain",
        "xml": "application/xml",
        "yaml": "application/yaml",
        "yml": "application/yaml",
    ]
}
