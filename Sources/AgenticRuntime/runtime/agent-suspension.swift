import Foundation

public enum AgentSuspensionReason: Sendable, Codable, Hashable {
    case approval(PendingApproval)
    case user_input(PendingUserInput)

    private enum CodingKeys: String, CodingKey {
        case kind
        case approval
        case user_input
    }

    private enum Kind: String, Codable {
        case approval
        case user_input

        init(
            from decoder: any Decoder
        ) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(
                String.self
            )

            switch rawValue {
            case "approval":
                self = .approval

            case "user_input", "userInput":
                self = .user_input

            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported AgentSuspensionReason.Kind '\(rawValue)'."
                )
            }
        }
    }

    public init(
        from decoder: any Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let kind = try container.decode(
            Kind.self,
            forKey: .kind
        )

        switch kind {
        case .approval:
            self = .approval(
                try container.decode(
                    PendingApproval.self,
                    forKey: .approval
                )
            )

        case .user_input:
            self = .user_input(
                try container.decode(
                    PendingUserInput.self,
                    forKey: .user_input
                )
            )
        }
    }

    public func encode(
        to encoder: any Encoder
    ) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )

        switch self {
        case .approval(let approval):
            try container.encode(
                Kind.approval,
                forKey: .kind
            )
            try container.encode(
                approval,
                forKey: .approval
            )

        case .user_input(let userInput):
            try container.encode(
                Kind.user_input,
                forKey: .kind
            )
            try container.encode(
                userInput,
                forKey: .user_input
            )
        }
    }

    public var pendingApproval: PendingApproval? {
        guard case .approval(let value) = self else {
            return nil
        }

        return value
    }

    public var pendingUserInput: PendingUserInput? {
        guard case .user_input(let value) = self else {
            return nil
        }

        return value
    }
}

public struct AgentSuspension: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public var reason: AgentSuspensionReason
    public let createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        reason: AgentSuspensionReason,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.reason = reason
        self.createdAt = createdAt
        self.metadata = metadata
    }

    public static func approval(
        _ approval: PendingApproval,
        metadata: [String: String] = [:]
    ) -> Self {
        .init(
            reason: .approval(
                approval
            ),
            metadata: metadata
        )
    }

    public static func user_input(
        _ userInput: PendingUserInput,
        metadata: [String: String] = [:]
    ) -> Self {
        .init(
            reason: .user_input(
                userInput
            ),
            metadata: metadata
        )
    }

    public var pendingApproval: PendingApproval? {
        reason.pendingApproval
    }

    public var pendingUserInput: PendingUserInput? {
        reason.pendingUserInput
    }
}
