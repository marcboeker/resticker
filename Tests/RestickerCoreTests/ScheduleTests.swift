import XCTest
@testable import RestickerCore

final class ScheduleTests: XCTestCase {
    private var config: Config {
        var value = Config.default
        value.backupIntervalMinutes = 240
        value.retryDelayMinutes = 15
        value.maxRetries = 3
        value.maintenanceIntervalHours = 24
        return value
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstLaunchIsDueAtOnce() {
        XCTAssertTrue(Schedule.isRunDue(state: RunState(), now: now))
    }

    func testNotDueBeforeTheIntervalHasPassed() {
        let state = Schedule.afterSuccess(state: RunState(), config: config, now: now)
        XCTAssertFalse(Schedule.isRunDue(state: state, now: now.addingTimeInterval(3599)))
        XCTAssertFalse(Schedule.isRunDue(state: state, now: now.addingTimeInterval(4 * 3600 - 1)))
    }

    func testDueExactlyAtTheInterval() {
        let state = Schedule.afterSuccess(state: RunState(), config: config, now: now)
        XCTAssertTrue(Schedule.isRunDue(state: state, now: now.addingTimeInterval(4 * 3600)))
    }

    /// The sleep case. Three days asleep means one run, not one run per missed slot.
    func testDueAfterALongSleep() {
        let state = Schedule.afterSuccess(state: RunState(), config: config, now: now)
        let afterSleep = now.addingTimeInterval(3 * 24 * 3600)
        XCTAssertTrue(Schedule.isRunDue(state: state, now: afterSleep))

        let ran = Schedule.afterSuccess(state: state, config: config, now: afterSleep)
        XCTAssertFalse(Schedule.isRunDue(state: ran, now: afterSleep.addingTimeInterval(60)))
    }

    func testFailureSchedulesTheShortRetry() {
        var state = RunState()
        state = Schedule.afterFailure(state: state, config: config, now: now)
        XCTAssertEqual(state.retryCount, 1)
        XCTAssertEqual(state.nextDueAt, now.addingTimeInterval(15 * 60))
    }

    /// Without this fallback an unreachable repository would be retried every minute
    /// forever, because the ordinary due date is already in the past.
    func testExhaustedRetriesWaitForTheNormalInterval() {
        var state = RunState()
        for _ in 0..<3 {
            state = Schedule.afterFailure(state: state, config: config, now: now)
        }
        XCTAssertEqual(state.retryCount, 3)

        state = Schedule.afterFailure(state: state, config: config, now: now)
        XCTAssertEqual(state.retryCount, 0)
        XCTAssertEqual(state.nextDueAt, now.addingTimeInterval(4 * 3600))
    }

    func testCancelLeavesTheScheduleUntouched() {
        let state = Schedule.afterSuccess(state: RunState(), config: config, now: now)
        XCTAssertEqual(Schedule.afterCancel(state: state), state)
    }

    func testCleanupIsDueOncePerDay() {
        var state = RunState()
        XCTAssertTrue(Schedule.isCleanupDue(state: state, config: config, now: now))

        state.lastCleanupAt = now
        XCTAssertFalse(Schedule.isCleanupDue(state: state, config: config, now: now.addingTimeInterval(4 * 3600)))
        XCTAssertTrue(Schedule.isCleanupDue(state: state, config: config, now: now.addingTimeInterval(24 * 3600)))
    }

    func testCleanupIntervalZeroRunsEveryTime() {
        var value = config
        value.maintenanceIntervalHours = 0
        var state = RunState()
        state.lastCleanupAt = now
        XCTAssertTrue(Schedule.isCleanupDue(state: state, config: value, now: now))
    }

    func testHistoryKeepsTheLastTwentyRuns() {
        var state = RunState()
        for index in 0..<25 {
            state.append(RunRecord(date: now.addingTimeInterval(Double(index)), outcome: .success, duration: 1, bytesAdded: Int64(index)))
        }
        XCTAssertEqual(state.history.count, 20)
        XCTAssertEqual(state.history.first?.bytesAdded, 5)
        XCTAssertEqual(state.history.last?.bytesAdded, 24)
    }
}
