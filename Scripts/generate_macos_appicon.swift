#!/usr/bin/env swift
import Cocoa
import SwiftUI

/// Generator script for macOS HIG-compliant Application Icons.
/// Renders authentic continuous super-ellipse squircles with calibrated visual scale,
/// multi-layer drop shadows, top specular rim highlights, and all standard macOS resolutions.

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
let cornerRadius: CGFloat = 185.0

// Scale the source artwork so that the atom graphic (which has inherent 130px padding in the iOS asset)
// expands from ~615px to ~740px within the 824px squircle body, matching the optical visual weight
// of native macOS icons like Notes, Spotify, and Calendar.
let artworkSize: CGFloat = 985.0

MainActor.assumeIsolated {
    let iconView = ZStack {
        Color.clear
        
        ZStack {
            // Background: deep cosmic obsidian gradient
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.09, blue: 0.12),
                            Color(red: 0.02, green: 0.02, blue: 0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Scaled atom artwork, clipped to the continuous squircle
            Image(nsImage: sourceImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: artworkSize, height: artworkSize)
            
            // Top specular inner highlight & outer edge border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.25), location: 0.0),
                            .init(color: Color.white.opacity(0.12), location: 0.2),
                            .init(color: Color.white.opacity(0.04), location: 0.8),
                            .init(color: Color.black.opacity(0.30), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        }
        .frame(width: bodySize, height: bodySize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Layer 1: Ambient Drop Shadow
        .shadow(color: Color.black.opacity(0.30), radius: 24, x: 0, y: 14)
        // Layer 2: Contact Shelf Shadow
        .shadow(color: Color.black.opacity(0.25), radius: 7, x: 0, y: 4)
    }
    .frame(width: canvasSize, height: canvasSize)

    let renderer = ImageRenderer(content: iconView)
    renderer.scale = 1.0
    guard let cgImage = renderer.cgImage else {
        print("❌ Failed to render master cgImage via ImageRenderer")
        exit(1)
    }

    let masterRep = NSBitmapImageRep(cgImage: cgImage)
    guard let masterPngData = masterRep.representation(using: .png, properties: [:]) else {
        print("❌ Failed to encode PNG data")
        exit(1)
    }

    let masterDestURL = targetDir.appendingPathComponent("icon_512x512@2x.png")
    do {
        try masterPngData.write(to: masterDestURL)
        print("✅ Saved master macOS squircle icon to \(masterDestURL.path)")
    } catch {
        print("❌ Failed to write master icon: \(error)")
        exit(1)
    }

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
        ("icon_512x512.png", 512)
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
}
