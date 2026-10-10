import Agentic
import Primitives

/// One model-visible function bound to a semantic Runtime capability.
///
/// This is a transport projection, not a Tool registration: only actual Tools
/// carry Tool ActionRisk, and invocation still requires live capability checks.
public struct ModelCapabilityProjection: Sendable, Codable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries == rhs.entries
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entries)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode([Entry].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }

    public struct Entry: Sendable, Codable, Hashable {
        public let function: ModelFunctionDescriptor
        public let target: CapabilityInvocation.Target

        public init(
            function: ModelFunctionDescriptor,
            target: CapabilityInvocation.Target
        ) {
            self.function = function
            self.target = target
        }
    }

    public enum ProjectionError: Error, Sendable {
        case missingTool(ToolIdentifier)
        case missingProgram(ProgramIdentifier)
        case missingInference(InferenceIdentifier)
        case duplicateProviderName(String)
    }

    public let entries: [Entry]
    private let targetsByName: [String: CapabilityInvocation.Target]

    /// Provider declarations only; semantic invocation identities remain
    /// bound to this exact projection, never encoded into provider inputs.
    public var functions: [ModelFunctionDescriptor] {
        entries.map(\.function)
    }

    init(_ candidates: [Entry]) throws {
        var targetsByName: [String: CapabilityInvocation.Target] = [:]
        for entry in candidates {
            guard targetsByName.updateValue(
                entry.target,
                forKey: entry.function.name
            ) == nil else {
                throw ProjectionError.duplicateProviderName(entry.function.name)
            }
        }
        self.entries = candidates.sorted {
            $0.function.name < $1.function.name
        }
        self.targetsByName = targetsByName
    }

    /// The exact lookup table belonging to this model request's projection.
    /// Invocation checks live Agent availability again; the request-bound
    /// function mapping is retained independently of later projection changes.
    public func target(named name: String) -> CapabilityInvocation.Target? {
        targetsByName[name]
    }

    public func name(for target: CapabilityInvocation.Target) -> String? {
        entries.first(where: { $0.target == target })?.function.name
    }

    /// Stable, bounded provider name. Keeping a mapping rather than encoding
    /// the identifier in provider output avoids interpreting arbitrary names.
    static func providerName(
        kind: String,
        identifier: String
    ) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identifier.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        let hexadecimal = String(hash, radix: 16)
        let padded = String(
            repeating: "0",
            count: max(0, 16 - hexadecimal.count)
        ) + hexadecimal
        return "agentic_\(kind)_\(padded)"
    }
}

/// A read-only projection over one installed binding snapshot and one Agent's
/// visible selection. This function is the sole projection implementation:
/// neither transport nor callers maintain a parallel capability registry.
extension InstalledCapabilities {
    func modelProjection(
        visible: AgentCapabilitySet
    ) throws -> ModelCapabilityProjection {
        var candidates: [ModelCapabilityProjection.Entry] = []

        for identifier in visible.tools {
            guard let descriptor = tools.modelFacingDefinition(
                identifiedBy: identifier
            ) else {
                throw ModelCapabilityProjection.ProjectionError.missingTool(identifier)
            }
            candidates.append(.init(
                function: descriptor.modelFunction,
                target: .tool(identifier)
            ))
        }

        for identifier in visible.programs {
            guard let binding = program(identifier) else {
                throw ModelCapabilityProjection.ProjectionError.missingProgram(identifier)
            }
            candidates.append(.init(
                function: .init(
                    name: ModelCapabilityProjection.providerName(
                        kind: "program", identifier: identifier.rawValue
                    ),
                    description: binding.definition.purpose,
                    input: binding.modelFacingInputSchema.jsonvalue
                ),
                target: .program(identifier)
            ))
        }

        for identifier in visible.inferences {
            guard let binding = inference(identifier) else {
                throw ModelCapabilityProjection.ProjectionError.missingInference(identifier)
            }
            candidates.append(.init(
                function: .init(
                    name: ModelCapabilityProjection.providerName(
                        kind: "inference", identifier: identifier.rawValue
                    ),
                    description: binding.definition.purpose,
                    input: binding.modelFacingInputSchema.jsonvalue
                ),
                target: .inference(identifier)
            ))
        }

        // Agents are not projected as callable functions until child delegation
        // has a governed execution and checkpoint contract.
        return try ModelCapabilityProjection(candidates)
    }
}
