import AppKit
import RestickerCore

/// Shows the in-memory log and appends new lines live while the window is open.
final class LogWindowController: NSWindowController, NSWindowDelegate {
    static let shared = LogWindowController()

    private let textView = NSTextView()
    private var subscription: LogFile.Subscription?
    private let maxCharacters = 5 * 1024 * 1024

    private init() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)

        scrollView.documentView = textView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Resticker Log"
        window.contentView = scrollView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        if subscription == nil {
            textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
            subscription = LogFile.shared.subscribe { [weak self] line in
                self?.append(line)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        subscription = nil
    }

    private func append(_ line: String) {
        guard let storage = textView.textStorage else { return }
        let atBottom = isScrolledToBottom
        storage.append(NSAttributedString(
            string: line + "\n",
            attributes: [.font: textView.font as Any, .foregroundColor: NSColor.textColor]
        ))
        trimIfNeeded(storage)
        if atBottom { textView.scrollToEndOfDocument(nil) }
    }

    /// Mirrors LogFile's own cap so a window left open for a long time doesn't grow without bound.
    private func trimIfNeeded(_ storage: NSTextStorage) {
        guard storage.length > maxCharacters else { return }
        let overflow = storage.length - maxCharacters
        let text = storage.string as NSString
        let searchRange = NSRange(location: overflow, length: text.length - overflow)
        let cut = text.rangeOfCharacter(from: .newlines, range: searchRange)
        let dropLength = cut.location != NSNotFound ? cut.location + cut.length : overflow
        storage.deleteCharacters(in: NSRange(location: 0, length: dropLength))
    }

    private var isScrolledToBottom: Bool {
        guard let scrollView = textView.enclosingScrollView else { return true }
        let visibleMaxY = scrollView.contentView.bounds.maxY
        return visibleMaxY >= textView.bounds.height - 4
    }
}
