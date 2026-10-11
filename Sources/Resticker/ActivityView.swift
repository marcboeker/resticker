import AppKit
import RestickerCore

/// The geometry of the blocks at the top of the menu: a symbol column, then a text column
/// that the title, the progress bar and every figure below it align to.
private enum Block {
    static let width: CGFloat = 288
    static let inset: CGFloat = 14
    static let symbolSize: CGFloat = 16
    static let textLeading: CGFloat = inset + symbolSize + 8
    static let textWidth: CGFloat = width - textLeading - inset
    static let verticalPadding: CGFloat = 8

    static func headerHeight(_ title: NSView) -> CGFloat {
        verticalPadding + title.fittingSize.height + verticalPadding
    }
}

private extension NSView {
    /// Puts the symbol and the title at the top of a block, and adds `others` as subviews
    /// for the caller to place. The menu stretches the view to its own width.
    func addHeader(icon: NSView, title: NSView, others: [NSView]) {
        autoresizingMask = [.width]
        for view in [icon, title] + others {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Block.inset),
            icon.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Block.symbolSize),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Block.textLeading),
            title.topAnchor.constraint(equalTo: topAnchor, constant: Block.verticalPadding),
        ])
    }
}

/// The state of the app when no run is active: a tinted symbol, a short title, and the
/// detail (an error message, the missing settings) wrapped below it. Errors wrap here,
/// instead of widening the whole menu as a one-line status did.
final class StatusBlockView: NSView {
    init(symbol: String, tone: Tone?, title: String, detail: String? = nil) {
        // The filled symbols have two layers: a white glyph on a disc in the tone's color.
        let icon = NSImageView.symbol(symbol, colors: tone.map { [.white, $0.color] } ?? [.secondaryLabelColor])
        let titleField = NSTextField.singleLineLabel(
            MenuText.styled(title, size: 13, weight: .semibold, color: tone == .bad ? .systemRed : .labelColor))

        var detailField: NSTextField?
        var height = Block.headerHeight(titleField)
        if let detail {
            let field = NSTextField(wrappingLabelWithString: "")
            // Capitalized here, so the callers can pass restic's and the settings' lowercase messages.
            let lines = detail.components(separatedBy: "\n").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            field.attributedStringValue = MenuText.label(lines.joined(separator: "\n"))
            field.preferredMaxLayoutWidth = Block.textWidth
            field.maximumNumberOfLines = 4
            field.cell?.truncatesLastVisibleLine = true
            height += 2 + field.fittingSize.height
            detailField = field
        }

        super.init(frame: NSRect(x: 0, y: 0, width: Block.width, height: ceil(height)))
        addHeader(icon: icon, title: titleField, others: [detailField].compactMap { $0 })
        titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Block.inset).isActive = true
        if let detailField {
            NSLayoutConstraint.activate([
                detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                detailField.widthAnchor.constraint(equalToConstant: Block.textWidth),
                detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// The running pipeline: what it does now, a progress bar, and during the backup step the
/// figures restic reports. `update(progress:)` changes it in place while the menu is open.
final class ActivityView: NSView {
    private let bar = ProgressBar()
    private let percentField = NSTextField.singleLineLabel(NSAttributedString())
    /// The rows only the backup step fills in.
    private struct Figures {
        let amount: NSTextField
        let time: NSTextField
        let file: NSTextField
    }
    private var figures: Figures?

    /// `showsFigures` adds the rows for restic's byte counts and current file. Only the
    /// backup step reports them.
    init(title: String, steps: [PipelineStep], current: PipelineStep?, progress: BackupProgress?, showsFigures: Bool) {
        let icon = NSImageView.symbol("arrow.triangle.2.circlepath", colors: [.controlAccentColor])
        let titleField = NSTextField.singleLineLabel(MenuText.styled(title, size: 13, weight: .semibold))

        var rows: [(view: NSView, gap: CGFloat)] = [(bar, 7)]
        if showsFigures {
            let file = NSTextField.singleLineLabel(MenuText.path(" "))
            file.usesSingleLineMode = true
            file.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let figures = Figures(
                amount: NSTextField.singleLineLabel(MenuText.figure("Reading files…")),
                time: NSTextField.singleLineLabel(MenuText.figure("")),
                file: file
            )
            self.figures = figures
            rows.append((figures.amount, 6))
            rows.append((figures.file, 1))
        }
        if steps.count > 1 {
            rows.append((NSTextField.singleLineLabel(MenuText.steps(steps, current: current)), 7))
        }

        var height = Block.headerHeight(titleField)
        for row in rows {
            height += row.gap + (row.view === bar ? ProgressBar.height : row.view.fittingSize.height)
        }

        super.init(frame: NSRect(x: 0, y: 0, width: Block.width, height: ceil(height)))
        addHeader(icon: icon, title: titleField, others: [percentField] + rows.map(\.view) + (figures.map { [$0.time] } ?? []))
        var constraints = [
            percentField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 8),
            percentField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Block.inset),
            percentField.firstBaselineAnchor.constraint(equalTo: titleField.firstBaselineAnchor),
            bar.heightAnchor.constraint(equalToConstant: ProgressBar.height),
        ]
        var above: NSView = titleField
        for row in rows {
            constraints += [
                row.view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Block.textLeading),
                row.view.topAnchor.constraint(equalTo: above.bottomAnchor, constant: row.gap),
            ]
            // The bar and the file path take the full text column; the amount leaves room
            // for the time at its right.
            if row.view === bar || row.view === figures?.file {
                constraints.append(row.view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Block.inset))
            }
            above = row.view
        }
        if let figures {
            constraints += [
                figures.time.leadingAnchor.constraint(greaterThanOrEqualTo: figures.amount.trailingAnchor, constant: 8),
                figures.time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Block.inset),
                figures.time.firstBaselineAnchor.constraint(equalTo: figures.amount.firstBaselineAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)

        if let progress { update(progress: progress) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(progress: BackupProgress) {
        guard let figures else { return }
        bar.fraction = progress.fraction
        set(percentField, MenuText.percent(progress.fraction.map { "\(Int($0 * 100))%" } ?? ""))

        if let done = progress.bytesDone, let total = progress.totalBytes, total > 0 {
            set(figures.amount, MenuText.figure("\(Formatting.bytes(done)) of \(Formatting.bytes(total))"))
        }
        // restic estimates the time only once its scan has found every file.
        let time = progress.secondsRemaining.map { "\(Formatting.duration(TimeInterval($0))) left" } ?? "Scanning…"
        set(figures.time, MenuText.figure(time))
        if let file = progress.currentFile {
            set(figures.file, MenuText.path((file as NSString).abbreviatingWithTildeInPath))
        }
    }

    /// Called when the menu closes, so the bar does not redraw a window nobody sees.
    func stopAnimating() {
        bar.stopAnimating()
    }

    /// Progress arrives many times a second. Setting an unchanged string still relayouts.
    private func set(_ field: NSTextField, _ text: NSAttributedString) {
        guard field.attributedStringValue != text else { return }
        field.attributedStringValue = text
    }
}

/// A thin rounded bar in the accent color. With a fraction it eases toward it, so the
/// steps between restic's status messages do not jump; without one it sweeps from left
/// to right. It draws from a common-modes timer, because the menu tracks the mouse in
/// its own run loop mode and a default timer would freeze while it is open.
private final class ProgressBar: NSView {
    static let height: CGFloat = 4

    /// 0...1, or nil while the step reports no progress.
    var fraction: Double? {
        didSet {
            guard fraction != oldValue else { return }
            // A menu that opens mid-run shows the current figure at once, not a fill from 0.
            if oldValue == nil, let fraction { shown = fraction }
            startAnimating()
        }
    }

    private var shown: Double = 0
    private var timer: Timer?
    private let sweepStart = Date()
    private let sweepPeriod: TimeInterval = 1.6

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimating() } else { startAnimating() }
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    private func startAnimating() {
        needsDisplay = true
        guard timer == nil, window != nil, !reduceMotion else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if let fraction {
            let distance = fraction - shown
            guard abs(distance) > 0.0005 else {
                // At rest until the next status message restarts the timer.
                shown = fraction
                stopAnimating()
                needsDisplay = true
                return
            }
            shown += distance * 0.15
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        track.fill()
        track.addClip()

        let fill: NSRect
        if let fraction {
            let value = reduceMotion ? fraction : shown
            guard value > 0 else { return }
            // Never narrower than the bar is high, so a small value still reads as a dot.
            fill = NSRect(x: 0, y: 0, width: max(bounds.width * value, bounds.height), height: bounds.height)
        } else if reduceMotion {
            NSColor.controlAccentColor.withAlphaComponent(0.4).setFill()
            track.fill()
            return
        } else {
            let t = Date().timeIntervalSince(sweepStart).truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let length = bounds.width * 0.3
            fill = NSRect(x: -length + (bounds.width + length) * eased, y: 0, width: length, height: bounds.height)
        }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}

private extension NSImageView {
    /// An SF Symbol in the block's symbol column, its layers in `colors`.
    static func symbol(_ name: String, colors: [NSColor]) -> NSImageView {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        return NSImageView(image: image ?? NSImage())
    }
}
