import Foundation

/// The user's settings, backed by `UserDefaults` and edited through the Settings window.
/// Repository secrets (the password, and any environment variables restic needs for a
/// cloud backend) never live here: they live in the keychain, and the app reads them
/// separately right before a run.
public struct Config: Equatable, Codable {
    public var resticBinaryPath: String
    public var repository: String
    public var sourcePaths: [String]
    /// Empty means off: no `--exclude-file` flag.
    public var excludeFile: String
    public var backupIntervalMinutes: Int
    public var maintenanceIntervalHours: Int
    public var retryDelayMinutes: Int
    public var maxRetries: Int
    public var notifyOnSuccessfulBackup: Bool
    public var resticGlobalArgs: [String]
    public var resticBackupArgs: [String]
    public var keepDaily: Int
    public var keepWeekly: Int
    public var keepMonthly: Int
    public var keepYearly: Int
    public var prune: Bool
    public var resticForgetExtraArgs: [String]
    public var resticCheckArgs: [String]
    public var resticUnlockArgs: [String]
    public var unlockEnabled: Bool
    public var forgetEnabled: Bool
    public var checkEnabled: Bool

    public static let `default` = Config(
        resticBinaryPath: "",
        repository: "",
        sourcePaths: [],
        excludeFile: "~/.resticignore",
        backupIntervalMinutes: 240,
        maintenanceIntervalHours: 24,
        retryDelayMinutes: 15,
        maxRetries: 3,
        notifyOnSuccessfulBackup: false,
        resticGlobalArgs: ["--compression", "max", "--pack-size", "64"],
        resticBackupArgs: ["--one-file-system", "--exclude-caches"],
        keepDaily: 4,
        keepWeekly: 7,
        keepMonthly: 4,
        keepYearly: 12,
        prune: true,
        resticForgetExtraArgs: [],
        resticCheckArgs: [],
        resticUnlockArgs: [],
        unlockEnabled: true,
        forgetEnabled: true,
        checkEnabled: true
    )

    /// One `UserDefaults` key per field, named after the field. `forgetEnabled` keeps the
    /// key `cleanupEnabled` that the menu bar toggle wrote before Settings existed.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case resticBinaryPath, repository, sourcePaths, excludeFile
        case backupIntervalMinutes, maintenanceIntervalHours, retryDelayMinutes, maxRetries
        case notifyOnSuccessfulBackup, resticGlobalArgs, resticBackupArgs
        case keepDaily, keepWeekly, keepMonthly, keepYearly, prune
        case resticForgetExtraArgs, resticCheckArgs, resticUnlockArgs
        case unlockEnabled
        case forgetEnabled = "cleanupEnabled"
        case checkEnabled
    }

    public var interval: TimeInterval { TimeInterval(max(1, backupIntervalMinutes) * 60) }
    public var maintenanceInterval: TimeInterval { TimeInterval(max(0, maintenanceIntervalHours) * 3600) }
    public var retryDelay: TimeInterval { TimeInterval(max(1, retryDelayMinutes) * 60) }
    public var expandedResticBinaryPath: String { Paths.expand(resticBinaryPath) }
    public var expandedSourcePaths: [String] { sourcePaths.map(Paths.expand) }
    public var expandedExcludeFile: String? { excludeFile.isEmpty ? nil : Paths.expand(excludeFile) }
    var hasUsableRestic: Bool { !resticBinaryPath.isEmpty && Paths.isExecutableFile(expandedResticBinaryPath) }

    /// The arguments passed to `restic forget`. A zero keep count means that rule is off
    /// and emits no flag; restic itself refuses to run with no keep policy and no
    /// extra args at all, which `problems()` reports as `.noRetentionPolicy`.
    public var forgetArgs: [String] {
        var args: [String] = []
        if keepDaily > 0 { args += ["--keep-daily", String(keepDaily)] }
        if keepWeekly > 0 { args += ["--keep-weekly", String(keepWeekly)] }
        if keepMonthly > 0 { args += ["--keep-monthly", String(keepMonthly)] }
        if keepYearly > 0 { args += ["--keep-yearly", String(keepYearly)] }
        if prune { args.append("--prune") }
        return args + resticForgetExtraArgs
    }

    /// Reasons the app cannot start a backup, one per affected setting so the Settings
    /// window can flag the right row. Keychain state (the password) is not checked here;
    /// the app appends `.noPassword` itself after calling this.
    public func problems() -> [ConfigProblem] {
        var found: [ConfigProblem] = []
        if repository.trimmingCharacters(in: .whitespaces).isEmpty {
            found.append(.noRepository)
        }
        if sourcePaths.isEmpty {
            found.append(.noSourcePaths)
        }
        if !hasUsableRestic {
            found.append(.resticNotFound(path: resticBinaryPath))
        }
        if forgetEnabled, keepDaily == 0, keepWeekly == 0, keepMonthly == 0, keepYearly == 0,
           resticForgetExtraArgs.isEmpty {
            found.append(.noRetentionPolicy)
        }
        return found
    }
}

/// A single reason the app is not ready to run, tied to the setting that causes it so the
/// Settings window can show it on the right row.
public enum ConfigProblem: Equatable {
    case noRepository
    case noSourcePaths
    case resticNotFound(path: String)
    case noRetentionPolicy
    case noPassword

    public var message: String {
        switch self {
        case .noRepository:
            return "no repository set"
        case .noSourcePaths:
            return "no source paths set"
        case .resticNotFound(let path):
            return path.isEmpty
                ? "restic not found, install it with `brew install restic`"
                : "restic not found at \(path)"
        case .noRetentionPolicy:
            return "no retention policy set, restic forget would refuse to run"
        case .noPassword:
            return "no password in keychain, set one in Settings"
        }
    }
}

extension Config {
    /// A key that is missing, or holds a value of the wrong type, loads the default, so
    /// one bad value never resets the whole config. Built on the memberwise init, so a new
    /// field that is not read here does not compile.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.init(
            resticBinaryPath: value(.resticBinaryPath, d.resticBinaryPath),
            repository: value(.repository, d.repository),
            sourcePaths: value(.sourcePaths, d.sourcePaths),
            excludeFile: value(.excludeFile, d.excludeFile),
            backupIntervalMinutes: value(.backupIntervalMinutes, d.backupIntervalMinutes),
            maintenanceIntervalHours: value(.maintenanceIntervalHours, d.maintenanceIntervalHours),
            retryDelayMinutes: value(.retryDelayMinutes, d.retryDelayMinutes),
            maxRetries: value(.maxRetries, d.maxRetries),
            notifyOnSuccessfulBackup: value(.notifyOnSuccessfulBackup, d.notifyOnSuccessfulBackup),
            resticGlobalArgs: value(.resticGlobalArgs, d.resticGlobalArgs),
            resticBackupArgs: value(.resticBackupArgs, d.resticBackupArgs),
            keepDaily: value(.keepDaily, d.keepDaily),
            keepWeekly: value(.keepWeekly, d.keepWeekly),
            keepMonthly: value(.keepMonthly, d.keepMonthly),
            keepYearly: value(.keepYearly, d.keepYearly),
            prune: value(.prune, d.prune),
            resticForgetExtraArgs: value(.resticForgetExtraArgs, d.resticForgetExtraArgs),
            resticCheckArgs: value(.resticCheckArgs, d.resticCheckArgs),
            resticUnlockArgs: value(.resticUnlockArgs, d.resticUnlockArgs),
            unlockEnabled: value(.unlockEnabled, d.unlockEnabled),
            forgetEnabled: value(.forgetEnabled, d.forgetEnabled),
            checkEnabled: value(.checkEnabled, d.checkEnabled)
        )
    }
}

/// Reads and writes `Config` to `UserDefaults`, one key per field, through `Codable`: the
/// config encodes to a property list dictionary, and each entry becomes its own key. There
/// is no migration from the old `config.json`: a fresh install just gets `Config.default`
/// until the user changes something in the Settings window.
public enum ConfigStore {
    public static func load(from defaults: UserDefaults = .standard) -> Config {
        var stored: [String: Any] = [:]
        for key in Config.CodingKeys.allCases {
            stored[key.rawValue] = defaults.object(forKey: key.rawValue)
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: stored, format: .binary, options: 0)
            return try PropertyListDecoder().decode(Config.self, from: data)
        } catch {
            LogFile.shared.write("config load failed, using defaults: \(error.localizedDescription)")
            return .default
        }
    }

    public static func save(_ config: Config, to defaults: UserDefaults = .standard) {
        do {
            let data = try PropertyListEncoder().encode(config)
            guard let entries = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
            for (key, value) in entries {
                defaults.set(value, forKey: key)
            }
        } catch {
            LogFile.shared.write("config save failed: \(error.localizedDescription)")
        }
    }

    /// Loads the config and, if `resticBinaryPath` is empty or no longer points at an
    /// executable, runs `ResticLocator` and saves what it finds. Called at launch and
    /// again before every run, since restic can be installed or moved while the app is up.
    @discardableResult
    public static func resolveResticIfNeeded(defaults: UserDefaults = .standard) -> Config {
        var config = load(from: defaults)
        guard !config.hasUsableRestic, let found = ResticLocator.detect() else { return config }
        config.resticBinaryPath = found
        save(config, to: defaults)
        return config
    }
}
