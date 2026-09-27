import Observation
import ServiceManagement
import RestickerCore

/// One sidebar page. Order here is also the order `SettingsWindowController` searches
/// when it opens the window on the first page that has a problem.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case repository = "Repository"
    case backup = "Backup"
    case schedule = "Schedule"
    case maintenance = "Maintenance"
    case advanced = "Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .repository: return "externaldrive"
        case .backup: return "folder"
        case .schedule: return "clock"
        case .maintenance: return "wrench.and.screwdriver"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

/// Ties a `ConfigProblem` to the page and row that show it, so both the sidebar badge and
/// the inline row warning can be driven from the same `Config.problems()` list.
extension ConfigProblem {
    var page: SettingsPage {
        switch self {
        case .noRepository, .noPassword: return .repository
        case .noSourcePaths: return .backup
        case .resticNotFound: return .general
        case .noRetentionPolicy: return .maintenance
        }
    }
}

/// A name/value pair for the environment variables table. Backed by a dictionary in the
/// keychain, but a dictionary has no stable order to edit against, so the model keeps an
/// ordered array with a UI-only identity instead.
struct EnvironmentEntry: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var value: String
}

/// The unit a duration stored in minutes is displayed in. `largestDividing` always shows
/// the roundest number: 240 minutes reads as "4 hours", not "0.16 days" or "240 minutes".
enum DurationUnit: String, CaseIterable, Identifiable {
    case minutes = "Minutes"
    case hours = "Hours"
    case days = "Days"

    var id: String { rawValue }
    var minutesPerUnit: Int {
        switch self {
        case .minutes: return 1
        case .hours: return 60
        case .days: return 1440
        }
    }

    /// `units` must be ordered smallest first.
    static func largestDividing(_ totalMinutes: Int, among units: [DurationUnit] = allCases) -> DurationUnit {
        units.last { totalMinutes % $0.minutesPerUnit == 0 } ?? units[0]
    }
}

/// Backs every Settings page. `SettingsWindowController` is the only writer of the fields
/// outside `config` itself (login item status, keychain-derived state, problems); a page
/// mutates `config` directly through bindings and reports the change through
/// `SettingsActions.save`, which is what actually persists it.
@MainActor
@Observable
final class SettingsModel {
    /// Owned here, not as `@State` in `SettingsRootView`, so `SettingsWindowController`
    /// can jump to a specific page (e.g. on first run, whichever page has a problem)
    /// without SwiftUI throwing the view away and losing everything else in `self`.
    var selection: SettingsPage? = .general
    var config = Config.default
    var loginItemStatus: SMAppService.Status = .notRegistered
    var hasPassword = false
    var environment: [EnvironmentEntry] = []
    /// Source paths currently denied by the sandbox/TCC, found by `SourcePathProbe`.
    var deniedSourcePaths: Set<String> = []
    var problems: [ConfigProblem] = []

    func hasProblem(_ page: SettingsPage) -> Bool {
        problems.contains { $0.page == page }
    }
}
