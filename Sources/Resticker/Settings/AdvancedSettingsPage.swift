import SwiftUI
import RestickerCore

/// Global arguments, passed to every restic invocation before the subcommand.
struct AdvancedSettingsPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Form {
            SettingsSection("restic", pageTitle: "Advanced") {
                SettingsFieldRow(
                    title: "Global args",
                    hint: "Passed before the subcommand on every restic call, such as `--compression`."
                ) {
                    ArgsField(model: model, keyPath: \.resticGlobalArgs, actions: actions)
                }
            }
        }
        .formStyle(.grouped)
    }
}
