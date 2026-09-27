import SwiftUI
import RestickerCore

/// The restic repository location, its password, and any extra environment variables a
/// cloud backend needs (S3 credentials and the like).
struct RepositorySettingsPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    @State private var showingPasswordSheet = false
    @State private var testState = TestState.idle

    private enum TestState: Equatable {
        case idle
        case running
        case finished(RepositoryTestResult)
    }

    private var testNote: RowNote? {
        switch testState {
        case .idle, .running: return nil
        case .finished(.success): return .success("Repository opened.")
        case .finished(.failure(let message)): return .failure(message)
        }
    }

    var body: some View {
        Form {
            SettingsSection("Repository", pageTitle: "Repository") {
                SettingsFieldRow(
                    title: "Location",
                    hint: "A local path or a restic backend URL.",
                    note: model.problems.contains(.noRepository) ? .warning("Set a repository location.") : nil,
                    examples: [
                        "/Volumes/Backup/restic",
                        "sftp:user@host:/path",
                        "s3:https://s3.amazonaws.com/bucket",
                        "rest:https://host:8000/",
                    ]
                ) {
                    CommittedTextField("sftp:user@host:/srv/restic", value: model.config.repository,
                                       commit: model.commit(\.repository, actions: actions))
                }

                SettingsRow(
                    title: "Password",
                    hint: "Kept in the keychain. Never shown again once set.",
                    note: model.problems.contains(.noPassword) ? .warning("Set a password before Resticker can back up.") : nil
                ) {
                    HStack {
                        Text(model.hasPassword ? "Stored in Keychain" : "Not set")
                            .foregroundStyle(.secondary)
                        Button(model.hasPassword ? "Change…" : "Set…") { showingPasswordSheet = true }
                    }
                }

                SettingsRow(
                    title: "Test repository",
                    hint: "Opens the repository with the settings on this page. Changes nothing.",
                    note: testNote
                ) {
                    HStack {
                        if testState == .running {
                            ProgressView().controlSize(.small)
                        }
                        Button("Test") {
                            testState = .running
                            actions.testRepository { testState = .finished($0) }
                        }
                        .disabled(testState == .running)
                    }
                }
            }

            SettingsSection("Environment") {
                SettingsRow(
                    title: "Environment variables",
                    hint: "Extra variables restic needs, such as cloud credentials. [Reference](https://restic.readthedocs.io/en/stable/075_scripting.html#environment-variables)"
                ) {
                    Button("Add") {
                        model.environment.append(EnvironmentEntry(name: "", value: ""))
                    }
                }
                environmentTable
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingPasswordSheet) {
            PasswordSheet { password in
                actions.setPassword(password)
                showingPasswordSheet = false
            } cancel: {
                showingPasswordSheet = false
            }
        }
    }

    /// One row per variable: name, masked value, and its own remove button. Both fields save
    /// on commit, like every other text field in Settings.
    private var environmentTable: some View {
        ForEach(model.environment) { entry in
            HStack {
                CommittedTextField("NAME", value: entry.name) { update(entry, \.name, to: $0) }
                    .font(.body.monospaced())
                    .frame(width: 200)
                CommittedTextField("value", value: entry.value, masked: true) { update(entry, \.value, to: $0) }
                RemoveButton(help: "Remove this variable") { remove(entry) }
            }
        }
    }

    private func update(_ entry: EnvironmentEntry, _ keyPath: WritableKeyPath<EnvironmentEntry, String>, to newValue: String) {
        guard let index = model.environment.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = model.environment
        updated[index][keyPath: keyPath] = newValue
        actions.setEnvironment(updated)
    }

    private func remove(_ entry: EnvironmentEntry) {
        actions.setEnvironment(model.environment.filter { $0.id != entry.id })
    }
}

/// A sheet with a single `SecureField`. The password never round trips back into the UI:
/// this view only ever sends a new value out through `save`.
private struct PasswordSheet: View {
    let save: (String) -> Void
    let cancel: () -> Void

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository Password")
                .font(.headline)
            Text("Stored in the keychain, used to unlock the restic repository.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecureField("Password", text: $password)
                .frame(width: 280)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save") { save(password) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(20)
    }
}
