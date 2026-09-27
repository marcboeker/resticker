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
    /// The repo's `config.example.json` is a human-readable mirror of the Swift string
    /// constant that the app actually writes on first launch. The two must never drift.
    ///
    /// `exampleText` fills in the real `sourcePaths` entry with the current user's home
    /// directory at runtime, so the file the app writes is always correct for whoever
    /// installs it. The repo copy can't do that — it's static — so it spells out
    /// "/Users/yourname" there instead. That's the one substitution allowed before the
    /// byte-for-byte comparison below, so this test still fails on any other drift
    /// (comments, key names, values) on any machine, not just this one.
    func testRepoExampleFileMatchesTheEmbeddedConstant() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ConfigTests.swift
            .deletingLastPathComponent() // RestickerCoreTests
            .deletingLastPathComponent() // Tests
        let exampleURL = repoRoot.appendingPathComponent("config.example.json")
        let onDisk = try String(contentsOf: exampleURL, encoding: .utf8)
        let normalized = onDisk.replacingOccurrences(of: "/Users/yourname", with: NSHomeDirectory())
        XCTAssertEqual(normalized, ConfigStore.exampleText)
    }

    func testCommentStrippedExampleDecodesToDefaultConfig() throws {
        let stripped = ConfigStore.stripComments(ConfigStore.exampleText)
        let decoded = try JSONDecoder().decode(Config.self, from: Data(stripped.utf8))
        XCTAssertEqual(decoded, Config.default)
    }

    func testCommentStrippingRemovesFullLineCommentsOnly() throws {
        let text = #"""
        {
          // a comment line, must be removed
          "repository": "rest:https://example.com/backups",
          "sourcePaths": ["/data"]
        }
        """#
        let stripped = ConfigStore.stripComments(text)
        XCTAssertFalse(stripped.contains("a comment line"))
        // A repository URL containing "//" on a real content line must survive untouched:
        // stripping from the first "//" found anywhere on a line would corrupt it.
        XCTAssertTrue(stripped.contains(#""repository": "rest:https://example.com/backups","#))
        let decoded = try JSONDecoder().decode(Config.self, from: Data(stripped.utf8))
        XCTAssertEqual(decoded.repository, "rest:https://example.com/backups")
    }
}
