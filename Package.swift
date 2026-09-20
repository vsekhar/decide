// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "decide",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "decide", targets: ["decide"]),
    ],
    dependencies: [
        // The library has no tags yet. A path keeps both checkouts in step.
        .package(path: "../DecisionModels"),
    ],
    targets: [
        .executableTarget(name: "decide", dependencies: ["DecideCore"]),
        .target(
            name: "DecideCore",
            dependencies: [
                .product(name: "DecisionModels", package: "DecisionModels"),
                .product(name: "DecisionModelsTypeSafe", package: "DecisionModels"),
                .product(name: "DecisionModelsOpenRouter", package: "DecisionModels"),
            ]
        ),
        .testTarget(
            name: "DecideCoreTests",
            dependencies: [
                "DecideCore",
                .product(name: "DecisionModelsTesting", package: "DecisionModels"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
