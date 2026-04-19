#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render-dmg-app-icon.swift <output-path> <size>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]

guard
    let canvasSize = Int(CommandLine.arguments[2]),
    canvasSize > 0
else {
    fputs("size must be a positive integer\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
let scriptURL = URL(fileURLWithPath: #filePath)
let logoURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("10x-macos/Assets.xcassets/10XbuilderLogo.imageset/10XbuilderLogo.svg")

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create bitmap\n", stderr)
    exit(1)
}

bitmap.size = NSSize(width: canvasSize, height: canvasSize)

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}

let canvas = CGFloat(canvasSize)
let tileRect = NSRect(
    x: 0,
    y: 0,
    width: canvas,
    height: canvas
)
let tileCornerRadius = tileRect.width * 0.224
guard let logoImage = NSImage(contentsOf: logoURL) else {
    fputs("failed to load brand logo at \(logoURL.path)\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.shouldAntialias = true
graphicsContext.imageInterpolation = .high

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas, height: canvas)).fill()

let tilePath = NSBezierPath(
    roundedRect: tileRect,
    xRadius: tileCornerRadius,
    yRadius: tileCornerRadius
)

NSColor.black.setFill()
tilePath.fill()

let logoMarginX = tileRect.width * 0.22
let logoMarginY = tileRect.height * 0.26
let maxLogoRect = tileRect.insetBy(dx: logoMarginX, dy: logoMarginY)
let logoSize = logoImage.size
let logoScale = min(
    maxLogoRect.width / max(logoSize.width, 1),
    maxLogoRect.height / max(logoSize.height, 1)
)
let drawSize = NSSize(width: logoSize.width * logoScale, height: logoSize.height * logoScale)
let drawRect = NSRect(
    x: tileRect.midX - (drawSize.width / 2),
    y: tileRect.midY - (drawSize.height / 2),
    width: drawSize.width,
    height: drawSize.height
)
logoImage.draw(
    in: drawRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

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
