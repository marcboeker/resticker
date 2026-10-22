import Foundation

/// Which paths of a snapshot to restore, and the `restic restore` arguments for them.
public enum RestoreSelection {
    /// `paths` without the ones that lie inside another selected path, sorted. A selected
    /// folder restores its whole subtree already.
    public static func normalized(_ paths: Set<String>) -> [String] {
        paths.filter { !isCovered($0, by: paths) }.sorted()
    }

    /// True when a proper ancestor of `path` is in `selected`.
    public static func isCovered(_ path: String, by selected: Set<String>) -> Bool {
        var parent = (path as NSString).deletingLastPathComponent
        while parent != "/" && !parent.isEmpty {
            if selected.contains(parent) { return true }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return false
    }

    /// restic reads `--include` as a glob, so a file called `a[1]` or `x*` needs escaping.
    static func escapedPattern(_ path: String) -> String {
        var result = ""
        for character in path {
            if "\\*?[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    /// Existing files are never overwritten. restic keeps the full original path below `target`.
    public static func arguments(snapshotId: String, target: String, paths: [String]) -> [String] {
        ["restore", snapshotId, "--target", target]
            + paths.flatMap { ["--include", escapedPattern($0)] }
            + ["--overwrite", "never", "--json"]
    }
}

public struct RestoreOutcome {
    public enum Result {
        /// restic ran to the end. Individual files can still have failed, see `errorCount`.
        case completed
        case failed
        case cancelled
    }

    public var result: Result
    public var summary: RestoreSummary?
    public var errorCount: Int
    public var message: String?

    public init(result: Result, summary: RestoreSummary? = nil, errorCount: Int = 0, message: String? = nil) {
        self.result = result
        self.summary = summary
        self.errorCount = errorCount
        self.message = message
    }

    /// restic prints the summary only after the last file is restored, and never after it got
    /// SIGINT (it exits 130 without one). So a summary wins over a late Cancel click. Exit 1
    /// with a summary means some files failed but the run reached its end.
    static func result(cancelled: Bool, status: Int32, hasSummary: Bool) -> Result {
        if hasSummary { return .completed }
        if cancelled { return .cancelled }
        return status == 0 ? .completed : .failed
    }
}

public enum RestoreEvent {
    case progress(RestoreProgress)
    case finished(RestoreOutcome)
}

/// Runs one `restic restore` in the background and reports on the main queue.
public final class RestoreRunner {
    private let command: ResticCommand
    private let arguments: [String]
    private let onEvent: (RestoreEvent) -> Void

    public init(
        config: Config,
        secrets: RepositorySecrets,
        snapshotId: String,
        target: String,
        paths: [String],
        onEvent: @escaping (RestoreEvent) -> Void
    ) {
        self.command = ResticCommand(config: config, secrets: secrets)
        self.arguments = RestoreSelection.arguments(snapshotId: snapshotId, target: target, paths: paths)
        self.onEvent = onEvent
    }

    public func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in run() }
    }

    /// Files restored so far stay.
    public func cancel() {
        command.cancel()
    }

    private func run() {
        let stateLock = NSLock()
        var summary: RestoreSummary?
        var errorCount = 0

        let execution = command.run(arguments) { line in
            switch RestoreMessage.decode(line: line) {
            case .status(let progress)?:
                self.emit(.progress(progress))
            case .summary(let value)?:
                stateLock.lock()
                summary = value
                stateLock.unlock()
            case .error?:
                stateLock.lock()
                errorCount += 1
                stateLock.unlock()
            case nil:
                break
            }
        }

        let result = RestoreOutcome.result(cancelled: command.cancelled, status: execution.status,
                                           hasSummary: summary != nil)
        emit(.finished(RestoreOutcome(result: result, summary: summary, errorCount: errorCount,
                                      message: result == .failed ? execution.lastError : nil)))
    }

    private func emit(_ event: RestoreEvent) {
        DispatchQueue.main.async { self.onEvent(event) }
    }
}
