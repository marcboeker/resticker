import XCTest
@testable import RestickerCore

final class RepositoryTesterTests: XCTestCase {
    func testExitZeroIsSuccess() {
        XCTAssertEqual(RepositoryTester.interpret(status: 0, stderr: ""), .success)
    }

    func testMissingRepository() {
        XCTAssertEqual(
            RepositoryTester.interpret(status: 10, stderr: "Fatal: repository does not exist"),
            .failure("No repository exists at this location. Create one with `restic init`.")
        )
    }

    func testWrongPassword() {
        XCTAssertEqual(
            RepositoryTester.interpret(status: 12, stderr: "Fatal: wrong password or no key found"),
            .failure("Wrong password for this repository.")
        )
    }

    func testSSHFailureShowsTheSSHCause() {
        let stderr = """
        subprocess ssh: ssh: Could not resolve hostname nas: nodename nor servname provided, or not known
        Fatal: unable to open repository at sftp:user@nas:/backups/mac: unable to start the sftp session, \
        error: error receiving version packet from server: server unexpectedly closed connection: unexpected EOF

        """
        XCTAssertEqual(
            RepositoryTester.interpret(status: 1, stderr: stderr),
            .failure("SSH failed: Could not resolve hostname nas: nodename nor servname provided, or not known")
        )
    }

    func testOtherFailureShowsLastLineWithoutFatalAndLocation() {
        let stderr = "Fatal: unable to open repository at s3:https://s3.amazonaws.com/bucket: Access Denied.\n"
        XCTAssertEqual(
            RepositoryTester.interpret(status: 1, stderr: stderr),
            .failure("Unable to open repository: Access Denied.")
        )
    }

    func testOtherFailureWithoutOutputShowsStatus() {
        XCTAssertEqual(RepositoryTester.interpret(status: 1, stderr: " \n"), .failure("restic exited with status 1."))
    }
}
