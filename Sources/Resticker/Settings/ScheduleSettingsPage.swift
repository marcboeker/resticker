import SwiftUI
import RestickerCore

/// How often Resticker backs up and retries, and how often it runs maintenance
/// (forget/check) afterwards.
struct ScheduleSettingsPage: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        Form {
            SettingsSection("Backup", pageTitle: "Schedule") {
                SettingsRow(title: "Backup every", hint: "How often Resticker starts a backup.") {
                    DurationField(totalMinutes: model.config.backupIntervalMinutes,
                                  commit: model.commit(\.backupIntervalMinutes, actions: actions))
                }
                SettingsRow(title: "Retry after", hint: "How long to wait after a failed backup.") {
                    DurationField(totalMinutes: model.config.retryDelayMinutes,
                                  commit: model.commit(\.retryDelayMinutes, actions: actions))
                }
                SettingsRow(title: "Max retries", hint: "After the last retry, Resticker waits for the next backup.") {
                    NumberStepper(value: model.binding(\.maxRetries, actions: actions), in: 0...20)
                }
            }

            SettingsSection("Maintenance") {
                SettingsRow(title: "Maintenance every", hint: "Runs forget and check after a successful backup.") {
                    MaintenanceIntervalField(totalHours: model.config.maintenanceIntervalHours,
                                             commit: model.commit(\.maintenanceIntervalHours, actions: actions))
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A number field plus a unit picker, for a duration stored in minutes. Changing the unit
/// re-expresses the same number under the new unit and saves immediately, the same as any
/// other picker; the number itself saves on commit (Return or focus loss).
struct DurationField: View {
    let totalMinutes: Int
    /// The units the picker offers, smallest first.
    var units: [DurationUnit] = DurationUnit.allCases
    let commit: (Int) -> Void

    @State private var amountText = ""
    @State private var unit = DurationUnit.minutes
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField("", text: $amountText)
                .labelsHidden()
                .settingsFieldChrome(focused: isFocused)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit(commitAmount)
                .onChange(of: isFocused) { wasFocused, focused in
                    if wasFocused, !focused { commitAmount() }
                }
            Picker("", selection: $unit) {
                ForEach(units) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: unit) { _, _ in commitAmount() }
        }
        .onAppear(perform: sync)
        .onChange(of: totalMinutes) { _, _ in
            if !isFocused { sync() }
        }
    }

    private func sync() {
        unit = DurationUnit.largestDividing(totalMinutes, among: units)
        amountText = String(totalMinutes / unit.minutesPerUnit)
    }

    private func commitAmount() {
        guard let amount = Int(amountText), amount > 0 else { sync(); return }
        // Capping the amount before multiplying keeps a huge entry from overflowing `Int`.
        let capped = min(amount, Config.maxDurationMinutes / unit.minutesPerUnit)
        if capped != amount { amountText = String(capped) }
        commit(capped * unit.minutesPerUnit)
    }
}

/// A `DurationField` in hours or days for `maintenanceIntervalHours`, behind a mode
/// picker: zero means "after every backup" and hides the number field rather than
/// showing "0 hours".
struct MaintenanceIntervalField: View {
    let totalHours: Int
    let commit: (Int) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { totalHours == 0 },
                // Switching off "after every backup" needs a real interval right away.
                set: { commit($0 ? 0 : 24) }
            )) {
                Text("Every").tag(false)
                Text("After every backup").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            if totalHours != 0 {
                DurationField(totalMinutes: totalHours * 60, units: [.hours, .days]) { commit($0 / 60) }
            }
        }
    }
}
