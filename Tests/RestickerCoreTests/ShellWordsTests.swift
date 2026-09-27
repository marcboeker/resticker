import XCTest
@testable import RestickerCore

final class ShellWordsTests: XCTestCase {
    func testSplitsOnWhitespace() {
        XCTAssertEqual(ShellWords.split("--one-file-system --exclude-caches"), ["--one-file-system", "--exclude-caches"])
    }

    func testSplitCollapsesRepeatedWhitespace() {
        XCTAssertEqual(ShellWords.split("  --foo   --bar  "), ["--foo", "--bar"])
    }

    func testSplitHonoursSingleQuotes() {
        XCTAssertEqual(ShellWords.split("--tag 'my host'"), ["--tag", "my host"])
    }

    func testSplitHonoursDoubleQuotes() {
        XCTAssertEqual(ShellWords.split(#"--tag "my host""#), ["--tag", "my host"])
    }

    func testSplitHonoursBackslashEscapes() {
        XCTAssertEqual(ShellWords.split(#"--tag my\ host"#), ["--tag", "my host"])
    }

    func testSplitHonoursEscapedQuoteInsideDoubleQuotes() {
        XCTAssertEqual(ShellWords.split(#""say \"hi\"""#), [#"say "hi""#])
    }

    func testUnterminatedQuoteTakesTheRestOfTheText() {
        XCTAssertEqual(ShellWords.split("--tag 'unterminated"), ["--tag", "unterminated"])
    }

    func testSplitOfEmptyTextIsEmptyArgs() {
        XCTAssertEqual(ShellWords.split(""), [])
        XCTAssertEqual(ShellWords.split("   "), [])
    }

    func testJoinQuotesOnlyArgsThatNeedIt() {
        XCTAssertEqual(ShellWords.join(["--foo", "bar"]), "--foo bar")
        XCTAssertEqual(ShellWords.join(["my host"]), "\"my host\"")
        XCTAssertEqual(ShellWords.join([""]), "\"\"")
    }

    func testRoundTripsSimpleArgs() {
        let args = ["--one-file-system", "--exclude-caches"]
        XCTAssertEqual(ShellWords.split(ShellWords.join(args)), args)
    }

    func testRoundTripsArgsWithWhitespaceAndQuotes() {
        let args = ["--tag", "my host", "it's", "say \"hi\"", "back\\slash", ""]
        XCTAssertEqual(ShellWords.split(ShellWords.join(args)), args)
    }

    func testRoundTripsEmptyArgList() {
        let args: [String] = []
        XCTAssertEqual(ShellWords.split(ShellWords.join(args)), args)
    }
}
