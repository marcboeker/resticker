import XCTest
@testable import RestickerCore

final class ConfigTests: XCTestCase {
    func testPartialConfigFallsBackToDefaults() throws {
        let json = #"{"repository":"sftp:nas:/backups/mac","intervalMinutes":60}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.repository, "sftp:nas:/backups/mac")
        XCTAssertEqual(config.intervalMinutes, 60)
        XCTAssertEqual(config.globalArgs, ["--compression", "max", "--pack-size", "64"])
        XCTAssertEqual(config.forgetArgs, Config.default.forgetArgs)
        XCTAssertEqual(config.cleanupIntervalHours, 24)
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
    /// would wrongly accept a resticPath that points at a folder instead of the binary.
    func testResticPathPointingAtADirectoryIsReportedAsAProblem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("resticker-config-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var config = Config.default
        config.resticPath = directory.path
        XCTAssertTrue(config.problems().contains { $0.hasPrefix("restic not found") })
    }

    func testMissingResticBinaryIsReportedAsAProblem() throws {
        var config = Config.default
        config.resticPath = "/no/such/binary-\(UUID().uuidString)"
        XCTAssertTrue(config.problems().contains { $0.hasPrefix("restic not found") })
    }

    func testExecutableResticBinaryIsNotAProblem() throws {
        var config = Config.default
        config.resticPath = "/bin/ls"
        XCTAssertFalse(config.problems().contains { $0.hasPrefix("restic not found") })
    }
}

extension ConfigTests {
    func testExampleFileKeepsSlashesReadable() throws {
        let text = String(data: try ConfigStore.exampleData(), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("\\/"), "JSONEncoder escaped the slashes in a hand edited file")
        XCTAssertTrue(text.contains("\"resticPath\" : \"/opt/homebrew/bin/restic\""))
        let decoded = try JSONDecoder().decode(Config.self, from: try ConfigStore.exampleData())
        XCTAssertEqual(decoded.excludeFile, "~/.resticignore")
    }
}
