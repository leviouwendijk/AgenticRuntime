import Agentic
import AgenticContextWindow

extension AgentLoop {
    func prepareModelRequest(
        from request: AgentRequest,
        checkpoint: AgentExecutor.Checkpoint
    ) async throws -> (request: AgentRequest, preparation: ContextWindow.InferencePreparation?) {
        var prepared = request
        var dynamic: ContextWindow.InferencePreparation?
        if configuration.contextMode == .dynamic {
            guard let allocator = contextAllocator else {
                throw ContextExecutionError.requiresDynamicMode
            }
            let preparation = try await allocator.prepareDynamic(
                request: prepared,
                for: checkpoint.id,
                using: contextServices?.resolver ?? ContextWindow.UnmountedResolver(),
                modelContextLimit: contextServices?.modelContextLimit
                    ?? configuration.contextPolicy.maximumInputTokens
                        + configuration.contextPolicy.reservedOutputTokens,
                compactions: await contextServices?.compactions?.compactions ?? [],
                calibration: await inputCalibration()
            )
            if let audit = contextServices?.audit {
                try await audit.record(
                    ContextWindow.InferenceAuditFingerprint.prepared(preparation)
                )
            }
            prepared = preparation.request
            dynamic = preparation
        }
        for harnessExtension in extensions {
            prepared = try await harnessExtension.prepare(
                request: prepared,
                state: checkpoint.state
            )
        }
        return (prepared, dynamic)
    }

    /// The provider's last count for the model this request will route to.
    func inputCalibration() async -> ContextWindow.InputCalibration? {
        guard let meter = contextServices?.inputMeter,
              let broker = model.invoker as? ModelBroker,
              let routed = try? broker.route(selection: model.selection)
        else {
            return nil
        }
        return await meter.calibration(for: routed.route.profile.model)
    }

    /// Anchors the next request's estimate to what the provider counted
    /// for this one.
    func recordInputCalibration(
        estimated: Int?,
        response: AgentResponse,
        route: AgentModelRouteRecord
    ) async {
        guard let meter = contextServices?.inputMeter,
              let estimated,
              let reported = response.usage?.contextTokens,
              let calibration = ContextWindow.InputCalibration(
                  estimatedTokens: estimated,
                  reportedTokens: reported
              )
        else {
            return
        }
        await meter.record(calibration, for: route.route.profile.model)
    }
}
