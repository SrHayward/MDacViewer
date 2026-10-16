// Generates Resources/AppIcon.icns — a rounded "M↓" tile in the app's colours.
// Run via: swift Scripts/make-icon.swift

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetDir = root.appendingPathComponent("build/AppIcon.iconset")
let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetDir)
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(
    at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)

func drawIcon(in rect: CGRect) {
    let size = rect.width

    // Rounded tile, macOS-style inset.
    let inset = size * 0.085
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = tile.width * 0.225
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.26, alpha: 1.0),
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1.0),
    ])!
    gradient.draw(in: tilePath, angle: -90)

    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    tilePath.lineWidth = max(1, size * 0.005)
    tilePath.stroke()

    // "M↓" mark.
    let fontSize = size * 0.46
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let text = "M↓" as NSString
    let textSize = text.size(withAttributes: attributes)
    let origin = CGPoint(
        x: tile.midX - textSize.width / 2,
        y: tile.midY - textSize.height / 2 + size * 0.02)
    text.draw(at: origin, withAttributes: attributes)
}

func pngData(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(in: CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    try pngData(pixels: variant.pixels)
        .write(to: iconsetDir.appendingPathComponent(variant.name))
}

// Preview copy so the icon can be eyeballed without opening the .icns.
try pngData(pixels: 1024).write(to: root.appendingPathComponent("build/icon-preview.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("Wrote \(icnsURL.path)")
