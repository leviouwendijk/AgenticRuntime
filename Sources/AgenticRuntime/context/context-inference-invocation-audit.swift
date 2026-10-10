import Agentic
import IO
import CryptoKit
import Foundation
import Tokens

public extension Context {
    /// Audit of a prepared frame or a model invocation. No prompt contents are
    /// stored here. A request digest is not a unique invocation identifier.
    struct InferenceAuditEvent: Sendable, Codable, Hashable {
        public enum Stage: String, Sendable, Codable, Hashable {
            case frame_prepared
            case submitted
            case completed
            case failed
        }

        public let id: String
        public let invocationID: String?
        public let stage: Stage
        public let requestSHA256: String
        public let semanticRequestBytes: Int
        public let estimatedInputTokens: Int
        public let workingSetID: String?
        public let frameSHA256: String?
        public let selectedPointers: [Pointer]
        public let skippedAllocationIDs: [String]
        public let history: HistorySelection?
        public let selection: AgentModelSelection?
        public let route: AgentModelRouteRecord?
        public let providerUsage: AgentUsage?
        public let failure: String?
        public let createdAt: Date

        public init(
            invocationID: String? = nil,
            stage: Stage,
            requestSHA256: String,
            semanticRequestBytes: Int,
            estimatedInputTokens: Int,
            workingSetID: String? = nil,
            frameSHA256: String? = nil,
            selectedPointers: [Pointer] = [],
            skippedAllocationIDs: [String] = [],
            history: HistorySelection? = nil,
            selection: AgentModelSelection? = nil,
            route: AgentModelRouteRecord? = nil,
            providerUsage: AgentUsage? = nil,
            failure: String? = nil
        ) {
            self.id = UUID().uuidString
            self.invocationID = invocationID
            self.stage = stage
            self.requestSHA256 = requestSHA256
            self.semanticRequestBytes = semanticRequestBytes
            self.estimatedInputTokens = estimatedInputTokens
            self.workingSetID = workingSetID
            self.frameSHA256 = frameSHA256
            self.selectedPointers = selectedPointers
            self.skippedAllocationIDs = skippedAllocationIDs
            self.history = history
            self.selection = selection
            self.route = route
            self.providerUsage = providerUsage
            self.failure = failure
            self.createdAt = Date()
        }
    }

    protocol InferenceAuditRecording: Sendable {
        func record(_ event: InferenceAuditEvent) async throws
    }

    actor MemoryInferenceAuditStore: InferenceAuditRecording {
        private var records: [InferenceAuditEvent] = []

        public init() {}

        public func record(_ event: InferenceAuditEvent) throws {
            records.append(event)
        }

        public func snapshot() -> [InferenceAuditEvent] {
            records
        }
    }

    /// Append-only JSONL store. The caller provides an authorized file path;
    /// source adapters do not receive filesystem privileges from this store.
    actor FileInferenceAuditStore: InferenceAuditRecording {
        public let fileURL: URL

        public init(fileURL: URL) throws {
            guard fileURL.isFileURL,
                  FileSystem.default.exists(
                    fileURL.deletingLastPathComponent()
                  )
            else {
                throw CocoaError(.fileNoSuchFile)
            }

            if !FileSystem.default.exists(fileURL) {
                var destination = try SystemFileDestination(
                    path: fileURL.path,
                    mode: .create
                )
                try destination.close()
            }

            self.fileURL = fileURL
        }

        public func record(_ event: InferenceAuditEvent) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(event)
            data.append(0x0A)

            var destination = try SystemFileDestination(
                path: fileURL.path,
                mode: .append
            )

            try data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else {
                    return
                }

                var written = 0
                while written < bytes.count {
                    let remaining = UnsafeRawBufferPointer(
                        start: baseAddress.advanced(by: written),
                        count: bytes.count - written
                    )

                    switch try destination.drain(remaining) {
                    case .bytes(let count):
                        written += count.value
                    case .unavailable:
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
            }

            try destination.close()
        }
    }

    /// Stable fingerprint of the provider-neutral request, not wire encoding.
    enum InferenceAuditFingerprint {
        public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        }

        public static func digest(_ data: Data) -> String {
            "sha256:" + SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }

        public static func prepared(_ preparation: InferencePreparation) throws -> InferenceAuditEvent {
            let bytes = try encode(preparation.request)
            let frameBytes = try encode(preparation.frame)
            return InferenceAuditEvent(
                stage: .frame_prepared,
                requestSHA256: digest(bytes),
                semanticRequestBytes: bytes.count,
                estimatedInputTokens: preparation.measurement.estimatedInputTokens,
                workingSetID: preparation.frame.workingSetID,
                frameSHA256: digest(frameBytes),
                selectedPointers: preparation.frame.items.map(\.observed),
                skippedAllocationIDs: preparation.frame.skippedAllocationIDs,
                history: preparation.history
            )
        }
    }

    /// Observe the EXACT semantic AgentModelInvocation received by the invoker.
    /// Does not assert visibility into gateway/provider-specific JSON or bytes.
    struct AuditedModelInvoker: AgentModelInvoking {
        public let wrapped: any AgentModelInvoking
        public let audit: any InferenceAuditRecording

        public init(wrapping wrapped: any AgentModelInvoking, audit: any InferenceAuditRecording) {
            self.wrapped = wrapped
            self.audit = audit
        }

        public func buffered(_ invocation: AgentModelInvocation) async throws -> AgentModelInvocation.Result {
            let id = UUID().uuidString
            let first = try submission(for: invocation, invocationID: id)
            // Fail before invocation if the durable pre-call audit cannot write.
            try await audit.record(first)
            do {
                let result = try await wrapped.buffered(invocation)
                // Post-inference observer errors MUST NOT cause a successful model
                // call to appear failed and accidentally be repeated/billed twice.
                try? await audit.record(completion(for: first, result: result))
                return result
            } catch {
                try? await audit.record(failure(for: first, error: error))
                throw error
            }
        }

        public func stream(_ invocation: AgentModelInvocation) -> AsyncThrowingStream<AgentModelInvocation.Event, Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let id = UUID().uuidString
                        let first = try submission(for: invocation, invocationID: id)
                        try await audit.record(first)
                        for try await event in wrapped.stream(invocation) {
                            if case .completed(let result) = event {
                                try? await audit.record(completion(for: first, result: result))
                            }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }

        private func submission(
            for invocation: AgentModelInvocation,
            invocationID: String
        ) throws -> InferenceAuditEvent {
            let bytes = try InferenceAuditFingerprint.encode(invocation.request)
            let estimate = TokenEstimator.estimate(
                String(decoding: bytes, as: UTF8.self),
                options: .agenticContext,
                source: "context.submitted_agent_request_json"
            )
            return InferenceAuditEvent(
                invocationID: invocationID,
                stage: .submitted,
                requestSHA256: InferenceAuditFingerprint.digest(bytes),
                semanticRequestBytes: bytes.count,
                estimatedInputTokens: estimate.estimatedTokens,
                selection: invocation.selection
            )
        }

        private func completion(
            for first: InferenceAuditEvent,
            result: AgentModelInvocation.Result
        ) -> InferenceAuditEvent {
            InferenceAuditEvent(
                invocationID: first.invocationID,
                stage: .completed,
                requestSHA256: first.requestSHA256,
                semanticRequestBytes: first.semanticRequestBytes,
                estimatedInputTokens: first.estimatedInputTokens,
                selection: first.selection,
                route: result.route,
                providerUsage: result.response.usage ?? result.route.usage
            )
        }

        private func failure(
            for first: InferenceAuditEvent,
            error: any Error
        ) -> InferenceAuditEvent {
            InferenceAuditEvent(
                invocationID: first.invocationID,
                stage: .failed,
                requestSHA256: first.requestSHA256,
                semanticRequestBytes: first.semanticRequestBytes,
                estimatedInputTokens: first.estimatedInputTokens,
                selection: first.selection,
                failure: String(describing: error)
            )
        }
    }
}
