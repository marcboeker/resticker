import AppKit
import ServiceManagement
import RestickerCore

extension AppDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(header("Resticker"))
        menu.addItem(.separator())

        let problems = readinessProblems()
        if !problems.isEmpty {
            for problem in problems {
                menu.addItem(info("Not configured: \(problem)"))
            }
            menu.addItem(.separator())
        }

        menu.addItem(info("Last backup:   \(Formatting.timestamp(state.lastSuccessAt))"))
        if state.lastSuccessAt != nil {
            menu.addItem(info("Transferred:   \(Formatting.bytes(state.lastBytesAdded)) in \(Formatting.duration(state.lastDuration))"))
        }
        menu.addItem(info("Last cleanup:  \(Formatting.timestamp(state.lastCleanupAt))"))
        menu.addItem(info("Next run:      \(Formatting.timestamp(state.nextDueAt))"))
        menu.addItem(info("Status:        \(statusLine)"))
        menu.addItem(.separator())

        menu.addItem(header("Recent snapshots:"))
        if snapshots.isEmpty {
            menu.addItem(info("none yet"))
        } else {
            for snapshot in snapshots {
                let size = snapshot.totalSize.map(Formatting.bytes) ?? "—"
                menu.addItem(info("\(Formatting.timestamp(snapshot.time))   \(snapshot.shortId)   \(size)"))
            }
        }
        menu.addItem(.separator())

        let backup = NSMenuItem(title: "Back Up Now", action: #selector(backupNow(_:)), keyEquivalent: "b")
        backup.target = self
        backup.isEnabled = runner == nil && problems.isEmpty
        menu.addItem(backup)

        let cancel = NSMenuItem(title: "Cancel Backup", action: #selector(cancelBackup(_:)), keyEquivalent: "")
        cancel.target = self
        cancel.isEnabled = runner != nil
        menu.addItem(cancel)
        menu.addItem(.separator())

        menu.addItem(header("Every run:"))
        menu.addItem(toggle("  Unlock before backup", key: ToggleKey.unlock, action: #selector(toggleUnlock(_:))))
        menu.addItem(header("Once a day:"))
        menu.addItem(toggle("  Cleanup (forget --prune)", key: ToggleKey.cleanup, action: #selector(toggleCleanup(_:))))
        menu.addItem(toggle("  Check", key: ToggleKey.check, action: #selector(toggleCheck(_:))))
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let log = NSMenuItem(title: "Open Log", action: #selector(openLog(_:)), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        let edit = NSMenuItem(title: "Edit Config", action: #selector(editConfig(_:)), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)]
        )
        return item
    }

    private func toggle(_ title: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        return item
    }

    @objc func toggleUnlock(_ sender: Any?) { flip(ToggleKey.unlock) }
    @objc func toggleCleanup(_ sender: Any?) { flip(ToggleKey.cleanup) }
    @objc func toggleCheck(_ sender: Any?) { flip(ToggleKey.check) }

    private func flip(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: key), forKey: key)
    }

    @objc func toggleStartAtLogin(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                LogFile.shared.write("login item removed")
            } else {
                try SMAppService.mainApp.register()
                LogFile.shared.write("login item registered")
            }
        } catch {
            LogFile.shared.write("login item change failed: \(error.localizedDescription)")
        }
    }

    @objc func openLog(_ sender: Any?) {
        LogWindowController.shared.show()
    }

    @objc func editConfig(_ sender: Any?) {
        if !FileManager.default.fileExists(atPath: Paths.configFile.path) {
            try? ConfigStore.writeExample()
        }
        openInTextEditor(Paths.configFile)
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    /// `open -t` uses the default plain text editor instead of whatever claims the file type.
    private func openInTextEditor(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", url.path]
        try? process.run()
    }
}
