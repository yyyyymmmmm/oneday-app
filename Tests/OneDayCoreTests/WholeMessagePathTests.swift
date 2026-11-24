import Foundation
import XCTest
@testable import OneDayCore

/// 聊天可靠性包（2026-11-13）整条裸路径消息钉测：
/// 用户实案——让 AI 发它生成的头像图，AI 两次只
/// 回一串裸路径 `/opt/data/cache/scratch/avatar_
/// small.png`、App 原样渲染成文字。形态判定在
/// FileRefDetector.wholeMessagePath：整条消息恰是
/// 一条裸路径才命中（渲染层据此改走附件形态直取
/// 字节）；正文里「提到」路径的形态一律不命中
/// （那些仍归 §129/§143 的存在性门口径）。
final class WholeMessagePathTests: XCTestCase {

    /// 实案原文：整条就是图片路径（服务端转录逐字）
    func testBareImagePathAloneMatches() {
        let ref = FileRefDetector.wholeMessagePath(
            in: "/opt/data/cache/scratch/avatar_small.png"
        )
        XCTAssertEqual(
            ref?.path, "/opt/data/cache/scratch/avatar_small.png"
        )
        XCTAssertNil(ref?.anchor)
        XCTAssertTrue(
            FileRefDetector.isImagePath(ref?.path ?? "")
        )
    }

    /// 非图片文件同认（出文件卡形态）
    func testBareFilePathAloneMatches() {
        let ref = FileRefDetector.wholeMessagePath(
            in: "/opt/data/reports/婚礼清单.pdf"
        )
        XCTAssertEqual(ref?.path, "/opt/data/reports/婚礼清单.pdf")
        XCTAssertFalse(
            FileRefDetector.isImagePath(ref?.path ?? "")
        )
    }

    /// 前后空白/尾换行不影响（消息落盘常见形态）
    func testSurroundingWhitespaceTolerated() {
        XCTAssertEqual(
            FileRefDetector.wholeMessagePath(
                in: "  /opt/data/cache/scratch/avatar_small.png\n"
            )?.path,
            "/opt/data/cache/scratch/avatar_small.png"
        )
    }

    /// §129 的一层包裹（反引号/粗体/列表符）整条时同认
    func testWrappedFormsMatch() {
        for text in [
            "`/opt/data/a/b.png`",
            "**/opt/data/a/b.png**",
            "- /opt/data/a/b.png",
        ] {
            XCTAssertEqual(
                FileRefDetector.wholeMessagePath(in: text)?.path,
                "/opt/data/a/b.png",
                "形态应命中：\(text)"
            )
        }
    }

    /// 带行号锚点：路径与锚点分开回（打开页定位用）
    func testAnchorSplitOut() {
        let ref = FileRefDetector.wholeMessagePath(
            in: "/opt/data/notes/清单.md#L12"
        )
        XCTAssertEqual(ref?.path, "/opt/data/notes/清单.md")
        XCTAssertNotNil(ref?.anchor)
    }

    /// 路径之外还有字＝正文提及，不命中（归 §129 纯文本/成牌口径）
    func testProseWithPathDoesNotMatch() {
        for text in [
            "图在这：/opt/data/cache/scratch/avatar_small.png",
            "/opt/data/cache/scratch/avatar_small.png 这是新头像",
            "文件已生成完毕。",
        ] {
            XCTAssertNil(
                FileRefDetector.wholeMessagePath(in: text),
                "不应命中：\(text)"
            )
        }
    }

    /// 多行（哪怕第二行只是说明）不命中
    func testMultilineDoesNotMatch() {
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "/opt/data/cache/scratch/avatar_small.png\n这是新头像"
            )
        )
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "新头像：\n/opt/data/cache/scratch/avatar_small.png"
            )
        )
    }

    /// 两条路径粘一行不命中（不是「单个」裸路径）
    func testTwoPathsDoNotMatch() {
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "/opt/data/a/b.png /opt/data/a/c.png"
            )
        )
    }

    /// 下载根外不认（设备/系统路径天然取不到字节，
    /// 不许假装附件）
    func testOutsideDownloadRootRejected() {
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "/System/Library/CoreServices/SystemVersion.plist"
            )
        )
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "/opt/database/evil.png"
            )
        )
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "/opt/data/../etc/passwd.png"
            )
        )
    }

    /// URL 不是服务端文件
    func testURLDoesNotMatch() {
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "https://example.com/opt/data/a.png"
            )
        )
    }

    /// 空/纯空白不命中
    func testEmptyDoesNotMatch() {
        XCTAssertNil(FileRefDetector.wholeMessagePath(in: ""))
        XCTAssertNil(FileRefDetector.wholeMessagePath(in: "  \n "))
    }

    /// 无扩展名形态不命中（不成文件形态）
    func testNoExtensionDoesNotMatch() {
        XCTAssertNil(
            FileRefDetector.wholeMessagePath(
                in: "/opt/data/cache/scratch/avatar_small"
            )
        )
    }
}
