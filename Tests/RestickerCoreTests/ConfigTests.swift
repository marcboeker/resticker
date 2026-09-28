import XCTest
@testable import RestickerCore

final class ConfigTests: XCTestCase {
    /// One fixed suite, wiped before and after each test, so these never touch the user's
    /// real UserDefaults. A unique name per test would leave an empty plist behind in
    /// ~/Library/Preferences on every run: removing a domain does not delete its file.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "net.at6.resticker.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testSaveThenLoadRoundTripsTheDefaults() {
        let defaults = makeDefaults()
        ConfigStore.save(Config.default, to: defaults)
        XCTAssertEqual(ConfigStore.load(from: defaults), Config.default)
    }

    func testSaveThenLoadRoundTripsACustomConfig() {
        let defaults = makeDefaults()
        var config = Config.default
        config.resticBinaryPath = "/usr/local/bin/restic"
        config.repository = "sftp:nas:/backups/mac"
        config.sourcePaths = ["~/Documents", "~/Pictures"]
        config.excludeFile = ""
        config.backupIntervalMinutes = 60
        config.keepDaily = 0
        config.keepWeekly = 2
        config.prune = false
        config.resticForgetExtraArgs = ["--tag", "mac"]
        config.unlockEnabled = false
        config.forgetEnabled = false
        config.checkEnabled = false

        ConfigStore.save(config, to: defaults)
        XCTAssertEqual(ConfigStore.load(from: defaults), config)
    }

    func testUnsetKeysLoadDefaults() {
        let defaults = makeDefaults()
        XCTAssertEqual(ConfigStore.load(from: defaults), Config.default)
    }

    /// `forgetEnabled` reuses the key the menu bar toggle wrote before Settings existed,
    /// so upgrading users keep whatever they had set.
    func testLegacyCleanupEnabledKeyMapsToForgetEnabled() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "cleanupEnabled")
        XCTAssertFalse(ConfigStore.load(from: defaults).forgetEnabled)

        defaults.set(true, forKey: "cleanupEnabled")
        XCTAssertTrue(ConfigStore.load(from: defaults).forgetEnabled)
    }

    func testSaveWritesOneKeyPerFieldUnderTheLegacyNameForForgetEnabled() {
        let defaults = makeDefaults()
        var config = Config.default
        config.forgetEnabled = false
        config.keepDaily = 9
        ConfigStore.save(config, to: defaults)
        XCTAssertEqual(defaults.object(forKey: "cleanupEnabled") as? Bool, false)
        XCTAssertNil(defaults.object(forKey: "forgetEnabled"))
        XCTAssertEqual(defaults.object(forKey: "keepDaily") as? Int, 9)
        XCTAssertEqual(defaults.array(forKey: "resticBackupArgs") as? [String], ["--one-file-system", "--exclude-caches"])
    }

    /// An empty exclude file is how "off" was stored before `excludeFile` stopped being
    /// optional, so it must still load as off.
    func testStoredEmptyExcludeFileLoadsAsOff() {
        let defaults = makeDefaults()
        defaults.set("", forKey: "excludeFile")
        let config = ConfigStore.load(from: defaults)
        XCTAssertEqual(config.excludeFile, "")
        XCTAssertNil(config.expandedExcludeFile)
    }

    func testAWronglyTypedValueLoadsItsDefaultAndKeepsTheRest() {
        let defaults = makeDefaults()
        defaults.set("not a number", forKey: "keepDaily")
        defaults.set("sftp:nas:/backups", forKey: "repository")
        let config = ConfigStore.load(from: defaults)
        XCTAssertEqual(config.keepDaily, Config.default.keepDaily)
        XCTAssertEqual(config.repository, "sftp:nas:/backups")
    }

    /// A value too large for the interval math loads clamped instead of crashing later.
    func testOutOfRangeDurationsLoadClamped() {
        let defaults = makeDefaults()
        defaults.set(Int.max, forKey: "backupIntervalMinutes")
        defaults.set(Int.max, forKey: "maintenanceIntervalHours")
        defaults.set(-5, forKey: "retryDelayMinutes")
        let config = ConfigStore.load(from: defaults)
        XCTAssertEqual(config.backupIntervalMinutes, 525_600)
        XCTAssertEqual(config.maintenanceIntervalHours, 8_760)
        XCTAssertEqual(config.retryDelayMinutes, 0)
        XCTAssertEqual(config.interval, 525_600 * 60)
        XCTAssertEqual(config.maintenanceInterval, 8_760 * 3600)
    }
}

// MARK: - forgetArgs

extension ConfigTests {
    func testForgetArgsBuildsOneFlagPerNonZeroKeepCount() {
        var config = Config.default
        config.keepDaily = 4
        config.keepWeekly = 7
        config.keepMonthly = 4
        config.keepYearly = 12
        config.prune = true
        config.resticForgetExtraArgs = []
        XCTAssertEqual(config.forgetArgs, [
            "--host", Config.systemHostname!,
            "--keep-daily", "4",
            "--keep-weekly", "7",
            "--keep-monthly", "4",
            "--keep-yearly", "12",
            "--prune",
        ])
    }

    func testForgetArgsOmitsZeroKeepCounts() {
        var config = Config.default
        config.keepDaily = 0
        config.keepWeekly = 7
        config.keepMonthly = 0
        config.keepYearly = 0
        config.prune = true
        XCTAssertEqual(config.forgetArgs, ["--host", Config.systemHostname!, "--keep-weekly", "7", "--prune"])
    }

    func testForgetArgsScopeToTheHostTheBackupRecords() {
        var config = Config.default
        XCTAssertEqual(Array(config.forgetArgs.prefix(2)), ["--host", Config.systemHostname!])

        config.resticBackupArgs = ["--one-file-system", "--host", "studio"]
        XCTAssertEqual(Array(config.forgetArgs.prefix(2)), ["--host", "studio"])

        config.resticBackupArgs = ["-H=studio"]
        XCTAssertEqual(Array(config.forgetArgs.prefix(2)), ["--host", "studio"])
    }

    func testForgetArgsAddNoHostWhenExtraArgsSetOne() {
        var config = Config.default
        config.resticForgetExtraArgs = ["--host=other"]
        XCTAssertEqual(config.forgetArgs.filter { $0.hasPrefix("--host") }, ["--host=other"])
    }

    /// Must match what restic's Go `os.Hostname()` records, which is `kern.hostname`.
    func testSystemHostnameMatchesTheHostnameCommand() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/hostname")
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(Config.systemHostname, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testForgetArgsOmitsPruneWhenOff() {
        var config = Config.default
        config.prune = false
        XCTAssertFalse(config.forgetArgs.contains("--prune"))
    }

    func testForgetArgsAppendsExtraArgsAfterEverythingElse() {
        var config = Config.default
        config.resticForgetExtraArgs = ["--tag", "mac"]
        XCTAssertEqual(config.forgetArgs.suffix(2), ["--tag", "mac"])
    }
}

// MARK: - problems()

extension ConfigTests {
    func testEmptyRepositoryIsReportedAsAProblem() {
        var config = Config.default
        config.repository = "  "
        XCTAssertTrue(config.problems().contains(.noRepository))
    }

    func testEmptySourcePathsIsReportedAsAProblem() {
        var config = Config.default
        config.sourcePaths = []
        XCTAssertTrue(config.problems().contains(.noSourcePaths))
    }

    func testEmptyResticBinaryPathIsReportedAsAProblem() {
        var config = Config.default
        config.resticBinaryPath = ""
        XCTAssertTrue(config.problems().contains(.resticNotFound(path: "")))
    }

    /// A directory is "executable" (traversable) almost always, so isExecutableFile alone
    /// would wrongly accept a resticBinaryPath that points at a folder instead of the binary.
    func testResticPathPointingAtADirectoryIsReportedAsAProblem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("resticker-config-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var config = Config.default
        config.resticBinaryPath = directory.path
        XCTAssertTrue(config.problems().contains(.resticNotFound(path: directory.path)))
    }

    func testMissingResticBinaryIsReportedAsAProblem() {
        var config = Config.default
        config.resticBinaryPath = "/no/such/binary-\(UUID().uuidString)"
        XCTAssertTrue(config.problems().contains { if case .resticNotFound = $0 { return true } else { return false } })
    }

    func testExecutableResticBinaryIsNotAProblem() {
        var config = Config.default
        config.resticBinaryPath = "/bin/ls"
        XCTAssertFalse(config.problems().contains { if case .resticNotFound = $0 { return true } else { return false } })
    }

    func testNoRetentionPolicyIsReportedOnlyWhenForgetIsEnabled() {
        var config = Config.default
        config.resticBinaryPath = "/bin/ls"
        config.repository = "sftp:nas:/backups"
        config.sourcePaths = ["~/Documents"]
        config.keepDaily = 0
        config.keepWeekly = 0
        config.keepMonthly = 0
        config.keepYearly = 0
        config.prune = false
        config.resticForgetExtraArgs = []

        config.forgetEnabled = true
        XCTAssertTrue(config.problems().contains(.noRetentionPolicy))

        config.forgetEnabled = false
        XCTAssertFalse(config.problems().contains(.noRetentionPolicy))
    }

    /// `--prune` alone is not a keep policy, so it must not suppress `.noRetentionPolicy`;
    /// only extra forget args (e.g. `--keep-tag`) count as an explicit policy here.
    func testNoRetentionPolicyIsNotReportedWhenExtraArgsArePresent() {
        var config = Config.default
        config.resticBinaryPath = "/bin/ls"
        config.repository = "sftp:nas:/backups"
        config.sourcePaths = ["~/Documents"]
        config.keepDaily = 0
        config.keepWeekly = 0
        config.keepMonthly = 0
        config.keepYearly = 0
        config.forgetEnabled = true
        config.prune = false
        config.resticForgetExtraArgs = ["--keep-tag", "pinned"]
        XCTAssertFalse(config.problems().contains(.noRetentionPolicy))
    }
}
