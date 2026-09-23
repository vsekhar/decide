// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "decide",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "decide", targets: ["decide"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vsekhar/DecisionModels.git", from: "0.3.0"),
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
