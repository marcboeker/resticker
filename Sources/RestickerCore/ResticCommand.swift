import Foundation

/// Runs restic commands one after another and lets another thread cancel them. The backup
/// and the restore runner share it, so the start/cancel race and the pipe reading exist once.
final class ResticCommand {
    struct Result {
        var status: Int32
        /// The last error restic reported. Nil when it exited 0.
        var lastError: String?
    }

    private let config: Config
    private let secrets: RepositorySecrets
    private let ioQueue = DispatchQueue(label: "one.m8n.resticker.io", attributes: .concurrent)
    private let lock = NSLock()
    private var currentProcess: Process?
    private var isCancelled = false

    init(config: Config, secrets: RepositorySecrets) {
        self.config = config
        self.secrets = secrets
    }

    var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    /// SIGINT lets restic remove its own lock before it exits. SIGKILL is the last resort
    /// and leaves a stale lock, which the unlock step clears on the next run.
    func cancel() {
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

    /// Runs `restic <arguments>` to its end. `onLine` gets every line of stdout and stderr,
    /// on background queues.
    func run(_ arguments: [String], onLine: ((String) -> Void)? = nil) -> Result {
        let name = arguments.first ?? "restic"
        let process = ResticProcess.make(config: config, secrets: secrets, arguments: arguments)
        // restic prints a status line as often as 60 times a second by default; the UI needs two.
        process.environment?["RESTIC_PROGRESS_FPS"] = "2"

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        // Starting the process under the lock means `cancel()` either sees the cancel flag
        // here first or finds the process already running; it can never miss it.
        lock.lock()
        if isCancelled {
            lock.unlock()
            return Result(status: -1, lastError: "cancelled")
        }
        do {
            try process.run()
            currentProcess = process
            lock.unlock()
        } catch {
            lock.unlock()
            LogFile.shared.write("\(name) could not start: \(error.localizedDescription)")
            return Result(status: -1, lastError: error.localizedDescription)
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
                LogFile.shared.write("[\(name)] \(line)")
            }
        }

        ioQueue.async(group: group) {
            readLines(from: errors.fileHandleForReading) { line in
                onLine?(line)
                if let text = ResticMessage.errorText(stderrLine: line) {
                    errorLock.lock()
                    lastError = text
                    errorLock.unlock()
                }
                LogFile.shared.write("[\(name)!] \(line)")
            }
        }

        process.waitUntilExit()
        group.wait()

        lock.lock()
        currentProcess = nil
        lock.unlock()

        let status = process.terminationStatus
        LogFile.shared.write("[\(name)] exit \(status)")
        errorLock.lock()
        let message = lastError
        errorLock.unlock()
        return Result(status: status, lastError: status == 0 ? nil : message)
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
