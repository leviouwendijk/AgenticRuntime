import Agentic
import AgenticContext

public extension ToolServices {
    /// The owner's `.always` context entries as a system message; nil
    /// without a `Context.Store` service or without such entries. Read on
    /// every run, so an entry saved mid-session reaches the next one.
    var contextEntryMessage: Message? {
        guard let store = try? require(Context.Store.self),
              let instructions = store.library().instructions
        else {
            return nil
        }
        return Message(role: .system, text: instructions)
    }
}
