import Agentic
import AgenticExecution
import AgenticTools

enum AgenticRuntimeToolCatalog {
    static func materialize(
        registrations: [AgentToolRegistration],
        registry: ToolRegistry
    ) throws -> AgentToolCatalog {
        let catalog = try AgentToolCatalog.materialize(
            registrations: registrations,
            registry: registry
        )

        return addingRuntimeIntrinsics(
            to: catalog
        )
    }
}

private extension AgenticRuntimeToolCatalog {
    static func addingRuntimeIntrinsics(
        to catalog: AgentToolCatalog
    ) -> AgentToolCatalog {
        let metadata = AgentToolCollectionMetadata.intrinsics
        var collections = catalog.collections
        var entries = catalog.entries
        var intrinsicIdentifiers = catalog.collection(
            identifiedBy: metadata.identifier
        )?.toolIdentifiers ?? []

        let runtimeIntrinsics = [
            AgentToolCatalogEntry(
                identifier: FindToolsTool.identifier,
                title: FindToolsTool.identifier.rawValue,
                description: FindToolsTool.description,
                risk: FindToolsTool.risk,
                isModelFacing: true,
                workingLocation: .fixed,
                origin: .intrinsic,
                collectionIdentifier: metadata.identifier,
                defaultExposure: metadata.defaultExposure
            ),
            AgentToolCatalogEntry(
                identifier: InspectToolExposureTool.identifier,
                title: InspectToolExposureTool.identifier.rawValue,
                description: InspectToolExposureTool.description,
                risk: InspectToolExposureTool.risk,
                isModelFacing: true,
                workingLocation: .fixed,
                origin: .intrinsic,
                collectionIdentifier: metadata.identifier,
                defaultExposure: metadata.defaultExposure
            ),
        ]

        var didAddIntrinsic = false

        for entry in runtimeIntrinsics
        where catalog.entry(
            identifiedBy: entry.identifier
        ) == nil {
            entries.append(
                entry
            )
            intrinsicIdentifiers.append(
                entry.identifier
            )
            didAddIntrinsic = true
        }

        guard didAddIntrinsic else {
            return catalog
        }

        let intrinsicCollection = AgentToolCollection(
            identifier: metadata.identifier,
            title: metadata.title,
            defaultExposure: metadata.defaultExposure,
            toolIdentifiers: intrinsicIdentifiers
        )

        if let index = collections.firstIndex(
            where: { collection in
                collection.identifier == metadata.identifier
            }
        ) {
            collections[index] = intrinsicCollection
        } else {
            collections.append(
                intrinsicCollection
            )
        }

        return .init(
            collections: collections,
            entries: entries
        )
    }
}
