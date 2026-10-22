import AppKit
import RestickerCore

extension AppDelegate {
    @objc func openRestore(_ sender: Any?) {
        restoreWindowController.show()
    }

    /// Windows make the app a regular one; with the last of them gone it is a menu bar app again.
    func leaveRegularPolicyIfLastWindow(closing: NSWindow?) {
        let others = NSApp.windows.filter {
            $0 !== closing && $0.isVisible && ($0.delegate is SettingsWindowController || $0.delegate is RestoreWindowController)
        }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    func startRestore(snapshotId: String, paths: [String], target: URL) {
        let model = restoreWindowController.model
        guard restoreRunner == nil else { return }
        // The window's Restore button does not know about backups, so say why nothing starts.
        guard runner == nil else {
            model.errorText = "A backup is running. Restore again when it has finished."
            return
        }
        config = ConfigStore.resolveResticIfNeeded()
        guard let secrets = Keychain.readSecrets() else {
            model.finish(RestoreOutcome(result: .failed, message: "could not read the keychain"), target: target)
            return
        }

        beginJob(reason: "restic restore", steps: [])
        model.isCancelling = false
        model.progress.value = nil
        model.run = .running
        let runner = RestoreRunner(config: config, secrets: secrets, snapshotId: snapshotId, target: target.path, paths: paths) {
            [weak self] event in
            self?.handle(restoreEvent: event, target: target)
        }
        restoreRunner = runner
        runner.start()
        updateStatusItem()
        rebuildMenuIfOpen()
    }

    @objc func cancelRestore(_ sender: Any?) {
        guard let restoreRunner else { return }
        restoreRunner.cancel()
        restoreWindowController.model.isCancelling = true
        rebuildMenuIfOpen()
    }

    private func handle(restoreEvent event: RestoreEvent, target: URL) {
        let model = restoreWindowController.model
        switch event {
        case .progress(let value):
            model.progress.value = value
            let shared = BackupProgress(fraction: value.fraction, bytesDone: value.bytesRestored, totalBytes: value.totalBytes)
            progress = shared
            updateStatusItem()
            activityView?.update(progress: shared)

        case .finished(let outcome):
            endJob()
            restoreRunner = nil
            let text = model.finish(outcome, target: target)
            restoreStatusFromHistory()
            // A user's own cancel needs no notification. Neither does a result they are looking at.
            if outcome.result != .cancelled, restoreWindowController.window?.isKeyWindow != true {
                notify(title: "Resticker: restore \(outcome.result == .failed ? "failed" : "finished")", body: text)
            }
            updateStatusItem()
            rebuildMenuIfOpen()
            // Backups that came due during the restore start now.
            startRunIfDue()
        }
    }
}
