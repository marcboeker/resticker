import XCTest
@testable import RestickerCore

final class RunStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNoHistoryMeansNoFailure() {
        XCTAssertFalse(RunState().lastRunFailed)
    }

    func testFailedRunCounts() {
        var state = RunState()
        state.append(RunRecord(date: now, outcome: .failure, duration: 10, bytesAdded: 0,
                               detail: "Backup failed: repository unreachable"))
        XCTAssertTrue(state.lastRunFailed)
    }

    func testSuccessfulRunWithFailedStepCounts() {
        var state = RunState()
        state.append(RunRecord(date: now, outcome: .success, duration: 10, bytesAdded: 512,
                               detail: "Check failed: repository offline"))
        XCTAssertTrue(state.lastRunFailed)
    }

    func testCleanSuccessDoesNotCount() {
        var state = RunState()
        state.append(RunRecord(date: now, outcome: .success, duration: 10, bytesAdded: 512))
        XCTAssertFalse(state.lastRunFailed)
    }

    func testCancelledRunAfterAFailureDoesNotCount() {
        var state = RunState()
        state.append(RunRecord(date: now, outcome: .failure, duration: 10, bytesAdded: 0,
                               detail: "Backup failed"))
        state.append(RunRecord(date: now, outcome: .cancelled, duration: 2, bytesAdded: 0))
        XCTAssertFalse(state.lastRunFailed)
    }
}
