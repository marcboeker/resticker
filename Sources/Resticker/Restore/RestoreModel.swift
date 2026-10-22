import AppKit
import RestickerCore

extension Snapshot: Identifiable {}

/// The figures of a running restore. They change twice a second, so only the bottom bar
/// observes them, and the rest of the window does not redraw.
@MainActor
final class RestoreProgressState: ObservableObject {
    @Published var value: RestoreProgress?
}

/// What the Restore window shows: the snapshots, the lazily loaded file tree of the
/// selected one, the checked items, and the state of the restore run. `AppDelegate` owns
/// the run itself and feeds its state into `run` and `progress`.
@MainActor
final class RestoreModel: ObservableObject {
    struct Finished {
        let text: String
        let target: URL
        let errorCount: Int
    }

    enum Run {
        case idle
        case running
        case finished(Finished)
    }

    @Published var snapshots: [Snapshot] = [] {
        didSet {
            showsHost = Set(snapshots.compactMap(\.hostname)).count > 1
            showsPaths = Set(snapshots.map { ($0.paths ?? []).sorted() }).count > 1
        }
    }
    /// The host and the paths only tell snapshots apart when the repository has several.
    private(set) var showsHost = false
    private(set) var showsPaths = false
    @Published var loadingSnapshots = false
    @Published var selectedID: Snapshot.ID? {
        didSet { if selectedID != oldValue { snapshotChanged() } }
    }
    /// Directory path -> its children, per snapshot ID. A snapshot never changes, so this is
    /// kept until the snapshot is gone from the repository.
    @Published private var cache: [Snapshot.ID: [String: [TreeNode]]] = [:]
    /// The listings in flight, by "snapshot ID + directory".
    @Published private var listings: [String: TreeListing] = [:]
    @Published private(set) var expanded: Set<String> = []
    /// Never holds a path inside another selected path.
    @Published private(set) var selected: Set<String> = []
    @Published var run: Run = .idle
    let progress = RestoreProgressState()
    @Published var isCancelling = false
    @Published var errorText: String?

    /// Set by the window controller, which owns the folder panel.
    var onRestore: () -> Void = {}
    var onCancel: () -> Void = {}
    private var config = Config.default
    private var secrets: RepositorySecrets?

    var isRunning: Bool {
        if case .running = run { return true }
        return false
    }

    var selectedSnapshot: Snapshot? { snapshots.first { $0.id == selectedID } }

    // MARK: - Snapshots

    /// Lists every snapshot and selects the newest.
    func open(config: Config, secrets: RepositorySecrets?) {
        self.config = config
        self.secrets = secrets
        selectedID = nil
        errorText = secrets == nil ? "Could not read the repository password from the keychain." : nil
        guard let secrets else { return }
        loadingSnapshots = true
        SnapshotLister.fetch(config: config, secrets: secrets, limit: nil) { [weak self] snapshots in
            guard let self else { return }
            self.loadingSnapshots = false
            self.snapshots = snapshots
            let ids = Set(snapshots.map(\.id))
            self.cache = self.cache.filter { ids.contains($0.key) }
            self.selectedID = snapshots.first?.id
        }
    }

    /// Stops every listing in flight: nobody looks at their snapshot any more.
    func cancelListings() {
        listings.values.forEach { $0.cancel() }
        listings = [:]
    }

    /// Lists the open folders again whose listings closing the window cancelled.
    func listExpanded() {
        expanded.union(["/"]).forEach(load)
    }

    private func snapshotChanged() {
        cancelListings()
        selected = []
        expanded = []
        errorText = nil
        if case .finished = run { run = .idle }
        guard let snapshot = selectedSnapshot else { return }
        guard let paths = snapshot.paths, !paths.isEmpty else { return load("/") }
        // Open the tree down to the backup paths. restic lists only their parent folders.
        let skeleton = TreeNode.skeleton(backupPaths: paths)
        cache[snapshot.id, default: [:]].merge(skeleton.folders) { cached, _ in cached }
        expanded = Set(skeleton.folders.keys).union(skeleton.parents)
        skeleton.parents.forEach(load)
    }

    // MARK: - Tree

    struct Row: Identifiable {
        let node: TreeNode
        let depth: Int
        var id: String { node.path }
    }

    /// The visible rows: expanded folders followed by their children.
    var rows: [Row] {
        guard let selectedID, let tree = cache[selectedID] else { return [] }
        var rows: [Row] = []
        func append(_ directory: String, depth: Int) {
            for node in tree[directory] ?? [] {
                rows.append(Row(node: node, depth: depth))
                if expanded.contains(node.path) { append(node.path, depth: depth + 1) }
            }
        }
        append("/", depth: 0)
        return rows
    }

    func isLoading(_ directory: String) -> Bool {
        selectedID.map { listings[$0 + directory] != nil } ?? false
    }

    func toggleExpanded(_ directory: String) {
        if expanded.remove(directory) == nil {
            expanded.insert(directory)
            load(directory)
        }
    }

    private func load(_ directory: String) {
        guard let id = selectedID, let secrets, cache[id]?[directory] == nil, listings[id + directory] == nil else { return }
        listings[id + directory] = SnapshotTree.list(config: config, secrets: secrets, snapshotId: id, directory: directory) { [weak self] result in
            guard let self else { return }
            self.listings[id + directory] = nil
            switch result {
            case .success(let nodes):
                self.cache[id, default: [:]][directory] = nodes
                // A folder that holds only a folder opens down to where its content branches.
                if id == self.selectedID, nodes.count == 1, let only = nodes.first, only.isDirectory {
                    self.expanded.insert(only.path)
                    self.load(only.path)
                }
            case .failure(let error) where id == self.selectedID:
                self.errorText = "Could not list \(directory): \(error.message)"
            case .failure:
                break
            }
        }
    }

    // MARK: - Selection

    /// A folder inside a checked folder shows as checked and cannot change.
    func isLocked(_ path: String) -> Bool {
        RestoreSelection.isCovered(path, by: selected)
    }

    func isChecked(_ path: String) -> Bool {
        selected.contains(path) || isLocked(path)
    }

    func toggle(_ path: String) {
        guard !isLocked(path) else { return }
        if selected.remove(path) == nil {
            selected.insert(path)
            selected = Set(RestoreSelection.normalized(selected))
        }
        if case .finished = run { run = .idle }
    }

    var selectedPaths: [String] { selected.sorted() }

    // MARK: - Run result

    /// Shows the finished run in the bottom bar and returns its line.
    @discardableResult
    func finish(_ outcome: RestoreOutcome, target: URL) -> String {
        let text: String
        switch outcome.result {
        case .cancelled:
            text = "Restore cancelled"
        case .failed:
            text = "Restore failed: \(outcome.message ?? "see the log for details")"
        case .completed:
            let summary = outcome.summary ?? RestoreSummary()
            text = "Restored \(summary.filesRestored) \(summary.filesRestored == 1 ? "file" : "files") "
                + "(\(Formatting.bytes(summary.bytesRestored))), \(summary.filesSkipped) skipped, "
                + "\(outcome.errorCount) \(outcome.errorCount == 1 ? "error" : "errors")"
        }
        isCancelling = false
        run = .finished(Finished(text: text, target: target, errorCount: outcome.errorCount))
        return text
    }
}
