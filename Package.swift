// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIVibe",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AIVibe", targets: ["AIVibe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.16.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.12.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.4"),
        // AppMetrica SDK официально не предоставлен через SPM.
        // Рекомендуется интегрировать через CocoaPods или бинарные фреймворки.
    ],
    targets: [
        .target(
            name: "AIVibe",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "AIVibe"
        ),
        .testTarget(
            name: "AIVibeTests",
            dependencies: ["AIVibe"],
            path: "AIVibeTests"
        ),
    ]
)
