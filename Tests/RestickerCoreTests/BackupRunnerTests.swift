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
