import XCTest
@testable import RestickerCore

final class ResticMessageTests: XCTestCase {
    func testDecodesStatus() {
        let line = #"{"message_type":"status","seconds_elapsed":12,"percent_done":0.4212,"total_files":100,"files_done":42,"total_bytes":1000,"bytes_done":421,"current_files":["/Users/tester/a.txt"]}"#
        guard case .status(let bytesRemaining, let file)? = ResticMessage.decode(line: line) else {
            return XCTFail("expected a status message")
        }
        XCTAssertEqual(bytesRemaining, 579)
        XCTAssertEqual(file, "/Users/tester/a.txt")
    }

    func testDecodesSummaryAndPrefersThePackedFigure() {
        let line = #"{"message_type":"summary","files_new":3,"files_changed":2,"files_unmodified":900,"data_added":10485760,"data_added_packed":4194304,"total_files_processed":905,"total_bytes_processed":52428800,"total_duration":201.5,"snapshot_id":"abc123"}"#
        guard case .summary(let summary)? = ResticMessage.decode(line: line) else {
            return XCTFail("expected a summary message")
        }
        XCTAssertEqual(summary.dataAddedPacked, 4_194_304)
        XCTAssertEqual(summary.dataAdded, 10_485_760)
        XCTAssertEqual(summary.filesNew, 3)
        XCTAssertEqual(summary.totalDuration, 201.5, accuracy: 0.001)
        XCTAssertEqual(summary.snapshotId, "abc123")
    }

    func testSummaryWithoutPackedFigureFallsBackToDataAdded() {
        let line = #"{"message_type":"summary","data_added":2048,"total_duration":1}"#
        guard case .summary(let summary)? = ResticMessage.decode(line: line) else {
            return XCTFail("expected a summary message")
        }
        XCTAssertEqual(summary.dataAddedPacked, 2048)
    }

    func testDecodesError() {
        let line = #"{"message_type":"error","error":{"message":"permission denied"},"during":"archival","item":"/Users/tester/secret"}"#
        guard case .error(let text)? = ResticMessage.decode(line: line) else {
            return XCTFail("expected an error message")
        }
        XCTAssertEqual(text, "permission denied (/Users/tester/secret)")
    }

    func testIgnoresPlainTextAndUnknownTypes() {
        XCTAssertNil(ResticMessage.decode(line: "using parent snapshot 1a2b3c"))
        XCTAssertNil(ResticMessage.decode(line: ""))
        XCTAssertNil(ResticMessage.decode(line: #"{"message_type":"verbose_status","action":"unchanged"}"#))
        XCTAssertNil(ResticMessage.decode(line: "{not json"))
    }
}
