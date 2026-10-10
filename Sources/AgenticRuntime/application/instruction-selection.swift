import Agentic

/// Selection is a read-only view of the authored Catalog, not an executable
/// installation or an additional mutable registry.
public struct InstructionSelection: Sendable {
    public let selected: [InstructionDefinition]
    public let missingIdentifiers: [InstructionIdentifier]

    public init(
        selected: [InstructionDefinition],
        missingIdentifiers: [InstructionIdentifier]
    ) {
        self.selected = selected
        self.missingIdentifiers = missingIdentifiers
    }

    public var instructions: Instructions {
        Instructions(selected.map { .instruction($0) })
    }
}

public enum InstructionSelectionError: Error, Sendable {
    case conflictingDefinitions(InstructionIdentifier)
}

public extension Catalog {
    /// Resolve in requested order. Missing identifiers remain visible to the
    /// caller. Conflicting definitions cannot silently overwrite one another.
    func selectingInstructions(
        _ identifiers: [InstructionIdentifier]
    ) throws -> InstructionSelection {
        var definitions: [InstructionIdentifier: InstructionDefinition] = [:]
        for definition in instructions {
            if let existing = definitions[definition.identifier],
               existing != definition {
                throw InstructionSelectionError.conflictingDefinitions(
                    definition.identifier
                )
            }
            definitions[definition.identifier] = definition
        }

        var seen: Set<InstructionIdentifier> = []
        var selected: [InstructionDefinition] = []
        var missing: [InstructionIdentifier] = []
        for identifier in identifiers {
            guard seen.insert(identifier).inserted else { continue }
            if let definition = definitions[identifier] {
                selected.append(definition)
            } else {
                missing.append(identifier)
            }
        }
        return .init(selected: selected, missingIdentifiers: missing)
    }
}