import XCTest
@testable import OneDayCore

final class VaultRequestMarkerTests: XCTestCase {

    // MARK: - 形态校验

    func testIsValidID_Valid() {
        XCTAssertTrue(VaultRequestMarker.isValidID("vreq_abcdefghijklmnopqrstuvwx"))
        XCTAssertTrue(VaultRequestMarker.isValidID("vreq_ABCDEFGHIJKLMNOPQRSTUVWX"))
        XCTAssertTrue(VaultRequestMarker.isValidID("vreq_0123456789_-ABCDEFGHIJKL"))
        XCTAssertTrue(VaultRequestMarker.isValidID("vreq_aB1_-aB1_-aB1_-aB1_-abcd"))
    }

    func testIsValidID_Invalid() {
        XCTAssertFalse(VaultRequestMarker.isValidID("vreq_short"))
        XCTAssertFalse(VaultRequestMarker.isValidID("vreq_toolongabcdefghijklmnopqr"))
        XCTAssertFalse(VaultRequestMarker.isValidID("dlv_abcdefghijklmnopqrstuvwx"))
        XCTAssertFalse(VaultRequestMarker.isValidID("vreq_"))
        XCTAssertFalse(VaultRequestMarker.isValidID("abcdefghijklmnopqrstuvwxwxyz"))
        XCTAssertFalse(VaultRequestMarker.isValidID("vreq_abc@efghijklmnopqrstuvwx"))
    }

    // MARK: - 整行标记摘除

    func testSplit_SingleMarker() {
        let input = """
        Some text before.
        [[vreq:vreq_abc123XYZ_-0123456789ABC]]
        Some text after.
        """
        let result = VaultRequestMarker.split(in: input)
        XCTAssertEqual(result.text, "Some text before.\nSome text after.")
        XCTAssertEqual(result.requestIDs, ["vreq_abc123XYZ_-0123456789ABC"])
    }

    func testSplit_MultipleMarkers() {
        let input = """
        [[vreq:vreq_111111111111111111111111]]
        Some text.
        [[vreq:vreq_222222222222222222222222]]
        """
        let result = VaultRequestMarker.split(in: input)
        XCTAssertEqual(result.requestIDs, ["vreq_111111111111111111111111", "vreq_222222222222222222222222"])
        XCTAssertEqual(result.text, "Some text.")
    }

    func testSplit_DuplicateMarkers() {
        let input = """
        [[vreq:vreq_aaaaaaaaaaaaaaaaaaaaaaaa]]
        [[vreq:vreq_aaaaaaaaaaaaaaaaaaaaaaaa]]
        """
        let result = VaultRequestMarker.split(in: input)
        XCTAssertEqual(result.requestIDs, ["vreq_aaaaaaaaaaaaaaaaaaaaaaaa"])
        XCTAssertTrue(result.text.isEmpty)
    }

    // MARK: - 行内摘除

    func testSplit_InlineMarkerPreservesSurroundingText() {
        let input = "Text [[vreq:vreq_abc123XYZ_-0123456789ABC]] more text"
        let result = VaultRequestMarker.split(in: input)
        XCTAssertEqual(result.requestIDs, ["vreq_abc123XYZ_-0123456789ABC"])
        XCTAssertEqual(result.text, "Text  more text")
    }

    // MARK: - 围栏内不摘

    func testSplit_InsideCodeFence() {
        let input = """
        Before fence
        ```
        [[vreq:vreq_abc123XYZ_-0123456789ABC]]
        ```
        After fence
        """
        let result = VaultRequestMarker.split(in: input)
        XCTAssertTrue(result.requestIDs.isEmpty)
        XCTAssertEqual(result.text, input)
    }

    // MARK: - 形态不对保留原文

    func testSplit_InvalidFormatPreserved() {
        let input = """
        [[vreq:vreq_short]]
        [[vreq:invalid_format123456789012]]
        """
        let result = VaultRequestMarker.split(in: input)
        XCTAssertTrue(result.requestIDs.isEmpty)
        XCTAssertEqual(result.text, input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - 无标记原文逐字

    func testSplit_NoMarkers() {
        let input = "Plain text with no markers at all."
        let result = VaultRequestMarker.split(in: input)
        XCTAssertTrue(result.requestIDs.isEmpty)
        XCTAssertEqual(result.text, input)
    }

    // MARK: - 空行收拾

    func testSplit_CollapseBlankLines() {
        let input = """
        Line 1
        [[vreq:vreq_abc123XYZ_-0123456789ABC]]


        Line 2
        """
        let result = VaultRequestMarker.split(in: input)
        XCTAssertEqual(result.text, "Line 1\n\nLine 2")
    }

    // MARK: - markerText

    func testMarkerText() {
        let id = "vreq_abc123XYZ_-0123456789ABC"
        XCTAssertEqual(
            VaultRequestMarker.markerText(for: id),
            "[[vreq:vreq_abc123XYZ_-0123456789ABC]]"
        )
    }
}
