// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoCrawlerCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "PhotoCrawlerCore",
            targets: ["PhotoCrawlerCore"]
        )
    ],
    targets: [
        .target(
            name: "PhotoCrawlerCore",
            dependencies: []
        ),
        .testTarget(
            name: "PhotoCrawlerCoreTests",
            dependencies: ["PhotoCrawlerCore"]
        )
    ]
)
