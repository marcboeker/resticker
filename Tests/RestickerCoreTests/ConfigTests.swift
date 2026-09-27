import XCTest
@testable import RestickerCore

final class ConfigTests: XCTestCase {
    func testPartialConfigFallsBackToDefaults() throws {
        let json = #"{"repository":"sftp:nas:/backups/mac","backupIntervalMinutes":60}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.repository, "sftp:nas:/backups/mac")
        XCTAssertEqual(config.backupIntervalMinutes, 60)
        XCTAssertEqual(config.resticGlobalArgs, ["--compression", "max", "--pack-size", "64"])
        XCTAssertEqual(config.resticForgetArgs, Config.default.resticForgetArgs)
        XCTAssertEqual(config.maintenanceIntervalHours, 24)
    }

    func testTildeExpansion() throws {
        let json = #"{"excludeFile":"~/.resticignore","sourcePaths":["~/Documents"]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.expandedExcludeFile, NSHomeDirectory() + "/.resticignore")
        XCTAssertEqual(config.expandedSourcePaths, [NSHomeDirectory() + "/Documents"])
    }

    func testEmptyRepositoryIsReportedAsAProblem() throws {
        let json = #"{"repository":"  "}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertTrue(config.problems().contains("no repository set"))
    }

    func testEmptySourcePathsIsReportedAsAProblem() throws {
        var config = Config.default
        config.sourcePaths = []
        XCTAssertTrue(config.problems().contains("no source paths set"))
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
        XCTAssertTrue(config.problems().contains { $0.hasPrefix("restic not found") })
    }

    func testMissingResticBinaryIsReportedAsAProblem() throws {
        var config = Config.default
        config.resticBinaryPath = "/no/such/binary-\(UUID().uuidString)"
        XCTAssertTrue(config.problems().contains { $0.hasPrefix("restic not found") })
    }

    func testExecutableResticBinaryIsNotAProblem() throws {
        var config = Config.default
        config.resticBinaryPath = "/bin/ls"
        XCTAssertFalse(config.problems().contains { $0.hasPrefix("restic not found") })
    }
}

extension ConfigTests {
    func testExampleFileKeepsSlashesReadable() throws {
        let text = String(data: try ConfigStore.exampleData(), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("\\/"), "JSONEncoder escaped the slashes in a hand edited file")
        XCTAssertTrue(text.contains("\"resticBinaryPath\" : \"/opt/homebrew/bin/restic\""))
        let decoded = try JSONDecoder().decode(Config.self, from: try ConfigStore.exampleData())
        XCTAssertEqual(decoded.excludeFile, "~/.resticignore")
    }
}
