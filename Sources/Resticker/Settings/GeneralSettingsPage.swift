import AppKit
import SwiftUI
import ServiceManagement
import RestickerCore

/// Start at login, backup notifications, and the restic binary location.
struct GeneralSettingsPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Form {
            SettingsSection("Startup", pageTitle: "General") {
                SettingsRow(title: "Start at login", hint: startAtLoginHint) {
                    startAtLoginControl
                }
            }

            SettingsSection("Notifications") {
                SettingsRow(
                    title: "Notify on successful backup",
                    hint: "Failed backups always show a notification.",
                    isOn: model.binding(\.notifyOnSuccessfulBackup, actions: actions)
                )
            }

            SettingsSection("restic") {
                SettingsFieldRow(
                    title: "restic binary",
                    hint: "Found automatically. Change it only if you have more than one.",
                    note: resticNotFoundNote
                ) {
                    HStack {
                        CommittedTextField("/opt/homebrew/bin/restic", value: model.config.resticBinaryPath) { newValue in
                            commitBinaryPath(newValue)
                        }
                        Button("Choose…") { chooseResticBinary() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseResticBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the restic binary."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        commitBinaryPath(url.path)
    }

    private func commitBinaryPath(_ newValue: String) {
        model.config.resticBinaryPath = newValue
        // Saved first even when empty, so a re-detect that finds nothing leaves the field
        // empty instead of bringing back the old path.
        actions.save(model.config)
        if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
            actions.redetectRestic()
        }
    }

    private var resticNotFoundNote: RowNote? {
        for problem in model.problems {
            if case .resticNotFound(let path) = problem {
                return .warning(path.isEmpty
                    ? "restic not found. Install it with \u{201c}brew install restic\u{201d}, or choose it above."
                    : "restic not found at \(path).")
            }
        }
        return nil
    }

    private var startAtLoginControl: some View {
        HStack(spacing: 8) {
            if model.loginItemStatus == .requiresApproval {
                Button("Open Login Items…") { actions.openLoginItemsSettings() }
            }
            SettingsSwitch(isOn: Binding(
                get: { model.loginItemStatus == .enabled || model.loginItemStatus == .requiresApproval },
                set: { actions.setStartAtLogin($0) }
            ))
        }
    }

    private var startAtLoginHint: LocalizedStringKey {
        model.loginItemStatus == .requiresApproval
            ? "Needs approval in System Settings \u{203a} Login Items."
            : "Opens Resticker when you log in."
    }
}
