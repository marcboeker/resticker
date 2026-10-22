import SwiftUI
import RestickerCore

struct RestoreView: View {
    @ObservedObject var model: RestoreModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                SnapshotList(model: model)
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                TreeList(model: model)
                    .frame(minWidth: 320)
            }
            Divider()
            BottomBar(model: model)
        }
    }
}

private struct SnapshotList: View {
    @ObservedObject var model: RestoreModel

    var body: some View {
        List(model.snapshots, selection: $model.selectedID) { snapshot in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Formatting.timestamp(snapshot.time)).fontWeight(.semibold)
                    Spacer()
                    Text(snapshot.totalSize.map(Formatting.bytes) ?? "—").foregroundStyle(.secondary)
                    Text(snapshot.shortId).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
                if let origin = origin(of: snapshot) {
                    Text(origin).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if model.loadingSnapshots {
                ProgressView().controlSize(.small)
            } else if model.snapshots.isEmpty {
                Text("No snapshots").foregroundStyle(.secondary)
            }
        }
    }

    private func origin(of snapshot: Snapshot) -> String? {
        var parts: [String] = []
        if model.showsHost, let host = snapshot.hostname { parts.append(host) }
        if model.showsPaths, let paths = snapshot.paths { parts.append(paths.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct TreeList: View {
    @ObservedObject var model: RestoreModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.errorText {
                Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                Divider()
            }
            let running = model.isRunning
            List(model.rows) { row in
                let path = row.node.path
                let isLocked = model.isLocked(path)
                TreeRow(
                    node: row.node,
                    depth: row.depth,
                    isExpanded: model.expanded.contains(path),
                    isChecked: model.isChecked(path),
                    isLoading: model.isLoading(path),
                    disabled: isLocked || running,
                    onExpand: { model.toggleExpanded(path) },
                    onToggle: { model.toggle(path) }
                )
                .equatable()
            }
            .listStyle(.plain)
            .overlay {
                if model.isLoading("/") { ProgressView().controlSize(.small) }
            }
        }
    }
}

/// Takes plain values and compares them without the closures, so a model change redraws
/// only the rows whose values changed.
private struct TreeRow: View, Equatable {
    let node: TreeNode
    let depth: Int
    let isExpanded: Bool
    let isChecked: Bool
    let isLoading: Bool
    let disabled: Bool
    let onExpand: () -> Void
    let onToggle: () -> Void

    static func == (lhs: TreeRow, rhs: TreeRow) -> Bool {
        lhs.node == rhs.node && lhs.depth == rhs.depth && lhs.isExpanded == rhs.isExpanded
            && lhs.isChecked == rhs.isChecked && lhs.isLoading == rhs.isLoading && lhs.disabled == rhs.disabled
    }

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(depth) * 16, height: 1)
            if node.isDirectory {
                Button(action: onExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            Toggle("", isOn: Binding(get: { isChecked }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(disabled)
            Image(systemName: node.isDirectory ? "folder" : "doc").foregroundStyle(.secondary)
            Text(node.name).lineLimit(1).truncationMode(.middle)
            if isLoading { ProgressView().controlSize(.mini) }
            Spacer()
            if let size = node.size {
                Text(Formatting.bytes(size)).foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}

private struct BottomBar: View {
    @ObservedObject var model: RestoreModel

    var body: some View {
        HStack(spacing: 12) {
            switch model.run {
            case .running:
                RunningFigures(progress: model.progress)
                Spacer()
                Button("Cancel") { model.onCancel() }.disabled(model.isCancelling)
            case .finished(let result):
                Text(result.text)
                if result.errorCount > 0 {
                    Button("Show Log") { LogWindowController.shared.show() }.buttonStyle(.link)
                }
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.open(result.target) }
                restoreButton
            case .idle:
                if !model.selected.isEmpty {
                    Text("\(model.selected.count) \(model.selected.count == 1 ? "item" : "items") selected")
                }
                Spacer()
                restoreButton
            }
        }
        .padding(10)
    }

    @ViewBuilder private var restoreButton: some View {
        if !model.selected.isEmpty {
            Button("Restore…") { model.onRestore() }.keyboardShortcut(.defaultAction)
        }
    }
}

/// The only view that observes the progress ticks.
private struct RunningFigures: View {
    @ObservedObject var progress: RestoreProgressState

    var body: some View {
        ProgressView(value: progress.value?.fraction).frame(width: 160)
        Text(Self.figures(progress.value)).monospacedDigit().foregroundStyle(.secondary)
    }

    private static func figures(_ progress: RestoreProgress?) -> String {
        guard let progress else { return "Starting…" }
        return "\(Int(progress.fraction * 100))% · \(progress.filesRestored) of \(progress.totalFiles) files · "
            + "\(Formatting.bytes(progress.bytesRestored)) of \(Formatting.bytes(progress.totalBytes))"
    }
}
