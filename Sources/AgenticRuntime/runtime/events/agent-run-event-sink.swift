import Agentic

public extension Run {
    /// Canonical run event sink.
    ///
    /// The run-event surface is a single typed `record(_ event: Run.Event)`
    /// channel. Transcript-specific recording methods remain separate and are
    /// not merged into `Run.Event` in this pass.
    protocol EventSink: Sendable {
        func record(
            _ event: Event
        ) async throws

        func recordMessage(
            _ message: Message
        ) async throws

        func recordFunctionCall(
            _ functionCall: FunctionCall
        ) async throws

        func recordToolResult(
            _ result: FunctionCall.Response
        ) async throws

        func recordSessionBranch(
            _ event: SessionBranchEvent
        ) async throws

        /// Writes anything staged; called at every step boundary.
        func flush() async throws
    }
}

public extension Run.EventSink {
    func record(
        _ event: Run.Event
    ) async throws {
    }

    func recordMessage(
        _ message: Message
    ) async throws {
    }

    func recordFunctionCall(
        _ functionCall: FunctionCall
    ) async throws {
    }

    func recordToolResult(
        _ result: FunctionCall.Response
    ) async throws {
    }

    func recordSessionBranch(
        _ event: SessionBranchEvent
    ) async throws {
    }

    func flush() async throws {
    }
}

// MARK: - Deprecated compatibility alias

