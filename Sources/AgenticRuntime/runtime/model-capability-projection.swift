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
    /// `standard_tool_call_capability`. Names only; the contract is `standard_tool_inspect_capability`'s.
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

    /// The provider name a dispatcher call means: by capability identifier
    /// or provider function name, else through `CapabilityReference.Raw`
    /// (aliases, `domain.name`, a bare name narrowed by `domain`). Nil when
    /// that does not name exactly one; `standard_tool_call_capability` then says why.
    func name(
        dispatchedAs identifier: String,
        domain: String? = nil,
        domains: [DomainDefinition] = []
    ) -> String? {
        if domain == nil {
            if target(named: identifier) != nil {
                return identifier
            }
            if let name = entries.first(where: { $0.target.identifier == identifier })?.function.name
                ?? callable.first(where: { $0.value.identifier == identifier })?.key {
                return name
            }
        }
        let kinds: [CapabilityKind] = (try? CapabilityIdentity(identifier)).map { [$0.kind] } ?? CapabilityKind.allCases
        for kind in kinds {
            if let reference = try? CapabilityReference(.init(
                identifier,
                domain: domain,
                kind: kind,
                domains: domains,
                offered: targets
            )) {
                return name(for: reference)
            }
        }
        return nil
    }

    /// A `standard_tool_call_capability` call as a call of the capability it names, under
    /// the same call id, so authorization, approval, preflight and the
    /// record treat it as that capability. Unchanged when it names nothing
    /// this request can call; the dispatcher tool then says why.
    func dispatched(
        _ call: FunctionCall,
        domains: [DomainDefinition] = []
    ) -> FunctionCall {
        var domain: String?
        if case .object(let outer) = call.input,
           case .object(let arguments)? = outer["arguments"],
           case .string(let value)? = arguments["domain"] {
            domain = value
        }
        guard call.name == Standard.Tools.CallCapability.identifier.rawValue,
              case .object(var outer) = call.input,
              case .object(let arguments)? = outer["arguments"],
              case .string(let identifier)? = arguments["identifier"],
              let name = name(dispatchedAs: identifier, domain: domain, domains: domains),
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
}

/// A read-only projection over one installed binding snapshot and one Agent's
/// visible selection. This function is the sole projection implementation:
/// neither transport nor callers maintain a parallel capability registry.
extension InstalledCapabilities {
    /// Every visible capability declared, in provider-name order.
    func modelProjection(
        visible: AgentCapabilitySet
    ) throws -> ModelCapabilityProjection {
        var taken: Set<String> = []
        return try ModelCapabilityProjection(visible.references.map { try projectionEntry(for: $0, taken: &taken) })
    }

    /// `declared` in this order with their schemas, and every other
    /// capability in `callable` by provider name only.
    func modelProjection(
        declared: [CapabilityReference],
        callable: AgentCapabilitySet
    ) throws -> ModelCapabilityProjection {
        let declaredSet = Set(declared)
        var taken: Set<String> = []
        let entries = try declared.map { try projectionEntry(for: $0, taken: &taken) }
        var names: [String: CapabilityReference] = [:]
        for reference in callable.references where !declaredSet.contains(reference) {
            names[uniqueName(for: reference, taken: &taken)] = reference
        }
        return try ModelCapabilityProjection(
            ordered: entries,
            callable: names
        )
    }

    /// The entry under a name not in `taken`, which it then joins. Names are
    /// `CapabilityReference.providerName`; a non-tool whose name is taken
    /// falls back to its hashed form (a tool's name is its identifier, which
    /// calls are matched against).
    func projectionEntry(
        for reference: CapabilityReference,
        taken: inout Set<String>
    ) throws -> ModelCapabilityProjection.Entry {
        try projectionEntry(for: reference, named: uniqueName(for: reference, taken: &taken))
    }

    func uniqueName(
        for reference: CapabilityReference,
        taken: inout Set<String>
    ) -> String {
        var name = reference.providerName
        if case .tool = reference {} else if taken.contains(name) {
            name = reference.hashedProviderName
        }
        taken.insert(name)
        return name
    }

    func projectionEntry(
        for reference: CapabilityReference,
        named name: String
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
                    name: name,
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
                    name: name,
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
                    name: name,
                    description: binding.modelFacingDescription,
                    input: binding.modelFacingInputSchema.jsonvalue
                ),
                target: reference
            )
        }
    }
}
