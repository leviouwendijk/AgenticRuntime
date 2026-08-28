import Agentic
import Foundation
import Path

public struct FileModelPricingCatalog: ModelPricingCatalog {
    public var catalogfile: StandardPath

    public init(
        catalogfile: StandardPath
    ) {
        self.catalogfile = catalogfile
    }

    public init(
        catalogfile: URL
    ) {
        self.init(
            catalogfile: StandardPath(
                fileURL: catalogfile,
                terminalHint: .file,
                inferFileType: false
            )
        )
    }

    public init(
        catalogdir: StandardPath,
        filename: String = "pricing-catalog.json"
    ) {
        self.init(
            catalogfile: catalogdir.child.file(
                filename
            )
        )
    }

    public init(
        catalogdir: URL,
        filename: String = "pricing-catalog.json"
    ) {
        self.init(
            catalogdir: StandardPath(
                fileURL: catalogdir,
                terminalHint: .directory,
                inferFileType: false
            ),
            filename: filename
        )
    }

    public func pricing(
        for key: ModelPricingKey
    ) throws -> ModelPricingSnapshot {
        let snapshots = try loadSnapshots()

        if let exact = snapshots.last(where: { $0.key == key }) {
            return exact
        }

        if key.region != nil {
            let fallback = ModelPricingKey(
                provider: key.provider,
                model: key.model,
                region: nil
            )

            if let fallback = snapshots.last(where: { $0.key == fallback }) {
                return fallback
            }
        }

        throw AgentCostError.missingPricingForModel(
            key
        )
    }

    public func loadDocument() throws -> ModelPricingCatalogDocument {
        let url = catalogfile.root_url

        guard PathExistence.exists(
            url: url
        ) else {
            return .init()
        }

        let data = try Data(
            contentsOf: url
        )

        guard !data.isEmpty else {
            return .init()
        }

        return try decoder.decode(
            ModelPricingCatalogDocument.self,
            from: data
        )
    }

    public func loadSnapshots() throws -> [ModelPricingSnapshot] {
        try loadDocument().snapshots
    }

    public func saveDocument(
        _ document: ModelPricingCatalogDocument
    ) throws {
        try PathCreation.parent(
            of: catalogfile
        )

        var document = document
        document.updatedAt = Date()

        let data = try encoder.encode(
            document
        )

        try data.write(
            to: catalogfile.root_url,
            options: .atomic
        )
    }

    public func saveSnapshots(
        _ snapshots: [ModelPricingSnapshot],
        metadata: [String: String] = [:]
    ) throws {
        let previous = try loadDocument()

        try saveDocument(
            .init(
                version: previous.version,
                snapshots: snapshots,
                createdAt: previous.createdAt,
                updatedAt: Date(),
                metadata: metadata.isEmpty ? previous.metadata : metadata
            )
        )
    }

    public func upsert(
        _ snapshot: ModelPricingSnapshot
    ) throws {
        var document = try loadDocument()

        document.snapshots.removeAll {
            $0.key == snapshot.key
        }

        document.snapshots.append(
            snapshot
        )

        document.snapshots.sort { lhs, rhs in
            if lhs.provider != rhs.provider {
                return lhs.provider < rhs.provider
            }

            if lhs.model != rhs.model {
                return lhs.model < rhs.model
            }

            return (lhs.region ?? "") < (rhs.region ?? "")
        }

        try saveDocument(
            document
        )
    }

    public func remove(
        key: ModelPricingKey
    ) throws {
        var document = try loadDocument()

        document.snapshots.removeAll {
            $0.key == key
        }

        try saveDocument(
            document
        )
    }
}

private extension FileModelPricingCatalog {
    var encoder: JSONEncoder {
        let encoder = JSONEncoder()

        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        encoder.dateEncodingStrategy = .iso8601

        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .iso8601

        return decoder
    }
}
