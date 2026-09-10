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
            name: "DailyCore",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ]
        ),
        .testTarget(
            name: "DailyCoreTests",
            dependencies: ["DailyCore"]
        ),
    ]
)
