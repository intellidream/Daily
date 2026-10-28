// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "DailyCore",
            targets: ["DailyCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.5.1")
    ],
    targets: [
        .target(
            name: "CAstronomy",
            dependencies: [],
            path: "Sources/CAstronomy",
            publicHeadersPath: "include"
        ),
        .target(
            name: "DailyCore",
            dependencies: [
                "CAstronomy",
                .product(name: "Supabase", package: "supabase-swift")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DailyCoreTests",
            dependencies: ["DailyCore"]
        ),
    ]
)
