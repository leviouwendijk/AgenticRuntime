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
        lhs.entries == rhs.entries && lhs.callable == rhs.callable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entries)
        hasher.combine(callable)
    }

    private enum CodingKeys: String, CodingKey {
        case entries, callable
    }

    public init(from decoder: any Decoder) throws {
        // Kept in the order it was advertised in. Older records are the
        // bare entry list.
        if let entries = try? decoder.singleValueContainer().decode([Entry].self) {
            try self.init(ordered: entries)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ordered: container.decode([Entry].self, forKey: .entries),
            callable: container.decodeIfPresent([String: CapabilityReference].self, forKey: .callable) ?? [:]
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        if !callable.isEmpty {
            try container.encode(callable, forKey: .callable)
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

    /// The functions declared to the provider, in the order sent.
    public let entries: [Entry]
    /// Every other capability this request can call, by provider name: not
    /// declared, so the tool definitions and the provider's cached prefix
    /// stay as they are, and called by that name or through
    /// `call_capability`. Names only; the contract is `inspect_capability`'s.
    public let callable: [String: CapabilityReference]
    private let targetsByName: [String: CapabilityReference]

    /// Provider declarations only; semantic invocation identities remain
    /// bound to this exact projection, never encoded into provider inputs.
    public var functions: [FunctionDescriptor] {
        entries.map(\.function)
    }

    /// Everything this request can call, declared or not.
    public var targets: [CapabilityReference] {
        entries.map(\.target) + callable.values
    }

    init(_ candidates: [Entry]) throws {
        try self.init(ordered: candidates.sorted {
            $0.function.name < $1.function.name
        })
    }

    /// Entries in exactly this order; `callable` names what is declared
    /// already are dropped.
    init(ordered candidates: [Entry], callable: [String: CapabilityReference] = [:]) throws {
        var targetsByName: [String: CapabilityReference] = [:]
        for entry in candidates {
            guard targetsByName.updateValue(
                entry.target,
                forKey: entry.function.name
            ) == nil else {
                throw ProjectionError.duplicateProviderName(entry.function.name)
            }
        }
        let declared = Set(targetsByName.values)
        self.entries = candidates
        self.callable = callable.filter { targetsByName[$0.key] == nil && !declared.contains($0.value) }
        self.targetsByName = targetsByName
    }

    /// The provider name a dispatcher call means, by capability identifier
    /// or by provider function name.
    func name(dispatchedAs identifier: String) -> String? {
        if target(named: identifier) != nil {
            return identifier
        }
        return entries.first { $0.target.identifier == identifier }?.function.name
            ?? callable.first { $0.value.identifier == identifier }?.key
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
              let name = name(dispatchedAs: identifier),
              name != call.name
        else { return call }
        var input = arguments["input"] ?? .object([:])
        // Some models send the input as a JSON string.
        if case .string(let text) = input,
           let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) {
            input = parsed
        }
        outer["arguments"] = input
        return FunctionCall(id: call.id, name: name, input: .object(outer))
    }

    /// The exact lookup table belonging to this model request's projection.
    /// Invocation checks live Agent availability again; the request-bound
    /// function mapping is retained independently of later projection changes.
    public func target(named name: String) -> CapabilityReference? {
        targetsByName[name] ?? callable[name]
    }

    public func name(for target: CapabilityReference) -> String? {
        entries.first(where: { $0.target == target })?.function.name
            ?? callable.first(where: { $0.value == target })?.key
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
    /// Every visible capability declared, in provider-name order.
    func modelProjection(
        visible: AgentCapabilitySet
    ) throws -> ModelCapabilityProjection {
        try ModelCapabilityProjection(visible.references.map(projectionEntry(for:)))
    }

    /// `declared` in this order with their schemas, and every other
    /// capability in `callable` by provider name only.
    func modelProjection(
        declared: [CapabilityReference],
        callable: AgentCapabilitySet
    ) throws -> ModelCapabilityProjection {
        let declaredSet = Set(declared)
        var names: [String: CapabilityReference] = [:]
        for reference in callable.references where !declaredSet.contains(reference) {
            names[try projectionEntry(for: reference).function.name] = reference
        }
        return try ModelCapabilityProjection(
            ordered: declared.map(projectionEntry(for:)),
            callable: names
        )
    }

    func projectionEntry(
        for reference: CapabilityReference
    ) throws -> ModelCapabilityProjection.Entry {
        switch reference {
        case .tool(let identifier):
            guard let descriptor = tools.modelFacingDefinition(
                identifiedBy: identifier
            ) else {
                throw ModelCapabilityProjection.ProjectionError.missingTool(identifier)
            }
            return .init(function: descriptor.modelFunction, target: reference)
        case .program(let identifier):
            guard let binding = program(identifier) else {
                throw ModelCapabilityProjection.ProjectionError.missingProgram(identifier)
            }
            return .init(
                function: .init(
                    name: ModelCapabilityProjection.providerName(
                        kind: "program", identifier: identifier.rawValue
                    ),
                    description: binding.definition.purpose,
                    input: binding.modelFacingInputSchema.jsonvalue
                ),
                target: reference
            )
        case .inference(let identifier):
            guard let binding = inference(identifier) else {
                throw ModelCapabilityProjection.ProjectionError.missingInference(identifier)
            }
            return .init(
                function: .init(
                    name: ModelCapabilityProjection.providerName(
                        kind: "inference", identifier: identifier.rawValue
                    ),
                    description: binding.definition.purpose,
                    input: binding.modelFacingInputSchema.jsonvalue
                ),
                target: reference
            )
        case .agent(let identifier):
            guard let binding = agentBinding(identifier) else {
                throw ModelCapabilityProjection.ProjectionError.missingAgent(identifier)
            }
            return .init(
                function: .init(
                    name: ModelCapabilityProjection.providerName(
                        kind: "agent", identifier: identifier.rawValue
                    ),
                    description: binding.modelFacingDescription,
                    input: binding.modelFacingInputSchema.jsonvalue
                ),
                target: reference
            )
        }
    }
}
