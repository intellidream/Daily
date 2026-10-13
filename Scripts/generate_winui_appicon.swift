#!/usr/bin/env swift
import Cocoa

/// Generator script for WinUI 3 Windows Application Icons and MSIX assets.
/// Takes the master rendered macOS squircle icon and transparent artwork,
/// and produces pixel-perfect Windows assets (.ico with multiple mipmaps,
/// StoreLogo, Square150x150, Square44x44 all target sizes, Splash, Wide tiles).

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #file)
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

let masterSquircleURL = projectRoot.appendingPathComponent("MacOS/Daily/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let transparentArtworkURL = projectRoot.appendingPathComponent("iOS/Daily/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
let targetAssetsDir = projectRoot.appendingPathComponent("WinUI/Daily.WinUI/Assets")

guard let masterSquircle = NSImage(contentsOf: masterSquircleURL) else {
    print("❌ Failed to load master squircle at \(masterSquircleURL.path)")
    exit(1)
}

guard let transparentArtwork = NSImage(contentsOf: transparentArtworkURL) else {
    print("❌ Failed to load transparent artwork at \(transparentArtworkURL.path)")
    exit(1)
}

func resizeImage(image: NSImage, targetSize: NSSize) -> NSImage {
    let newImage = NSImage(size: targetSize)
    newImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    newImage.unlockFocus()
    return newImage
}

func savePng(image: NSImage, url: URL) {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("❌ Failed to create PNG for \(url.lastPathComponent)")
        return
    }
    do {
        try pngData.write(to: url)
        print("  ✅ Saved \(url.lastPathComponent) (\(Int(image.size.width))x\(Int(image.size.height)))")
    } catch {
        print("❌ Error writing \(url.lastPathComponent): \(error)")
    }
}

func createIco(images: [(size: Int, image: NSImage)], url: URL) {
    var pngDatas: [Data] = []
    for item in images {
        let resized = resizeImage(image: item.image, targetSize: NSSize(width: item.size, height: item.size))
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { continue }
        pngDatas.append(png)
    }

    let count = UInt16(pngDatas.count)
    var header = Data()
    var reserved: UInt16 = 0
    var type: UInt16 = 1 // 1 for ICO
    header.append(Data(bytes: &reserved, count: 2))
    header.append(Data(bytes: &type, count: 2))
    var countLe = count.littleEndian
    header.append(Data(bytes: &countLe, count: 2))

    var dirEntries = Data()
    var offset = UInt32(6 + 16 * pngDatas.count)

    for (index, png) in pngDatas.enumerated() {
        let size = images[index].size
        let w: UInt8 = size >= 256 ? 0 : UInt8(size)
        let h: UInt8 = size >= 256 ? 0 : UInt8(size)
        let colorCount: UInt8 = 0
        let res: UInt8 = 0
        let planes: UInt16 = 1
        let bpp: UInt16 = 32
        let byteSize = UInt32(png.count)

        dirEntries.append(w)
        dirEntries.append(h)
        dirEntries.append(colorCount)
        dirEntries.append(res)
        var planesLe = planes.littleEndian
        dirEntries.append(Data(bytes: &planesLe, count: 2))
        var bppLe = bpp.littleEndian
        dirEntries.append(Data(bytes: &bppLe, count: 2))
        var sizeLe = byteSize.littleEndian
        dirEntries.append(Data(bytes: &sizeLe, count: 4))
        var offsetLe = offset.littleEndian
        dirEntries.append(Data(bytes: &offsetLe, count: 4))

        offset += byteSize
    }

    var fullIco = Data()
    fullIco.append(header)
    fullIco.append(dirEntries)
    for png in pngDatas {
        fullIco.append(png)
    }

    do {
        try fullIco.write(to: url)
        print("  💎 Saved Multi-Resolution ICO: \(url.lastPathComponent)")
    } catch {
        print("❌ Failed to write ICO to \(url.path): \(error)")
    }
}

print("🚀 Generating WinUI Windows 11 App Icons & Assets from Orbit Master...")

// 1. Multi-resolution AppIcon.ico
let icoSizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
let icoImages = icoSizes.map { (size: $0, image: masterSquircle) }
createIco(images: icoImages, url: targetAssetsDir.appendingPathComponent("AppIcon.ico"))

// 2. Tray icons (using transparent artwork and squircle)
createIco(images: [16, 20, 24, 32, 48].map { (size: $0, image: masterSquircle) },
          url: targetAssetsDir.appendingPathComponent("TrayIconDarkTheme.ico"))
createIco(images: [16, 20, 24, 32, 48].map { (size: $0, image: masterSquircle) },
          url: targetAssetsDir.appendingPathComponent("TrayIconLightTheme.ico"))

// 3. Square150x150
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 150, height: 150)),
        url: targetAssetsDir.appendingPathComponent("Square150x150Logo.scale-100.png"))
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 300, height: 300)),
        url: targetAssetsDir.appendingPathComponent("Square150x150Logo.scale-200.png"))

// 4. Square44x44
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 44, height: 44)),
        url: targetAssetsDir.appendingPathComponent("Square44x44Logo.png"))
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 44, height: 44)),
        url: targetAssetsDir.appendingPathComponent("Square44x44Logo.scale-100.png"))
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 88, height: 88)),
        url: targetAssetsDir.appendingPathComponent("Square44x44Logo.scale-200.png"))

// Unplated Taskbar target sizes (use transparent artwork for clean taskbar integration)
let unplatedSizes = [16, 20, 24, 32, 48, 256]
for s in unplatedSizes {
    savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: s, height: s)),
            url: targetAssetsDir.appendingPathComponent("Square44x44Logo.targetsize-\(s)_altform-unplated.png"))
}
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 48, height: 48)),
        url: targetAssetsDir.appendingPathComponent("Square44x44Logo.targetsize-48_altform-lightunplated.png"))

// 5. StoreLogo (50x50)
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 50, height: 50)),
        url: targetAssetsDir.appendingPathComponent("StoreLogo.png"))

// 6. Wide310x150Logo (620x300 for scale-200)
let wideImage = NSImage(size: NSSize(width: 620, height: 300))
wideImage.lockFocus()
// Background: #0B1121 dark cosmic gradient
if let context = NSGraphicsContext.current?.cgContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.043, green: 0.067, blue: 0.129, alpha: 1.0),
        CGColor(red: 0.020, green: 0.035, blue: 0.075, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 300), end: CGPoint(x: 0, y: 0), options: [])
    }
}
let iconWideSize: CGFloat = 200
let iconWideX: CGFloat = (620 - iconWideSize) / 2
let iconWideY: CGFloat = (300 - iconWideSize) / 2
masterSquircle.draw(in: NSRect(x: iconWideX, y: iconWideY, width: iconWideSize, height: iconWideSize))
wideImage.unlockFocus()
savePng(image: wideImage, url: targetAssetsDir.appendingPathComponent("Wide310x150Logo.scale-200.png"))

// 7. SplashScreen (1240x600 for scale-200)
let splashImage = NSImage(size: NSSize(width: 1240, height: 600))
splashImage.lockFocus()
if let context = NSGraphicsContext.current?.cgContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.043, green: 0.067, blue: 0.129, alpha: 1.0),
        CGColor(red: 0.012, green: 0.024, blue: 0.047, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 600), end: CGPoint(x: 0, y: 0), options: [])
    }
}
let splashIconSize: CGFloat = 260
let splashIconX: CGFloat = (1240 - splashIconSize) / 2
let splashIconY: CGFloat = (600 - splashIconSize) / 2
masterSquircle.draw(in: NSRect(x: splashIconX, y: splashIconY, width: splashIconSize, height: splashIconSize))
splashImage.unlockFocus()
savePng(image: splashImage, url: targetAssetsDir.appendingPathComponent("SplashScreen.scale-200.png"))

// 8. In-App Orbit Icon (OrbitIcon.png at 256x256 and 512x512)
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 256, height: 256)),
        url: targetAssetsDir.appendingPathComponent("OrbitIcon-256.png"))
savePng(image: resizeImage(image: masterSquircle, targetSize: NSSize(width: 512, height: 512)),
        url: targetAssetsDir.appendingPathComponent("OrbitIcon-512.png"))

print("🎉 WinUI Orbit Icon Generation Completed!")
