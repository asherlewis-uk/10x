#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: render-dmg-background.swift <output-path> <width> <height>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]

guard
    let width = Double(CommandLine.arguments[2]),
    let height = Double(CommandLine.arguments[3]),
    width > 0,
    height > 0
else {
    fputs("width and height must be positive numbers\n", stderr)
    exit(1)
}

let canvasSize = NSSize(width: width, height: height)
let bounds = NSRect(origin: .zero, size: canvasSize)
let outputURL = URL(fileURLWithPath: outputPath)
let title = "Drag 10x into Applications"

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create bitmap context\n", stderr)
    exit(1)
}

bitmap.size = canvasSize

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}

func drawBaseBackground() {
    let background = NSColor(calibratedWhite: 1.0, alpha: 1)
    background.setFill()
    bounds.fill()
}

func drawInstructionText() {
    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center

    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
        .paragraphStyle: titleStyle,
    ]

    let titleRect = NSRect(x: 56, y: height - 58, width: width - 112, height: 30)

    title.draw(in: titleRect, withAttributes: titleAttributes)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

drawBaseBackground()
drawInstructionText()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: outputURL)
} catch {
    fputs("failed to write PNG: \(error)\n", stderr)
    exit(1)
}
