import Foundation

public enum PipelineStep: String {
    case unlock
    case backup
    case forget
    case check

    public var title: String {
        switch self {
        case .unlock: return "Unlock"
        case .backup: return "Backup"
        case .forget: return "Cleanup"
        case .check: return "Check"
        }
    }
}

public struct PipelineOptions {
    public var unlock: Bool
    public var cleanup: Bool
    public var check: Bool
    /// True when the once a day maintenance window is open.
    public var runMaintenance: Bool

    public init(unlock: Bool, cleanup: Bool, check: Bool, runMaintenance: Bool) {
        self.unlock = unlock
        self.cleanup = cleanup
        self.check = check
        self.runMaintenance = runMaintenance
    }

    /// The steps a run with these options goes through when none of them fails.
    public var steps: [PipelineStep] {
        var steps: [PipelineStep] = unlock ? [.unlock, .backup] : [.backup]
        if runMaintenance && cleanup { steps.append(.forget) }
        if runMaintenance && check { steps.append(.check) }
        return steps
    }
}

public struct RunOutcome {
    public var outcome: RunRecord.Outcome
    public var summary: BackupSummary?
    public var failedStep: PipelineStep?
    public var message: String?
    public var duration: TimeInterval
    /// True when the maintenance steps ran to an end, passed or failed. False when they
    /// were skipped or the user cancelled them.
    public var maintenanceAttempted: Bool
}

public enum RunEvent {
    case stepStarted(PipelineStep)
    case progress(BackupProgress)
    case finished(RunOutcome)
}

/// Runs the restic pipeline in the background and reports progress on the main queue.
public final class BackupRunner {
    private let config: Config
    private let options: PipelineOptions
    private let onEvent: (RunEvent) -> Void

    private let queue = DispatchQueue(label: "one.m8n.resticker.runner")
    private let command: ResticCommand

    /// `secrets` are read from the keychain by the caller right before starting a run.
    public init(
        config: Config,
        secrets: RepositorySecrets,
        options: PipelineOptions,
        onEvent: @escaping (RunEvent) -> Void
    ) {
        self.config = config
        self.options = options
        self.onEvent = onEvent
        self.command = ResticCommand(config: config, secrets: secrets)
    }

    public func start() {
        queue.async { [self] in runPipeline() }
    }

    /// Files restic already uploaded stay in the repository; a stale lock left by a hard
    /// kill is cleared by the unlock step on the next run.
    public func cancel() {
        command.cancel()
    }

    private var cancelled: Bool { command.cancelled }

    // MARK: - Pipeline

    private func runPipeline() {
        let began = Date()
        var summary: BackupSummary?

        func finish(_ outcome: RunRecord.Outcome, step: PipelineStep?, message: String?, maintenance: Bool) {
            let result = RunOutcome(
                outcome: outcome,
                summary: summary,
                failedStep: step,
                message: message,
                duration: Date().timeIntervalSince(began),
                maintenanceAttempted: maintenance
            )
            emit(.finished(result))
        }

        if options.unlock {
            emit(.stepStarted(.unlock))
            let result = execute(.unlock, arguments: config.resticUnlockArgs)
            if cancelled { return finish(.cancelled, step: nil, message: nil, maintenance: false) }
            if result.status != 0 {
                return finish(.failure, step: .unlock, message: result.lastError, maintenance: false)
            }
        }

        emit(.stepStarted(.backup))
        var backupArguments = config.resticBackupArgs + ["--json"]
        if let excludeFile = config.expandedExcludeFile, FileManager.default.fileExists(atPath: excludeFile) {
            backupArguments += ["--exclude-file", excludeFile]
        }
        backupArguments += config.expandedSourcePaths

        let backup = execute(.backup, arguments: backupArguments) { line in
            switch ResticMessage.decode(line: line) {
            case .status(let progress):
                self.emit(.progress(progress))
            case .summary(let value):
                summary = value
            default:
                break
            }
        }

        if cancelled { return finish(.cancelled, step: nil, message: nil, maintenance: false) }
        // Unreadable source files (exit 3) are common and not shown; restic's stderr lines
        // naming them are in the log.
        if !BackupRunner.snapshotWritten(backupStatus: backup.status) {
            return finish(.failure, step: .backup, message: backup.lastError, maintenance: false)
        }

        // The backup succeeded. Maintenance failures from here on never cause a backup retry.
        // A cancel keeps the backup's success but reports the maintenance as not attempted,
        // so it is not recorded as done.
        guard options.runMaintenance, options.cleanup || options.check else {
            return finish(.success, step: nil, message: nil, maintenance: false)
        }

        if options.cleanup {
            emit(.stepStarted(.forget))
            let result = execute(.forget, arguments: config.forgetArgs)
            if cancelled { return finish(.success, step: nil, message: nil, maintenance: false) }
            if result.status != 0 {
                return finish(.success, step: .forget, message: result.lastError, maintenance: true)
            }
        }

        if options.check {
            emit(.stepStarted(.check))
            let result = execute(.check, arguments: config.resticCheckArgs)
            if cancelled { return finish(.success, step: nil, message: nil, maintenance: false) }
            if result.status != 0 {
                return finish(.success, step: .check, message: result.lastError, maintenance: true)
            }
        }

        finish(.success, step: nil, message: nil, maintenance: true)
    }

    /// restic exits 3 when it wrote the snapshot but could not read some source files,
    /// for example files that macOS privacy protection blocks. That snapshot is kept.
    static func snapshotWritten(backupStatus status: Int32) -> Bool {
        status == 0 || status == 3
    }

    private func execute(
        _ step: PipelineStep,
        arguments: [String],
        onLine: ((String) -> Void)? = nil
    ) -> ResticCommand.Result {
        command.run([step.rawValue] + arguments, onLine: onLine)
    }

    private func emit(_ event: RunEvent) {
        DispatchQueue.main.async { self.onEvent(event) }
    }
}
