#!/usr/bin/env swift
// Draws the app icon (the markdown mark on a dark rounded square) and writes an
// .iconset directory. build.sh turns that into Icon.icns with iconutil.
//
//   swift Tools/make-icon.swift <output.iconset>

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/AppIcon.iconset"

// Sizes macOS wants in an iconset: (pixels, filename).
let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

func draw(size: CGFloat, into context: CGContext) {
    let scale = size / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icons leave a margin; the art sits in the middle ~82%.
    let inset: CGFloat = 92
    let plate = CGRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
    let corner: CGFloat = 185

    // Background: subtle top-to-bottom gradient, GitHub-dark colored.
    context.saveGState()
    let plateShape = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.addPath(plateShape)
    context.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(colorSpace: colorSpace, components: [0.196, 0.235, 0.286, 1])!,
            CGColor(colorSpace: colorSpace, components: [0.051, 0.067, 0.090, 1])!,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: plate.maxY),
        end: CGPoint(x: 0, y: plate.minY),
        options: []
    )
    context.restoreGState()

    // Hairline highlight along the top edge, the usual macOS icon treatment.
    context.saveGState()
    context.addPath(plateShape)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    context.setLineWidth(6)
    context.strokePath()
    context.restoreGState()

    // The markdown mark, drawn in its native 208x128 coordinate space and
    // mapped into the plate.
    let markWidth: CGFloat = 208
    let markHeight: CGFloat = 128
    let targetWidth = plate.width * 0.68
    let markScale = targetWidth / markWidth
    let originX = plate.midX - (markWidth * markScale) / 2
    let originY = plate.midY - (markHeight * markScale) / 2

    // Negative y scale flips the mark's SVG-style y-down coordinates.
    var transform = CGAffineTransform(
        translationX: originX,
        y: originY + markHeight * markScale
    ).scaledBy(x: markScale, y: -markScale)

    context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    context.setFillColor(CGColor(gray: 1, alpha: 0.95))
    context.setLineJoin(.round)

    let border = CGPath(
        roundedRect: CGRect(x: 5, y: 5, width: 198, height: 118),
        cornerWidth: 12,
        cornerHeight: 12,
        transform: nil
    )
    if let bordered = border.copy(using: &transform) {
        context.addPath(bordered)
        context.setLineWidth(10 * markScale)
        context.strokePath()
    }

    let glyph = CGMutablePath()
    // "M"
    glyph.addLines(between: [
        CGPoint(x: 30, y: 98), CGPoint(x: 30, y: 30), CGPoint(x: 50, y: 30),
        CGPoint(x: 70, y: 55), CGPoint(x: 90, y: 30), CGPoint(x: 110, y: 30),
        CGPoint(x: 110, y: 98), CGPoint(x: 90, y: 98), CGPoint(x: 90, y: 59),
        CGPoint(x: 70, y: 84), CGPoint(x: 50, y: 59), CGPoint(x: 50, y: 98),
    ])
    glyph.closeSubpath()
    // Down arrow
    glyph.addLines(between: [
        CGPoint(x: 155, y: 98), CGPoint(x: 125, y: 65), CGPoint(x: 145, y: 65),
        CGPoint(x: 145, y: 30), CGPoint(x: 165, y: 30), CGPoint(x: 165, y: 65),
        CGPoint(x: 185, y: 65),
    ])
    glyph.closeSubpath()

    if let filled = glyph.copy(using: &transform) {
        context.addPath(filled)
        context.fillPath()
    }
}

func png(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    )!

    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphicsContext
    let context = graphicsContext.cgContext
    context.setAllowsAntialiasing(true)
    draw(size: CGFloat(size), into: context)
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])!
}

let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
for (size, name) in variants {
    try png(size: size).write(to: outputURL.appendingPathComponent(name))
}
print("wrote \(variants.count) images to \(outputPath)")
