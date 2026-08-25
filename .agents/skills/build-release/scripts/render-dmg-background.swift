#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: render-dmg-background.swift OUTPUT_PATH VERSION\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let version = CommandLine.arguments[2]
let canvasSize = NSSize(width: 700, height: 440)
let canvasRect = NSRect(origin: .zero, size: canvasSize)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("Failed to allocate the DMG background canvas\n".utf8))
    exit(1)
}

func drawCentered(
    _ text: String,
    topY: CGFloat,
    font: NSFont,
    color: NSColor,
    tracking: CGFloat = 0
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(
            x: (canvasSize.width - size.width) / 2,
            y: canvasSize.height - topY - size.height
        ),
        withAttributes: attributes
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let background = NSGradient(colors: [
    NSColor(red: 0.025, green: 0.055, blue: 0.105, alpha: 1),
    NSColor(red: 0.055, green: 0.105, blue: 0.185, alpha: 1),
    NSColor(red: 0.025, green: 0.060, blue: 0.120, alpha: 1),
])!
background.draw(in: canvasRect, angle: -18)

NSColor(red: 0.20, green: 0.78, blue: 1.0, alpha: 0.06).setStroke()
for x in stride(from: CGFloat(20), through: canvasSize.width, by: 40) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: x, y: 0))
    line.line(to: NSPoint(x: x, y: canvasSize.height))
    line.lineWidth = 1
    line.stroke()
}
for y in stride(from: CGFloat(20), through: canvasSize.height, by: 40) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 0, y: y))
    line.line(to: NSPoint(x: canvasSize.width, y: y))
    line.lineWidth = 1
    line.stroke()
}

let accentGlow = NSBezierPath(ovalIn: NSRect(x: 250, y: 90, width: 200, height: 200))
NSColor(red: 0.06, green: 0.62, blue: 1.0, alpha: 0.08).setFill()
accentGlow.fill()

drawCentered(
    "AGENTQUOTA  \(version)",
    topY: 34,
    font: .systemFont(ofSize: 12, weight: .semibold),
    color: NSColor(red: 0.36, green: 0.80, blue: 1.0, alpha: 0.9),
    tracking: 1.8
)
drawCentered(
    "Install AgentQuota",
    topY: 62,
    font: .systemFont(ofSize: 31, weight: .bold),
    color: .white
)
drawCentered(
    "Drag AgentQuota into Applications",
    topY: 105,
    font: .systemFont(ofSize: 16, weight: .medium),
    color: NSColor(white: 0.82, alpha: 1)
)

let arrowPill = NSBezierPath(
    roundedRect: NSRect(x: 292, y: 162, width: 116, height: 52),
    xRadius: 26,
    yRadius: 26
)
NSColor(red: 0.05, green: 0.49, blue: 0.95, alpha: 0.23).setFill()
arrowPill.fill()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 315, y: 188))
arrow.line(to: NSPoint(x: 383, y: 188))
arrow.lineWidth = 7
arrow.lineCapStyle = .round
NSColor(red: 0.31, green: 0.82, blue: 1.0, alpha: 1).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 390, y: 188))
arrowHead.line(to: NSPoint(x: 374, y: 201))
arrowHead.line(to: NSPoint(x: 374, y: 175))
arrowHead.close()
NSColor(red: 0.31, green: 0.82, blue: 1.0, alpha: 1).setFill()
arrowHead.fill()

drawCentered(
    "macOS 26  •  Apple silicon",
    topY: 398,
    font: .systemFont(ofSize: 12, weight: .medium),
    color: NSColor(white: 0.58, alpha: 1),
    tracking: 0.4
)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to render the DMG background\n".utf8))
    exit(1)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Failed to write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
