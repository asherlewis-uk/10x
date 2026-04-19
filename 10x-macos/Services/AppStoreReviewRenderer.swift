import AppKit
import Foundation

enum AppStoreReviewRenderer {
    static let screenshotSize = CGSize(width: 1290, height: 2796)
    private static let deviceBodyAspectRatio: CGFloat = 0.478
    private static let deviceVerticalInset: CGFloat = 72
    private static let minimumTextToDeviceSpacing: CGFloat = 88

    private struct ScreenshotTextLayout {
        let frame: CGRect
        let headline: NSAttributedString
        let headlineRect: CGRect
        let subheadline: NSAttributedString?
        let subheadlineRect: CGRect?
    }

    static func renderScreenshot(
        spec: AppStoreReviewScreenshotSpec,
        sourceImage: NSImage
    ) -> NSImage? {
        renderBitmap(size: screenshotSize) {
            let canvasRect = CGRect(origin: .zero, size: screenshotSize)
            let palette = normalizedPalette(spec.backgroundColors, fallback: ["#F7F9FC", "#E7EEF8", "#5C7FBD"])
            drawScreenshotBackdrop(rect: canvasRect, palette: palette)

            let primaryTextColor = screenshotPrimaryTextColor(for: palette)
            let textLayout = screenshotTextLayout(
                in: canvasRect,
                spec: spec,
                primaryColor: primaryTextColor
            )
            drawScreenshotCopy(textLayout)

            let deviceScale = CGFloat(max(0.82, min(spec.deviceScale, 0.98)))
            let widthFactor = max(0.74, min(0.88, deviceScale * 0.92))
            let preferredDeviceWidth = canvasRect.width * widthFactor
            let preferredDeviceHeight = preferredDeviceWidth / deviceBodyAspectRatio
            let textToDeviceSpacing = screenshotTextToDeviceSpacing(spec)
            let fittedDeviceSize = screenshotDeviceSize(
                in: canvasRect,
                spec: spec,
                textFrame: textLayout.frame,
                preferredSize: CGSize(width: preferredDeviceWidth, height: preferredDeviceHeight),
                textToDeviceSpacing: textToDeviceSpacing
            )
            let deviceRect = screenshotDeviceRect(
                in: canvasRect,
                spec: spec,
                textFrame: textLayout.frame,
                deviceWidth: fittedDeviceSize.width,
                deviceHeight: fittedDeviceSize.height,
                textToDeviceSpacing: textToDeviceSpacing
            )

            drawDeviceMockup(
                spec: spec,
                sourceImage: sourceImage,
                in: deviceRect,
                rotationDegrees: spec.rotationDegrees
            )
        }
    }

    private static func renderBitmap(size: CGSize, draw: () -> Void) -> NSImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        rep.size = NSSize(width: size.width, height: size.height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        draw()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func drawGradient(colors: [NSColor], in rect: CGRect) {
        let cgColors = colors.map(\.cgColor) as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors,
            locations: nil
        ) else {
            return
        }
        let context = NSGraphicsContext.current?.cgContext
        context?.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    private static func drawScreenshotBackdrop(rect: CGRect, palette: [NSColor]) {
        let backgroundColors = screenshotBackgroundColors(from: palette)
        drawGradient(colors: backgroundColors, in: rect)

        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: rect).fill()
    }

    private static func screenshotTextLayout(
        in canvasRect: CGRect,
        spec: AppStoreReviewScreenshotSpec,
        primaryColor: NSColor
    ) -> ScreenshotTextLayout {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = paragraphAlignment(spec.textAlignment)
        paragraph.lineBreakMode = .byWordWrapping

        let width = screenshotTextWidth(in: canvasRect, spec: spec)
        let x = screenshotTextOriginX(in: canvasRect, width: width, alignment: spec.textAlignment)
        let headline = NSAttributedString(
            string: spec.headlineAllCaps ? spec.headline.uppercased() : spec.headline,
            attributes: [
                .font: screenshotFont(
                    size: 88 * CGFloat(max(0.84, min(spec.headlineScale, 1.24))),
                    family: spec.headlineFontFamily,
                    weight: spec.headlineWeight,
                    italic: spec.headlineItalic
                ),
                .foregroundColor: primaryColor,
                .paragraphStyle: paragraph,
                .kern: CGFloat(max(-2.5, min(spec.headlineTracking, 3.0))),
            ]
        )
        let headlineHeight = attributedTextHeight(headline, width: width)

        let subheadlineText = spec.subheadline.trimmingCharacters(in: .whitespacesAndNewlines)
        let subheadline = subheadlineText.isEmpty
            ? nil
            : NSAttributedString(
                string: subheadlineText,
                attributes: [
                    .font: screenshotFont(
                        size: 34 * CGFloat(max(0.76, min(spec.subheadlineScale, 1.24))),
                        family: spec.subheadlineFontFamily,
                        weight: spec.subheadlineWeight,
                        italic: spec.subheadlineItalic
                    ),
                    .foregroundColor: primaryColor.withAlphaComponent(0.68),
                    .paragraphStyle: paragraph,
                    .kern: 0.2,
                ]
            )
        let subheadlineHeight = subheadline.map { attributedTextHeight($0, width: width) } ?? 0
        let gap: CGFloat = subheadline == nil ? 0 : 18
        let totalHeight = headlineHeight + subheadlineHeight + gap
        let y: CGFloat = spec.textPlacement == .top
            ? canvasRect.height - totalHeight - 96
            : 110

        return ScreenshotTextLayout(
            frame: CGRect(x: x, y: y, width: width, height: totalHeight),
            headline: headline,
            headlineRect: CGRect(
                x: x,
                y: y + subheadlineHeight + gap,
                width: width,
                height: headlineHeight
            ),
            subheadline: subheadline,
            subheadlineRect: subheadline.map { _ in
                CGRect(x: x, y: y, width: width, height: subheadlineHeight)
            }
        )
    }

    private static func drawScreenshotCopy(_ layout: ScreenshotTextLayout) {
        layout.headline.draw(
            with: layout.headlineRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        if let subheadline = layout.subheadline,
           let subheadlineRect = layout.subheadlineRect {
            subheadline.draw(
                with: subheadlineRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }
    }

    private static func screenshotTextWidth(
        in canvasRect: CGRect,
        spec: AppStoreReviewScreenshotSpec
    ) -> CGFloat {
        let widthRatio = CGFloat(max(0.52, min(spec.headlineWidthRatio, 1.0)))
        let sideInset: CGFloat = 120
        let fullWidth = canvasRect.width - (sideInset * 2)
        return max(520, fullWidth * widthRatio)
    }

    private static func screenshotTextOriginX(
        in canvasRect: CGRect,
        width: CGFloat,
        alignment: AppStoreReviewTextAlignment
    ) -> CGFloat {
        let sideInset: CGFloat = 120
        switch alignment {
        case .center:
            return canvasRect.midX - width / 2
        case .trailing:
            return canvasRect.maxX - sideInset - width
        case .leading:
            return sideInset
        }
    }

    private static func attributedTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(
            text.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
        )
    }

    private static func screenshotTextToDeviceSpacing(_ spec: AppStoreReviewScreenshotSpec) -> CGFloat {
        CGFloat(max(minimumTextToDeviceSpacing, min(spec.textToDeviceSpacing, 140)))
    }

    private static func screenshotDeviceSize(
        in canvasRect: CGRect,
        spec: AppStoreReviewScreenshotSpec,
        textFrame: CGRect,
        preferredSize: CGSize,
        textToDeviceSpacing: CGFloat
    ) -> CGSize {
        let horizontalInset: CGFloat = 84
        let maxWidth = max(420, canvasRect.width - (horizontalInset * 2))
        let availableHeight: CGFloat
        switch spec.textPlacement {
        case .top:
            availableHeight = textFrame.minY - textToDeviceSpacing - deviceVerticalInset
        case .bottom:
            availableHeight = canvasRect.maxY - textFrame.maxY - textToDeviceSpacing - deviceVerticalInset
        }
        let maxHeight = max(900, availableHeight)
        let scale = min(
            1,
            maxWidth / preferredSize.width,
            maxHeight / preferredSize.height
        )
        return CGSize(
            width: preferredSize.width * scale,
            height: preferredSize.height * scale
        )
    }

    private static func screenshotDeviceRect(
        in canvasRect: CGRect,
        spec: AppStoreReviewScreenshotSpec,
        textFrame: CGRect,
        deviceWidth: CGFloat,
        deviceHeight: CGFloat,
        textToDeviceSpacing: CGFloat
    ) -> CGRect {
        let x = (canvasRect.width - deviceWidth) / 2
        let rawY: CGFloat = spec.textPlacement == .top
            ? textFrame.minY - textToDeviceSpacing - deviceHeight
            : textFrame.maxY + textToDeviceSpacing
        let minimumY = deviceVerticalInset
        let maximumY = canvasRect.height - deviceHeight - deviceVerticalInset
        let y = min(max(rawY, minimumY), maximumY)
        return CGRect(x: x, y: y, width: deviceWidth, height: deviceHeight)
    }

    private static func drawDeviceMockup(
        spec: AppStoreReviewScreenshotSpec,
        sourceImage: NSImage,
        in bodyRect: CGRect,
        rotationDegrees: Double
    ) {
        let cornerRadius = bodyRect.width * 0.19
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)
        let screenBezel = bodyRect.width * 0.034
        let screenBounds = bodyRect.insetBy(dx: screenBezel, dy: screenBezel)
        let screenRect = aspectFitRect(
            for: CGSize(width: sourceAspectRatio(for: sourceImage), height: 1),
            inside: screenBounds
        )
        let screenRadius = screenRect.width * 0.14
        let center = CGPoint(x: bodyRect.midX, y: bodyRect.midY)
        let context = NSGraphicsContext.current?.cgContext

        withRotation(angleDegrees: rotationDegrees, around: center) {
            context?.saveGState()
            context?.setShadow(
                offset: CGSize(width: 0, height: -20),
                blur: 46,
                color: NSColor.black.withAlphaComponent(0.14).cgColor
            )
            NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1).setFill()
            bodyPath.fill()
            context?.restoreGState()

            let rimPath = NSBezierPath(
                roundedRect: bodyRect.insetBy(dx: 1.5, dy: 1.5),
                xRadius: cornerRadius - 1.5,
                yRadius: cornerRadius - 1.5
            )
            NSColor(red: 0.30, green: 0.32, blue: 0.36, alpha: 0.92).setStroke()
            rimPath.lineWidth = 3
            rimPath.stroke()

            let innerRimPath = NSBezierPath(
                roundedRect: bodyRect.insetBy(dx: 7, dy: 7),
                xRadius: cornerRadius - 8,
                yRadius: cornerRadius - 8
            )
            NSColor.white.withAlphaComponent(0.06).setStroke()
            innerRimPath.lineWidth = 1.6
            innerRimPath.stroke()

            drawSideButton(
                rect: CGRect(
                    x: bodyRect.minX - 6,
                    y: bodyRect.midY + bodyRect.height * 0.14,
                    width: 8,
                    height: bodyRect.height * 0.10
                )
            )
            drawSideButton(
                rect: CGRect(
                    x: bodyRect.minX - 5,
                    y: bodyRect.midY - bodyRect.height * 0.01,
                    width: 7,
                    height: bodyRect.height * 0.08
                )
            )
            drawSideButton(
                rect: CGRect(
                    x: bodyRect.maxX - 2,
                    y: bodyRect.midY + bodyRect.height * 0.08,
                    width: 6,
                    height: bodyRect.height * 0.13
                )
            )

            context?.saveGState()
            let screenPath = NSBezierPath(
                roundedRect: screenRect,
                xRadius: screenRadius,
                yRadius: screenRadius
            )
            screenPath.addClip()
            NSColor.black.setFill()
            screenPath.fill()
            sourceImage.draw(
                in: screenContentRect(
                    for: sourceImage.size,
                    inside: screenRect,
                    zoom: spec.screenZoom,
                    focusX: spec.screenFocusX,
                    focusY: spec.screenFocusY
                ),
                from: fullSourceRect(for: sourceImage),
                operation: .sourceOver,
                fraction: 1
            )
            context?.restoreGState()

            let screenStroke = NSBezierPath(
                roundedRect: screenRect,
                xRadius: screenRadius,
                yRadius: screenRadius
            )
            NSColor.white.withAlphaComponent(0.10).setStroke()
            screenStroke.lineWidth = 1.4
            screenStroke.stroke()
        }
    }

    private static func drawSideButton(rect: CGRect) {
        let buttonPath = NSBezierPath(roundedRect: rect, xRadius: rect.width / 2, yRadius: rect.width / 2)
        NSColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1).setFill()
        buttonPath.fill()
    }

    private static func fullSourceRect(for image: NSImage) -> CGRect {
        let sourceSize = image.size
        return CGRect(origin: .zero, size: sourceSize)
    }

    private static func sourceAspectRatio(for image: NSImage) -> CGFloat {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return screenshotSize.width / screenshotSize.height
        }
        return sourceSize.width / sourceSize.height
    }

    private static func aspectFitRect(for sourceSize: CGSize, inside targetRect: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return targetRect }
        let scale = min(targetRect.width / sourceSize.width, targetRect.height / sourceSize.height)
        let fittedSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: targetRect.midX - fittedSize.width / 2,
            y: targetRect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private static func screenContentRect(
        for sourceSize: CGSize,
        inside targetRect: CGRect,
        zoom: Double,
        focusX: Double,
        focusY: Double
    ) -> CGRect {
        let fittedRect = aspectFitRect(for: sourceSize, inside: targetRect)
        let clampedZoom = CGFloat(max(1.0, min(zoom, 1.6)))
        guard clampedZoom > 1.001 else { return fittedRect }

        let scaledSize = CGSize(
            width: fittedRect.width * clampedZoom,
            height: fittedRect.height * clampedZoom
        )
        let maxOffsetX = max(0, scaledSize.width - targetRect.width)
        let maxOffsetY = max(0, scaledSize.height - targetRect.height)
        let clampedFocusX = CGFloat(max(0, min(focusX, 1)))
        let clampedFocusY = CGFloat(max(0, min(focusY, 1)))

        return CGRect(
            x: targetRect.minX - (maxOffsetX * clampedFocusX),
            y: targetRect.minY - (maxOffsetY * clampedFocusY),
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    private static func screenshotBackgroundColors(from palette: [NSColor]) -> [NSColor] {
        let first = palette.first ?? NSColor.white
        let middle = palette.dropFirst().first ?? first
        let last = palette.last ?? middle
        return [
            first.lightened(0.03),
            middle.lightened(0.07),
            last.lightened(0.26),
        ]
    }

    private static func screenshotPrimaryTextColor(for palette: [NSColor]) -> NSColor {
        let luminance = palette.map(\.relativeLuminance).reduce(0, +) / CGFloat(max(1, palette.count))
        if luminance > 0.50 {
            return NSColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1)
        }
        return NSColor.white
    }

    private static func withRotation(angleDegrees: Double, around point: CGPoint, draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.rotate(byDegrees: angleDegrees)
        transform.translateX(by: -point.x, yBy: -point.y)
        transform.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func paragraphAlignment(_ alignment: AppStoreReviewTextAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading:
            return .left
        case .center:
            return .center
        case .trailing:
            return .right
        }
    }

    private static func screenshotFont(
        size: CGFloat,
        family: AppStoreReviewFontFamily,
        weight: AppStoreReviewHeadlineWeight,
        italic: Bool
    ) -> NSFont {
        let font = baseFont(size: size, family: family, weight: weight)
        guard italic else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private static func nsFontWeight(for weight: AppStoreReviewHeadlineWeight) -> NSFont.Weight {
        switch weight {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .black:
            return .black
        }
    }

    private static func baseFont(
        size: CGFloat,
        family: AppStoreReviewFontFamily,
        weight: AppStoreReviewHeadlineWeight
    ) -> NSFont {
        switch family {
        case .system:
            return NSFont.systemFont(ofSize: size, weight: nsFontWeight(for: weight))
        case .rounded:
            return designedSystemFont(size: size, weight: weight, design: .rounded)
        case .serif:
            return designedSystemFont(size: size, weight: weight, design: .serif)
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: nsFontWeight(for: weight))
        case .condensed:
            return condensedFont(size: size, weight: weight)
        }
    }

    private static func designedSystemFont(
        size: CGFloat,
        weight: AppStoreReviewHeadlineWeight,
        design: NSFontDescriptor.SystemDesign
    ) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: nsFontWeight(for: weight))
        guard let descriptor = base.fontDescriptor.withDesign(design),
              let font = NSFont(descriptor: descriptor, size: size)
        else {
            return base
        }
        return font
    }

    private static func condensedFont(
        size: CGFloat,
        weight: AppStoreReviewHeadlineWeight
    ) -> NSFont {
        let names: [String]
        switch weight {
        case .regular:
            names = ["AvenirNextCondensed-Regular", "HelveticaNeue"]
        case .medium:
            names = ["AvenirNextCondensed-Medium", "HelveticaNeue-Medium"]
        case .semibold:
            names = ["AvenirNextCondensed-DemiBold", "HelveticaNeue-Bold"]
        case .bold:
            names = ["AvenirNextCondensed-Bold", "HelveticaNeue-CondensedBold"]
        case .black:
            names = ["HelveticaNeue-CondensedBlack", "AvenirNextCondensed-Heavy"]
        }
        for name in names {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: size, weight: nsFontWeight(for: weight))
    }

    private static func normalizedPalette(_ values: [String], fallback: [String]) -> [NSColor] {
        let resolved = values.compactMap(NSColor.init(hexString:))
        if resolved.count >= 2 {
            return resolved
        }
        return fallback.compactMap(NSColor.init(hexString:))
    }
}

extension NSImage {
    func downsampledPNGData(maxDimension: CGFloat) -> Data? {
        let originalSize = size
        guard originalSize.width > 0, originalSize.height > 0 else {
            return pngData
        }

        let longestSide = max(originalSize.width, originalSize.height)
        guard longestSide > maxDimension else {
            return pngData
        }

        let scale = maxDimension / longestSide
        let scaledSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(scaledSize.width.rounded(.up)),
            pixelsHigh: Int(scaledSize.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        rep.size = NSSize(width: scaledSize.width, height: scaledSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        self.draw(in: CGRect(origin: .zero, size: scaledSize))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    func normalizedAppIconCanvasIfNeeded() -> NSImage {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return self
        }

        let pixelWidth = bitmap.pixelsWide
        let pixelHeight = bitmap.pixelsHigh
        guard pixelWidth > 0, pixelHeight > 0 else {
            return self
        }

        guard let matteColor = averagedCornerColor(in: bitmap, width: pixelWidth, height: pixelHeight) else {
            return self
        }

        let sampleStep = max(1, min(pixelWidth, pixelHeight) / 256)
        let coverageThreshold: CGFloat = 0.42
        let colorThreshold: CGFloat = 0.065

        func differsFromMatte(_ color: NSColor?) -> Bool {
            guard let rgba = AppIconRGBA(color: color) else { return false }
            return rgba.distance(to: matteColor) > colorThreshold
        }

        func rowCoverage(_ y: Int) -> CGFloat {
            var total = 0
            var differing = 0
            var x = 0
            while x < pixelWidth {
                total += 1
                if differsFromMatte(bitmap.colorAt(x: x, y: y)) {
                    differing += 1
                }
                x += sampleStep
            }
            return total == 0 ? 0 : CGFloat(differing) / CGFloat(total)
        }

        func columnCoverage(_ x: Int) -> CGFloat {
            var total = 0
            var differing = 0
            var y = 0
            while y < pixelHeight {
                total += 1
                if differsFromMatte(bitmap.colorAt(x: x, y: y)) {
                    differing += 1
                }
                y += sampleStep
            }
            return total == 0 ? 0 : CGFloat(differing) / CGFloat(total)
        }

        let contentRows = (0..<pixelHeight).filter { rowCoverage($0) > coverageThreshold }
        let contentColumns = (0..<pixelWidth).filter { columnCoverage($0) > coverageThreshold }

        guard let minY = contentRows.first,
              let maxY = contentRows.last,
              let minX = contentColumns.first,
              let maxX = contentColumns.last
        else {
            return self
        }

        let cropWidth = maxX - minX + 1
        let cropHeight = maxY - minY + 1
        let widthRatio = CGFloat(cropWidth) / CGFloat(pixelWidth)
        let heightRatio = CGFloat(cropHeight) / CGFloat(pixelHeight)

        guard widthRatio < 0.95, heightRatio < 0.95,
              widthRatio > 0.55, heightRatio > 0.55
        else {
            return self
        }

        let padding = Int((CGFloat(min(pixelWidth, pixelHeight)) * 0.01).rounded(.up))
        let originX = max(minX - padding, 0)
        let originY = max(minY - padding, 0)
        let endX = min(maxX + padding, pixelWidth - 1)
        let endY = min(maxY + padding, pixelHeight - 1)
        let paddedCropWidth = endX - originX + 1
        let paddedCropHeight = endY - originY + 1

        let outputSize = CGSize(
            width: size.width > 0 ? size.width : CGFloat(pixelWidth),
            height: size.height > 0 ? size.height : CGFloat(pixelHeight)
        )
        let sourceRect = CGRect(
            x: CGFloat(originX) * outputSize.width / CGFloat(pixelWidth),
            y: CGFloat(originY) * outputSize.height / CGFloat(pixelHeight),
            width: CGFloat(paddedCropWidth) * outputSize.width / CGFloat(pixelWidth),
            height: CGFloat(paddedCropHeight) * outputSize.height / CGFloat(pixelHeight)
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputSize.width.rounded(.up)),
            pixelsHigh: Int(outputSize.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return self
        }

        rep.size = NSSize(width: outputSize.width, height: outputSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        self.draw(
            in: CGRect(origin: .zero, size: outputSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let normalized = NSImage(size: NSSize(width: outputSize.width, height: outputSize.height))
        normalized.addRepresentation(rep)
        return normalized
    }

    private func averagedCornerColor(
        in bitmap: NSBitmapImageRep,
        width: Int,
        height: Int
    ) -> AppIconRGBA? {
        let points = [
            (0, 0),
            (max(width - 1, 0), 0),
            (0, max(height - 1, 0)),
            (max(width - 1, 0), max(height - 1, 0)),
        ]

        let samples = points.compactMap { point in
            AppIconRGBA(color: bitmap.colorAt(x: point.0, y: point.1))
        }
        guard !samples.isEmpty else { return nil }

        let total = samples.reduce(AppIconRGBA.zero) { partial, sample in
            AppIconRGBA(
                red: partial.red + sample.red,
                green: partial.green + sample.green,
                blue: partial.blue + sample.blue,
                alpha: partial.alpha + sample.alpha
            )
        }
        let count = CGFloat(samples.count)
        return AppIconRGBA(
            red: total.red / count,
            green: total.green / count,
            blue: total.blue / count,
            alpha: total.alpha / count
        )
    }
}

private struct AppIconRGBA {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static let zero = AppIconRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(color: NSColor?) {
        guard let color,
              let rgb = color.usingColorSpace(.deviceRGB)
        else {
            return nil
        }
        self.init(
            red: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: rgb.alphaComponent
        )
    }

    func distance(to other: AppIconRGBA) -> CGFloat {
        max(
            abs(red - other.red),
            abs(green - other.green),
            abs(blue - other.blue),
            abs(alpha - other.alpha)
        )
    }
}

private extension NSColor {
    convenience init?(hexString: String?) {
        let raw = (hexString ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard raw.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&value) else { return nil }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    func mixed(with color: NSColor, amount: CGFloat) -> NSColor {
        let lhs = usingColorSpace(.deviceRGB) ?? self
        let rhs = color.usingColorSpace(.deviceRGB) ?? color
        let clamped = max(0, min(amount, 1))
        return NSColor(
            red: lhs.redComponent + (rhs.redComponent - lhs.redComponent) * clamped,
            green: lhs.greenComponent + (rhs.greenComponent - lhs.greenComponent) * clamped,
            blue: lhs.blueComponent + (rhs.blueComponent - lhs.blueComponent) * clamped,
            alpha: lhs.alphaComponent + (rhs.alphaComponent - lhs.alphaComponent) * clamped
        )
    }

    func lightened(_ amount: CGFloat) -> NSColor {
        mixed(with: .white, amount: amount)
    }

    var relativeLuminance: CGFloat {
        let rgb = usingColorSpace(.deviceRGB) ?? self
        return (0.2126 * rgb.redComponent) + (0.7152 * rgb.greenComponent) + (0.0722 * rgb.blueComponent)
    }
}
