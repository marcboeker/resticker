import AppKit
import ServiceManagement
import SwiftUI
import RestickerCore

/// The "Resticker Settings" window: a `NavigationSplitView` with six pages, System
/// Settings style. Owns the only `SettingsModel` and is the sole writer of `Config` and
/// the keychain on behalf of the UI - pages never touch `ConfigStore`, `Keychain`, or
/// `AppDelegate` directly, only `model` and the `SettingsActions` built here.
///
/// Resticker has no dock icon (`LSUIElement`), so like any accessory app it cannot
/// reliably bring a window to the front or receive key events for it. While this window
/// is open the app switches to a regular activation policy, the same trick
/// `NSApp.setActivationPolicy` documents for menu bar apps that occasionally need a real
/// window; `windowWillClose` switches back.
@MainActor
final class SettingsWindowController: NSWindowController {
    private unowned let appDelegate: AppDelegate
    private let model = SettingsModel()

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Resticker Settings"
        // Lets the sidebar reach the top of the window, like System Settings. The title
        // still names the window in the Window menu; showing it as text too would repeat
        // each page's own bold title right underneath it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let root = SettingsRootView(model: model, actions: makeActions())
        window.contentViewController = NSHostingController(rootView: root)
        // `contentViewController` resizes the window to its ideal size, which for most
        // pages is smaller than the window's opening size; ask for that size back.
        window.setContentSize(NSSize(width: 720, height: 560))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows the window, optionally jumping straight to `page` first - used at launch to
    /// open on whichever page has a configuration problem.
    func show(page: SettingsPage? = nil) {
        if let page { model.selection = page }
        refresh()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Reading state in

    /// Reloads every field from `AppDelegate`, the keychain, and the system. Called when
    /// the window opens and whenever it regains key status, since the user may have
    /// changed the login item or a keychain item outside Resticker meanwhile.
    private func refresh() {
        model.loginItemStatus = SMAppService.mainApp.status
        model.hasPassword = Keychain.hasPassword()
        // Rebuilding the rows gives each a new id, which throws away any row the user is
        // editing, so only rebuild when the keychain holds something else.
        let stored = Keychain.readEnvironment()
        if stored != Self.variables(from: model.environment) {
            model.environment = stored
                .sorted { $0.key < $1.key }
                .map { EnvironmentEntry(name: $0.key, value: $0.value) }
        }
        reloadConfig()
        probe(paths: model.config.sourcePaths)
    }

    /// Re-reads the saved config and re-detects restic if its path no longer works.
    private func reloadConfig() {
        let resolved = ConfigStore.resolveResticIfNeeded()
        appDelegate.config = resolved
        model.config = resolved
        recomputeProblems()
    }

    /// The entries as the keychain stores them: names trimmed, unnamed rows dropped.
    private static func variables(from entries: [EnvironmentEntry]) -> [String: String] {
        var variables: [String: String] = [:]
        for entry in entries {
            let name = entry.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            variables[name] = entry.value
        }
        return variables
    }

    private func recomputeProblems() {
        model.problems = appDelegate.readinessProblems()
    }

    // MARK: - Writing state out

    /// The single path every plain `Config` edit takes: persist it, apply it to the
    /// running app immediately, and recompute which rows show a problem.
    private func save(_ config: Config) {
        appDelegate.applyConfigChange(config)
        model.config = appDelegate.config
        recomputeProblems()
    }

    /// Probes each path off the main thread, since a path under TCC's control blocks on
    /// the system privacy dialog until the user answers it.
    private func probe(paths: [String]) {
        guard !paths.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = paths.map { ($0, SourcePathProbe.isPermissionDenied($0)) }
            DispatchQueue.main.async {
                guard let self else { return }
                // Built locally and assigned once, so observers see one change, not one per path.
                var denied = self.model.deniedSourcePaths
                for (path, isDenied) in results {
                    if isDenied {
                        denied.insert(path)
                    } else {
                        denied.remove(path)
                    }
                }
                if denied != self.model.deniedSourcePaths {
                    self.model.deniedSourcePaths = denied
                }
            }
        }
    }

    private func makeActions() -> SettingsActions {
        SettingsActions(
            save: { [weak self] in self?.save($0) },

            setStartAtLogin: { [weak self] enabled in
                guard let self else { return }
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    LogFile.shared.write("login item change failed: \(error.localizedDescription)")
                }
                // Registering does not always land on .enabled; it may come back
                // .requiresApproval instead, so the status is always re-read.
                self.model.loginItemStatus = SMAppService.mainApp.status
            },
            openLoginItemsSettings: { SMAppService.openSystemSettingsLoginItems() },
            redetectRestic: { [weak self] in self?.reloadConfig() },

            setPassword: { [weak self] password in
                guard let self else { return }
                if Keychain.savePassword(password) {
                    LogFile.shared.write("repository password set via Settings")
                    self.model.hasPassword = true
                    self.recomputeProblems()
                    self.appDelegate.refreshSnapshots()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Could Not Save Password"
                    alert.informativeText = "See the log for details."
                    alert.runModal()
                }
            },
            setEnvironment: { [weak self] entries in
                self?.model.environment = entries
                Keychain.saveEnvironment(Self.variables(from: entries))
            },

            addSourcePaths: { [weak self] paths in
                guard let self else { return }
                let existing = Set(self.model.config.sourcePaths)
                let newPaths = paths.filter { !existing.contains($0) }
                guard !newPaths.isEmpty else { return }
                var config = self.model.config
                config.sourcePaths += newPaths
                self.save(config)
                self.probe(paths: newPaths)
            },
            removeSourcePath: { [weak self] path in
                guard let self else { return }
                var config = self.model.config
                config.sourcePaths.removeAll { $0 == path }
                self.model.deniedSourcePaths.remove(path)
                self.save(config)
            },
            openPrivacySettings: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            },
            testRepository: { [weak self] completion in
                guard let self else { return }
                // A click on a button does not take focus, so an edited Location field would
                // still hold its draft. End editing first and test on the next run loop turn,
                // after the commit has saved the new value.
                self.window?.makeFirstResponder(nil)
                DispatchQueue.main.async { self.testRepository(completion: completion) }
            }
        )
    }

    private func testRepository(completion: @escaping (RepositoryTestResult) -> Void) {
        let config = model.config
        // Only restic and the repository location matter for a test; source paths and
        // the retention policy do not.
        let blocking = config.problems().first {
            if case .resticNotFound = $0 { return true }
            return $0 == .noRepository
        }
        if let problem = blocking {
            completion(.failure(problem.message))
            return
        }
        guard let secrets = Keychain.readSecrets() else {
            completion(.failure(ConfigProblem.noPassword.message))
            return
        }
        RepositoryTester.test(config: config, secrets: secrets, completion: completion)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    /// Ends editing first, so a text field that still has focus commits its draft
    /// instead of losing it when the window closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
