import AppKit
import SwiftUI
import RestickerCore

/// The "Restore" window. Like the Settings window it switches the app to a regular
/// activation policy while it is open, since a menu bar app cannot otherwise bring a
/// window to the front.
@MainActor
final class RestoreWindowController: NSWindowController, NSWindowDelegate {
    private unowned let appDelegate: AppDelegate
    let model = RestoreModel()

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Restore"
        window.contentMinSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: RestoreView(model: model))
        window.setContentSize(NSSize(width: 820, height: 540))

        model.onRestore = { [weak self] in self?.chooseTargetAndRestore() }
        model.onCancel = { [weak appDelegate] in appDelegate?.cancelRestore(nil) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        // A running restore keeps showing its progress, and an open window keeps what the
        // user checked; anything else starts from a fresh list.
        if window?.isVisible != true {
            if model.isRunning {
                model.listExpanded()
            } else {
                model.open(config: appDelegate.config, secrets: Keychain.readSecrets())
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    private func chooseTargetAndRestore() {
        guard let window, let snapshot = model.selectedSnapshot else { return }
        let paths = model.selectedPaths
        guard !paths.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Restore"
        panel.message = "Choose the folder to restore into. Existing files are kept."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let target = panel.url else { return }
            self?.appDelegate.startRestore(snapshotId: snapshot.id, paths: paths, target: target)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelListings()
        appDelegate.leaveRegularPolicyIfLastWindow(closing: window)
    }
}
