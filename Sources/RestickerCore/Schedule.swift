import Foundation

/// Pure schedule arithmetic. A wrong answer here means backups silently never run,
/// so this is the one part of the app that is unit tested.
public enum Schedule {
    /// A run is due when the stored due date has passed. A missing due date means
    /// the app has never run, so it is due at once. Sleep needs no special case:
    /// after a wake the due date is simply in the past.
    public static func isRunDue(state: RunState, now: Date) -> Bool {
        guard let due = state.nextDueAt else { return true }
        return now >= due
    }

    public static func afterSuccess(state: RunState, config: Config, now: Date) -> RunState {
        var next = state
        next.lastSuccessAt = now
        next.nextDueAt = now.addingTimeInterval(config.interval)
        next.retryCount = 0
        return next
    }

    /// Retries use the short delay until they run out, then the run waits for the
    /// normal interval. Without that fallback an unreachable repository would be
    /// retried forever, because the regular due date is already in the past.
    public static func afterFailure(state: RunState, config: Config, now: Date) -> RunState {
        var next = state
        if next.retryCount < config.maxRetries {
            next.retryCount += 1
            next.nextDueAt = now.addingTimeInterval(config.retryDelay)
        } else {
            next.retryCount = 0
            next.nextDueAt = now.addingTimeInterval(config.interval)
        }
        return next
    }

    /// A cancelled run counts as neither success nor failure, so the schedule does not move.
    public static func afterCancel(state: RunState) -> RunState {
        state
    }

    /// Maintenance runs at most once per cleanup interval, and only after a backup succeeded.
    public static func isCleanupDue(state: RunState, config: Config, now: Date) -> Bool {
        if config.maintenanceIntervalHours <= 0 { return true }
        guard let last = state.lastCleanupAt else { return true }
        return now >= last.addingTimeInterval(config.maintenanceInterval)
    }
}
