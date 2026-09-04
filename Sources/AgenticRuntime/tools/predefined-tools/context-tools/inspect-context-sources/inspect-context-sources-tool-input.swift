import Schema
import SchemaMacros

@JSONSchema
public struct InspectContextSourcesToolInput: Sendable, Codable, Hashable {
    public let plan: ContextCompositionPlan

    public init(
        plan: ContextCompositionPlan
    ) {
        self.plan = plan
    }
}