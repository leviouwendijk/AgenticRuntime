import Agentic
import Foundation

public extension FileModelPricingCatalog {
    func importSnapshots(
        _ snapshots: [ModelPricingSnapshot],
        replacingExisting: Bool = false,
        metadata: [String: String] = [:]
    ) throws {
        if replacingExisting {
            try saveSnapshots(
                snapshots,
                metadata: metadata
            )

            return
        }

        var document = try loadDocument()

        for snapshot in snapshots {
            document.snapshots.removeAll {
                $0.key == snapshot.key
            }

            document.snapshots.append(
                snapshot
            )
        }

        document.metadata.merge(
            metadata
        ) { _, new in
            new
        }

        try saveDocument(
            document
        )
    }

    func exportDocument() throws -> ModelPricingCatalogDocument {
        try loadDocument()
    }
}
