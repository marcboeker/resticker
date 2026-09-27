import XCTest
@testable import RestickerCore

final class ResticLocatorTests: XCTestCase {
    func testFindsResticAtTheFirstCommonPath() {
        let found = ResticLocator.detect(
            fileExists: { $0 == "/opt/homebrew/bin/restic" },
            shellPath: { XCTFail("should not need PATH when a common path exists"); return nil }
        )
        XCTAssertEqual(found, "/opt/homebrew/bin/restic")
    }

    func testTriesCommonPathsInOrder() {
        let found = ResticLocator.detect(
            fileExists: { $0 == "/usr/bin/restic" },
            shellPath: { nil }
        )
        XCTAssertEqual(found, "/usr/bin/restic")
    }

    func testFallsBackToShellPath() {
        let found = ResticLocator.detect(
            fileExists: { $0 == "/opt/restic/bin/restic" },
            shellPath: { "/usr/bin:/opt/restic/bin:/bin" }
        )
        XCTAssertEqual(found, "/opt/restic/bin/restic")
    }

    func testReturnsNilWhenNothingIsFound() {
        let found = ResticLocator.detect(
            fileExists: { _ in false },
            shellPath: { "/usr/bin:/bin" }
        )
        XCTAssertNil(found)
    }

    func testReturnsNilWhenShellPathIsUnavailable() {
        let found = ResticLocator.detect(
            fileExists: { _ in false },
            shellPath: { nil }
        )
        XCTAssertNil(found)
    }
}
