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
    case progress(bytesRemaining: Int64?, currentFile: String?)
    case finished(RunOutcome)
}

/// Runs the restic pipeline in the background and reports progress on the main queue.
public final class BackupRunner {
    private let config: Config
    private let secrets: RepositorySecrets
    private let options: PipelineOptions
    private let onEvent: (RunEvent) -> Void

    private let queue = DispatchQueue(label: "net.at6.resticker.runner")
    private let ioQueue = DispatchQueue(label: "net.at6.resticker.io", attributes: .concurrent)
    private let lock = NSLock()
    private var currentProcess: Process?
    private var isCancelled = false

    /// `secrets` are read from the keychain by the caller right before starting a run.
    public init(
        config: Config,
        secrets: RepositorySecrets,
        options: PipelineOptions,
        onEvent: @escaping (RunEvent) -> Void
    ) {
        self.config = config
        self.secrets = secrets
        self.options = options
        self.onEvent = onEvent
    }

    public func start() {
        queue.async { [self] in runPipeline() }
    }

    /// SIGINT lets restic remove its own lock before it exits. SIGKILL is the last resort
    /// and leaves a stale lock, which the unlock step clears on the next run.
    public func cancel() {
        lock.lock()
        isCancelled = true
        let process = currentProcess
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.interrupt()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

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
            case .status(let bytesRemaining, let file):
                self.emit(.progress(bytesRemaining: bytesRemaining, currentFile: file))
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

    // MARK: - Process handling

    private struct ExecutionResult {
        var status: Int32
        var lastError: String?
    }

    private func execute(
        _ step: PipelineStep,
        arguments: [String],
        onLine: ((String) -> Void)? = nil
    ) -> ExecutionResult {
        let process = ResticProcess.make(config: config, secrets: secrets, arguments: [step.rawValue] + arguments)

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        // Starting the process under the lock means `cancel()` either sees the cancel flag
        // here first or finds the process already running; it can never miss it.
        lock.lock()
        if isCancelled {
            lock.unlock()
            return ExecutionResult(status: -1, lastError: "cancelled")
        }
        do {
            try process.run()
            currentProcess = process
            lock.unlock()
        } catch {
            lock.unlock()
            LogFile.shared.write("\(step.rawValue) could not start: \(error.localizedDescription)")
            return ExecutionResult(status: -1, lastError: error.localizedDescription)
        }

        let errorLock = NSLock()
        var lastError: String?
        let group = DispatchGroup()

        ioQueue.async(group: group) {
            readLines(from: output.fileHandleForReading) { line in
                onLine?(line)
                let message = ResticMessage.decode(line: line)
                if case .error(let text)? = message {
                    errorLock.lock()
                    lastError = text
                    errorLock.unlock()
                }
                // Status messages arrive many times a second and would drown the log.
                if case .status? = message { return }
                LogFile.shared.write("[\(step.rawValue)] \(line)")
            }
        }

        ioQueue.async(group: group) {
            readLines(from: errors.fileHandleForReading) { line in
                if let text = ResticMessage.errorText(stderrLine: line) {
                    errorLock.lock()
                    lastError = text
                    errorLock.unlock()
                }
                LogFile.shared.write("[\(step.rawValue)!] \(line)")
            }
        }

        process.waitUntilExit()
        group.wait()

        lock.lock()
        currentProcess = nil
        lock.unlock()

        let status = process.terminationStatus
        LogFile.shared.write("[\(step.rawValue)] exit \(status)")
        errorLock.lock()
        let message = lastError
        errorLock.unlock()
        return ExecutionResult(status: status, lastError: status == 0 ? nil : message)
    }

    private func emit(_ event: RunEvent) {
        DispatchQueue.main.async { self.onEvent(event) }
    }
}

/// Reads a file handle to end of file and hands over complete lines.
private func readLines(from handle: FileHandle, _ emit: (String) -> Void) {
    var buffer = Data()
    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        while let index = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<index)
            buffer.removeSubrange(buffer.startIndex...index)
            if let text = String(data: line, encoding: .utf8) { emit(text) }
        }
    }
    if !buffer.isEmpty, let text = String(data: buffer, encoding: .utf8) { emit(text) }
}
