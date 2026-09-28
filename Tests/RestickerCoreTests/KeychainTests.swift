import Security
import XCTest
@testable import RestickerCore

final class KeychainTests: XCTestCase {
    /// A denied read stops scheduled runs; any other failure lets them retry each minute.
    func testDenyAndCancelInTheDialogCountAsDenied() {
        XCTAssertEqual(KeychainReadError(status: errSecAuthFailed), .denied)
        XCTAssertEqual(KeychainReadError(status: errSecUserCanceled), .denied)
        XCTAssertEqual(KeychainReadError(status: errSecItemNotFound), .notFound)
        XCTAssertEqual(KeychainReadError(status: errSecInteractionNotAllowed), .failed(errSecInteractionNotAllowed))
    }
}
