import AppKit
import Foundation
import UniformTypeIdentifiers

struct PreviewScreenCapture: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let relativeImagePath: String
    let perceptualHash: UInt64
    let pixelWidth: Int
    let pixelHeight: Int
    var viewName: String?

    init(
        id: String = UUID().uuidString,
        relativeImagePath: String,
        perceptualHash: UInt64,
        pixelWidth: Int,
        pixelHeight: Int,
        viewName: String? = nil
    ) {
        self.id = id
        self.relativeImagePath = relativeImagePath
        self.perceptualHash = perceptualHash
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.viewName = viewName
    }
}

extension PreviewScreenCapture {
    nonisolated var displayName: String {
        let trimmed = viewName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Screen" : trimmed
    }

    nonisolated var chatMentionName: String {
        BuilderMessageAttachment.previewViewMentionName(from: displayName)
    }

    nonisolated var chatMentionTag: String {
        "@\(chatMentionName)"
    }
}

extension UTType {
    static let tenXPreviewScreen = UTType(exportedAs: "app.10x.preview-screen")
}

enum PreviewScreenFingerprint {
    static let duplicateHammingThreshold = 3

    nonisolated static func hash(for image: NSImage) -> UInt64? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let width = 9
        let height = 8
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                let index = row * width + column
                hash <<= 1
                if pixels[index] > pixels[index + 1] {
                    hash |= 1
                }
            }
        }
        return hash
    }

    nonisolated static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}

enum PreviewScreenHeuristics {
    private struct SampleMetrics {
        let variance: Double
        let averageEdgeEnergy: Double
    }

    private nonisolated static func sampleMetrics(for image: NSImage) -> SampleMetrics? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        let width = 24
        let height = 24
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let normalizedPixels = pixels.map { Double($0) / 255.0 }
        let mean = normalizedPixels.reduce(0, +) / Double(normalizedPixels.count)
        let variance = normalizedPixels.reduce(0) { partial, value in
            let diff = value - mean
            return partial + (diff * diff)
        } / Double(normalizedPixels.count)

        var edgeEnergy = 0.0
        var edgeCount = 0.0
        for row in 0..<height {
            for column in 0..<width {
                let index = row * width + column
                let current = normalizedPixels[index]
                if column + 1 < width {
                    edgeEnergy += abs(current - normalizedPixels[index + 1])
                    edgeCount += 1
                }
                if row + 1 < height {
                    edgeEnergy += abs(current - normalizedPixels[index + width])
                    edgeCount += 1
                }
            }
        }

        return SampleMetrics(
            variance: variance,
            averageEdgeEnergy: edgeCount > 0 ? edgeEnergy / edgeCount : 0
        )
    }

    nonisolated static func isLikelyBlank(_ image: NSImage) -> Bool {
        guard let metrics = sampleMetrics(for: image) else { return false }
        return metrics.variance < 0.0009 && metrics.averageEdgeEnergy < 0.014
    }

    nonisolated static func isLikelyLoadingPlaceholder(_ image: NSImage) -> Bool {
        guard let metrics = sampleMetrics(for: image) else { return false }
        return metrics.variance < 0.0018 && metrics.averageEdgeEnergy < 0.022
    }

    nonisolated static func shouldIgnore(_ image: NSImage) -> Bool {
        isLikelyBlank(image) || isLikelyLoadingPlaceholder(image)
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    var pixelDimensions: CGSize {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
}
