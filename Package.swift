// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "photo-crawler",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "Packages/PhotoCrawlerCore")
    ],
    targets: [
        .executableTarget(
            name: "photo-crawler",
            dependencies: [
                .product(name: "PhotoCrawlerCore", package: "PhotoCrawlerCore")
            ],
            path: "Sources/CLI"
        )
    ]
)
