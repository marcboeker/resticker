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

    /// Records a maintenance pass unless its forget step failed. A failed forget left the
    /// old snapshots in place, so cleanup stays due and the next backup tries again. A
    /// failed check still counts: the repository needs a person, and repeating an
    /// expensive check after every backup would only repeat the same notification.
    public static func afterMaintenance(state: RunState, failedStep: PipelineStep?, now: Date) -> RunState {
        guard failedStep != .forget else { return state }
        var next = state
        next.lastCleanupAt = now
        return next
    }

    /// Recomputes the next due date after `backupIntervalMinutes` changes in Settings, so
    /// a shorter interval takes effect right away instead of waiting for a due date that
    /// was set under the old one.
    public static func afterIntervalChange(state: RunState, config: Config) -> RunState {
        // A pending retry is on its own short schedule; leave it alone regardless of what
        // the regular interval just changed to.
        guard state.retryCount == 0 else { return state }
        // After the retries ran out, `nextDueAt` counts from that failure, not from the
        // last success; recomputing from the success would restart the retry cycle at once.
        guard state.history.last?.outcome != .failure else { return state }
        guard let lastSuccess = state.lastSuccessAt else { return state }
        var next = state
        // If this lands in the past, that just means the next tick finds it due —
        // isRunDue needs no special case for it.
        next.nextDueAt = lastSuccess.addingTimeInterval(config.interval)
        return next
    }
}
