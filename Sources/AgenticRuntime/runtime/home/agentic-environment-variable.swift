import Milieu

public enum AgenticEnvironmentVariable: String, EnvironmentExtractable {
    case agentic_home = "AGENTIC_HOME"
    case xdg_config_home = "XDG_CONFIG_HOME"

    public var key: EnvironmentExtractableKey {
        .symbol(rawValue)
    }
}
