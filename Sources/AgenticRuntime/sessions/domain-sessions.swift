import Agentic

/// Read-only introspection over Agentic sessions.
///
/// Tools resolve `AgentSessionCatalog` (durable) or `AgentSessionHistory`
/// (in-memory) from the invocation's services, so the host decides which
/// history (if any) an Agent may read.
@Domain
public enum Sessions {}
