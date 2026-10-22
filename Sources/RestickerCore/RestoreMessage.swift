import Foundation

/// The final message of `restic restore --json`. restic leaves out the counters that are
/// zero, and an empty run (nothing matched) prints no counters at all.
public struct RestoreSummary: Decodable, Equatable {
    public var filesRestored: Int
    public var filesSkipped: Int
    public var bytesRestored: Int64

    enum CodingKeys: String, CodingKey {
        case filesRestored = "files_restored"
        case filesSkipped = "files_skipped"
        case bytesRestored = "bytes_restored"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filesRestored = try c.decodeIfPresent(Int.self, forKey: .filesRestored) ?? 0
        filesSkipped = try c.decodeIfPresent(Int.self, forKey: .filesSkipped) ?? 0
        bytesRestored = try c.decodeIfPresent(Int64.self, forKey: .bytesRestored) ?? 0
    }

    public init(filesRestored: Int = 0, filesSkipped: Int = 0, bytesRestored: Int64 = 0) {
        self.filesRestored = filesRestored
        self.filesSkipped = filesSkipped
        self.bytesRestored = bytesRestored
    }
}

/// One `status` message of `restic restore --json`.
public struct RestoreProgress: Decodable, Equatable {
    /// 0...1
    public var fraction: Double
    public var totalFiles: Int
    public var filesRestored: Int
    public var totalBytes: Int64
    public var bytesRestored: Int64

    enum CodingKeys: String, CodingKey {
        case fraction = "percent_done"
        case totalFiles = "total_files"
        case filesRestored = "files_restored"
        case totalBytes = "total_bytes"
        case bytesRestored = "bytes_restored"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fraction = min(max(try c.decodeIfPresent(Double.self, forKey: .fraction) ?? 0, 0), 1)
        totalFiles = try c.decodeIfPresent(Int.self, forKey: .totalFiles) ?? 0
        filesRestored = try c.decodeIfPresent(Int.self, forKey: .filesRestored) ?? 0
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        bytesRestored = try c.decodeIfPresent(Int64.self, forKey: .bytesRestored) ?? 0
    }

    public init(fraction: Double = 0, totalFiles: Int = 0, filesRestored: Int = 0,
                totalBytes: Int64 = 0, bytesRestored: Int64 = 0) {
        self.fraction = fraction
        self.totalFiles = totalFiles
        self.filesRestored = filesRestored
        self.totalBytes = totalBytes
        self.bytesRestored = bytesRestored
    }
}

public enum RestoreMessage: Equatable {
    case status(RestoreProgress)
    case summary(RestoreSummary)
    /// One file or directory that could not be restored. The run goes on.
    case error(String)

    private struct Envelope: Decodable {
        let messageType: String?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
        }
    }

    private static let decoder = JSONDecoder()

    /// Returns nil for anything that is not a restic JSON message.
    public static func decode(line: String) -> RestoreMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let envelope = try? decoder.decode(Envelope.self, from: data) else { return nil }

        switch envelope.messageType {
        case "status":
            return (try? decoder.decode(RestoreProgress.self, from: data)).map(RestoreMessage.status)
        case "summary":
            return (try? decoder.decode(RestoreSummary.self, from: data)).map(RestoreMessage.summary)
        case "error":
            if case .error(let text)? = ResticMessage.decode(line: trimmed) { return .error(text) }
            return nil
        default:
            return nil
        }
    }
}
