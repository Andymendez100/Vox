#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Icon Generator

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22

    // Background: dark navy-to-indigo gradient with rounded rect
    let bgPath = CGPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                        transform: nil)
    context.addPath(bgPath)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.08, green: 0.08, blue: 0.20, alpha: 1.0),  // dark navy
        CGColor(red: 0.15, green: 0.10, blue: 0.35, alpha: 1.0),  // indigo
        CGColor(red: 0.10, green: 0.06, blue: 0.25, alpha: 1.0),  // deep purple
    ] as CFArray
    let gradientLocations: [CGFloat] = [0.0, 0.5, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: s),
                                   end: CGPoint(x: s, y: 0),
                                   options: [])
    }

    // Subtle inner glow
    context.resetClip()
    context.addPath(bgPath)
    context.clip()

    let glowColors = [
        CGColor(red: 0.3, green: 0.2, blue: 0.6, alpha: 0.15),
        CGColor(red: 0.3, green: 0.2, blue: 0.6, alpha: 0.0),
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        context.drawRadialGradient(glowGradient,
                                    startCenter: CGPoint(x: s * 0.5, y: s * 0.55),
                                    startRadius: 0,
                                    endCenter: CGPoint(x: s * 0.5, y: s * 0.55),
                                    endRadius: s * 0.5,
                                    options: [])
    }

    // Sound wave arcs (left side)
    let micCenter = CGPoint(x: s * 0.5, y: s * 0.52)
    let arcColor = CGColor(red: 1.0, green: 0.35, blue: 0.30, alpha: 0.25)
    context.setStrokeColor(arcColor)
    context.setLineWidth(s * 0.018)
    context.setLineCap(.round)

    for i in 1...3 {
        let radius = s * (0.22 + CGFloat(i) * 0.06)
        let alpha = 0.3 - CGFloat(i) * 0.07
        context.setStrokeColor(CGColor(red: 1.0, green: 0.35, blue: 0.30, alpha: alpha))

        // Left arc
        context.addArc(center: micCenter, radius: radius,
                       startAngle: .pi * 0.65, endAngle: .pi * 0.85, clockwise: false)
        context.strokePath()

        // Right arc
        context.addArc(center: micCenter, radius: radius,
                       startAngle: -.pi * 0.15, endAngle: .pi * 0.15, clockwise: true)
        context.strokePath()
    }

    // Microphone body (rounded rectangle)
    let micWidth = s * 0.15
    let micHeight = s * 0.24
    let micX = s * 0.5 - micWidth / 2
    let micY = s * 0.45
    let micRect = CGRect(x: micX, y: micY, width: micWidth, height: micHeight)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micWidth / 2, cornerHeight: micWidth / 2, transform: nil)

    // Mic gradient: coral to red
    context.saveGState()
    context.addPath(micPath)
    context.clip()

    let micColors = [
        CGColor(red: 1.0, green: 0.38, blue: 0.30, alpha: 1.0),  // coral
        CGColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1.0),  // red
    ] as CFArray
    if let micGradient = CGGradient(colorsSpace: colorSpace, colors: micColors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(micGradient,
                                   start: CGPoint(x: micX, y: micY + micHeight),
                                   end: CGPoint(x: micX + micWidth, y: micY),
                                   options: [])
    }
    context.restoreGState()

    // Microphone grille lines
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15))
    context.setLineWidth(s * 0.006)
    let lineSpacing = micHeight * 0.15
    for i in 1...4 {
        let lineY = micY + micHeight * 0.2 + lineSpacing * CGFloat(i)
        if lineY < micY + micHeight - micWidth * 0.3 {
            let inset = micWidth * 0.2
            context.move(to: CGPoint(x: micX + inset, y: lineY))
            context.addLine(to: CGPoint(x: micX + micWidth - inset, y: lineY))
            context.strokePath()
        }
    }

    // Microphone cradle (U-shape arc below mic)
    let cradleRadius = s * 0.12
    let cradleCenter = CGPoint(x: s * 0.5, y: micY + micHeight * 0.15)
    context.setStrokeColor(CGColor(red: 1.0, green: 0.38, blue: 0.30, alpha: 0.8))
    context.setLineWidth(s * 0.022)
    context.addArc(center: cradleCenter, radius: cradleRadius,
                   startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
    context.strokePath()

    // Stand (vertical line from cradle to base)
    let standTop = cradleCenter.y - cradleRadius * sin(.pi * 0.15)
    let standBottom = s * 0.24
    context.setStrokeColor(CGColor(red: 1.0, green: 0.38, blue: 0.30, alpha: 0.7))
    context.setLineWidth(s * 0.022)
    context.move(to: CGPoint(x: s * 0.5, y: standTop))
    context.addLine(to: CGPoint(x: s * 0.5, y: standBottom))
    context.strokePath()

    // Base (horizontal line)
    let baseWidth = s * 0.12
    context.move(to: CGPoint(x: s * 0.5 - baseWidth / 2, y: standBottom))
    context.addLine(to: CGPoint(x: s * 0.5 + baseWidth / 2, y: standBottom))
    context.strokePath()

    // Subtle highlight on mic
    context.saveGState()
    context.addPath(micPath)
    context.clip()
    let highlightColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.25),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
    ] as CFArray
    if let highlightGrad = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(highlightGrad,
                                   start: CGPoint(x: micX, y: micY + micHeight),
                                   end: CGPoint(x: micX + micWidth * 0.7, y: micY),
                                   options: [])
    }
    context.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String, size: Int) {
    let targetSize = NSSize(width: size, height: size)
    let resized = NSImage(size: targetSize)
    resized.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1.0)
    resized.unlockFocus()

    guard let tiffData = resized.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate PNG for size \(size)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
    } catch {
        print("Failed to write \(path): \(error)")
    }
}

// MARK: - Main

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let projectDir = URL(fileURLWithPath: scriptDir).deletingLastPathComponent().path
let iconsetDir = "\(projectDir)/SttTool/Resources/AppIcon.iconset"

// Create iconset directory
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// Generate master image at 1024x1024
let masterImage = generateIcon(size: 1024)

// Required sizes for .iconset
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let path = "\(iconsetDir)/\(entry.name).png"
    savePNG(masterImage, to: path, size: entry.pixels)
    print("Generated \(entry.name).png (\(entry.pixels)x\(entry.pixels))")
}

print("\nIconset created at: \(iconsetDir)")
print("Run: iconutil -c icns \"\(iconsetDir)\" -o \"\(projectDir)/SttTool/Resources/AppIcon.icns\"")
