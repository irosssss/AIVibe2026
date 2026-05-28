// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIVibe",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "AIVibe", targets: ["AIVibe"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.16.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.12.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.4")
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
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "AIVibe",
            swiftSettings: [
                // Swift 6.2 approachable concurrency — включаем по одной фиче,
                // чтобы видеть какая создаёт какие warning'и.
                // ⚠️ defaultIsolation(MainActor.self) НЕ включаем — ломает
                // ReducerOf<Self> в TCA 1.25 (см. PointFree discussion #3714).
                //
                // InferSendableFromCaptures, GlobalActorIsolatedTypesUsability,
                // DisableOutwardActorInference — уже включены по умолчанию в Swift 6.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "AIVibeTests",
            dependencies: ["AIVibe"],
            path: "AIVibeTests"
        )
    ]
)
