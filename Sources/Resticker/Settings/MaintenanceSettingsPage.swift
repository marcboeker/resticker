import SwiftUI
import RestickerCore

/// The retention policy (`restic forget`) and integrity check (`restic check`) that run
/// after a backup, once per maintenance interval.
struct MaintenanceSettingsPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Form {
            SettingsSection("Forget", pageTitle: "Maintenance") {
                SettingsRow(
                    title: "Forget old snapshots",
                    hint: "Runs restic forget with the keep rules below. A rule set to 0 is off.",
                    note: model.problems.contains(.noRetentionPolicy)
                        ? .warning("Keep at least one snapshot, add extra forget args, or turn this off.")
                        : nil,
                    isOn: model.binding(\.forgetEnabled, actions: actions)
                )
                Group {
                    SettingsRow(title: "Keep daily", hint: "Passed as `--keep-daily`.") {
                        NumberStepper(value: model.binding(\.keepDaily, actions: actions), in: 0...365)
                    }
                    SettingsRow(title: "Keep weekly", hint: "Passed as `--keep-weekly`.") {
                        NumberStepper(value: model.binding(\.keepWeekly, actions: actions), in: 0...520)
                    }
                    SettingsRow(title: "Keep monthly", hint: "Passed as `--keep-monthly`.") {
                        NumberStepper(value: model.binding(\.keepMonthly, actions: actions), in: 0...600)
                    }
                    SettingsRow(title: "Keep yearly", hint: "Passed as `--keep-yearly`.") {
                        NumberStepper(value: model.binding(\.keepYearly, actions: actions), in: 0...100)
                    }
                    SettingsRow(
                        title: "Prune",
                        hint: "Frees the space of removed snapshots right away, with `--prune`.",
                        isOn: model.binding(\.prune, actions: actions)
                    )
                    SettingsFieldRow(title: "Extra forget args", hint: "Extra arguments for restic forget, such as `--keep-tag`.") {
                        ArgsField(model: model, keyPath: \.resticForgetExtraArgs, actions: actions)
                    }
                }
                .disabled(!model.config.forgetEnabled)
            }

            SettingsSection("Check") {
                SettingsRow(
                    title: "Check repository",
                    hint: "Runs restic check to find damaged data.",
                    isOn: model.binding(\.checkEnabled, actions: actions)
                )
                SettingsFieldRow(title: "Check args", hint: "Extra arguments for restic check, such as `--read-data`.") {
                    ArgsField(model: model, keyPath: \.resticCheckArgs, actions: actions)
                }
                .disabled(!model.config.checkEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
