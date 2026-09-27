import XCTest
@testable import RestickerCore

final class SnapshotTests: XCTestCase {
    func testDecodesListNewestFirstWithNanosecondTimestamps() throws {
        let json = """
        [
          {
            "time": "2026-09-10T08:12:03.123456789+02:00",
            "tree": "abcd",
            "paths": ["/Users/tester"],
            "hostname": "mac",
            "id": "1111111111111111111111111111111111111111111111111111111111111111",
            "short_id": "11111111",
            "summary": {
              "total_bytes_processed": 52428800
            }
          },
          {
            "time": "2026-09-11T08:12:03.5+02:00",
            "tree": "efgh",
            "paths": ["/Users/tester"],
            "hostname": "mac",
            "id": "2222222222222222222222222222222222222222222222222222222222222222",
            "short_id": "22222222",
            "summary": {
              "total_bytes_processed": 62914560
            }
          },
          {
            "time": "2026-09-09T08:12:03Z",
            "tree": "ijkl",
            "paths": ["/Users/tester"],
            "hostname": "mac",
            "id": "3333333333333333333333333333333333333333333333333333333333333333",
            "short_id": "33333333"
          }
        ]
        """
        let snapshots = try Snapshot.decodeList(from: Data(json.utf8))

        XCTAssertEqual(snapshots.map(\.shortId), ["22222222", "11111111", "33333333"])
        XCTAssertEqual(snapshots[0].totalSize, 62_914_560)
        XCTAssertNil(snapshots[2].totalSize)

        let capped = try Snapshot.decodeList(from: Data(json.utf8), limit: 2)
        XCTAssertEqual(capped.map(\.shortId), ["22222222", "11111111"])
    }

    func testDecodeListThrowsOnUnparseableTimestamp() {
        let json = #"[{"time":"not-a-date","id":"a","short_id":"a"}]"#
        XCTAssertThrowsError(try Snapshot.decodeList(from: Data(json.utf8)))
    }
}
