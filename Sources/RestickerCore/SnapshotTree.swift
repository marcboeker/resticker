import Foundation

/// One file or folder of a snapshot, from a `node` line of `restic ls --json`.
public struct TreeNode: Decodable, Equatable, Identifiable {
    public let name: String
    public let type: String
    /// Absolute path inside the snapshot.
    public let path: String
    public let size: Int64?

    public var id: String { path }
    public var isDirectory: Bool { type == "dir" }

    public init(name: String, type: String, path: String, size: Int64? = nil) {
        self.name = name
        self.type = type
        self.path = path
        self.size = size
    }

    private struct Line: Decodable {
        let messageType: String?
        let node: TreeNode?

        enum CodingKeys: String, CodingKey { case messageType = "message_type" }

        init(from decoder: Decoder) throws {
            messageType = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .messageType)
            node = messageType == "node" ? try TreeNode(from: decoder) : nil
        }
    }

    /// Decodes the lines `restic ls --json <snapshot> <directory>` prints: the snapshot, then
    /// `directory` itself (unless it is the root), then its children. Only the children
    /// are returned, folders first, then by name.
    static func decodeList(lines: [String], directory: String) -> [TreeNode] {
        let decoder = JSONDecoder()
        let nodes = lines.compactMap { line -> TreeNode? in
            guard let data = line.data(using: .utf8) else { return nil }
            return (try? decoder.decode(Line.self, from: data))?.node
        }
        return nodes.filter { $0.path != directory }.sorted(by: displayOrder)
    }

    private static func displayOrder(_ a: TreeNode, _ b: TreeNode) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// A snapshot holds only its backup paths and the folders above them, so the folders
    /// above the backup paths' parent folders need no `restic ls`. Returns those folders'
    /// children, and the parent folders, which restic still has to list: only it knows
    /// whether a backup path is a file or a folder.
    public static func skeleton(backupPaths: [String]) -> (folders: [String: [TreeNode]], parents: Set<String>) {
        let roots = Set(backupPaths)
        let parents = Set(backupPaths.map { ($0 as NSString).deletingLastPathComponent })
        var children: [String: Set<String>] = [:]
        for parent in parents {
            var path = parent
            while path.hasPrefix("/") && path != "/" {
                let up = (path as NSString).deletingLastPathComponent
                // A folder that is, or lies inside, a backup path holds more than the
                // skeleton knows, so restic lists it.
                let isBackedUp = roots.contains(up) || RestoreSelection.isCovered(up, by: roots)
                if !parents.contains(up) && !isBackedUp { children[up, default: []].insert(path) }
                path = up
            }
        }
        let folders = children.mapValues { paths in
            paths.map { TreeNode(name: ($0 as NSString).lastPathComponent, type: "dir", path: $0) }
                .sorted(by: displayOrder)
        }
        return (folders, parents)
    }
}

public struct TreeListError: Error {
    public let message: String
}

/// A running `restic ls`. Cancelling it stops restic and drops the result, so a listing
/// nobody waits for does not hold repository locks or bandwidth.
public final class TreeListing {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    init() {}

    var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    /// SIGINT lets restic remove its lock before it exits; SIGKILL is the last resort.
    public func cancel() {
        lock.lock()
        isCancelled = true
        let process = process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.interrupt()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// Starting under the lock means `cancel()` either sets the flag before this sees it, or
    /// finds the process running; it can never miss it. Returns false when cancelled.
    fileprivate func start(_ process: Process) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled { return false }
        try process.run()
        self.process = process
        return true
    }
}

public enum SnapshotTree {
    /// Lists one level of `directory` ("/" for the top) off the main thread. Errors go to the log.
    /// After `cancel()` on the main thread, `completion` is not called.
    @discardableResult
    public static func list(
        config: Config,
        secrets: RepositorySecrets,
        snapshotId: String,
        directory: String,
        completion: @escaping (Result<[TreeNode], TreeListError>) -> Void
    ) -> TreeListing {
        let listing = TreeListing()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = run(listing, config: config, secrets: secrets, snapshotId: snapshotId, directory: directory)
            DispatchQueue.main.async {
                if !listing.cancelled { completion(result) }
            }
        }
        return listing
    }

    private static func run(
        _ listing: TreeListing, config: Config, secrets: RepositorySecrets, snapshotId: String, directory: String
    ) -> Result<[TreeNode], TreeListError> {
        let process = ResticProcess.make(config: config, secrets: secrets,
                                         arguments: ["ls", "--json", snapshotId, directory])
        // One pipe for both streams, so neither can fill up and stop restic. With --json
        // the errors are JSON lines too, and the node decoder skips them.
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            guard try listing.start(process) else {
                return .failure(TreeListError(message: "cancelled"))
            }
        } catch {
            LogFile.shared.write("[ls!] could not start: \(error.localizedDescription)")
            return .failure(TreeListError(message: error.localizedDescription))
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if listing.cancelled { return .failure(TreeListError(message: "cancelled")) }

        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        guard process.terminationStatus == 0 else {
            let message = lines.compactMap { ResticMessage.errorText(stderrLine: $0) }.last ?? "restic exited with code \(process.terminationStatus)"
            LogFile.shared.write("[ls!] \(message)")
            return .failure(TreeListError(message: message))
        }
        return .success(TreeNode.decodeList(lines: lines, directory: directory))
    }
}
