import Foundation

/// Builds every `restic` invocation the app makes, so the executable path, the global
/// arguments, the environment and the log line stay identical across call sites.
enum ResticProcess {
    /// `arguments` is the subcommand and its own flags; the global config arguments are
    /// prefixed here. The caller still owns the pipes and the waiting.
    static func make(config: Config, password: String, arguments: [String]) -> Process {
        let argv = config.resticGlobalArgs + arguments
        LogFile.shared.write("run: restic \(argv.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.expandedResticBinaryPath)
        process.arguments = argv
        process.environment = environment(config: config, password: password)
        return process
    }

    /// A GUI app inherits a bare PATH, so restic would not find ssh or rclone.
    private static func environment(config: Config, password: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        for (key, value) in config.environmentVariables {
            env[key] = value
        }
        env["RESTIC_REPOSITORY"] = config.repository
        env["RESTIC_PASSWORD"] = password
        return env
    }
}
