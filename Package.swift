// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "decide",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "decide", targets: ["decide"]),
    ],
    dependencies: [
        // To build against the working copy in ../DecisionModels instead:
        //   swift package edit DecisionModels --path ../DecisionModels
        // and `swift package unedit DecisionModels` to go back to the tag.
        .package(url: "https://github.com/vsekhar/DecisionModels.git", from: "0.1.0"),
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
