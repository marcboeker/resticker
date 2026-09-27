import Foundation

/// The user owned settings file. The app never writes this file after it creates the example.
public struct Config: Codable, Equatable {
    public var resticPath: String
    public var repository: String
    public var sourcePaths: [String]
    public var excludeFile: String?
    public var intervalMinutes: Int
    public var cleanupIntervalHours: Int
    public var retryDelayMinutes: Int
    public var maxRetries: Int
    public var notifyOnSuccess: Bool
    public var env: [String: String]
    public var globalArgs: [String]
    public var backupArgs: [String]
    public var forgetArgs: [String]
    public var checkArgs: [String]
    public var unlockArgs: [String]

    public static let `default` = Config(
        resticPath: "/opt/homebrew/bin/restic",
        repository: "/Volumes/Backup/restic",
        sourcePaths: ["\(NSHomeDirectory())"],
        excludeFile: "~/.resticignore",
        intervalMinutes: 240,
        cleanupIntervalHours: 24,
        retryDelayMinutes: 15,
        maxRetries: 3,
        notifyOnSuccess: false,
        env: [:],
        globalArgs: ["--compression", "max", "--pack-size", "64"],
        backupArgs: ["--one-file-system", "--exclude-caches"],
        forgetArgs: ["--prune", "-l", "6", "-d", "7", "-w", "7", "-m", "4", "-y", "12"],
        checkArgs: [],
        unlockArgs: []
    )

    public init(
        resticPath: String,
        repository: String,
        sourcePaths: [String],
        excludeFile: String?,
        intervalMinutes: Int,
        cleanupIntervalHours: Int,
        retryDelayMinutes: Int,
        maxRetries: Int,
        notifyOnSuccess: Bool,
        env: [String: String],
        globalArgs: [String],
        backupArgs: [String],
        forgetArgs: [String],
        checkArgs: [String],
        unlockArgs: [String]
    ) {
        self.resticPath = resticPath
        self.repository = repository
        self.sourcePaths = sourcePaths
        self.excludeFile = excludeFile
        self.intervalMinutes = intervalMinutes
        self.cleanupIntervalHours = cleanupIntervalHours
        self.retryDelayMinutes = retryDelayMinutes
        self.maxRetries = maxRetries
        self.notifyOnSuccess = notifyOnSuccess
        self.env = env
        self.globalArgs = globalArgs
        self.backupArgs = backupArgs
        self.forgetArgs = forgetArgs
        self.checkArgs = checkArgs
        self.unlockArgs = unlockArgs
    }

    /// Every key is optional. A two line config file is valid, the rest falls back to the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        resticPath = try c.decodeIfPresent(String.self, forKey: .resticPath) ?? d.resticPath
        repository = try c.decodeIfPresent(String.self, forKey: .repository) ?? d.repository
        sourcePaths = try c.decodeIfPresent([String].self, forKey: .sourcePaths) ?? d.sourcePaths
        excludeFile = try c.decodeIfPresent(String.self, forKey: .excludeFile) ?? d.excludeFile
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        cleanupIntervalHours = try c.decodeIfPresent(Int.self, forKey: .cleanupIntervalHours) ?? d.cleanupIntervalHours
        retryDelayMinutes = try c.decodeIfPresent(Int.self, forKey: .retryDelayMinutes) ?? d.retryDelayMinutes
        maxRetries = try c.decodeIfPresent(Int.self, forKey: .maxRetries) ?? d.maxRetries
        notifyOnSuccess = try c.decodeIfPresent(Bool.self, forKey: .notifyOnSuccess) ?? d.notifyOnSuccess
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? d.env
        globalArgs = try c.decodeIfPresent([String].self, forKey: .globalArgs) ?? d.globalArgs
        backupArgs = try c.decodeIfPresent([String].self, forKey: .backupArgs) ?? d.backupArgs
        forgetArgs = try c.decodeIfPresent([String].self, forKey: .forgetArgs) ?? d.forgetArgs
        checkArgs = try c.decodeIfPresent([String].self, forKey: .checkArgs) ?? d.checkArgs
        unlockArgs = try c.decodeIfPresent([String].self, forKey: .unlockArgs) ?? d.unlockArgs
    }

    public var interval: TimeInterval { TimeInterval(max(1, intervalMinutes) * 60) }
    public var cleanupInterval: TimeInterval { TimeInterval(max(0, cleanupIntervalHours) * 3600) }
    public var retryDelay: TimeInterval { TimeInterval(max(1, retryDelayMinutes) * 60) }
    public var expandedResticPath: String { Paths.expand(resticPath) }
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
        let exists = FileManager.default.fileExists(atPath: expandedResticPath, isDirectory: &isDirectory)
        // isExecutableFile(atPath:) alone would accept a directory: directories are
        // "executable" (traversable) almost always, so a misconfigured resticPath that
        // points at a folder must not read back as "configured".
        if !exists || isDirectory.boolValue || !FileManager.default.isExecutableFile(atPath: expandedResticPath) {
            found.append("restic not found at \(resticPath)")
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
