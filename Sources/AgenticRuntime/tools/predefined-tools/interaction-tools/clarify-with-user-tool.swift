import Agentic
import AgenticExecution
import AgenticWorkspace
import Primitives
import Schema
import SchemaMacros

@JSONSchema
public struct ClarifyWithUserToolInput: Sendable, Codable, Hashable {
    public let prompt: String
    public let reason: String?
    public let input: UserInputSpec
    public let presentation: UserInputPresentation?
    public let metadata: [String: String]

    public init(
        prompt: String,
        reason: String? = nil,
        input: UserInputSpec = .text(
            .init()
        ),
        presentation: UserInputPresentation? = nil,
        metadata: [String: String] = [:]
    ) {
        self.prompt = prompt
        self.reason = reason
        self.input = input
        self.presentation = presentation
        self.metadata = metadata
    }

    public var pendingUserInput: PendingUserInput {
        .init(
            prompt: prompt,
            reason: reason,
            input: input,
            presentation: presentation,
            metadata: metadata
        )
    }
}

public struct ClarifyWithUserToolOutput: Sendable, Codable, Hashable {
    public let kind: String
    public let pendingUserInput: PendingUserInput

    public init(
        kind: String = "pending_user_input",
        pendingUserInput: PendingUserInput
    ) {
        self.kind = kind
        self.pendingUserInput = pendingUserInput
    }
}

public struct ClarifyWithUserTool: AgentTool {
    public typealias Input = ClarifyWithUserToolInput
    public typealias Output = ClarifyWithUserToolOutput

    public static let identifier: AgentToolIdentifier = "clarify_with_user"
    public static let description = "Suspend the current agent run and ask the user for missing information needed to continue."
    public static let risk: ActionRisk = .observe

    public var identifier: AgentToolIdentifier { Self.identifier }
    public var description: String { Self.description }
    public var risk: ActionRisk { Self.risk }

    public init() {}

    public func preflight(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> ToolPreflight {

        return .init(
            toolName: name,
            risk: risk,
            workspaceRoot: context.workspace?.rootURL.path,
            targetPaths: [],
            summary: input.prompt,
            estimatedWriteCount: 0,
            estimatedByteCount: 0,
            sideEffects: [
                "suspends the current agent run",
                "waits for typed user input before continuing"
            ]
        )
    }

    public func call(
        _ input: Input,
        context: AgentToolExecutionContext
    ) async throws -> Output {

        return ClarifyWithUserToolOutput(
                pendingUserInput: input.pendingUserInput
            )
    }
}