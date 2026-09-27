import Foundation

/// Finds a restic binary the user never pointed the app at, so a fresh install works
/// without a trip to Settings first. `fileExists` and `shellPath` are injectable so tests
/// never touch the real filesystem or spawn a shell.
public enum ResticLocator {
    private static let commonPaths = [
        "/opt/homebrew/bin/restic",
        "/usr/local/bin/restic",
        "/usr/bin/restic",
    ]

    /// Checks the common Homebrew/system locations first, then every directory in the
    /// login shell's `PATH`, since a GUI app inherits none of the user's shell setup.
    /// Returns the first hit that is an executable file, not a directory.
    public static func detect(
        fileExists: (String) -> Bool = Paths.isExecutableFile,
        shellPath: () -> String? = { loginShellPath }
    ) -> String? {
        for path in commonPaths where fileExists(path) {
            return path
        }
        guard let path = shellPath() else { return nil }
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/restic"
            if fileExists(candidate) { return candidate }
        }
        return nil
    }

    /// Read once per launch: `detect` runs on every timer tick while restic is missing, and
    /// a login shell with a heavy profile can take seconds to start.
    @usableFromInline static let loginShellPath = readLoginShellPath()

    /// Runs `$SHELL -l -c 'echo $PATH'` to read PATH the way Terminal sees it, with login
    /// profile scripts applied. A short timeout keeps a misbehaving shell from hanging
    /// app launch; either way that failure just falls back to "restic not found".
    private static func readLoginShellPath() -> String? {
        guard let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        // A login profile can print its own text (a greeting, a tool's notice) before the
        // `echo`, so only the last non-empty line is PATH.
        let lastLine = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return lastLine
    }
}
