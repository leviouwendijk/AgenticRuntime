import Agentic
import AgenticRuntime
import Foundation
import Primitives
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    static func runToolSourceImpact() throws -> [TestDiagnostic] {
        let observation = ToolPreflight(
            tool: .init(rawValue: "fixture.compiler.inspect"),
            risk: .privileged,
            summary: "Inspect compiler symbol",
            mayChangeSource: false
        )

        let unknown = ToolPreflight(
            tool: .init(rawValue: "fixture.privileged.unknown"),
            risk: .privileged,
            summary: "Unknown privileged operation"
        )

        let mutation = ToolPreflight(
            tool: .init(rawValue: "fixture.source.mutation"),
            risk: .boundedmutate,
            summary: "Modify source files",
            mayChangeSource: true
        )

        try Expect.equal(
            observation.mayInvalidateSourceState,
            false,
            "privileged observation does not invalidate source-dependent siblings"
        )
        try Expect.equal(
            unknown.mayInvalidateSourceState,
            true,
            "unknown privileged operations remain conservative"
        )
        try Expect.equal(
            mutation.mayInvalidateSourceState,
            true,
            "source mutations invalidate source-dependent siblings"
        )

        let encoded = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(
            ToolPreflight.self,
            from: encoded
        )
        try Expect.equal(
            decoded.mayInvalidateSourceState,
            false,
            "source-impact declaration survives persistence"
        )

        var legacy = try JSONDecoder().decode(
            [String: JSONValue].self,
            from: encoded
        )
        legacy.removeValue(forKey: "mayChangeSource")
        let restored = try JSONDecoder().decode(
            ToolPreflight.self,
            from: JSONEncoder().encode(legacy)
        )
        try Expect.equal(
            restored.mayInvalidateSourceState,
            true,
            "legacy preflights retain conservative behavior"
        )

        return [
            .field("source_impact", "explicit observations and conservative legacy fallback verified")
        ]
    }
}
