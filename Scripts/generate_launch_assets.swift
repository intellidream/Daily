import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let fileManager = FileManager.default
let projectDir = URL(fileURLWithPath: "/Users/mihai/Source/Daily")

let masterIconPath = projectDir.appendingPathComponent("Resources/AppIcon/appicon_orbit_1024.png")

guard fileManager.fileExists(atPath: masterIconPath.path) else {
    print("❌ Master icon not found at: \(masterIconPath.path)")
    exit(1)
}

print("🌟 Loading Master Orbit Icon from: \(masterIconPath.path)")
guard let imageSource = CGImageSourceCreateWithURL(masterIconPath as CFURL, nil),
      let masterCGImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    print("❌ Failed to decode master CGImage")
    exit(1)
}

// Crop to the actual 828x828 squircle (removing the 98px black padding around it)
let cropRect = CGRect(x: 98, y: 98, width: 828, height: 828)
guard let croppedSquircle = masterCGImage.cropping(to: cropRect) else {
    print("❌ Failed to crop master CGImage")
    exit(1)
}
print("✅ Cropped to squircle: \(croppedSquircle.width)x\(croppedSquircle.height)")

func renderMaskedSquircle(source: CGImage, targetSize: Int) -> CGImage? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: targetSize,
        height: targetSize,
        bitsPerComponent: 8,
        bytesPerRow: targetSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    
    context.interpolationQuality = .high
    
    // Create squircle / rounded rect clipping path
    let rect = CGRect(x: 0, y: 0, width: targetSize, height: targetSize)
    let cornerRadius = CGFloat(targetSize) * 0.2237 // Apple iOS squircle ratio
    let clipPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    context.saveGState()
    context.addPath(clipPath)
    context.clip()
    
    // Draw cropped icon
    context.draw(source, in: rect)
    
    // Draw subtle specular border highlight
    context.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.22))
    context.setLineWidth(max(1.0, CGFloat(targetSize) / 120.0))
    context.addPath(clipPath)
    context.strokePath()
    
    context.restoreGState()
    
    return context.makeImage()
}

func exportPNG(image: CGImage, destinationURL: URL) throws {
    let parentDir = destinationURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
    
    guard let dest = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "LaunchGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ImageDestination"])
    }
    
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "LaunchGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG"])
    }
}

// 1. Generate LaunchLogo.imageset
let launchLogoDir = projectDir.appendingPathComponent("iOS/Daily/Resources/Assets.xcassets/LaunchLogo.imageset")
try fileManager.createDirectory(at: launchLogoDir, withIntermediateDirectories: true)

let sizes: [(scale: String, px: Int)] = [
    ("1x", 120),
    ("2x", 240),
    ("3x", 360)
]

for item in sizes {
    guard let rendered = renderMaskedSquircle(source: croppedSquircle, targetSize: item.px) else {
        print("❌ Failed to render squircle for \(item.scale)")
        continue
    }
    let filename = "LaunchLogo@\(item.scale).png"
    let fileURL = launchLogoDir.appendingPathComponent(filename)
    try exportPNG(image: rendered, destinationURL: fileURL)
    print("  -> Generated \(filename) (\(item.px)x\(item.px), masked squircle with transparent corners)")
}

let launchLogoJSON: [String: Any] = [
    "images": [
        [
            "filename": "LaunchLogo@1x.png",
            "idiom": "universal",
            "scale": "1x"
        ],
        [
            "filename": "LaunchLogo@2x.png",
            "idiom": "universal",
            "scale": "2x"
        ],
        [
            "filename": "LaunchLogo@3x.png",
            "idiom": "universal",
            "scale": "3x"
        ]
    ],
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

let logoJsonData = try JSONSerialization.data(withJSONObject: launchLogoJSON, options: [.prettyPrinted, .sortedKeys])
try logoJsonData.write(to: launchLogoDir.appendingPathComponent("Contents.json"))
print("✅ LaunchLogo.imageset updated successfully")

// Also update AppLogo.imageset
let appLogoDir = projectDir.appendingPathComponent("iOS/Daily/Resources/Assets.xcassets/AppLogo.imageset")
try fileManager.createDirectory(at: appLogoDir, withIntermediateDirectories: true)
for item in sizes {
    guard let rendered = renderMaskedSquircle(source: croppedSquircle, targetSize: item.px) else { continue }
    let filename = "AppLogo@\(item.scale).png"
    let fileURL = appLogoDir.appendingPathComponent(filename)
    try exportPNG(image: rendered, destinationURL: fileURL)
}
let appLogoJSON: [String: Any] = [
    "images": [
        ["filename": "AppLogo@1x.png", "idiom": "universal", "scale": "1x"],
        ["filename": "AppLogo@2x.png", "idiom": "universal", "scale": "2x"],
        ["filename": "AppLogo@3x.png", "idiom": "universal", "scale": "3x"]
    ],
    "info": ["author": "xcode", "version": 1]
]
let appLogoJsonData = try JSONSerialization.data(withJSONObject: appLogoJSON, options: [.prettyPrinted, .sortedKeys])
try appLogoJsonData.write(to: appLogoDir.appendingPathComponent("Contents.json"))
print("✅ AppLogo.imageset updated successfully")

print("🎉 SQUIRCLE MASKED LAUNCH ASSETS GENERATED!")
