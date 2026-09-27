import Foundation

/// In-memory log, capped near 5 MB. restic is far too talkative for a file.
public final class LogFile {
    public static let shared = LogFile()

    /// Held by a subscriber to receive live lines; unsubscribes automatically on deinit.
    public final class Subscription {
        fileprivate let cancel: () -> Void
        fileprivate init(cancel: @escaping () -> Void) { self.cancel = cancel }
        deinit { cancel() }
    }

    private let maxBytes = 5 * 1024 * 1024
    private let queue = DispatchQueue(label: "net.at6.resticker.log")
    private var lines: [String] = []
    private var totalBytes = 0
    private var listeners: [UUID: (String) -> Void] = [:]

    private init() {}

    public func write(_ message: String) {
        queue.async { [self] in
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(stamp) \(message)"
            append(line)
            let subscribers = Array(listeners.values)
            guard !subscribers.isEmpty else { return }
            DispatchQueue.main.async {
                for notify in subscribers { notify(line) }
            }
        }
    }

    /// Delivers the current buffer, then every new line as it arrives, on the main queue.
    public func subscribe(_ onLine: @escaping (String) -> Void) -> Subscription {
        let token = UUID()
        queue.sync {
            listeners[token] = onLine
            let snapshot = lines
            DispatchQueue.main.async {
                for line in snapshot { onLine(line) }
            }
        }
        return Subscription { [weak self] in
            self?.queue.async { self?.listeners.removeValue(forKey: token) }
        }
    }

    private func append(_ line: String) {
        lines.append(line)
        totalBytes += line.utf8.count + 1
        while totalBytes > maxBytes, lines.count > 1 {
            totalBytes -= lines.removeFirst().utf8.count + 1
        }
    }
}
