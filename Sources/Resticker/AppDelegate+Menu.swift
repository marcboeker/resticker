import AppKit
import RestickerCore

extension AppDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        activityView?.stopAnimating()
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
        let status = NSMenuItem()
        status.view = statusBlock(problems: problems)
        menu.addItem(status)

        menu.addItem(detail("Last backup", timestampValue(state.lastSuccessAt)))
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

        // One of the two at a time: a disabled twin of each would only add noise.
        if runner == nil {
            menu.addItem(actionItem("Back Up Now", #selector(backupNow(_:)), key: "b",
                                    enabled: problems.isEmpty && restoreRunner == nil))
        } else {
            menu.addItem(actionItem("Cancel Backup", #selector(cancelBackup(_:)), key: ".", enabled: !isCancelling))
        }
        if restoreRunner == nil {
            menu.addItem(actionItem("Restore…", #selector(openRestore(_:)), key: "r",
                                    enabled: problems.isEmpty && runner == nil))
        } else {
            menu.addItem(actionItem("Cancel Restore", #selector(cancelRestore(_:)), key: ".",
                                    enabled: !restoreWindowController.model.isCancelling))
        }
        menu.addItem(.separator())

        menu.addItem(actionItem("Open Log", #selector(openLog(_:)), key: ""))
        menu.addItem(actionItem("Settings…", #selector(openSettings(_:)), key: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", #selector(quit(_:)), key: "q"))
    }

    private func actionItem(_ title: String, _ action: Selector, key: String, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        return item
    }

    /// The block at the top of the menu. A running pipeline shows its progress; otherwise
    /// the block says whether the backups are in order, and what to fix if they are not.
    private func statusBlock(problems: [ConfigProblem]) -> NSView {
        if runner != nil || restoreRunner != nil {
            let view = ActivityView(
                title: activityTitle,
                steps: runSteps,
                current: currentStep,
                progress: progress,
                showsFigures: currentStep == .backup && !isCancelling
            )
            activityView = view
            return view
        }
        activityView = nil
        if !problems.isEmpty {
            return StatusBlockView(symbol: "gearshape.circle.fill", tone: .warning, title: "Not configured",
                                   detail: problems.map(\.message).joined(separator: "\n"))
        }
        if iconState == .error, let failure {
            return StatusBlockView(symbol: "exclamationmark.triangle.fill", tone: .bad, title: failure.title, detail: failure.detail)
        }
        if state.lastSuccessAt == nil {
            return StatusBlockView(symbol: "circle.dashed", tone: nil, title: "No backup yet")
        }
        if isBackupRecent {
            return StatusBlockView(symbol: "checkmark.circle.fill", tone: .good, title: "Up to date")
        }
        return StatusBlockView(symbol: "exclamationmark.circle.fill", tone: .warning, title: "Last backup over a day ago")
    }

    private var activityTitle: String {
        if restoreRunner != nil { return restoreWindowController.model.isCancelling ? "Cancelling…" : "Restoring…" }
        if isCancelling { return "Cancelling…" }
        switch currentStep {
        case nil: return "Starting…"
        case .unlock: return "Unlocking repository…"
        case .backup: return "Backing up…"
        case .forget: return "Cleaning up snapshots…"
        case .check: return "Checking repository…"
        }
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
    private func timestampValue(_ date: Date?) -> NSAttributedString {
        guard date != nil else { return MenuText.muted(Formatting.timestamp(nil)) }
        return MenuText.value(Formatting.timestamp(date))
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

extension NSTextField {
    /// `NSTextField(labelWithAttributedString:)` makes a wrapping label, but the menu rows
    /// are one line high. A plain label does not wrap.
    static func singleLineLabel(_ text: NSAttributedString) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = text
        return field
    }
}

/// How the status block should read at a glance, shown as the color of its symbol.
enum Tone {
    case good
    case warning
    case bad

    var color: NSColor {
        switch self {
        case .good: .systemGreen
        case .warning: .systemOrange
        case .bad: .systemRed
        }
    }
}

/// The menu's type scale. Contrast carries the hierarchy: labels are dim, values are
/// bright, and the values that need no reading (absent dates, snapshot IDs) are faint.
enum MenuText {
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

    /// A bright value with tabular digits.
    static func value(_ text: String, weight: NSFont.Weight = .medium) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    static func muted(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    static func code(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }

    /// Headlines, the percentage and the file path of the status block.
    /// `digits` keeps a changing number from jittering.
    static func styled(
        _ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor,
        digits: Bool = false, truncatesMiddle: Bool = false
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: digits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        if truncatesMiddle {
            // Both the root and the file name of a path show.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            attributes[.paragraphStyle] = paragraph
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// The small figures under the progress bar.
    static func figure(_ text: String) -> NSAttributedString {
        styled(text, size: 11, color: .secondaryLabelColor, digits: true)
    }

    static func percent(_ text: String) -> NSAttributedString {
        styled(text, size: 13, weight: .medium, color: .secondaryLabelColor, digits: true)
    }

    static func path(_ text: String) -> NSAttributedString {
        styled(text, size: 11, color: .tertiaryLabelColor, truncatesMiddle: true)
    }

    /// The run's steps in order: done steps dim, the current one bright, later ones faint.
    static func steps(_ steps: [PipelineStep], current: PipelineStep?) -> NSAttributedString {
        let currentIndex = current.flatMap { steps.firstIndex(of: $0) } ?? -1
        let result = NSMutableAttributedString()
        for (index, step) in steps.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ›  ", attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.quaternaryLabelColor,
                ]))
            }
            let color: NSColor = index < currentIndex ? .secondaryLabelColor
                : index == currentIndex ? .labelColor : .tertiaryLabelColor
            result.append(NSAttributedString(string: step.title, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: index == currentIndex ? .semibold : .regular),
                .foregroundColor: color,
            ]))
        }
        return result
    }
}
