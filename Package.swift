// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AgenticRuntime",
    products: [
        .library(
            name: "AgenticRuntime",
            targets: ["AgenticRuntime"]
        ),
    ],
    targets: [
        .target(
            name: "AgenticRuntime"
        ),
    ],
    swiftLanguageModes: [.v6]
)
