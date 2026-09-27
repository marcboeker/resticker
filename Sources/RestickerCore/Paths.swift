import Foundation

/// Every file the app reads or writes.
public enum Paths {
    public static var configDirectory: URL {
        home.appendingPathComponent(".config/resticker", isDirectory: true)
    }

    public static var configFile: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    public static var stateDirectory: URL {
        home.appendingPathComponent("Library/Application Support/Resticker", isDirectory: true)
    }

    public static var stateFile: URL {
        stateDirectory.appendingPathComponent("state.json")
    }

    private static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Expands a leading tilde. Paths in the config file are written the way a human writes them.
    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
