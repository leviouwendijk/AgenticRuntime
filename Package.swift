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
        .library(
            name: "AgenticRuntimeCommands",
            targets: [
                "AgenticRuntimeCommands",
            ]
        ),
        .executable(
            name: "artest",
            targets: [
                "AgenticRuntimeTestFlows",
            ]
        ),
        .executable(
            name: "aginttest",
            targets: [
                "AgenticRuntimeIntegrationTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/Agentic.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticExecution.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticWorkspace.git",
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
            url: "https://github.com/leviouwendijk/SchemaMacros.git",
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
            url: "https://github.com/leviouwendijk/AgenticTools.git",
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
            url: "https://github.com/leviouwendijk/AgenticInterfaces.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AgenticAdapters.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/AWSConnector.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Difference.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Arguments.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Clipboard.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Terminal.git",
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
                    name: "AgenticExecution",
                    package: "AgenticExecution"
                ),
                .product(
                    name: "AgenticWorkspace",
                    package: "AgenticWorkspace"
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
                    name: "AgenticTools",
                    package: "AgenticTools"
                ),
                .product(
                    name: "Primitives",
                    package: "Primitives"
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
                    name: "AgenticInterfaces",
                    package: "AgenticInterfaces"
                ),
            ]
        ),
        .target(
            name: "AgenticRuntimeCommands",
            dependencies: [
                "AgenticRuntime",
                .product(
                    name: "AgenticExecution",
                    package: "AgenticExecution"
                ),
                .product(
                    name: "AgenticWorkspace",
                    package: "AgenticWorkspace"
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
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticInterfaces",
                    package: "AgenticInterfaces"
                ),
                .product(
                    name: "Arguments",
                    package: "Arguments"
                ),
                .product(
                    name: "Clipboard",
                    package: "Clipboard"
                ),
                .product(
                    name: "Terminal",
                    package: "Terminal"
                ),
            ]
        ),
        .executableTarget(
            name: "AgenticRuntimeTestFlows",
            dependencies: [
                "AgenticRuntime",
                "AgenticRuntimeCommands",
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticInterfaces",
                    package: "AgenticInterfaces"
                ),
                .product(
                    name: "AgenticExecution",
                    package: "AgenticExecution"
                ),
                .product(
                    name: "AgenticWorkspace",
                    package: "AgenticWorkspace"
                ),
                .product(
                    name: "AgenticApple",
                    package: "AgenticAdapters"
                ),
                .product(
                    name: "Primitives",
                    package: "Primitives"
                ),
                .product(
                    name: "AgenticIO",
                    package: "AgenticIO"
                ),
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
        .executableTarget(
            name: "AgenticRuntimeIntegrationTestFlows",
            dependencies: [
                "AgenticRuntime",
                "AgenticRuntimeCommands",
                .product(
                    name: "Agentic",
                    package: "Agentic"
                ),
                .product(
                    name: "AgenticExecution",
                    package: "AgenticExecution"
                ),
                .product(
                    name: "AgenticWorkspace",
                    package: "AgenticWorkspace"
                ),
                .product(
                    name: "AgenticModels",
                    package: "AgenticModels"
                ),
                .product(
                    name: "AgenticIO",
                    package: "AgenticIO"
                ),
                .product(
                    name: "AgenticTools",
                    package: "AgenticTools"
                ),
                .product(
                    name: "AgenticInterfaces",
                    package: "AgenticInterfaces"
                ),
                .product(
                    name: "AgenticApple",
                    package: "AgenticAdapters"
                ),
                .product(
                    name: "AgenticAWS",
                    package: "AgenticAdapters"
                ),
                .product(
                    name: "AWSConnector",
                    package: "AWSConnector"
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
                    name: "SchemaMacros",
                    package: "SchemaMacros"
                ),
                .product(
                    name: "Difference",
                    package: "Difference"
                ),
                .product(
                    name: "Terminal",
                    package: "Terminal"
                ),
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
