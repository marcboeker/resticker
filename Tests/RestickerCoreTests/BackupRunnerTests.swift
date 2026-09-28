import XCTest
@testable import RestickerCore

final class BackupRunnerTests: XCTestCase {
    func testCompleteBackupWroteSnapshot() {
        XCTAssertTrue(BackupRunner.snapshotWritten(backupStatus: 0))
    }

    func testUnreadableSourceFilesStillWroteSnapshot() {
        XCTAssertTrue(BackupRunner.snapshotWritten(backupStatus: 3))
    }

    func testOtherExitCodesWroteNoSnapshot() {
        // 1 fatal error, 10 no repository, 11 lock failed, 12 wrong password, 130 interrupted.
        for status: Int32 in [-1, 1, 10, 11, 12, 130] {
            XCTAssertFalse(BackupRunner.snapshotWritten(backupStatus: status), "exit \(status)")
        }
    }
}

final class BackupRunnerCancelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// A stand-in for restic: every step passes at once, except `slowStep`, which waits
    /// until the runner interrupts it.
    private func fakeRestic(slowStep: PipelineStep) throws -> String {
        let url = directory.appendingPathComponent("restic")
        let script = """
        #!/bin/sh
        if [ "$1" = "\(slowStep.rawValue)" ]; then exec sleep 30; fi
        exit 0
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func runAndCancel(during slowStep: PipelineStep) throws -> RunOutcome {
        var config = Config.default
        config.resticBinaryPath = try fakeRestic(slowStep: slowStep)
        config.resticGlobalArgs = []
        config.sourcePaths = []
        config.excludeFile = ""
        let options = PipelineOptions(unlock: false, cleanup: true, check: true, runMaintenance: true)

        let finished = expectation(description: "finished")
        var outcome: RunOutcome?
        var runner: BackupRunner!
        runner = BackupRunner(config: config, secrets: RepositorySecrets(password: "x", environment: [:]),
                              options: options) { event in
            switch event {
            case .stepStarted(let step) where step == slowStep:
                // The step event can arrive before the process starts; cancel covers both.
                runner.cancel()
            case .finished(let value):
                outcome = value
                finished.fulfill()
            default:
                break
            }
        }
        runner.start()
        wait(for: [finished], timeout: 20)
        return try XCTUnwrap(outcome)
    }

    func testCancelDuringCleanupKeepsBackupButNotMaintenance() throws {
        let outcome = try runAndCancel(during: .forget)
        XCTAssertEqual(outcome.outcome, .success)
        XCTAssertNil(outcome.failedStep)
        XCTAssertFalse(outcome.maintenanceAttempted)
    }

    func testCancelDuringCheckKeepsBackupButNotMaintenance() throws {
        let outcome = try runAndCancel(during: .check)
        XCTAssertEqual(outcome.outcome, .success)
        XCTAssertNil(outcome.failedStep)
        XCTAssertFalse(outcome.maintenanceAttempted)
    }
}
