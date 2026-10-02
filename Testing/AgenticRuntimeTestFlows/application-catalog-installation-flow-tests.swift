import Agentic
import AgenticRuntime
import Macros
import Schema
import TestFlows
import Workspace

@Domain
enum InstallationCatalogDomainFixture {}

extension InstallationCatalogDomainFixture.Tools {
    @Tool("fixture.installation_catalog_bound")
    struct Bound:
        Tool,
        DomainInstallable
    {
        @JSONSchema
        struct Input: HashableSource {
            init() {}
        }

        @JSONSchema
        struct Output: HashableResult {
            let value: String

            init(
                value: String
            ) {
                self.value = value
            }
        }

        static let purpose =
            "Proves a Domain catalog declaration can bind to a separately installed executable Tool."

        static let risk: ActionRisk = .observe

        init() {}

        static func install(
            into sink: any DomainInstallation.Sink
        ) {
            sink.install(
                Self()
            )
        }

        func call(
            _ input: Input,
            workspace _: WorkspaceContext?
        ) async throws -> Output {
            _ = input

            return Output(
                value: "bound"
            )
        }
    }

    @Tool("fixture.installation_catalog_semantic_only")
    struct SemanticOnly: Tool {
        @JSONSchema
        struct Input: HashableSource {
            init() {}
        }

        @JSONSchema
        struct Output: HashableResult {
            let value: String

            init(
                value: String
            ) {
                self.value = value
            }
        }

        static let purpose =
            "Proves semantic catalog presence does not fabricate executable Tool availability."

        static let risk: ActionRisk = .observe

        init() {}

        func call(
            _ input: Input,
            workspace _: WorkspaceContext?
        ) async throws -> Output {
            _ = input

            return Output(
                value: "semantic-only"
            )
        }
    }
}

extension InstallationCatalogDomainFixture.Agents {
    @Agent
    enum Worker {
        @JSONSchema
        struct Input: HashableSource {
            init() {}
        }

        @JSONSchema
        struct Output: HashableResult {
            let value: String

            init(
                value: String
            ) {
                self.value = value
            }
        }

        static let purpose =
            "Proves Agent definitions contained in an installed Domain catalog remain available to Runtime application composition."
    }
}

@Tool("fixture.installation_catalog_unscoped")
struct InstallationCatalogUnscopedToolFixture: Tool {
    @JSONSchema
    struct Input: HashableSource {
        init() {}
    }

    @JSONSchema
    struct Output: HashableResult {
        let value: String

        init(
            value: String
        ) {
            self.value = value
        }
    }

    static let purpose =
        "Proves a top-level unscoped Tool can still be installed explicitly without leaking into a Domain catalog."

    static let risk: ActionRisk = .observe

    init() {}

    func call(
        _ input: Input,
        workspace _: WorkspaceContext?
    ) async throws -> Output {
        _ = input

        return Output(
            value: "unscoped"
        )
    }
}

extension AgenticProgramRuntimeFlowTesting {
    static func runApplicationCatalogInstallation()
        async throws
        -> [TestDiagnostic]
    {
        let catalog =
            InstallationCatalogDomainFixture.catalog

        let boundIdentifier =
            InstallationCatalogDomainFixture
            .Tools
            .Bound
            .definition
            .identifier

        let semanticOnlyIdentifier =
            InstallationCatalogDomainFixture
            .Tools
            .SemanticOnly
            .definition
            .identifier

        let agentIdentifier =
            InstallationCatalogDomainFixture
            .Agents
            .Worker
            .definition
            .identifier

        let unscopedIdentifier =
            InstallationCatalogUnscopedToolFixture
            .definition
            .identifier

        let domainToolIdentifiers = Set(
            catalog.tools.map(\.identifier)
        )

        let unscopedToolIdentifiers = Set(
            Catalog.unscoped.tools.map(\.identifier)
        )

        try Expect.equal(
            catalog.domains,
            [
                InstallationCatalogDomainFixture.definition,
            ],
            "Derived Domain catalog retains its Domain definition"
        )
        try Expect.equal(
            domainToolIdentifiers.contains(
                boundIdentifier
            ),
            true,
            "Derived Domain catalog retains a Tool that will receive a separate executable binding"
        )
        try Expect.equal(
            domainToolIdentifiers.contains(
                semanticOnlyIdentifier
            ),
            true,
            "Derived Domain catalog retains semantic Tool declarations even without executable installation"
        )
        try Expect.equal(
            catalog.agents.contains(
                where: { definition in
                    definition.identifier == agentIdentifier
                }
            ),
            true,
            "Derived Domain catalog retains Agent definitions"
        )
        try Expect.equal(
            domainToolIdentifiers.contains(
                unscopedIdentifier
            ),
            false,
            "Derived Domain catalog excludes top-level unscoped Tool declarations"
        )
        try Expect.equal(
            unscopedToolIdentifiers.contains(
                unscopedIdentifier
            ),
            true,
            "Catalog.unscoped retains the top-level Tool declaration"
        )

        let application = Agentic.application(
            "fixture.catalog_installation"
        ) {
            install(
                catalog
            )
            install(
                InstallationCatalogDomainFixture
                    .Tools
                    .Bound()
            )
            install(
                InstallationCatalogUnscopedToolFixture()
            )
        }

        try Expect.equal(
            application.catalog,
            catalog,
            "install(Catalog) preserves the full semantic catalog on the application"
        )
        try Expect.equal(
            application.catalog.agents.contains(
                where: { definition in
                    definition.identifier == agentIdentifier
                }
            ),
            true,
            "Agent definitions remain present in the installed semantic Catalog"
        )
        try Expect.equal(
            application.agentDefinitions.contains(
                where: { definition in
                    definition.identifier == agentIdentifier
                }
            ),
            false,
            "Semantic Catalog installation does not fabricate an explicit Agent installation"
        )
        try Expect.equal(
            application.toolRegistrations.count,
            2,
            "Catalog installation does not fabricate Tool registrations while granular Tools remain installable"
        )

        let runtime = try await AgenticRuntime(
            application: application
        )

        let domainApplication = Agentic.application(
            "fixture.domain_installation"
        ) {
            install(
                InstallationCatalogDomainFixture.self
            )
            install(
                InstallationCatalogUnscopedToolFixture()
            )
        }

        try Expect.equal(
            domainApplication.catalog,
            catalog,
            "install(Domain.self) installs the complete derived semantic catalog"
        )
        try Expect.equal(
            domainApplication.agentDefinitions.contains(
                where: { definition in
                    definition.identifier == agentIdentifier
                }
            ),
            true,
            "install(Domain.self) realizes linker-derived Agent installation"
        )
        try Expect.equal(
            domainApplication.toolRegistrations.count,
            2,
            "Domain installation realizes the bound Domain Tool while preserving an explicitly installed unscoped Tool"
        )

        let domainRuntime = try await AgenticRuntime(
            application: domainApplication
        )

        try Expect.equal(
            domainRuntime.tools.inspect(
                identifiedBy: boundIdentifier
            ) != nil,
            true,
            "install(Domain.self) realizes an explicitly installable Domain Tool"
        )
        try Expect.equal(
            domainRuntime.tools.inspect(
                identifiedBy: semanticOnlyIdentifier
            ) == nil,
            true,
            "install(Domain.self) preserves semantic-only declarations without fabricating executability"
        )
        try Expect.equal(
            domainRuntime.tools.inspect(
                identifiedBy: unscopedIdentifier
            ) != nil,
            true,
            "Domain installation does not interfere with explicit unscoped installation"
        )

        try Expect.equal(
            runtime.catalog,
            catalog,
            "Runtime retains the installed semantic Catalog"
        )
        try Expect.equal(
            runtime.tools.inspect(
                identifiedBy: boundIdentifier
            ) != nil,
            true,
            "A semantic Tool becomes executable when a matching granular Tool is separately installed"
        )
        try Expect.equal(
            runtime.tools.inspect(
                identifiedBy: semanticOnlyIdentifier
            ) == nil,
            true,
            "Semantic Catalog presence alone does not fabricate an executable Tool"
        )
        try Expect.equal(
            runtime.tools.inspect(
                identifiedBy: unscopedIdentifier
            ) != nil,
            true,
            "A top-level unscoped Tool remains explicitly installable"
        )

        return [
            .field(
                "catalog_domains",
                String(application.catalog.domains.count)
            ),
            .field(
                "catalog_declarations",
                String(application.catalog.declarations.count)
            ),
            .field(
                "tool_registrations",
                String(application.toolRegistrations.count)
            ),
            .field(
                "agent_definitions",
                String(application.agentDefinitions.count)
            ),
        ]
    }
}
