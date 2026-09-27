import AppKit
import RestickerCore

extension AppDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    /// Redraws the open menu, so a snapshot refresh started from its reload button shows
    /// its spinner and then its result without the user reopening the menu.
    func rebuildMenuIfOpen() {
        guard isMenuOpen else { return }
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(header("Resticker (\(appVersion))"))
        menu.addItem(.separator())

        let problems = readinessProblems()
        if !problems.isEmpty {
            for problem in problems {
                menu.addItem(info("Not configured: \(problem.message)"))
            }
            menu.addItem(.separator())
        }

        menu.addItem(detail("Last backup", Formatting.timestamp(state.lastSuccessAt)))
        if state.lastSuccessAt != nil {
            menu.addItem(detail("Transferred", "\(Formatting.bytes(state.lastBytesAdded)) in \(Formatting.duration(state.lastDuration))"))
        }
        menu.addItem(detail("Last cleanup", Formatting.timestamp(state.lastCleanupAt)))
        menu.addItem(detail("Next run", Formatting.timestamp(state.nextDueAt)))
        menu.addItem(detail("Status", statusLine))
        menu.addItem(.separator())

        let snapshotsHeader = NSMenuItem()
        snapshotsHeader.view = SnapshotsHeaderView(
            loading: snapshotsLoading,
            canReload: runner == nil && problems.isEmpty,
            target: self,
            action: #selector(reloadSnapshots(_:))
        )
        menu.addItem(snapshotsHeader)
        if snapshots.isEmpty {
            menu.addItem(info("none yet"))
        } else {
            for snapshot in snapshots {
                menu.addItem(snapshotItem(snapshot))
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

        let log = NSMenuItem(title: "Open Log", action: #selector(openLog(_:)), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// A status row: the label on the left, the value at the menu's right edge.
    private func detail(_ label: String, _ value: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = DetailRowView(label: label, value: value)
        return item
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "main"
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

    /// A snapshot row: the date in bold on the left, the size and the ID at the right edge.
    private func snapshotItem(_ snapshot: Snapshot) -> NSMenuItem {
        let size = snapshot.totalSize.map(Formatting.bytes) ?? "—"
        let item = NSMenuItem()
        item.view = DetailRowView(label: Formatting.timestamp(snapshot.time), value: "\(size)  (\(snapshot.shortId))", boldLabel: true)
        return item
    }

    @objc func reloadSnapshots(_ sender: Any?) {
        // The refresh redraws the menu, which removes the clicked button. Let its action
        // return before that happens.
        DispatchQueue.main.async { self.refreshSnapshots() }
    }

    @objc func openLog(_ sender: Any?) {
        LogWindowController.shared.show()
    }

    @objc func openSettings(_ sender: Any?) {
        settingsWindowController.show()
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

/// The "Recent snapshots:" header with a small reload button at its trailing edge. A view
/// rather than a plain item, so a click reloads without closing the menu. Shows a spinner
/// while a refresh runs.
private final class SnapshotsHeaderView: NSView {
    init(loading: Bool, canReload: Bool, target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        // The menu stretches the view to its own width.
        autoresizingMask = [.width]

        let label = NSTextField(labelWithString: "Recent snapshots:")
        label.font = .menuFont(ofSize: 0)
        label.textColor = .disabledControlTextColor

        let trailing: NSView
        if loading {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            trailing = spinner
        } else {
            let image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload snapshots")!
            let button = NSButton(image: image, target: target, action: action)
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.isEnabled = canReload
            button.toolTip = "Reload snapshots"
            trailing = button
        }

        for view in [label, trailing] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.widthAnchor.constraint(equalToConstant: 16),
            trailing.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// A row with `label` at the leading edge and `value` at the trailing edge, in the same
/// insets as `SnapshotsHeaderView`. A view rather than a plain item: a plain item's title
/// stops short of the menu's right edge, because the menu keeps room there for the key
/// equivalents of other items.
private final class DetailRowView: NSView {
    init(label: String, value: String, boldLabel: Bool = false) {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: boldLabel ? .bold : .regular)
        let valueField = NSTextField(labelWithString: value)
        valueField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        let inset: CGFloat = 14
        let gap: CGFloat = 24
        let width = inset + labelField.fittingSize.width + gap + valueField.fittingSize.width + inset
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(width), height: 24))
        // The menu stretches the view to its own width.
        autoresizingMask = [.width]

        for field in [labelField, valueField] {
            field.textColor = .secondaryLabelColor
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: gap),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            valueField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
