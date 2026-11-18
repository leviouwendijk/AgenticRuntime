import AgenticConfiguration
import AgenticContext
import Foundation
import Frame

public extension FrameAgenticModule {
    /// Writes `Agentic.frame`, `Context.frame` and every module the
    /// application's domains declare, such as `Scheduling.frame`.
    @discardableResult
    static func install<Application: AgenticApplicationProviding>(
        for application: Application.Type,
        into directory: URL = Frame.modulesDirectory
    ) throws -> [URL] {
        let declared = (application as? any AgenticFrameModulesProviding.Type)?.frameModules ?? []
        return try ([module, ContextFrame.module] + declared).map { try $0.install(into: directory) }
    }
}

/// An application whose domains read their own `domains/<name>.frame`
/// files; their modules are installed with `Agentic.frame` for editors.
public protocol AgenticFrameModulesProviding: AgenticApplicationProviding {
    static var frameModules: [Frame.Module] { get }
    /// A complete file per domain to start from; `agentic example`
    /// prints them.
    static var frameExamples: [AgenticFrameExample] { get }
}

public extension AgenticFrameModulesProviding {
    static var frameExamples: [AgenticFrameExample] { [] }
}

public extension AgenticFrameExample {
    /// A `context/` file, as `ContextFrame.example` holds it.
    static var context: Self {
        .init(
            name: "context",
            path: "context/business.frame",
            summary: "What agents may know about your world: entries with a summary, tags and a body.",
            text: ContextFrame.example
        )
    }

    /// `settings` and `context` first, then what the application declares.
    static func all<Application: AgenticApplicationProviding>(
        for application: Application.Type
    ) -> [Self] {
        let declared = (application as? any AgenticFrameModulesProviding.Type)?.frameExamples ?? []
        return [settings, context] + declared
    }
}
