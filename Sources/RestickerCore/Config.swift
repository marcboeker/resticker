import Foundation

/// The user owned settings file. The app never writes this file after it creates the example.
public struct Config: Codable, Equatable {
    public var resticBinaryPath: String
    public var repository: String
    public var sourcePaths: [String]
    public var excludeFile: String?
    public var backupIntervalMinutes: Int
    public var maintenanceIntervalHours: Int
    public var retryDelayMinutes: Int
    public var maxRetries: Int
    public var notifyOnSuccessfulBackup: Bool
    public var environmentVariables: [String: String]
    public var resticGlobalArgs: [String]
    public var resticBackupArgs: [String]
    public var resticForgetArgs: [String]
    public var resticCheckArgs: [String]
    public var resticUnlockArgs: [String]

    public static let `default` = Config(
        resticBinaryPath: "/opt/homebrew/bin/restic",
        repository: "/Volumes/Backup/restic",
        sourcePaths: ["\(NSHomeDirectory())"],
        excludeFile: "~/.resticignore",
        backupIntervalMinutes: 240,
        maintenanceIntervalHours: 24,
        retryDelayMinutes: 15,
        maxRetries: 3,
        notifyOnSuccessfulBackup: false,
        environmentVariables: [:],
        resticGlobalArgs: ["--compression", "max", "--pack-size", "64"],
        resticBackupArgs: ["--one-file-system", "--exclude-caches"],
        resticForgetArgs: ["--prune", "-l", "6", "-d", "7", "-w", "7", "-m", "4", "-y", "12"],
        resticCheckArgs: [],
        resticUnlockArgs: []
    )

    public init(
        resticBinaryPath: String,
        repository: String,
        sourcePaths: [String],
        excludeFile: String?,
        backupIntervalMinutes: Int,
        maintenanceIntervalHours: Int,
        retryDelayMinutes: Int,
        maxRetries: Int,
        notifyOnSuccessfulBackup: Bool,
        environmentVariables: [String: String],
        resticGlobalArgs: [String],
        resticBackupArgs: [String],
        resticForgetArgs: [String],
        resticCheckArgs: [String],
        resticUnlockArgs: [String]
    ) {
        self.resticBinaryPath = resticBinaryPath
        self.repository = repository
        self.sourcePaths = sourcePaths
        self.excludeFile = excludeFile
        self.backupIntervalMinutes = backupIntervalMinutes
        self.maintenanceIntervalHours = maintenanceIntervalHours
        self.retryDelayMinutes = retryDelayMinutes
        self.maxRetries = maxRetries
        self.notifyOnSuccessfulBackup = notifyOnSuccessfulBackup
        self.environmentVariables = environmentVariables
        self.resticGlobalArgs = resticGlobalArgs
        self.resticBackupArgs = resticBackupArgs
        self.resticForgetArgs = resticForgetArgs
        self.resticCheckArgs = resticCheckArgs
        self.resticUnlockArgs = resticUnlockArgs
    }

    /// Every key is optional. A two line config file is valid, the rest falls back to the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        resticBinaryPath = try c.decodeIfPresent(String.self, forKey: .resticBinaryPath) ?? d.resticBinaryPath
        repository = try c.decodeIfPresent(String.self, forKey: .repository) ?? d.repository
        sourcePaths = try c.decodeIfPresent([String].self, forKey: .sourcePaths) ?? d.sourcePaths
        excludeFile = try c.decodeIfPresent(String.self, forKey: .excludeFile) ?? d.excludeFile
        backupIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .backupIntervalMinutes) ?? d.backupIntervalMinutes
        maintenanceIntervalHours = try c.decodeIfPresent(Int.self, forKey: .maintenanceIntervalHours) ?? d.maintenanceIntervalHours
        retryDelayMinutes = try c.decodeIfPresent(Int.self, forKey: .retryDelayMinutes) ?? d.retryDelayMinutes
        maxRetries = try c.decodeIfPresent(Int.self, forKey: .maxRetries) ?? d.maxRetries
        notifyOnSuccessfulBackup = try c.decodeIfPresent(Bool.self, forKey: .notifyOnSuccessfulBackup) ?? d.notifyOnSuccessfulBackup
        environmentVariables = try c.decodeIfPresent([String: String].self, forKey: .environmentVariables) ?? d.environmentVariables
        resticGlobalArgs = try c.decodeIfPresent([String].self, forKey: .resticGlobalArgs) ?? d.resticGlobalArgs
        resticBackupArgs = try c.decodeIfPresent([String].self, forKey: .resticBackupArgs) ?? d.resticBackupArgs
        resticForgetArgs = try c.decodeIfPresent([String].self, forKey: .resticForgetArgs) ?? d.resticForgetArgs
        resticCheckArgs = try c.decodeIfPresent([String].self, forKey: .resticCheckArgs) ?? d.resticCheckArgs
        resticUnlockArgs = try c.decodeIfPresent([String].self, forKey: .resticUnlockArgs) ?? d.resticUnlockArgs
    }

    public var interval: TimeInterval { TimeInterval(max(1, backupIntervalMinutes) * 60) }
    public var maintenanceInterval: TimeInterval { TimeInterval(max(0, maintenanceIntervalHours) * 3600) }
    public var retryDelay: TimeInterval { TimeInterval(max(1, retryDelayMinutes) * 60) }
    public var expandedResticBinaryPath: String { Paths.expand(resticBinaryPath) }
    public var expandedSourcePaths: [String] { sourcePaths.map(Paths.expand) }
    public var expandedExcludeFile: String? { excludeFile.map(Paths.expand) }

    /// Reasons the app cannot start a backup. Empty means ready.
    public func problems() -> [String] {
        var found: [String] = []
        if repository.trimmingCharacters(in: .whitespaces).isEmpty {
            found.append("no repository set")
        }
        if sourcePaths.isEmpty {
            found.append("no source paths set")
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: expandedResticBinaryPath, isDirectory: &isDirectory)
        // isExecutableFile(atPath:) alone would accept a directory: directories are
        // "executable" (traversable) almost always, so a misconfigured resticBinaryPath that
        // points at a folder must not read back as "configured".
        if !exists || isDirectory.boolValue || !FileManager.default.isExecutableFile(atPath: expandedResticBinaryPath) {
            found.append("restic not found at \(resticBinaryPath)")
        }
        return found
    }
}

public enum ConfigStore {
    /// Loads the config file, creating it from the defaults when it does not exist yet.
    public static func load() throws -> Config {
        let url = Paths.configFile
        if !FileManager.default.fileExists(atPath: url.path) {
            try writeExample()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public static func writeExample() throws {
        try FileManager.default.createDirectory(at: Paths.configDirectory, withIntermediateDirectories: true)
        try exampleData().write(to: Paths.configFile)
        // The environmentVariables dictionary can hold cloud-backend credentials, so the file must not be
        // left world-readable at its default FileManager permissions.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.configFile.path)
    }

    /// The config file is edited by hand, so slashes stay unescaped.
    public static func exampleData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var example = Config.default
        example.excludeFile = "~/.resticignore"
        return try encoder.encode(example)
    }

    public static func modificationDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.configFile.path)
        return attrs?[.modificationDate] as? Date
    }
}
