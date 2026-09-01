import Agentic
import AgenticExecution
import AgenticInterfaces
import AgenticRuntimeCommands
import TestFlows

enum AgenticRuntimeHostProjectionFlowTesting {
    enum Failure:
        Error
    {
        case missingStdout
        case missingStderr
        case missingDetails
    }

    static func runOutputDocuments() throws -> [TestFlowDiagnostic] {
        let invocation = try fixtureInvocation()
        let call = invocation.review.call
        let plan = AgentToolPlan(
            id: "host-output-documents-plan",
            root: .call(
                call
            )
        )
        let run = AgentToolPlanRun(
            id: "host-output-documents-run",
            plan: plan,
            relationship: .root,
            attempts: [
                .init(
                    number: 1,
                    scope: .plan,
                    result: .init(
                        planID: plan.id,
                        outcome: .succeeded,
                        records: [
                            .init(
                                path: "root",
                                call: call,
                                outcome: .succeeded,
                                invocation: invocation
                            ),
                        ]
                    )
                ),
            ],
            revision: 1,
            state: .completed
        )
        let snapshot = HostProjection.snapshot(
            runs: [
                run,
            ],
            context: "host output documents"
        )

        guard let stdout = snapshot.documents.first(
            where: {
                $0.kind == .stdout
            }
        ) else {
            throw Failure.missingStdout
        }

        guard let stderr = snapshot.documents.first(
            where: {
                $0.kind == .stderr
            }
        ) else {
            throw Failure.missingStderr
        }

        guard snapshot.documents.contains(
            where: {
                $0.kind == .details
            }
        ) else {
            throw Failure.missingDetails
        }

        try Expect.equal(
            stdout.id,
            "host-output-documents-run:host-output-documents-call:stdout",
            "stdout document identity is stable by run, step, and stream"
        )
        try Expect.equal(
            stdout.body,
            "compile started\ncompile finished\n",
            "stdout observations preserve authored order without synthetic separators"
        )
        try Expect.equal(
            stderr.id,
            "host-output-documents-run:host-output-documents-call:stderr",
            "stderr document identity is stable by run, step, and stream"
        )
        try Expect.equal(
            stderr.body,
            "error: fixture failed\n",
            "stderr preserves raw standard-error observation content"
        )
        try Expect.equal(
            stdout.body.contains(
                "diagnostic-only"
            ),
            false,
            "non-stream observations do not leak into stdout documents"
        )

        return [
            .field(
                "stdout-bytes",
                "\(stdout.body.utf8.count)"
            ),
            .field(
                "stderr-bytes",
                "\(stderr.body.utf8.count)"
            ),
            .field(
                "documents",
                "\(snapshot.documents.count)"
            ),
        ]
    }

    static func runEmptyOutputDocuments() throws -> [TestFlowDiagnostic] {
        let invocation = try emptyFixtureInvocation()
        let call = invocation.review.call
        let plan = AgentToolPlan(
            id: "host-empty-output-documents-plan",
            root: .call(
                call
            )
        )
        let run = AgentToolPlanRun(
            id: "host-empty-output-documents-run",
            plan: plan,
            relationship: .root,
            attempts: [
                .init(
                    number: 1,
                    scope: .plan,
                    result: .init(
                        planID: plan.id,
                        outcome: .succeeded,
                        records: [
                            .init(
                                path: "root",
                                call: call,
                                outcome: .succeeded,
                                invocation: invocation
                            ),
                        ]
                    )
                ),
            ],
            revision: 1,
            state: .completed
        )
        let snapshot = HostProjection.snapshot(
            runs: [
                run,
            ],
            context: "host empty output documents"
        )

        guard let stdout = snapshot.documents.first(
            where: {
                $0.kind == .stdout
            }
        ) else {
            throw Failure.missingStdout
        }

        guard let stderr = snapshot.documents.first(
            where: {
                $0.kind == .stderr
            }
        ) else {
            throw Failure.missingStderr
        }

        try Expect.equal(
            stdout.body,
            "stdout is empty.",
            "executed zero-byte stdout is explicit"
        )
        try Expect.equal(
            stderr.body,
            "stderr is empty.",
            "executed zero-byte stderr is explicit"
        )

        return [
            .field(
                "stdout",
                stdout.body
            ),
            .field(
                "stderr",
                stderr.body
            ),
        ]
    }
}

private extension AgenticRuntimeHostProjectionFlowTesting {
    struct FixtureOutput:
        Sendable,
        Codable,
        Hashable
    {
        let value: String
    }

    static func emptyFixtureInvocation() throws -> ToolInvocation.Result {
        let output = try JSONToolBridge.encode(
            FixtureOutput(
                value: "authoritative-empty"
            )
        )
        let call = AgentToolCall(
            id: "host-empty-output-documents-call",
            name: "host_empty_output_documents_fixture",
            input: output
        )
        let review = ToolInvocation.Review(
            call: call,
            preflight: .init(
                toolName: call.name,
                risk: .observe,
                summary: "Host empty output projection fixture."
            ),
            requirement: .no_approval_needed,
            guidelineRelations: []
        )
        let result = AgentToolResult(
            toolCallID: call.id,
            name: call.name,
            output: output,
            processing: nil,
            isError: false
        )

        return .init(
            review: review,
            decision: .approved,
            toolResult: result
        )
    }

    static func fixtureInvocation() throws -> ToolInvocation.Result {
        let output = try JSONToolBridge.encode(
            FixtureOutput(
                value: "authoritative"
            )
        )
        let call = AgentToolCall(
            id: "host-output-documents-call",
            name: "host_output_documents_fixture",
            input: output
        )
        let review = ToolInvocation.Review(
            call: call,
            preflight: .init(
                toolName: call.name,
                risk: .observe,
                summary: "Host output projection fixture."
            ),
            requirement: .no_approval_needed,
            guidelineRelations: []
        )
        let result = AgentToolResult(
            toolCallID: call.id,
            name: call.name,
            output: output,
            processing: .init(
                projection: .init(
                    status: "passed",
                    summary: "Fixture completed."
                ),
                observations: [
                    .init(
                        kind: .standard_output,
                        content: "compile started\n"
                    ),
                    .init(
                        kind: .diagnostic,
                        content: "diagnostic-only\n"
                    ),
                    .init(
                        kind: .standard_output,
                        content: "compile finished\n"
                    ),
                    .init(
                        kind: .standard_error,
                        label: "compiler stderr",
                        content: "error: fixture failed\n"
                    ),
                ]
            ),
            isError: false
        )

        return .init(
            review: review,
            decision: .approved,
            toolResult: result
        )
    }
}
