import Foundation

/// Builds every `restic` invocation the app makes, so the executable path, the global
/// arguments, the environment and the log line stay identical across call sites.
enum ResticProcess {
    /// `arguments` is the subcommand and its own flags; the global config arguments are
    /// prefixed here. `secrets` is whatever the caller read from the keychain right before
    /// this run; the caller still owns the pipes and the waiting.
    static func make(config: Config, secrets: RepositorySecrets, arguments: [String]) -> Process {
        let argv = config.resticGlobalArgs + arguments
        LogFile.shared.write("run: restic \(argv.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.expandedResticBinaryPath)
        process.arguments = argv
        process.environment = buildEnvironment(config: config, secrets: secrets)
        return process
    }

    /// A GUI app inherits a bare PATH, so restic would not find ssh or rclone.
    private static func buildEnvironment(config: Config, secrets: RepositorySecrets) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extraPath + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        for (key, value) in secrets.environment {
            env[key] = value
        }
        env["RESTIC_REPOSITORY"] = config.repository
        env["RESTIC_PASSWORD"] = secrets.password
        return env
    }
}
