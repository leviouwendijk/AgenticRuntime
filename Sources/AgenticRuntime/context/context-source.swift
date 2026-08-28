import Agentic

public enum ContextSource: Sendable, Codable, Hashable {
    case text(String)
    case message(AgentMessage)
    case transcriptEvent(AgentTranscriptEvent)
    case files(ContextFileSource)
    case skill(AgentSkill)
}
