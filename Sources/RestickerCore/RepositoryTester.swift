import Foundation

public enum RepositoryTestResult: Equatable {
    case success
    case failure(String)
}

/// Checks that restic can reach the repository and open it with the password, for the
/// Test button in Settings. Runs `restic cat config`: it needs the same access and
/// decryption as a backup but only reads, unlike `unlock`, which deletes stale locks.
public enum RepositoryTester {
    /// An unreachable sftp host can make restic wait for a long time.
    static let timeout: TimeInterval = 60

    public static func test(
        config: Config,
        secrets: RepositorySecrets,
        completion: @escaping (RepositoryTestResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = run(config: config, secrets: secrets)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func run(config: Config, secrets: RepositorySecrets) -> RepositoryTestResult {
        let process = ResticProcess.make(config: config, secrets: secrets, arguments: ["cat", "config"])
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return .failure("restic could not start: \(error.localizedDescription)")
        }
        var timedOut = false
        let deadline = DispatchWorkItem {
            timedOut = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        deadline.cancel()

        if timedOut {
            return .failure("No answer from the repository after \(Int(timeout)) seconds.")
        }
        let result = interpret(status: process.terminationStatus, stderr: stderr)
        LogFile.shared.write("repository test: \(result)")
        return result
    }

    /// restic 0.17 and later exit with 10 for a missing repository and 12 for a wrong
    /// password. Other failures are summarized from restic's error output.
    static func interpret(status: Int32, stderr: String) -> RepositoryTestResult {
        switch status {
        case 0:
            return .success
        case 10:
            return .failure("No repository exists at this location. Create one with `restic init`.")
        case 12:
            return .failure("Wrong password for this repository.")
        default:
            return .failure(summarize(stderr: stderr) ?? "restic exited with status \(status).")
        }
    }

    /// For sftp, restic's last line only says the session failed ("error receiving version
    /// packet"); the cause is in an earlier line that restic copies from ssh, so that line
    /// wins. Otherwise the last line is used, without the "Fatal: " prefix and without the
    /// repository location, which the Location field already shows.
    static func summarize(stderr: String) -> String? {
        let lines = stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let sshPrefix = "subprocess ssh: "
        if var cause = lines.last(where: { $0.hasPrefix(sshPrefix) }) {
            cause.removeFirst(sshPrefix.count)
            if cause.hasPrefix("ssh: ") { cause.removeFirst("ssh: ".count) }
            return "SSH failed: \(cause)"
        }

        guard var message = lines.last else { return nil }
        if message.hasPrefix("Fatal: ") {
            message.removeFirst("Fatal: ".count)
        }
        // "unable to open repository at sftp:user@host:/path: reason" -> "unable to open repository: reason"
        message = message.replacingOccurrences(
            of: #"^(unable to open repository) at .+?: "#, with: "$1: ", options: .regularExpression
        )
        return message.prefix(1).uppercased() + message.dropFirst()
    }
}
