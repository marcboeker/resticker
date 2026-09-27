import Foundation

/// Every file the app reads or writes.
public enum Paths {
    public static var stateDirectory: URL {
        home.appendingPathComponent("Library/Application Support/Resticker", isDirectory: true)
    }

    public static var stateFile: URL {
        stateDirectory.appendingPathComponent("state.json")
    }

    private static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Expands a leading tilde. Paths are stored the way a human types them.
    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// The inverse of `expand`, for showing a path the way a human would type it.
    public static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// True for an executable file. `isExecutableFile(atPath:)` alone would accept a
    /// directory: directories are "executable" (traversable) almost always, so a
    /// misconfigured restic path that points at a folder must not count as found.
    public static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }
}
