import AgenticExecution
import Schema

extension ContextCompositionPlan: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .any
    }
}

extension UserInputSpec: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .any
    }
}

extension UserInputPresentation: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .any
    }
}

extension AgentSessionStatus: JSONSchemaProviding {
    public static var jsonschema: JSONSchema {
        .string(
            cases: allCases.map(\.rawValue)
        )
    }
}
