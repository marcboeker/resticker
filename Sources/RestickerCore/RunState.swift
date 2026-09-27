import Foundation

public struct RunRecord: Codable, Equatable {
    public enum Outcome: String, Codable {
        case success
        case failure
        case cancelled
    }

    public var date: Date
    public var outcome: Outcome
    public var duration: TimeInterval
    public var bytesAdded: Int64
    public var detail: String?

    public init(date: Date, outcome: Outcome, duration: TimeInterval, bytesAdded: Int64, detail: String? = nil) {
        self.date = date
        self.outcome = outcome
        self.duration = duration
        self.bytesAdded = bytesAdded
        self.detail = detail
    }
}

/// Everything the app remembers between launches. Written by the app, not by the user.
public struct RunState: Codable, Equatable {
    public static let historyLimit = 20

    public var lastSuccessAt: Date?
    public var lastCleanupAt: Date?
    public var nextDueAt: Date?
    public var retryCount: Int
    public var lastBytesAdded: Int64
    public var lastDuration: TimeInterval
    public var history: [RunRecord]

    public init(
        lastSuccessAt: Date? = nil,
        lastCleanupAt: Date? = nil,
        nextDueAt: Date? = nil,
        retryCount: Int = 0,
        lastBytesAdded: Int64 = 0,
        lastDuration: TimeInterval = 0,
        history: [RunRecord] = []
    ) {
        self.lastSuccessAt = lastSuccessAt
        self.lastCleanupAt = lastCleanupAt
        self.nextDueAt = nextDueAt
        self.retryCount = retryCount
        self.lastBytesAdded = lastBytesAdded
        self.lastDuration = lastDuration
        self.history = history
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastSuccessAt = try c.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        lastCleanupAt = try c.decodeIfPresent(Date.self, forKey: .lastCleanupAt)
        nextDueAt = try c.decodeIfPresent(Date.self, forKey: .nextDueAt)
        retryCount = try c.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        lastBytesAdded = try c.decodeIfPresent(Int64.self, forKey: .lastBytesAdded) ?? 0
        lastDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .lastDuration) ?? 0
        history = try c.decodeIfPresent([RunRecord].self, forKey: .history) ?? []
    }

    public mutating func append(_ record: RunRecord) {
        history.append(record)
        if history.count > RunState.historyLimit {
            history.removeFirst(history.count - RunState.historyLimit)
        }
    }

    /// True when the most recent run failed: either the whole run, or a successful
    /// backup whose unlock, cleanup, or check step failed.
    public var lastRunFailed: Bool {
        guard let last = history.last else { return false }
        return last.outcome == .failure || (last.outcome == .success && last.detail != nil)
    }
}

public enum StateStore {
    public static func load() -> RunState {
        guard let data = try? Data(contentsOf: Paths.stateFile) else { return RunState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RunState.self, from: data)) ?? RunState()
    }

    public static func save(_ state: RunState) {
        do {
            try FileManager.default.createDirectory(at: Paths.stateDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: Paths.stateFile)
        } catch {
            LogFile.shared.write("state save failed: \(error.localizedDescription)")
        }
    }
}
