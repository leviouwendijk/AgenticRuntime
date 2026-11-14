import Agentic
import Schema

/// How a model calls an Agent: one definition shared by the request
/// projection and by `inspect_capability`, so the two cannot drift apart.
extension AgentBinding {
    /// The Agent's input, wrapped with the delegation envelope.
    var modelFacingInputSchema: JSONSchema {
        CapabilityModelInputSchema.envelope(
            semanticInput: contract.input,
            execution: .object {
                JSONSchema.property(
                    "workspace_scope",
                    schema: .string(),
                    required: false,
                    description: "Workspace path the Agent may work in; without it the Agent has no file access."
                )
            }
        )
    }

    /// The purpose, plus how to grant file access: a delegated Agent without
    /// a scope cannot read or write files.
    var modelFacingDescription: String {
        definition.purpose
            + " Set execution.workspace_scope to the path it may work in; without it, it has no file access."
    }
}
