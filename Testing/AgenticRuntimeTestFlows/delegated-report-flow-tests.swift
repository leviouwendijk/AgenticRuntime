import AgenticRuntime
import Primitives
import Schema
import TestFlows

extension AgenticProgramRuntimeFlowTesting {
    /// A delegated report is JSON that satisfies the output contract;
    /// valid JSON of the wrong shape is refused.
    static func runDelegatedReport() throws -> [TestDiagnostic] {
        let contract = JSONSchema.object {
            JSONSchema.property("summary", schema: .string(), required: true)
            JSONSchema.property("files", schema: .array(items: .string()), required: true)
        }
        let valid = #"{"summary":"done","files":["a.swift"]}"#

        try Expect.equal(
            try DelegatedReport.value(from: valid, contract: contract),
            .object(["summary": .string("done"), "files": .array([.string("a.swift")])]),
            "a conforming report"
        )
        try Expect.equal(
            try DelegatedReport.value(from: "```json\n\(valid)\n```", contract: contract),
            try DelegatedReport.value(from: valid, contract: contract),
            "a fenced report"
        )
        for (label, text, failure) in [
            ("prose", "I finished the task.", DelegatedReport.Failure.not_json),
            ("array", #"["done"]"#, nil),
            ("missing field", #"{"summary":"done"}"#, nil),
            ("wrong type", #"{"summary":"done","files":"a.swift"}"#, nil),
        ] as [(String, String, DelegatedReport.Failure?)] {
            do {
                _ = try DelegatedReport.value(from: text, contract: contract)
                try Expect.true(false, "\(label) is refused")
            } catch let error as DelegatedReport.Failure {
                if let failure {
                    try Expect.equal(error, failure, label)
                } else if case .contract = error {
                } else {
                    try Expect.true(false, "\(label) fails the contract, not JSON parsing: \(error)")
                }
            }
        }
        return []
    }
}
