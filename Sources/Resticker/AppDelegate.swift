import AppKit
import UserNotifications
import RestickerCore

enum IconState {
    case idle
    case running
    case error
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()

    var config = Config.default
    var state = RunState()

    /// Created lazily so it captures `self` only once the app has finished setting up.
    lazy var settingsWindowController = SettingsWindowController(appDelegate: self)

    var runner: BackupRunner?
    /// Set when the user denied the keychain dialog. Each scheduled run (and each snapshot
    /// refresh) would show that dialog again, so they wait until "Back up now" or a
    /// password saved in Settings clears it.
    private var keychainDenied = false
    private var timer: Timer?
    private var activityToken: NSObjectProtocol?

    var snapshots: [Snapshot] = []
    private(set) var snapshotsLoading = false
    private var snapshotsRefreshPending = false
    /// Set between `menuWillOpen` and `menuDidClose`, so a snapshot refresh that finishes
    /// while the menu is open can redraw it in place.
    var isMenuOpen = false

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
        config = ConfigStore.resolveResticIfNeeded()
        state = StateStore.load()
        // The icon state does not persist, so a relaunch must rebuild the error
        // indication from the recorded runs.
        restoreStatusFromHistory()

        NSApp.mainMenu = MainMenu.make()

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
            // Timer's closure type predates Swift concurrency and isn't itself
            // @MainActor, but Timer always fires on the run loop it was scheduled on -
            // the main one, here - so this really is already on the main actor.
            MainActor.assumeIsolated { self?.tick() }
        }
        LogFile.shared.write("resticker started")
        tick()
        refreshSnapshots()

        // First run, or a config that lost its restic/repository/password since the last
        // launch: send the user straight to the page that explains why, instead of a menu
        // that just says "Not configured".
        let problems = readinessProblems()
        if let firstProblemPage = SettingsPage.allCases.first(where: { page in problems.contains { $0.page == page } }) {
            settingsWindowController.show(page: firstProblemPage)
        }
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

    /// Reasons a backup cannot start right now. Empty means ready.
    func readinessProblems() -> [ConfigProblem] {
        var problems = config.problems()
        if !Keychain.hasPassword() {
            problems.append(.noPassword)
        }
        return problems
    }

    // MARK: - Scheduling

    private func tick() {
        // Picks up anything Settings saved, and re-resolves restic if it moved or was
        // installed since the last tick.
        config = ConfigStore.resolveResticIfNeeded()
        startRunIfDue()
    }

    /// Refreshes the idle/error status from the current `config`, then starts a backup if
    /// one is due and nothing blocks it. Shared by `tick()` and `applyConfigChange`.
    private func startRunIfDue() {
        guard runner == nil else { return }
        guard readinessProblems().isEmpty else {
            statusLine = "Not configured"
            iconState = .error
            updateStatusItem()
            return
        }
        guard !keychainDenied else {
            statusLine = Self.keychainDeniedStatus
            iconState = .error
            updateStatusItem()
            return
        }
        updateStatusItem()
        if Schedule.isRunDue(state: state, now: Date()) {
            startRun()
        }
    }

    /// Called by the Settings window after every save it makes, so an edit takes effect
    /// right away instead of waiting for the next minute's timer tick. A backup already
    /// running keeps using the config it started with; only the next run sees this one.
    func applyConfigChange(_ newConfig: Config) {
        ConfigStore.save(newConfig)
        let intervalChanged = newConfig.backupIntervalMinutes != config.backupIntervalMinutes
        let repositoryChanged = newConfig.repository != config.repository
        config = newConfig
        if intervalChanged {
            state = Schedule.afterIntervalChange(state: state, config: config)
            StateStore.save(state)
        }
        if repositoryChanged {
            // The listed snapshots belong to the old repository.
            snapshots = []
            refreshSnapshots()
        }
        startRunIfDue()
    }

    @objc func backupNow(_ sender: Any?) {
        // The user asked, so showing the keychain dialog again is fine.
        keychainDenied = false
        startRun()
    }

    private static let keychainDeniedStatus = "Keychain access denied — click Back up now to retry"

    /// Called by the Settings window after it saved a new repository password. The app
    /// wrote that item itself, so reading it back does not show the dialog the user denied.
    func passwordSaved() {
        guard keychainDenied else { return }
        keychainDenied = false
        restoreStatusFromHistory()
        startRunIfDue()
    }

    /// Shows the last recorded run's error, or idle when it passed.
    private func restoreStatusFromHistory() {
        if state.lastRunFailed {
            iconState = .error
            statusLine = state.history.last?.detail ?? "Last backup failed"
        } else {
            iconState = .idle
            statusLine = "Idle"
        }
    }

    @objc func cancelBackup(_ sender: Any?) {
        guard let runner else { return }
        runner.cancel()
        statusLine = "Cancelling…"
        updateStatusItem()
    }

    func startRun() {
        guard runner == nil else { return }
        config = ConfigStore.resolveResticIfNeeded()
        let problems = readinessProblems()
        guard problems.isEmpty else {
            statusLine = "Not configured: \(problems.map(\.message).joined(separator: ", "))"
            iconState = .error
            updateStatusItem()
            return
        }
        let secrets: RepositorySecrets
        switch Keychain.readSecretsResult() {
        case .success(let value):
            secrets = value
        case .failure(let error):
            keychainDenied = error == .denied
            statusLine = keychainDenied ? Self.keychainDeniedStatus : "Keychain read failed"
            iconState = .error
            updateStatusItem()
            return
        }

        let options = PipelineOptions(
            unlock: config.unlockEnabled,
            cleanup: config.forgetEnabled,
            check: config.checkEnabled,
            runMaintenance: Schedule.isCleanupDue(state: state, config: config, now: Date())
        )

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "restic backup"
        )

        bytesRemaining = nil
        iconState = .running
        statusLine = "Starting…"
        let backupRunner = BackupRunner(
            config: config,
            secrets: secrets,
            options: options
        ) { [weak self] event in
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
                state = Schedule.afterMaintenance(state: state, failedStep: outcome.failedStep, now: now)
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
                if config.notifyOnSuccessfulBackup {
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
    /// A request that arrives while a fetch runs is remembered and served when it returns,
    /// since the repository, password or snapshots may have changed since it started.
    func refreshSnapshots() {
        if snapshotsLoading {
            snapshotsRefreshPending = true
            return
        }
        // Secrets that read back prove the keychain half of readinessProblems().
        guard runner == nil, !keychainDenied, config.problems().isEmpty else { return }
        let secrets: RepositorySecrets
        switch Keychain.readSecretsResult() {
        case .success(let value):
            secrets = value
        case .failure(let error):
            keychainDenied = error == .denied
            return
        }
        snapshotsLoading = true
        rebuildMenuIfOpen()
        let repository = config.repository
        SnapshotLister.fetch(config: config, secrets: secrets, limit: 5) { [weak self] snapshots in
            guard let self else { return }
            self.snapshotsLoading = false
            // Snapshots of a repository that Settings replaced meanwhile must not show.
            if repository == self.config.repository {
                self.snapshots = snapshots
            }
            self.rebuildMenuIfOpen()
            if self.snapshotsRefreshPending {
                self.snapshotsRefreshPending = false
                self.refreshSnapshots()
            }
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
    var isBackupRecent: Bool {
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
            MainActor.assumeIsolated { self?.renderAnimatedFrame() }
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
