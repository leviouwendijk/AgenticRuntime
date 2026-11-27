// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "AgenticRuntime",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "AgenticRuntime",
            targets: [
                "AgenticRuntime",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-agentic/Agentic.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Surface.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Workspace.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-langs/Tokens.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Primitives.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Difference.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Schema.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Macros.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Path.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Milieu.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-agentic/AgenticIO.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/IO.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Readers.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Writers.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/lco-langs/Frame.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Version.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Selection.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-lco/Errors.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "AgenticRuntime",
            dependencies: [
                .product(
                    name: "Surface",
                    package: "Surface"
                ),
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "Version",
                    package: "Version"
                ),
                .product(
                    name: "Writers",
                    package: "Writers"
                ),
                .product(
                    name: "AgenticStandard",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticContextWindow",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticConfiguration",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticContext",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticSensitivity",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticSessions",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticIntents",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticHarness",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticModels",
                    package: "Agentic"
                ),
                .product(
                    name: "Workspace",
                    package: "Workspace"
                ),
                .product(
                    name: "Tokens",
                    package: "Tokens"
                ),
                .product(
                    name: "AgenticIO",
                    package: "AgenticIO"
                ),
                .product(
                    name: "IO",
                    package: "IO"
                ),
                .product(
                    name: "Readers",
                    package: "Readers"
                ),
                .product(
                    name: "Frame",
                    package: "Frame"
                ),
                .product(
                    name: "Primitives",
                    package: "Primitives"
                ),
                .product(
                    name: "Schema",
                    package: "Schema"
                ),
                .product(
                    name: "Macros",
                    package: "Macros"
                ),
                .product(
                    name: "Path",
                    package: "Path"
                ),
                .product(
                    name: "PathParsing",
                    package: "Path"
                ),
                .product(
                    name: "Selection",
                    package: "Selection"
                ),
                .product(
                    name: "SelectionParsing",
                    package: "Selection"
                ),
                .product(
                    name: "Milieu",
                    package: "Milieu"
                ),
                .product(
                    name: "Errors",
                    package: "Errors"
                ),
                .product(
                    name: "Difference",
                    package: "Difference"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        settings.append(
            .unsafeFlags(
                [
                    "-continue-building-after-errors"
                ]
            )
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
