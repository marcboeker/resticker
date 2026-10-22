import XCTest
@testable import RestickerCore

final class RestoreTests: XCTestCase {
    // Lines as restic 0.19.1 prints them for `ls --json <snapshot> /src/c`.
    func testListKeepsOnlyChildrenFoldersFirst() {
        let lines = [
            #"{"time":"2026-10-22T14:07:14.262022+02:00","paths":["/src"],"hostname":"Mac.local","id":"c11c","short_id":"c11c","message_type":"snapshot","struct_type":"snapshot"}"#,
            #"{"name":"c","type":"dir","path":"/src/c","uid":501,"mode":2147484141,"message_type":"node","struct_type":"node"}"#,
            #"{"name":"f10.txt","type":"file","path":"/src/c/f10.txt","size":3,"message_type":"node","struct_type":"node"}"#,
            #"{"name":"f2.txt","type":"file","path":"/src/c/f2.txt","size":3,"message_type":"node","struct_type":"node"}"#,
            #"{"name":"lnk","type":"symlink","path":"/src/c/lnk","message_type":"node","struct_type":"node"}"#,
            #"{"name":"sub","type":"dir","path":"/src/c/sub","message_type":"node","struct_type":"node"}"#,
            "not json",
        ]
        let nodes = TreeNode.decodeList(lines: lines, directory: "/src/c")
        XCTAssertEqual(nodes.map(\.name), ["sub", "f2.txt", "f10.txt", "lnk"])
        XCTAssertTrue(nodes[0].isDirectory)
        XCTAssertEqual(nodes[1].size, 3)
    }

    func testListOfRootHasNoSelfNode() {
        let lines = [
            #"{"message_type":"snapshot","id":"x"}"#,
            #"{"name":"tmp","type":"dir","path":"/tmp","message_type":"node"}"#,
        ]
        XCTAssertEqual(TreeNode.decodeList(lines: lines, directory: "/").map(\.path), ["/tmp"])
    }

    func testSkeletonMakesTheFoldersAboveTheBackupPaths() {
        let skeleton = TreeNode.skeleton(backupPaths: ["/Users/me/Documents", "/Users/me/Pictures", "/etc/hosts", "/Users/me/a/b"])
        XCTAssertEqual(skeleton.parents, ["/Users/me", "/etc", "/Users/me/a"])
        XCTAssertEqual(skeleton.folders.mapValues { $0.map(\.path) }, [
            "/": ["/etc", "/Users"],
            "/Users": ["/Users/me"],
        ])
        XCTAssertTrue(skeleton.folders["/"]!.allSatisfy(\.isDirectory))
        // A backup of "/" itself leaves nothing to make.
        XCTAssertEqual(TreeNode.skeleton(backupPaths: ["/"]).folders, [:])
        XCTAssertEqual(TreeNode.skeleton(backupPaths: ["/"]).parents, ["/"])
        // "/a" is backed up whole, so the skeleton must not stand in for its listing.
        XCTAssertEqual(TreeNode.skeleton(backupPaths: ["/a", "/a/b/c"]).folders, [:])
    }

    func testDecodesStatus() {
        let line = #"{"message_type":"status","percent_done":0.4056,"total_files":309,"files_restored":302,"total_bytes":300001098,"bytes_restored":121685924}"#
        XCTAssertEqual(RestoreMessage.decode(line: line), .status(RestoreProgress(
            fraction: 0.4056, totalFiles: 309, filesRestored: 302, totalBytes: 300001098, bytesRestored: 121685924)))
    }

    func testDecodesSummaryWithSkippedAndEmptySummary() {
        let skipped = #"{"message_type":"summary","total_files":2,"files_restored":4,"files_skipped":2,"bytes_skipped":3}"#
        XCTAssertEqual(RestoreMessage.decode(line: skipped),
                       .summary(RestoreSummary(filesRestored: 4, filesSkipped: 2)))
        // Nothing matched the include patterns.
        XCTAssertEqual(RestoreMessage.decode(line: #"{"message_type":"summary"}"#), .summary(RestoreSummary()))
    }

    func testDecodesItemErrorOnly() {
        let item = #"{"message_type":"error","error":{"message":"mkdir /t/src/c: permission denied"},"during":"restore","item":"/src/c"}"#
        XCTAssertEqual(RestoreMessage.decode(line: item), .error("mkdir /t/src/c: permission denied"))
        let fatal = #"{"message_type":"exit_error","code":1,"message":"Fatal: There were 5 errors"}"#
        // The fatal message is not an item error; ResticCommand keeps it as the last error.
        XCTAssertNil(RestoreMessage.decode(line: fatal))
        XCTAssertNil(RestoreMessage.decode(line: "signal interrupt received, cleaning up"))
    }

    func testNormalizedDropsPathsInsideASelectedFolder() {
        let selected: Set<String> = ["/a/b", "/a/b/c.txt", "/a/b/d/e", "/a/x.txt", "/ab"]
        XCTAssertEqual(RestoreSelection.normalized(selected), ["/a/b", "/a/x.txt", "/ab"])
        XCTAssertTrue(RestoreSelection.isCovered("/a/b/c.txt", by: ["/a/b"]))
        XCTAssertFalse(RestoreSelection.isCovered("/a/b", by: ["/a/b"]))
    }

    func testArguments() {
        XCTAssertEqual(
            RestoreSelection.arguments(snapshotId: "c11c", target: "/Volumes/out", paths: ["/src/c", "/src/we[i]rd/x*y.txt"]),
            ["restore", "c11c", "--target", "/Volumes/out",
             "--include", "/src/c", "--include", #"/src/we\[i\]rd/x\*y.txt"#,
             "--overwrite", "never", "--json"])
    }

    // restic 0.19.1 on SIGINT mid-run: exit 130, no summary. A Cancel click after the summary
    // (or after restic exited) must not hide a finished restore.
    func testOutcomeResult() {
        XCTAssertEqual(RestoreOutcome.result(cancelled: true, status: 130, hasSummary: false), .cancelled)
        XCTAssertEqual(RestoreOutcome.result(cancelled: true, status: 0, hasSummary: true), .completed)
        XCTAssertEqual(RestoreOutcome.result(cancelled: false, status: 1, hasSummary: true), .completed)
        XCTAssertEqual(RestoreOutcome.result(cancelled: false, status: 1, hasSummary: false), .failed)
        XCTAssertEqual(RestoreOutcome.result(cancelled: false, status: 0, hasSummary: false), .completed)
    }
}
