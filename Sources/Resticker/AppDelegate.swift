import AppKit
import ServiceManagement
import UserNotifications
import RestickerCore

enum IconState {
    case idle
    case running
    case error
}

enum ToggleKey {
    static let unlock = "unlockEnabled"
    static let cleanup = "cleanupEnabled"
    static let check = "checkEnabled"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()

    var config = Config.default
    private var configModified: Date?
    var state = RunState()

    var runner: BackupRunner?
    private var timer: Timer?
    private var activityToken: NSObjectProtocol?

    var snapshots: [Snapshot] = []
    private var snapshotsLoading = false

    var iconState: IconState = .idle
    var statusLine = "Idle"
    var bytesRemaining: Int64?

    private var currentSymbolName: String?
    private var currentSymbolImage: NSImage?
    private var animationTimer: Timer?
    private var animationStart: Date?
    private let iconRotationPeriod: TimeInterval = 1.4
    private let dotsPulsePeriod: TimeInterval = 1.2

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            ToggleKey.unlock: true,
            ToggleKey.cleanup: true,
            ToggleKey.check: true,
        ])

        loadConfig(force: true)
        state = StateStore.load()
        // The icon state does not persist, so a relaunch must rebuild the error
        // indication from the recorded runs.
        if state.lastRunFailed {
            iconState = .error
            statusLine = state.history.last?.detail ?? "Last backup failed"
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateStatusItem()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error { LogFile.shared.write("notification authorization failed: \(error.localizedDescription)") }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        LogFile.shared.write("resticker started")
        tick()
        refreshSnapshots()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runner?.cancel()
        stopAnimating()
    }

    @objc private func systemDidWake() {
        LogFile.shared.write("system woke up")
        tick()
    }

    // MARK: - Config

    private func loadConfig(force: Bool) {
        let modified = ConfigStore.modificationDate()
        if !force, modified == configModified { return }
        do {
            config = try ConfigStore.load()
            configModified = ConfigStore.modificationDate()
        } catch {
            LogFile.shared.write("config load failed: \(error.localizedDescription)")
            statusLine = "Config error: \(error.localizedDescription)"
            iconState = .error
        }
    }

    /// Reasons a backup cannot start right now. Empty means ready.
    func readinessProblems() -> [String] {
        var problems = config.problems()
        if !Keychain.hasPassword() {
            problems.append("no password in keychain, run: make set-password")
        }
        return problems
    }

    // MARK: - Scheduling

    private func tick() {
        loadConfig(force: false)
        guard runner == nil else { return }
        guard readinessProblems().isEmpty else {
            statusLine = "Not configured"
            iconState = .error
            updateStatusItem()
            return
        }
        updateStatusItem()
        if Schedule.isRunDue(state: state, now: Date()) {
            startRun()
        }
    }

    @objc func backupNow(_ sender: Any?) {
        startRun()
    }

    @objc func cancelBackup(_ sender: Any?) {
        runner?.cancel()
        statusLine = "Cancelling…"
        updateStatusItem()
    }

    func startRun() {
        guard runner == nil else { return }
        let problems = readinessProblems()
        guard problems.isEmpty else {
            statusLine = "Not configured: \(problems.joined(separator: ", "))"
            iconState = .error
            updateStatusItem()
            return
        }
        guard let password = Keychain.readPassword() else {
            statusLine = "Keychain read failed"
            iconState = .error
            updateStatusItem()
            return
        }

        let defaults = UserDefaults.standard
        let options = PipelineOptions(
            unlock: defaults.bool(forKey: ToggleKey.unlock),
            cleanup: defaults.bool(forKey: ToggleKey.cleanup),
            check: defaults.bool(forKey: ToggleKey.check),
            runMaintenance: Schedule.isCleanupDue(state: state, config: config, now: Date())
        )

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "restic backup"
        )

        bytesRemaining = nil
        iconState = .running
        statusLine = "Starting…"
        let backupRunner = BackupRunner(config: config, password: password, options: options) { [weak self] event in
            self?.handle(event)
        }
        runner = backupRunner
        backupRunner.start()
        updateStatusItem()
    }

    // MARK: - Run events

    private func handle(_ event: RunEvent) {
        switch event {
        case .stepStarted(let step):
            bytesRemaining = nil
            statusLine = "Running \(step.title.lowercased())…"
            iconState = .running
            updateStatusItem()

        case .progress(let remaining, _):
            bytesRemaining = remaining
            statusLine = "Running backup…"
            updateStatusItem()

        case .finished(let outcome):
            finish(outcome)
        }
    }

    private func finish(_ outcome: RunOutcome) {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        runner = nil
        bytesRemaining = nil
        let now = Date()

        switch outcome.outcome {
        case .success:
            state = Schedule.afterSuccess(state: state, config: config, now: now)
            state.lastBytesAdded = outcome.summary?.dataAddedPacked ?? 0
            state.lastDuration = outcome.duration
            if outcome.maintenanceAttempted {
                state.lastCleanupAt = now
            }
            if let step = outcome.failedStep {
                let detail = "\(step.title) failed: \(outcome.message ?? "unknown error")"
                statusLine = detail
                iconState = .error
                state.append(RunRecord(date: now, outcome: .success, duration: outcome.duration,
                                       bytesAdded: state.lastBytesAdded, detail: detail))
                notify(title: "Resticker: \(step.title) failed", body: outcome.message ?? "See the log for details.")
            } else {
                statusLine = "Idle"
                iconState = .idle
                state.append(RunRecord(date: now, outcome: .success, duration: outcome.duration,
                                       bytesAdded: state.lastBytesAdded))
                if config.notifyOnSuccess {
                    notify(title: "Resticker: backup finished",
                           body: "\(Formatting.bytes(state.lastBytesAdded)) in \(Formatting.duration(outcome.duration))")
                }
            }
            // Only a run that got this far wrote a snapshot, so only this branch refreshes.
            refreshSnapshots()

        case .failure:
            state = Schedule.afterFailure(state: state, config: config, now: now)
            let step = outcome.failedStep?.title ?? "Backup"
            let detail = "\(step) failed: \(outcome.message ?? "unknown error")"
            statusLine = detail
            iconState = .error
            state.append(RunRecord(date: now, outcome: .failure, duration: outcome.duration,
                                   bytesAdded: 0, detail: detail))
            notify(title: "Resticker: \(step.lowercased()) failed", body: outcome.message ?? "See the log for details.")

        case .cancelled:
            state = Schedule.afterCancel(state: state)
            statusLine = "Idle"
            iconState = .idle
            state.append(RunRecord(date: now, outcome: .cancelled, duration: outcome.duration, bytesAdded: 0))
        }

        StateStore.save(state)
        updateStatusItem()
    }

    /// Refreshes the snapshot list shown in the menu. Runs off the main thread since it
    /// shells out to restic; the menu keeps showing the previous list until this returns.
    /// Skipped while a backup holds the repository lock, since the run refreshes on finish.
    private func refreshSnapshots() {
        // A password that reads back proves the keychain half of readinessProblems().
        guard runner == nil, !snapshotsLoading, config.problems().isEmpty,
              let password = Keychain.readPassword() else { return }
        snapshotsLoading = true
        SnapshotLister.fetch(config: config, password: password, limit: 5) { [weak self] snapshots in
            guard let self else { return }
            self.snapshotsLoading = false
            self.snapshots = snapshots
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Status item

    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        switch iconState {
        case .idle: symbolName = "externaldrive"
        case .running: symbolName = "arrow.triangle.2.circlepath"
        case .error: symbolName = "exclamationmark.triangle"
        }
        if symbolName != currentSymbolName {
            currentSymbolName = symbolName
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Resticker")
            image?.isTemplate = true
            currentSymbolImage = image
        }

        if let remaining = bytesRemaining, remaining > 0 {
            button.title = " \(Formatting.remainingBytes(remaining))"
        } else {
            button.title = ""
        }

        let showDots = iconState == .running && bytesRemaining == nil
        if iconState == .running || showDots {
            startAnimating()
            renderAnimatedFrame()
        } else {
            stopAnimating()
            if iconState == .idle, let icon = currentSymbolImage, isBackupRecent {
                button.image = badgedIcon(icon)
            } else {
                button.image = currentSymbolImage
            }
        }
    }

    /// True when the last successful backup finished less than 24 hours ago.
    private var isBackupRecent: Bool {
        guard let lastSuccessAt = state.lastSuccessAt else { return false }
        return Date().timeIntervalSince(lastSuccessAt) < 24 * 60 * 60
    }

    /// Draws a small checkmark badge over the top right corner of the icon.
    private func badgedIcon(_ icon: NSImage) -> NSImage {
        let size = icon.size
        let composed = NSImage(size: size)
        composed.isTemplate = true
        composed.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        if let checkmark = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
            checkmark.isTemplate = true
            let badgeDiameter = size.height * 0.55
            let badgeRect = NSRect(
                x: size.width - badgeDiameter * 0.75,
                y: size.height - badgeDiameter * 0.75,
                width: badgeDiameter,
                height: badgeDiameter
            )
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            NSBezierPath(ovalIn: badgeRect.insetBy(dx: -0.75, dy: -0.75)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            checkmark.draw(in: badgeRect)
        }
        composed.unlockFocus()
        return composed
    }

    // MARK: - Icon animation

    /// Redraws the icon as a single template bitmap each tick, rotating only the icon
    /// (never the button's title) around its own centerpoint, with pulsing dots drawn
    /// alongside it when the upload size isn't known yet.
    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationStart = Date()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.renderAnimatedFrame()
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationStart = nil
    }

    private func renderAnimatedFrame() {
        guard let button = statusItem?.button, let icon = currentSymbolImage, let start = animationStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        let rotation = iconState == .running
            ? CGFloat((elapsed / iconRotationPeriod * 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi))
            : 0
        let showDots = iconState == .running && bytesRemaining == nil
        button.image = composedIcon(icon, rotation: rotation, dotsElapsed: showDots ? elapsed : nil)
    }

    private func composedIcon(_ icon: NSImage, rotation: CGFloat, dotsElapsed: TimeInterval?) -> NSImage {
        let iconSize = icon.size
        let dotDiameter: CGFloat = 3
        let dotSpacing: CGFloat = 3
        let groupPadding: CGFloat = 4
        let dotsWidth = dotsElapsed != nil ? dotDiameter * 3 + dotSpacing * 2 + groupPadding : 0
        let canvasSize = NSSize(width: iconSize.width + dotsWidth, height: max(iconSize.height, dotDiameter))

        let composed = NSImage(size: canvasSize)
        composed.isTemplate = true
        composed.lockFocus()

        let iconRect = NSRect(x: 0, y: (canvasSize.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
        if rotation != 0, let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            let center = NSPoint(x: iconRect.midX, y: iconRect.midY)
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byRadians: -rotation)
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()
            icon.draw(in: iconRect)
            context.restoreGraphicsState()
        } else {
            icon.draw(in: iconRect)
        }

        if let elapsed = dotsElapsed {
            let dotsOrigin = iconSize.width + groupPadding
            let dotY = (canvasSize.height - dotDiameter) / 2
            for i in 0..<3 {
                let phase = elapsed / dotsPulsePeriod * 2 * .pi - Double(i) * (2 * .pi / 3)
                let alpha = 0.25 + 0.75 * (0.5 + 0.5 * sin(phase))
                NSColor.black.withAlphaComponent(alpha).setFill()
                let x = dotsOrigin + CGFloat(i) * (dotDiameter + dotSpacing)
                NSBezierPath(ovalIn: NSRect(x: x, y: dotY, width: dotDiameter, height: dotDiameter)).fill()
            }
        }

        composed.unlockFocus()
        return composed
    }
}
