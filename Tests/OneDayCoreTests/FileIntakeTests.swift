import XCTest
@testable import OneDayCore

/// 0.36.31（件三）：文件接入预检钉死——大小闸
/// 100MB 与服务端契约对齐、先查后读的判定边界、
/// 被拒汇总点名的名单拼装（1/2/3+ 与混合两类）
final class FileIntakeTests: XCTestCase {

    // MARK: 大小预检判定

    func testSizeVerdictAcceptsAtLimit() {
        XCTAssertEqual(
            FileIntake.sizeVerdict(declaredSize: FileIntake.maxFileBytes),
            .acceptable
        )
    }

    func testSizeVerdictRejectsAboveLimit() {
        XCTAssertEqual(
            FileIntake.sizeVerdict(
                declaredSize: FileIntake.maxFileBytes + 1
            ),
            .tooLarge
        )
    }

    func testSizeVerdictAcceptsZeroAndSmall() {
        XCTAssertEqual(FileIntake.sizeVerdict(declaredSize: 0), .acceptable)
        XCTAssertEqual(FileIntake.sizeVerdict(declaredSize: 1), .acceptable)
    }

    func testSizeVerdictUnknownWhenSizeMissing() {
        XCTAssertEqual(FileIntake.sizeVerdict(declaredSize: nil), .unknownSize)
    }

    func testIsOversizedBoundary() {
        XCTAssertFalse(FileIntake.isOversized(byteCount: FileIntake.maxFileBytes))
        XCTAssertTrue(
            FileIntake.isOversized(byteCount: FileIntake.maxFileBytes + 1)
        )
        XCTAssertFalse(FileIntake.isOversized(byteCount: 0))
    }

    // MARK: 汇总点名

    func testRejectionNoticeNilWhenNothingRejected() {
        XCTAssertNil(FileIntake.rejectionNotice(oversized: [], unreadable: []))
    }

    func testRejectionNoticeSingleOversized() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(oversized: ["报告.pdf"], unreadable: []),
            "「报告.pdf」超过 100MB，未加入待发列表。"
        )
    }

    func testRejectionNoticeTwoOversized() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: ["a.zip", "b.zip"], unreadable: []
            ),
            "「a.zip」、「b.zip」超过 100MB，未加入待发列表。"
        )
    }

    func testRejectionNoticeThreeOversizedFoldsToCount() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: ["a.zip", "b.zip", "c.zip"], unreadable: []
            ),
            "「a.zip」、「b.zip」等 3 个文件超过 100MB，未加入待发列表。"
        )
    }

    func testRejectionNoticeSingleUnreadable() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(oversized: [], unreadable: ["x.txt"]),
            "读取「x.txt」失败，未加入待发列表。"
        )
    }

    func testRejectionNoticeTwoUnreadable() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: [], unreadable: ["a.txt", "b.txt"]
            ),
            "「a.txt」、「b.txt」没能读取，未加入待发列表。"
        )
    }

    func testRejectionNoticeManyUnreadableFoldsToCount() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: [], unreadable: ["a.txt", "b.txt", "c.txt", "d.txt"]
            ),
            "「a.txt」、「b.txt」等 4 个文件没能读取，未加入待发列表。"
        )
    }

    func testRejectionNoticeMixedBothKinds() {
        XCTAssertEqual(
            FileIntake.rejectionNotice(
                oversized: ["big.zip"], unreadable: ["x.txt"]
            ),
            "「big.zip」超过 100MB，未加入待发列表。读取「x.txt」失败，未加入待发列表。"
        )
    }

    // MARK: - 文本编码转码（0.46.1 扩围 C）

    /// 「中文」的 GBK 字节（中＝D6D0、文＝CEC4）
    private var gbkChinese: Data {
        Data([0xD6, 0xD0, 0xCE, 0xC4])
    }

    func testTranscodeGBKTextToUTF8() {
        let result = FileIntake.transcodedForUpload(
            fileName: "笔记.txt", data: gbkChinese
        )
        XCTAssertEqual(result.outcome, .transcoded)
        XCTAssertEqual(result.data, "中文".data(using: .utf8))
        // ASCII 与 GBK 混排（OK＋中文＋换行）同样转对
        let mixed = FileIntake.transcodedForUpload(
            fileName: "代码.mq5",
            data: Data([0x4F, 0x4B, 0xD6, 0xD0, 0xCE, 0xC4, 0x0A])
        )
        XCTAssertEqual(mixed.outcome, .transcoded)
        XCTAssertEqual(mixed.data, "OK中文\n".data(using: .utf8))
    }

    func testTranscodeLeavesValidUTF8Untouched() {
        let utf8 = "中文 test".data(using: .utf8)!
        let result = FileIntake.transcodedForUpload(
            fileName: "笔记.md", data: utf8
        )
        XCTAssertEqual(result.outcome, .unchanged)
        XCTAssertEqual(result.data, utf8)
        // 纯 ASCII 是合法 UTF-8 的子集、同样不动
        let ascii = FileIntake.transcodedForUpload(
            fileName: "a.json", data: Data("{\"a\":1}".utf8)
        )
        XCTAssertEqual(ascii.outcome, .unchanged)
    }

    func testTranscodeSkipsNonTextExtensions() {
        // zip 头字节（PK\x03\x04…）不是合法 UTF-8，
        // 但 .zip 不在文本集——绝不误转
        let zipHead = Data([0x50, 0x4B, 0x03, 0x04, 0xD6, 0xD0])
        let result = FileIntake.transcodedForUpload(
            fileName: "三藏.zip", data: zipHead
        )
        XCTAssertEqual(result.outcome, .unchanged)
        XCTAssertEqual(result.data, zipHead)
        // 文本内容配二进制扩展名同样不碰
        let bin = FileIntake.transcodedForUpload(
            fileName: "data.bin", data: gbkChinese
        )
        XCTAssertEqual(bin.outcome, .unchanged)
        XCTAssertEqual(bin.data, gbkChinese)
    }

    func testTranscodeUndecodableBytes() {
        // 0xFF 在 UTF-8 与 GB18030 里都不是合法字节
        let garbage = Data([0xFF, 0xFF, 0xFF, 0xFF])
        let result = FileIntake.transcodedForUpload(
            fileName: "坏文件.txt", data: garbage
        )
        XCTAssertEqual(result.outcome, .undecodable)
        XCTAssertEqual(result.data, garbage)
    }

    func testTranscodeNotice() {
        XCTAssertNil(
            FileIntake.transcodeNotice(transcoded: [], undecodable: [])
        )
        let one = FileIntake.transcodeNotice(
            transcoded: ["笔记.txt"], undecodable: []
        )
        XCTAssertNotNil(one)
        XCTAssertTrue(one!.contains("「笔记.txt」"))
        let bad = FileIntake.transcodeNotice(
            transcoded: [], undecodable: ["坏文件.txt"]
        )
        XCTAssertNotNil(bad)
        XCTAssertTrue(bad!.contains("「坏文件.txt」"))
    }
}
