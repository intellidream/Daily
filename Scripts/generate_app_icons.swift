import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - App Icon Generation Script for Daily (iOS, macOS, Windows)

let fileManager = FileManager.default
let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

let masterIconPath = currentDir.appendingPathComponent("WatchOS/DailyWatch/DailyWatch Watch App/Assets.xcassets/AppIcon.appiconset/appicon.png")

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

print("✅ Master Image loaded: \(masterCGImage.width)x\(masterCGImage.height)")

// MARK: - Resampling & Color Conversion Helpers

func resizeImage(master: CGImage, targetWidth: Int, targetHeight: Int) -> CGImage? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: targetWidth * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    
    context.interpolationQuality = .high
    context.draw(master, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage()
}

/// Exports a CGImage as a 24-bit Truecolor RGB PNG (NO ALPHA CHANNEL).
/// Guaranteed to satisfy Apple App Store ITMS-90717 compliance.
func exportRGB24PNG(image: CGImage, destinationURL: URL) throws {
    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    
    // Step 1: Render into 32-bit buffer
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
    }
    
    // Fill with black background in case of any edge transparency
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    guard let pixelData = context.data else {
        throw NSError(domain: "IconGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain context data"])
    }
    
    let ptr = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var rgb24Data = [UInt8](repeating: 0, count: width * height * 3)
    
    for i in 0..<(width * height) {
        rgb24Data[i * 3 + 0] = ptr[i * 4 + 0] // Red
        rgb24Data[i * 3 + 1] = ptr[i * 4 + 1] // Green
        rgb24Data[i * 3 + 2] = ptr[i * 4 + 2] // Blue
    }
    
    // Step 2: Create 24-bit CGImage
    let provider = CGDataProvider(data: NSData(bytes: &rgb24Data, length: rgb24Data.count))!
    let rgb24Image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 24,
        bytesPerRow: width * 3,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )!
    
    // Step 3: Write PNG using ImageIO
    let parentDir = destinationURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
    
    guard let dest = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconGen", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create ImageDestination"])
    }
    
    CGImageDestinationAddImage(dest, rgb24Image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "IconGen", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG destination"])
    }
}

/// Exports standard 32-bit RGBA PNG (for macOS and Windows)
func exportRGBA32PNG(image: CGImage, destinationURL: URL) throws {
    let parentDir = destinationURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
    
    guard let dest = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconGen", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create ImageDestination"])
    }
    
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "IconGen", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG destination"])
    }
}

// MARK: - 1. iOS Asset Catalog Generation

print("\n📱 [1/4] Generating iOS AppIcon.appiconset...")

let iosAppIconDir = currentDir.appendingPathComponent("iOS/Daily/Resources/Assets.xcassets/AppIcon.appiconset")
try fileManager.createDirectory(at: iosAppIconDir, withIntermediateDirectories: true)

struct IOSIconSpec {
    let filename: String
    let size: Int
    let pointSize: String
    let scale: String
    let idiom: String
    let role: String?
}

let iosSpecs: [IOSIconSpec] = [
    // Universal App Store Icon (1024x1024) - NO ALPHA
    IOSIconSpec(filename: "AppIcon-1024.png", size: 1024, pointSize: "1024x1024", scale: "1x", idiom: "universal", role: nil),
    
    // iPhone Notification
    IOSIconSpec(filename: "AppIcon-20x20@2x.png", size: 40, pointSize: "20x20", scale: "2x", idiom: "iphone", role: "notificationCenter"),
    IOSIconSpec(filename: "AppIcon-20x20@3x.png", size: 60, pointSize: "20x20", scale: "3x", idiom: "iphone", role: "notificationCenter"),
    
    // iPhone Settings
    IOSIconSpec(filename: "AppIcon-29x29@2x.png", size: 58, pointSize: "29x29", scale: "2x", idiom: "iphone", role: "companionSettings"),
    IOSIconSpec(filename: "AppIcon-29x29@3x.png", size: 87, pointSize: "29x29", scale: "3x", idiom: "iphone", role: "companionSettings"),
    
    // iPhone Spotlight
    IOSIconSpec(filename: "AppIcon-40x40@2x.png", size: 80, pointSize: "40x40", scale: "2x", idiom: "iphone", role: "spotlight"),
    IOSIconSpec(filename: "AppIcon-40x40@3x.png", size: 120, pointSize: "40x40", scale: "3x", idiom: "iphone", role: "spotlight"),
    
    // iPhone App (Home Screen)
    IOSIconSpec(filename: "AppIcon-60x60@2x.png", size: 120, pointSize: "60x60", scale: "2x", idiom: "iphone", role: "app"),
    IOSIconSpec(filename: "AppIcon-60x60@3x.png", size: 180, pointSize: "60x60", scale: "3x", idiom: "iphone", role: "app"),
    
    // iPad App
    IOSIconSpec(filename: "AppIcon-76x76@1x.png", size: 76, pointSize: "76x76", scale: "1x", idiom: "ipad", role: "app"),
    IOSIconSpec(filename: "AppIcon-76x76@2x.png", size: 152, pointSize: "76x76", scale: "2x", idiom: "ipad", role: "app"),
    
    // iPad Pro
    IOSIconSpec(filename: "AppIcon-83.5x83.5@2x.png", size: 167, pointSize: "83.5x83.5", scale: "2x", idiom: "ipad", role: "app")
]

for spec in iosSpecs {
    guard let resized = resizeImage(master: masterCGImage, targetWidth: spec.size, targetHeight: spec.size) else {
        print("❌ Failed to resize for \(spec.filename)")
        continue
    }
    let targetURL = iosAppIconDir.appendingPathComponent(spec.filename)
    try exportRGB24PNG(image: resized, destinationURL: targetURL)
    print("  -> Generated \(spec.filename) (\(spec.size)x\(spec.size) px, 24-bit RGB)")
}

// Generate Contents.json for iOS AppIcon.appiconset
var jsonImages: [[String: String]] = []
for spec in iosSpecs {
    var entry: [String: String] = [
        "filename": spec.filename,
        "idiom": spec.idiom,
        "scale": spec.scale,
        "size": spec.pointSize
    ]
    if spec.idiom == "universal" {
        entry["platform"] = "ios"
    }
    jsonImages.append(entry)
}

let contentsJSON: [String: Any] = [
    "images": jsonImages,
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

let contentsData = try JSONSerialization.data(withJSONObject: contentsJSON, options: [.prettyPrinted, .sortedKeys])
try contentsData.write(to: iosAppIconDir.appendingPathComponent("Contents.json"))
print("  ✅ Updated iOS Contents.json with \(jsonImages.count) variants")

// MARK: - 2. macOS Native .icns & .iconset Generation

print("\n🖥️  [2/4] Generating macOS Daily.iconset & Daily.icns...")

let macIconsetDir = currentDir.appendingPathComponent("Resources/AppIcon/Daily.iconset")
try fileManager.createDirectory(at: macIconsetDir, withIntermediateDirectories: true)

struct MacIconSpec {
    let filename: String
    let size: Int
}

let macSpecs: [MacIconSpec] = [
    MacIconSpec(filename: "icon_16x16.png", size: 16),
    MacIconSpec(filename: "icon_16x16@2x.png", size: 32),
    MacIconSpec(filename: "icon_32x32.png", size: 32),
    MacIconSpec(filename: "icon_32x32@2x.png", size: 64),
    MacIconSpec(filename: "icon_128x128.png", size: 128),
    MacIconSpec(filename: "icon_128x128@2x.png", size: 256),
    MacIconSpec(filename: "icon_256x256.png", size: 256),
    MacIconSpec(filename: "icon_256x256@2x.png", size: 512),
    MacIconSpec(filename: "icon_512x512.png", size: 512),
    MacIconSpec(filename: "icon_512x512@2x.png", size: 1024)
]

for spec in macSpecs {
    guard let resized = resizeImage(master: masterCGImage, targetWidth: spec.size, targetHeight: spec.size) else {
        print("❌ Failed to resize for \(spec.filename)")
        continue
    }
    let targetURL = macIconsetDir.appendingPathComponent(spec.filename)
    try exportRGBA32PNG(image: resized, destinationURL: targetURL)
    print("  -> Generated \(spec.filename) (\(spec.size)x\(spec.size) px)")
}

let icnsOutputURL = currentDir.appendingPathComponent("Resources/AppIcon/Daily.icns")
let iconutilProcess = Process()
iconutilProcess.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilProcess.arguments = ["-c", "icns", macIconsetDir.path, "-o", icnsOutputURL.path]

do {
    try iconutilProcess.run()
    iconutilProcess.waitUntilExit()
    if iconutilProcess.terminationStatus == 0 {
        print("  ✅ Compiled macOS Daily.icns successfully! (\(icnsOutputURL.path))")
    } else {
        print("  ⚠️ iconutil exited with status \(iconutilProcess.terminationStatus)")
    }
} catch {
    print("  ❌ Failed to run iconutil: \(error.localizedDescription)")
}

// MARK: - 3. Windows Multi-Resolution .ico & WinUI Tiles

print("\n🪟 [3/4] Generating Windows Multi-Resolution Daily.ico & WinUI 3 Assets...")

let windowsSizes = [16, 24, 32, 48, 64, 128, 256]
var pngBlobs: [(size: Int, data: Data)] = []

for s in windowsSizes {
    guard let resized = resizeImage(master: masterCGImage, targetWidth: s, targetHeight: s) else { continue }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, resized, nil)
    CGImageDestinationFinalize(dest)
    pngBlobs.append((size: s, data: data as Data))
}

// Write .ico binary container
var icoData = Data()
// Header: 6 bytes
var reserved: UInt16 = 0
var type: UInt16 = 1 // 1 for ICO
var count: UInt16 = UInt16(pngBlobs.count)

icoData.append(contentsOf: withUnsafeBytes(of: &reserved) { Array($0) })
icoData.append(contentsOf: withUnsafeBytes(of: &type) { Array($0) })
icoData.append(contentsOf: withUnsafeBytes(of: &count) { Array($0) })

var currentOffset: UInt32 = UInt32(6 + 16 * pngBlobs.count)

for blob in pngBlobs {
    let w: UInt8 = blob.size == 256 ? 0 : UInt8(blob.size)
    let h: UInt8 = blob.size == 256 ? 0 : UInt8(blob.size)
    var colorCount: UInt8 = 0
    var bReserved: UInt8 = 0
    var planes: UInt16 = 1
    var bitCount: UInt16 = 32
    var bytesInRes: UInt32 = UInt32(blob.data.count)
    var offset: UInt32 = currentOffset
    
    icoData.append(w)
    icoData.append(h)
    icoData.append(colorCount)
    icoData.append(bReserved)
    icoData.append(contentsOf: withUnsafeBytes(of: &planes) { Array($0) })
    icoData.append(contentsOf: withUnsafeBytes(of: &bitCount) { Array($0) })
    icoData.append(contentsOf: withUnsafeBytes(of: &bytesInRes) { Array($0) })
    icoData.append(contentsOf: withUnsafeBytes(of: &offset) { Array($0) })
    
    currentOffset += bytesInRes
}

for blob in pngBlobs {
    icoData.append(blob.data)
}

let icoURL = currentDir.appendingPathComponent("Resources/AppIcon/Daily.ico")
try icoData.write(to: icoURL)
print("  ✅ Compiled Windows Daily.ico (\(windowsSizes.map { "\($0)" }.joined(separator: ", ")) px) -> \(icoURL.path)")

// WinUI 3 Specific Tiles
let winTilesDir = currentDir.appendingPathComponent("Resources/AppIcon/Windows")
let winTiles: [(name: String, size: Int)] = [
    ("Square44x44Logo.png", 44),
    ("Square44x44Logo@2x.png", 88),
    ("Square150x150Logo.png", 150),
    ("Square150x150Logo@2x.png", 300),
    ("StoreLogo.png", 50)
]

for tile in winTiles {
    guard let resized = resizeImage(master: masterCGImage, targetWidth: tile.size, targetHeight: tile.size) else { continue }
    let tileURL = winTilesDir.appendingPathComponent(tile.name)
    try exportRGBA32PNG(image: resized, destinationURL: tileURL)
    print("  -> Generated WinUI Tile \(tile.name) (\(tile.size)x\(tile.size) px)")
}

// MARK: - 4. Master High-Resolution Reference Icon

print("\n🎨 [4/4] Writing High-Resolution Master PNG...")
let masterExportURL = currentDir.appendingPathComponent("Resources/AppIcon/appicon_orbit_1024.png")
try exportRGBA32PNG(image: masterCGImage, destinationURL: masterExportURL)
print("  ✅ Master asset saved to: \(masterExportURL.path)")

print("\n🎉 ALL MULTI-PLATFORM ICONS GENERATED SUCCESSFULLY!\n")
