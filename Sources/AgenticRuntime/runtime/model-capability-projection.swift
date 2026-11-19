import Agentic
import AgenticStandard
import Foundation
import Primitives
import Schema

/// One model-visible function bound to a semantic Runtime capability.
///
/// This is a transport projection, not a Tool registration: only actual Tools
/// carry Tool ActionRisk, and invocation still requires live capability checks.
public struct ModelCapabilityProjection: Sendable, Codable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries == rhs.entries && lhs.deferred == rhs.deferred
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entries)
        hasher.combine(deferred)
    }

    private enum CodingKeys: String, CodingKey {
        case entries, deferred
    }

    public init(from decoder: any Decoder) throws {
        // Kept in the order it was advertised in. Older records are the
        // bare entry list, with nothing deferred.
        if let entries = try? decoder.singleValueContainer().decode([Entry].self) {
            try self.init(ordered: entries)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ordered: container.decode([Entry].self, forKey: .entries),
            deferred: container.decodeIfPresent([String].self, forKey: .deferred) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        if !deferred.isEmpty {
            try container.encode(deferred, forKey: .deferred)
        }
    }

    public struct Entry: Sendable, Codable, Hashable {
        public let function: FunctionDescriptor
        public let target: CapabilityReference

        public init(
            function: FunctionDescriptor,
            target: CapabilityReference
        ) {
            self.function = function
            self.target = target
        }
    }

    public enum ProjectionError: Error, Sendable {
        case missingTool(ToolIdentifier)
        case missingProgram(ProgramIdentifier)
        case missingInference(InferenceIdentifier)
        case missingAgent(AgentIdentifier)
        case duplicateProviderName(String)
    }

    public let entries: [Entry]
    /// Names of entries callable in this request but not declared to the
    /// provider: revealed after the session's tool definitions were fixed,
    /// they are called through `call_capability`.
    public let deferred: [String]
    private let targetsByName: [String: CapabilityReference]

    /// The entries declared to the provider.
    public var declared: [Entry] {
        entries.filter { !deferred.contains($0.function.name) }
    }

    /// Provider declarations only; semantic invocation identities remain
    /// bound to this exact projection, never encoded into provider inputs.
    public var functions: [FunctionDescriptor] {
        declared.map(\.function)
    }

    init(_ candidates: [Entry]) throws {
        try self.init(ordered: candidates.sorted {
            $0.function.name < $1.function.name
        })
    }

    /// Entries in exactly this order.
    init(ordered candidates: [Entry], deferred: [String] = []) throws {
        var targetsByName: [String: CapabilityReference] = [:]
        for entry in candidates {
            guard targetsByName.updateValue(
                entry.target,
                forKey: entry.function.name
            ) == nil else {
                throw ProjectionError.duplicateProviderName(entry.function.name)
            }
        }
        self.entries = candidates
        self.deferred = deferred.filter { targetsByName[$0] != nil }
        self.targetsByName = targetsByName
    }

    /// The same entries, with these called through the dispatcher.
    func deferring(_ names: [String]) -> Self {
        (try? Self(ordered: entries, deferred: names)) ?? self
    }

    /// The entry a dispatcher call names, by capability identifier or by
    /// provider function name.
    func entry(dispatchedAs identifier: String) -> Entry? {
        entries.first { $0.function.name == identifier || $0.target.identifier == identifier }
    }

    /// A `call_capability` call as a call of the capability it names, under
    /// the same call id, so authorization, approval, preflight and the
    /// record treat it as that capability. Unchanged when it names nothing
    /// this request can call; the dispatcher tool then says why.
    func dispatched(_ call: FunctionCall) -> FunctionCall {
        guard call.name == Standard.Tools.CallCapability.identifier.rawValue,
              case .object(var outer) = call.input,
              case .object(let arguments)? = outer["arguments"],
              case .string(let identifier)? = arguments["identifier"],
              let entry = entry(dispatchedAs: identifier),
              entry.function.name != call.name
        else { return call }
        var input = arguments["input"] ?? .object([:])
        // Some models send the input as a JSON string.
        if case .string(let text) = input,
           let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) {
            input = parsed
        }
        outer["arguments"] = input
        return FunctionCall(id: call.id, name: entry.function.name, input: .object(outer))
    }

    /// The same entries, those named in `names` first in that order, the
    /// rest after in theirs.
    func ordered(by names: [String]) -> Self {
        let byName = Dictionary(entries.map { ($0.function.name, $0) }, uniquingKeysWith: { first, _ in first })
        let first = names.compactMap { byName[$0] }
        let placed = Set(first.map(\.function.name))
        // Names are unique already, so this cannot fail.
        return (try? Self(
            ordered: first + entries.filter { !placed.contains($0.function.name) },
            deferred: deferred
        )) ?? self
    }

    /// The exact lookup table belonging to this model request's projection.
    /// Invocation checks live Agent availability again; the request-bound
    /// function mapping is retained independently of later projection changes.
    public func target(named name: String) -> CapabilityReference? {
        targetsByName[name]
    }

    public func name(for target: CapabilityReference) -> String? {
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

        for identifier in visible.agents {
            guard let binding = agentBinding(identifier) else {
                throw ModelCapabilityProjection.ProjectionError.missingAgent(identifier)
            }
            candidates.append(.init(
                function: .init(
                    name: ModelCapabilityProjection.providerName(
                        kind: "agent", identifier: identifier.rawValue
                    ),
                    description: binding.modelFacingDescription,
                    input: binding.modelFacingInputSchema.jsonvalue
                ),
                target: .agent(identifier)
            ))
        }
        return try ModelCapabilityProjection(candidates)
    }
}
