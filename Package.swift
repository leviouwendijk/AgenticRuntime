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
        .executable(
            name: "t_ar_main",
            targets: [
                "AgenticRuntimeTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/Agentic.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Workspace.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticModels.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticUsage.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Primitives.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Schema.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Macros.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Path.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Milieu.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticIO.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Concatenation.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Selection.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Errors.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "AgenticRuntime",
            dependencies: [
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticStandard",
                    package: "Agentic"
                ),
                .product(
                    name: "Workspace",
                    package: "Workspace"
                ),
                .product(
                    name: "AgenticModels",
                    package: "AgenticModels"
                ),
                .product(
                    name: "AgenticUsage",
                    package: "AgenticUsage"
                ),
                .product(
                    name: "AgenticIO",
                    package: "AgenticIO"
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
                    name: "Concatenation",
                    package: "Concatenation"
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
            ]
        ),
        .executableTarget(
            name: "AgenticRuntimeTestFlows",
            dependencies: [
                "AgenticRuntime",
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticStandard",
                    package: "Agentic"
                ),
                .product(
                    name: "Workspace",
                    package: "Workspace"
                ),
                .product(
                    name: "AgenticIO",
                    package: "AgenticIO"
                ),
                .product(
                    name: "Path",
                    package: "Path"
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
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ],
            path: "Testing/AgenticRuntimeTestFlows"
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
