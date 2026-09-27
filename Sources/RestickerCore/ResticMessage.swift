import Foundation

/// The final message of `restic backup --json`.
public struct BackupSummary: Codable, Equatable {
    public var filesNew: Int
    public var filesChanged: Int
    public var filesUnmodified: Int
    public var dataAdded: Int64
    public var dataAddedPacked: Int64
    public var totalFilesProcessed: Int
    public var totalBytesProcessed: Int64
    public var totalDuration: Double
    public var snapshotId: String?

    enum CodingKeys: String, CodingKey {
        case filesNew = "files_new"
        case filesChanged = "files_changed"
        case filesUnmodified = "files_unmodified"
        case dataAdded = "data_added"
        case dataAddedPacked = "data_added_packed"
        case totalFilesProcessed = "total_files_processed"
        case totalBytesProcessed = "total_bytes_processed"
        case totalDuration = "total_duration"
        case snapshotId = "snapshot_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filesNew = try c.decodeIfPresent(Int.self, forKey: .filesNew) ?? 0
        filesChanged = try c.decodeIfPresent(Int.self, forKey: .filesChanged) ?? 0
        filesUnmodified = try c.decodeIfPresent(Int.self, forKey: .filesUnmodified) ?? 0
        dataAdded = try c.decodeIfPresent(Int64.self, forKey: .dataAdded) ?? 0
        // Older restic builds have no packed figure. Fall back so the menu never shows zero
        // for a run that really did upload data.
        dataAddedPacked = try c.decodeIfPresent(Int64.self, forKey: .dataAddedPacked) ?? dataAdded
        totalFilesProcessed = try c.decodeIfPresent(Int.self, forKey: .totalFilesProcessed) ?? 0
        totalBytesProcessed = try c.decodeIfPresent(Int64.self, forKey: .totalBytesProcessed) ?? 0
        totalDuration = try c.decodeIfPresent(Double.self, forKey: .totalDuration) ?? 0
        snapshotId = try c.decodeIfPresent(String.self, forKey: .snapshotId)
    }

    public init(
        filesNew: Int = 0,
        filesChanged: Int = 0,
        filesUnmodified: Int = 0,
        dataAdded: Int64 = 0,
        dataAddedPacked: Int64 = 0,
        totalFilesProcessed: Int = 0,
        totalBytesProcessed: Int64 = 0,
        totalDuration: Double = 0,
        snapshotId: String? = nil
    ) {
        self.filesNew = filesNew
        self.filesChanged = filesChanged
        self.filesUnmodified = filesUnmodified
        self.dataAdded = dataAdded
        self.dataAddedPacked = dataAddedPacked
        self.totalFilesProcessed = totalFilesProcessed
        self.totalBytesProcessed = totalBytesProcessed
        self.totalDuration = totalDuration
        self.snapshotId = snapshotId
    }
}

public enum ResticMessage: Equatable {
    case status(bytesRemaining: Int64?, currentFile: String?)
    case summary(BackupSummary)
    case error(String)

    private struct Envelope: Decodable {
        let messageType: String?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
        }
    }

    private struct Status: Decodable {
        let totalBytes: Int64?
        let bytesDone: Int64?
        let currentFiles: [String]?

        enum CodingKeys: String, CodingKey {
            case totalBytes = "total_bytes"
            case bytesDone = "bytes_done"
            case currentFiles = "current_files"
        }
    }

    private struct ErrorMessage: Decodable {
        let error: Detail?
        let during: String?
        let item: String?

        struct Detail: Decodable {
            let message: String?
        }
    }

    /// Returns nil for anything that is not a restic JSON message, which includes
    /// plain text warnings on stderr. Those go to the log untouched.
    public static func decode(line: String) -> ResticMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return nil }

        switch envelope.messageType {
        case "status":
            guard let status = try? decoder.decode(Status.self, from: data) else { return nil }
            var remaining: Int64?
            if let total = status.totalBytes, let done = status.bytesDone {
                remaining = max(0, total - done)
            }
            return .status(bytesRemaining: remaining, currentFile: status.currentFiles?.first)
        case "summary":
            guard let summary = try? decoder.decode(BackupSummary.self, from: data) else { return nil }
            return .summary(summary)
        case "error":
            guard let message = try? decoder.decode(ErrorMessage.self, from: data) else { return nil }
            let text = message.error?.message ?? "unknown error"
            if let item = message.item, !item.isEmpty {
                return .error("\(text) (\(item))")
            }
            return .error(text)
        default:
            return nil
        }
    }
}
