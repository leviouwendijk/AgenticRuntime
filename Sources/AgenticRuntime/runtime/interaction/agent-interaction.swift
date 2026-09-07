import AgenticExecution
import Foundation

public enum AgentInteraction {
    public enum Kind:
        String,
        Sendable,
        Codable,
        Hashable,
        CaseIterable
    {
        case approval
        case user_input
    }

    public typealias Requirement = AgentSuspensionReason

    public struct Request:
        Sendable,
        Codable,
        Hashable,
        Identifiable
    {
        public let sessionID: String
        public let suspension: AgentSuspension

        public init(
            sessionID: String,
            suspension: AgentSuspension
        ) {
            self.sessionID = sessionID
            self.suspension = suspension
        }

        public var id: String {
            suspension.id
        }

        public var requirement: Requirement {
            suspension.reason
        }

        public var kind: Kind {
            requirement.interactionKind
        }

        public var createdAt: Date {
            suspension.createdAt
        }

        public var metadata: [String: String] {
            suspension.metadata
        }
    }

    public enum Resolution:
        Sendable,
        Codable,
        Hashable
    {
        case approval(ApprovalDecision)
        case user_input(UserInputAnswer)

        private enum CodingKeys:
            String,
            CodingKey
        {
            case kind
            case approval
            case user_input
        }

        private enum CodingKind:
            String,
            Codable
        {
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
                        debugDescription: "Unsupported AgentInteraction.Resolution kind '\(rawValue)'."
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
                CodingKind.self,
                forKey: .kind
            )

            switch kind {
            case .approval:
                self = .approval(
                    try container.decode(
                        ApprovalDecision.self,
                        forKey: .approval
                    )
                )

            case .user_input:
                self = .user_input(
                    try container.decode(
                        UserInputAnswer.self,
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
            case .approval(let decision):
                try container.encode(
                    CodingKind.approval,
                    forKey: .kind
                )
                try container.encode(
                    decision,
                    forKey: .approval
                )

            case .user_input(let answer):
                try container.encode(
                    CodingKind.user_input,
                    forKey: .kind
                )
                try container.encode(
                    answer,
                    forKey: .user_input
                )
            }
        }

        public var kind: Kind {
            switch self {
            case .approval:
                return .approval

            case .user_input:
                return .user_input
            }
        }
    }

    public struct Response:
        Sendable,
        Codable,
        Hashable
    {
        public let requestID: String
        public let sessionID: String
        public let resolution: Resolution
        public let createdAt: Date
        public var metadata: [String: String]

        public init(
            requestID: String,
            sessionID: String,
            resolution: Resolution,
            createdAt: Date = Date(),
            metadata: [String: String] = [:]
        ) {
            self.requestID = requestID
            self.sessionID = sessionID
            self.resolution = resolution
            self.createdAt = createdAt
            self.metadata = metadata
        }

        public init(
            request: Request,
            resolution: Resolution,
            createdAt: Date = Date(),
            metadata: [String: String] = [:]
        ) {
            self.init(
                requestID: request.id,
                sessionID: request.sessionID,
                resolution: resolution,
                createdAt: createdAt,
                metadata: metadata
            )
        }

        public var kind: Kind {
            resolution.kind
        }
    }
}

public extension AgentSuspensionReason {
    var interactionKind: AgentInteraction.Kind {
        switch self {
        case .approval:
            return .approval

        case .user_input:
            return .user_input
        }
    }
}
