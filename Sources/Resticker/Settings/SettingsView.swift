import SwiftUI
import RestickerCore

/// The writes a settings page can make. A page never touches `ConfigStore`, `Keychain`,
/// or `AppDelegate` directly: it only reads `SettingsModel` and calls back through here,
/// which `SettingsWindowController` implements.
struct SettingsActions {
    /// Persists `config`, applies it to the running app immediately, and recomputes
    /// `problems`. Every row that edits a plain `Config` field goes through this, either
    /// straight away (toggles, pickers, steppers) or once the user commits an edit
    /// (text and number fields, via `SettingsModel.binding`'s callers).
    var save: (Config) -> Void

    // General
    var setStartAtLogin: (Bool) -> Void
    var openLoginItemsSettings: () -> Void
    var redetectRestic: () -> Void

    // Repository
    var setPassword: (String) -> Void
    var setEnvironment: ([EnvironmentEntry]) -> Void

    // Backup
    var addSourcePaths: ([String]) -> Void
    var removeSourcePath: (String) -> Void
    var openPrivacySettings: () -> Void

    // Repository test
    var testRepository: (@escaping (RepositoryTestResult) -> Void) -> Void
}

extension SettingsModel {
    /// A binding into `config` that saves through `actions` on every change. Use this for
    /// toggles, pickers, and steppers, which save immediately rather than on commit.
    func binding<Value>(_ keyPath: WritableKeyPath<Config, Value>, actions: SettingsActions) -> Binding<Value> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { self.commit(keyPath, actions: actions)($0) }
        )
    }

    /// Writes one `config` field and saves through `actions`. Use this for fields that
    /// save on commit, such as `CommittedTextField` and `DurationField`.
    func commit<Value>(_ keyPath: WritableKeyPath<Config, Value>, actions: SettingsActions) -> (Value) -> Void {
        { newValue in
            self.config[keyPath: keyPath] = newValue
            actions.save(self.config)
        }
    }
}

/// A text field for a list of restic arguments, edited as one shell-quoted line.
struct ArgsField: View {
    let model: SettingsModel
    let keyPath: WritableKeyPath<Config, [String]>
    let actions: SettingsActions

    var body: some View {
        CommittedTextField("none", value: ShellWords.join(model.config[keyPath: keyPath])) { text in
            model.commit(keyPath, actions: actions)(ShellWords.split(text))
        }
    }
}

/// The Settings window's content: a fixed sidebar of six pages, System Settings style.
struct SettingsRootView: View {
    @Bindable var model: SettingsModel
    let actions: SettingsActions

    var body: some View {
        NavigationSplitView {
            // `id: \.self` tags each row with the page itself. The default `Identifiable` id is
            // a String, which never matches the `SettingsPage?` selection, so clicks would be ignored.
            List(SettingsPage.allCases, id: \.self, selection: $model.selection) { page in
                Label {
                    HStack {
                        Text(page.rawValue)
                        Spacer()
                        if model.hasProblem(page) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } icon: {
                    Image(systemName: page.symbol)
                }
            }
            .navigationSplitViewColumnWidth(200)
            // Six fixed pages: hiding the sidebar has no use.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // The titlebar is transparent and empty over the detail column, so let the
            // page title start at the top edge instead of below it.
            Group {
                switch model.selection ?? .general {
                case .general: GeneralSettingsPage(model: model, actions: actions)
                case .repository: RepositorySettingsPage(model: model, actions: actions)
                case .backup: BackupSettingsPage(model: model, actions: actions)
                case .schedule: ScheduleSettingsPage(model: model, actions: actions)
                case .maintenance: MaintenanceSettingsPage(model: model, actions: actions)
                case .advanced: AdvancedSettingsPage(model: model, actions: actions)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

/// A section of a grouped `Form`. Every section on every page has a header, so the pages
/// read the same. The first section of a page also passes `pageTitle`, which sits above its
/// header: a grouped `Form` merges an empty title-only section into the next one and
/// draws that section's header as grey footer text.
struct SettingsSection<Content: View>: View {
    let title: String
    var pageTitle: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, pageTitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.pageTitle = pageTitle
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            VStack(alignment: .leading, spacing: 16) {
                if let pageTitle {
                    Text(pageTitle)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                }
                Text(title)
            }
        }
    }
}

/// A status line under a row's hint: a configuration problem, or the result of an action
/// the row ran. Shown at full width in the label column, because restic errors are long
/// and the right hand column would squeeze and cut them.
enum RowNote: Equatable, View {
    case warning(String)
    case failure(String)
    case success(String)

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch self {
        case .warning(let text): (text, "exclamationmark.triangle.fill", .orange)
        case .failure(let text): (text, "xmark.octagon.fill", .red)
        case .success(let text): (text, "checkmark.circle.fill", .green)
        }
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.subheadline)
        .foregroundStyle(color)
    }
}

/// The left hand column of every row: a title, a one line grey hint, and an optional note.
/// The hint is the setting's only documentation, so every row writes one. It is a
/// `LocalizedStringKey` so that Markdown renders: `code` for restic commands and flags,
/// and [links](url).
struct RowLabel: View {
    let title: String
    let hint: LocalizedStringKey
    var note: RowNote?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                note.padding(.top, 2)
            }
        }
    }
}

/// One row: a `RowLabel` on the left, its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let hint: LocalizedStringKey
    var note: RowNote?
    @ViewBuilder let control: () -> Control

    var body: some View {
        LabeledContent {
            control()
        } label: {
            RowLabel(title: title, hint: hint, note: note)
        }
    }
}

extension SettingsRow where Control == SettingsSwitch {
    /// A row whose control is an on/off switch.
    init(title: String, hint: LocalizedStringKey, note: RowNote? = nil, isOn: Binding<Bool>) {
        self.init(title: title, hint: hint, note: note) { SettingsSwitch(isOn: isOn) }
    }
}

/// The switch every on/off setting uses. A grouped `Form` draws a plain `Toggle` as a
/// checkbox.
struct SettingsSwitch: View {
    let isOn: Binding<Bool>

    var body: some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

/// A row for a text input. Paths, repository URLs, and restic args are too long for the
/// right hand column of `SettingsRow`, so the field spans the full row under the label.
/// `examples` are listed under the field, one per line, so the user can compare them with
/// what they typed.
struct SettingsFieldRow<Field: View>: View {
    let title: String
    let hint: LocalizedStringKey
    var note: RowNote?
    var examples: [String] = []
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RowLabel(title: title, hint: hint, note: note)
            field()
            if !examples.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Examples")
                    ForEach(examples, id: \.self) { example in
                        Text(example)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// The trailing button that removes one entry from a list section.
struct RemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// A stepper with its value on the left, for the right hand column of `SettingsRow`.
/// `Stepper`'s own label sits after the arrows and leaves the row's right edge ragged.
struct NumberStepper: View {
    let value: Binding<Int>
    let range: ClosedRange<Int>

    init(value: Binding<Int>, in range: ClosedRange<Int>) {
        self.value = value
        self.range = range
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(value.wrappedValue)")
                .monospacedDigit()
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }
}

extension View {
    /// The border every Settings text field draws. `.roundedBorder` has a fixed height that
    /// puts the placeholder off center, so the fields use `.plain` with this frame instead.
    func settingsFieldChrome(focused: Bool) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(focused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: focused ? 2 : 1)
            }
    }
}

/// A text field that saves on Return or on losing focus, per the Settings editing rules.
/// Backed by a local draft so keystrokes never write through until committed.
///
/// A grouped `Form` turns a `TextField`'s title into a row label and draws the field without
/// a border, so the title stays empty, the placeholder goes into `prompt`, and
/// `settingsFieldChrome` makes the field look like an input. Text is left aligned: these
/// fields span the full row, and a long path or URL reads from its start. Small value
/// fields in the right hand column, like `DurationField`, align right instead.
struct CommittedTextField: View {
    let placeholder: String
    @State private var draft: String
    private let value: String
    private let masked: Bool
    private let commit: (String) -> Void
    @FocusState private var isFocused: Bool

    /// `masked` shows bullets while the field is not focused, for secrets that may be edited.
    init(_ placeholder: String = "", value: String, masked: Bool = false, commit: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.value = value
        self.masked = masked
        self.commit = commit
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField("", text: text, prompt: Text(placeholder))
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .lineLimit(1)
            .focused($isFocused)
            .settingsFieldChrome(focused: isFocused)
            .onSubmit(commitIfChanged)
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused, !focused { commitIfChanged() }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused { draft = newValue }
            }
            // Switching sidebar pages removes the field without a focus change.
            .onDisappear(perform: commitIfChanged)
    }

    private var text: Binding<String> {
        guard masked, !isFocused, !draft.isEmpty else { return $draft }
        return .constant(String(repeating: "•", count: 8))
    }

    private func commitIfChanged() {
        guard draft != value else { return }
        commit(draft)
    }
}
