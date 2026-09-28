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

        menu.addItem(row(
            MenuText.title("Resticker"),
            MenuText.code(appVersion),
            height: 30
        ))
        menu.addItem(.separator())

        let problems = readinessProblems()
        if !problems.isEmpty {
            for problem in problems {
                menu.addItem(row(MenuText.warning("Not configured: \(problem.message)"), NSAttributedString()))
            }
            menu.addItem(.separator())
        }

        menu.addItem(detail("Status", MenuText.value(statusLine, tone: statusTone)))
        menu.addItem(detail("Last backup", timestampValue(state.lastSuccessAt, tone: lastBackupTone)))
        if state.lastSuccessAt != nil {
            let transferred = MenuText.value(Formatting.bytes(state.lastBytesAdded))
            transferred.append(MenuText.label(" in "))
            transferred.append(MenuText.value(Formatting.duration(state.lastDuration)))
            menu.addItem(detail("Transferred", transferred))
        }
        menu.addItem(detail("Last cleanup", timestampValue(state.lastCleanupAt)))
        menu.addItem(detail("Next run", timestampValue(state.nextDueAt)))
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
            menu.addItem(row(MenuText.muted("None yet"), NSAttributedString()))
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

    /// A status row: the dim label on the left, the bright value at the menu's right edge.
    private func detail(_ label: String, _ value: NSAttributedString) -> NSMenuItem {
        row(MenuText.label(label), value)
    }

    private func row(_ label: NSAttributedString, _ value: NSAttributedString, height: CGFloat = 24) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = DetailRowView(label: label, value: value, height: height)
        return item
    }

    /// "never" is the absence of a value, so it recedes instead of reading like one.
    private func timestampValue(_ date: Date?, tone: Tone? = nil) -> NSAttributedString {
        guard date != nil else { return MenuText.muted(Formatting.timestamp(nil), tone: tone) }
        return MenuText.value(Formatting.timestamp(date), tone: tone)
    }

    private var statusTone: Tone {
        switch iconState {
        case .idle: .good
        case .running: .busy
        case .error: .bad
        }
    }

    /// Green within the day that the menu bar icon shows its check mark for, orange after it.
    private var lastBackupTone: Tone {
        if state.lastSuccessAt == nil { return .bad }
        return isBackupRecent ? .good : .warning
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "main"
    }

    /// A snapshot row: the date in semibold on the left; at the right edge the size, then
    /// the ID in a faint monospaced font, so the column of IDs lines up and stays quiet.
    private func snapshotItem(_ snapshot: Snapshot) -> NSMenuItem {
        let size = MenuText.value(snapshot.totalSize.map(Formatting.bytes) ?? "—")
        size.append(MenuText.code("  \(snapshot.shortId)"))
        return row(MenuText.value(Formatting.timestamp(snapshot.time), weight: .semibold), size)
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

        let label = NSTextField.singleLineLabel(MenuText.section("Recent snapshots"))

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
    init(label: NSAttributedString, value: NSAttributedString, height: CGFloat) {
        let labelField = NSTextField.singleLineLabel(label)
        let valueField = NSTextField.singleLineLabel(value)

        let inset: CGFloat = 14
        let gap: CGFloat = 24
        let width = inset + labelField.fittingSize.width + gap + valueField.fittingSize.width + inset
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(width), height: height))
        // The menu stretches the view to its own width.
        autoresizingMask = [.width]

        for field in [labelField, valueField] {
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

private extension NSTextField {
    /// `NSTextField(labelWithAttributedString:)` makes a wrapping label, but the menu rows
    /// are one line high. A plain label does not wrap.
    static func singleLineLabel(_ text: NSAttributedString) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = text
        return field
    }
}

/// How a menu value should read at a glance, shown as a colored dot before it.
enum Tone {
    case good
    case busy
    case warning
    case bad

    var color: NSColor {
        switch self {
        case .good: .systemGreen
        case .busy: .controlAccentColor
        case .warning: .systemOrange
        case .bad: .systemRed
        }
    }
}

/// The menu's type scale. Contrast carries the hierarchy: labels are dim, values are
/// bright, and the values that need no reading (absent dates, snapshot IDs) are faint.
private enum MenuText {
    static let size: CGFloat = 12

    static func title(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    /// Small caps with wide letter spacing, like a sidebar section heading.
    static func section(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.8,
        ])
    }

    static func label(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    /// A bright value with tabular digits. A tone puts a colored dot before it; a bad tone
    /// also colors the text, because an error must not look like a normal value.
    static func value(_ text: String, weight: NSFont.Weight = .medium, tone: Tone? = nil) -> NSMutableAttributedString {
        let color: NSColor = tone == .bad ? .systemRed : .labelColor
        let result = dot(tone)
        result.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]))
        return result
    }

    static func muted(_ text: String, tone: Tone? = nil) -> NSMutableAttributedString {
        let result = dot(tone)
        result.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]))
        return result
    }

    static func code(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    static func warning(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: "⚠︎ \(text)", attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.systemOrange,
        ])
    }

    private static func dot(_ tone: Tone?) -> NSMutableAttributedString {
        guard let tone else { return NSMutableAttributedString() }
        return NSMutableAttributedString(string: "●  ", attributes: [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: tone.color,
            .baselineOffset: 1.5,
        ])
    }
}
