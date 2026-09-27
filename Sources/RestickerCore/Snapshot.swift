import Foundation

/// One entry from `restic snapshots --json`.
public struct Snapshot: Decodable {
    public let id: String
    public let shortId: String
    public let time: Date
    /// restic started recording a summary per snapshot only in recent versions, so older
    /// snapshots carry none. It is the same payload `restic backup --json` ends with.
    public let summary: BackupSummary?

    /// Total size of the files backed up at that point, nil when the snapshot has no summary.
    public var totalSize: Int64? { summary?.totalBytesProcessed }

    private enum CodingKeys: String, CodingKey {
        case id
        case shortId = "short_id"
        case time
        case summary
    }

    /// Decodes the array `restic snapshots --json` prints, and returns the newest first.
    static func decodeList(from data: Data, limit: Int? = nil) throws -> [Snapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ResticDate.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad restic timestamp: \(string)")
        }
        let snapshots = try decoder.decode([Snapshot].self, from: data).sorted { $0.time > $1.time }
        guard let limit else { return snapshots }
        return Array(snapshots.prefix(limit))
    }
}

/// restic emits RFC3339 timestamps with nanosecond fractions, more digits than
/// ISO8601DateFormatter parses. Nothing here needs sub-second precision — the menu shows
/// minutes — so the fraction is dropped before parsing.
enum ResticDate {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        let plain = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return formatter.date(from: plain)
    }
}

/// Lists the newest snapshots off the main thread.
public enum SnapshotLister {
    public static func fetch(config: Config, password: String, limit: Int, completion: @escaping ([Snapshot]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let snapshots = run(config: config, password: password, limit: limit)
            DispatchQueue.main.async { completion(snapshots) }
        }
    }

    private static func run(config: Config, password: String, limit: Int) -> [Snapshot] {
        // `--latest` counts per host and path group, so it can return more than `limit`
        // rows. The list is cut to size again after decoding.
        let process = ResticProcess.make(config: config, password: password,
                                         arguments: ["snapshots", "--json", "--latest", String(limit)])

        let output = Pipe()
        process.standardOutput = output
        // Nothing reads restic's diagnostics here, and an undrained pipe would stop the
        // child once its buffer fills.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            LogFile.shared.write("snapshot list could not start: \(error.localizedDescription)")
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            LogFile.shared.write("snapshot list exited \(process.terminationStatus)")
            return []
        }

        guard let snapshots = try? Snapshot.decodeList(from: data, limit: limit) else {
            LogFile.shared.write("snapshot list decode failed")
            return []
        }
        return snapshots
    }
}
