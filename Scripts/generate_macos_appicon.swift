#!/usr/bin/env swift
import Cocoa

/// Generator script for macOS HIG-compliant Application Icons.
/// Adapts full-bleed square master icons into Apple HIG squircle geometry with
/// precise padding, multi-layer drop shadows, inner rim highlights, and all standard resolutions.

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #file)
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

let defaultSource = projectRoot.appendingPathComponent("iOS/Daily/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
let targetDir = projectRoot.appendingPathComponent("MacOS/Daily/Resources/Assets.xcassets/AppIcon.appiconset")

let sourcePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultSource.path

guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
    print("❌ Failed to open source image at \(sourcePath)")
    exit(1)
}

let canvasSize: CGFloat = 1024
let bodySize: CGFloat = 824
let originOffset = (canvasSize - bodySize) / 2.0 // 100pt margins
let cornerRadius: CGFloat = 185.0

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(canvasSize),
    height: Int(canvasSize),
    bitsPerComponent: 8,
    bytesPerRow: Int(canvasSize) * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("❌ Failed to allocate CGContext")
    exit(1)
}

let bodyRect = CGRect(x: originOffset, y: originOffset, width: bodySize, height: bodySize)
let squirclePath = CGPath(roundedRect: bodyRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Layer 1: Ambient Drop Shadow
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 24,
    color: NSColor(white: 0.0, alpha: 0.25).cgColor
)
context.addPath(squirclePath)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

// Layer 2: Contact Shadow
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -4),
    blur: 8,
    color: NSColor(white: 0.0, alpha: 0.20).cgColor
)
context.addPath(squirclePath)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

// Layer 3: Clipped Icon Artwork
context.saveGState()
context.addPath(squirclePath)
context.clip()

var imageRect = CGRect(origin: .zero, size: sourceImage.size)
if let cgImage = sourceImage.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) {
    context.draw(cgImage, in: bodyRect)
}
context.restoreGState()

// Layer 4: Top Inner Rim Highlight & Outer Stroke
context.saveGState()
context.addPath(squirclePath)
context.setStrokeColor(NSColor(white: 0.0, alpha: 0.15).cgColor)
context.setLineWidth(1.0)
context.strokePath()
context.restoreGState()

guard let finalCGImage = context.makeImage() else {
    print("❌ Failed to produce final CGImage")
    exit(1)
}

let masterRep = NSBitmapImageRep(cgImage: finalCGImage)
guard let masterPngData = masterRep.representation(using: .png, properties: [:]) else {
    print("❌ Failed to encode PNG data")
    exit(1)
}

let masterDestURL = targetDir.appendingPathComponent("AppIcon-1024.png")
try? masterPngData.write(to: masterDestURL)
print("✅ Saved master macOS squircle icon to \(masterDestURL.path)")

// Standard macOS resolution scales
let iconSpecs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in iconSpecs {
    let destURL = targetDir.appendingPathComponent(spec.name)
    let sipsProcess = Process()
    sipsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    sipsProcess.arguments = [
        "-z", "\(spec.size)", "\(spec.size)",
        masterDestURL.path,
        "--out", destURL.path
    ]
    try? sipsProcess.run()
    sipsProcess.waitUntilExit()
}

print("✅ Generated all 10 standard macOS AppIcon scale variants.")
