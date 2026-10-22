import XCTest
@testable import RestickerCore

final class SnapshotTreeCancelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// A stand-in for a slow `restic ls`: it marks that it started, then waits until SIGINT.
    private func config() throws -> Config {
        let url = directory.appendingPathComponent("restic")
        let script = """
        #!/bin/sh
        touch "\(directory.path)/started"
        trap 'touch "\(directory.path)/interrupted"; exit 130' INT
        sleep 30 &
        wait
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        var config = Config.default
        config.resticBinaryPath = url.path
        config.resticGlobalArgs = []
        return config
    }

    private func list(_ config: Config, onCompletion: @escaping () -> Void) -> TreeListing {
        SnapshotTree.list(config: config, secrets: RepositorySecrets(password: "x", environment: [:]),
                          snapshotId: "abc", directory: "/") { _ in onCompletion() }
    }

    private func wait(for file: String) -> Bool {
        let path = directory.appendingPathComponent(file).path
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    func testCancelInterruptsRunningListingWithoutCompletion() throws {
        var completed = false
        let listing = list(try config()) { completed = true }
        XCTAssertTrue(wait(for: "started"))
        listing.cancel()
        XCTAssertTrue(wait(for: "interrupted"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(completed)
    }

    func testCancelRightAfterListSkipsCompletion() throws {
        var completed = false
        list(try config()) { completed = true }.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(completed)
    }
}
