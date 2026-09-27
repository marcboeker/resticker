import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RestickerCore

/// Source paths, the exclude file, and the two flags that run alongside every backup.
struct BackupSettingsPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Form {
            SettingsSection("Sources", pageTitle: "Backup") {
                SettingsRow(
                    title: "Source paths",
                    hint: "Files and folders to back up. You can also drag them in from Finder.",
                    note: model.problems.contains(.noSourcePaths) ? .warning("Add at least one source path.") : nil
                ) {
                    Button("Add…") { chooseSourcePaths() }
                }
                ForEach(model.config.sourcePaths, id: \.self) { path in
                    sourcePathRow(path)
                }
            }

            SettingsSection("Options") {
                SettingsFieldRow(
                    title: "Exclude file",
                    hint: "Patterns to skip, passed as `--exclude-file`. Leave empty to turn it off."
                ) {
                    HStack {
                        CommittedTextField("~/.resticignore", value: model.config.excludeFile,
                                           commit: model.commit(\.excludeFile, actions: actions))
                        Button("Choose…") { chooseExcludeFile() }
                    }
                }
                SettingsRow(
                    title: "Unlock before backup",
                    hint: "Runs restic unlock first, to clear a lock left by a crashed run.",
                    isOn: model.binding(\.unlockEnabled, actions: actions)
                )
                SettingsFieldRow(title: "Unlock args", hint: "Extra arguments for restic unlock.") {
                    ArgsField(model: model, keyPath: \.resticUnlockArgs, actions: actions)
                }
                .disabled(!model.config.unlockEnabled)
                SettingsFieldRow(
                    title: "Backup args",
                    hint: "Extra arguments for restic backup, such as `--exclude` or `--tag`."
                ) {
                    ArgsField(model: model, keyPath: \.resticBackupArgs, actions: actions)
                }
            }
        }
        .formStyle(.grouped)
        // A grouped `Form` has no per-section drop target, so the whole page takes drops.
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private func sourcePathRow(_ path: String) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(Paths.abbreviate(path))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.deniedSourcePaths.contains(path) {
                    RowNote.warning("Resticker cannot read this folder.")
                }
            }
            Spacer()
            if model.deniedSourcePaths.contains(path) {
                Button("Open Privacy Settings…") { actions.openPrivacySettings() }
            }
            RemoveButton(help: "Remove this path") { actions.removeSourcePath(path) }
        }
    }

    private func chooseSourcePaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders to back up."
        guard panel.runModal() == .OK else { return }
        actions.addSourcePaths(panel.urls.map(\.path))
    }

    private func chooseExcludeFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an exclude file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.config.excludeFile = url.path
        actions.save(model.config)
    }

    /// Standard SwiftUI file-drop decoding: a dropped Finder item arrives as the raw bytes
    /// of a file URL, not as a `URL` object.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    actions.addSourcePaths([url.path])
                }
            }
        }
        return true
    }
}
