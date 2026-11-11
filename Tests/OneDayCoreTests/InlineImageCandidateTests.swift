import Foundation
import XCTest
@testable import OneDayCore

/// §143 裸路径图片内联钉测（用户 2026-11-11
/// 17:13 报障）：助手正文里裸写的图片路径（独立
/// 成行/段内单独成词）应成内联图片候选、不再降
/// 为文件牌；§129 的门一项不松——根外/围栏/紧贴
/// 提及不收，非图片文件不走本口、成牌链原样。
/// 存在性不在 Core 判（App 层 §129 三分），本测
/// 只钉形态口。
final class InlineImageCandidateTests: XCTestCase {

    // MARK: - 报障同形（生产实证 消息 1775）

    /// state.db 消息 1775 原文：路径独立成行（自
    /// 成一段）、文件真实存在，旧口径仍只出文件
    /// 牌——新口须收为独立行图片候选
    func testIncidentMessagePathIsStandaloneCandidate() {
        let text = """
        文件已经保存到磁盘上，就在这个路径。如果 App 能显示文件卡片，点它就能打开：

        /opt/data/screenshot_20261111_1709.png

        这次发的是 ASCII 文件名，避免中文路径导致打不开。
        """
        let candidates = FileRefDetector.inlineImageCandidates(
            in: text
        )
        XCTAssertEqual(
            candidates,
            [
                FileRefDetector.InlineImageRef(
                    path: "/opt/data/screenshot_20261111_1709.png",
                    isStandaloneLine: true
                ),
            ]
        )
    }

    /// 报障同形＋确证后摘行：独立行摘除、前后段
    /// 落完好、空行收拾干净
    func testStrippingIncidentStandaloneLine() {
        let text = """
        文件已经保存到磁盘上，就在这个路径。如果 App 能显示文件卡片，点它就能打开：

        /opt/data/screenshot_20261111_1709.png

        这次发的是 ASCII 文件名，避免中文路径导致打不开。
        """
        let stripped = FileRefDetector.strippingStandaloneLines(
            in: text,
            paths: ["/opt/data/screenshot_20261111_1709.png"]
        )
        XCTAssertEqual(
            stripped,
            """
            文件已经保存到磁盘上，就在这个路径。如果 App 能显示文件卡片，点它就能打开：

            这次发的是 ASCII 文件名，避免中文路径导致打不开。
            """
        )
    }

    // MARK: - 段内单独成词

    /// 段落中部：全角冒号引出、逗号收尾——单独成
    /// 词，收为段内候选（非独立行）
    func testMidParagraphImageIsWordCandidate() {
        let text = "截图存好了：/opt/data/shots/a.png，你看看"
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(in: text),
            [
                FileRefDetector.InlineImageRef(
                    path: "/opt/data/shots/a.png",
                    isStandaloneLine: false
                ),
            ]
        )
    }

    /// 行首起词、英文句点收尾、括号包裹，三种常
    /// 见段内形态都算单独成词
    func testWordBoundaryForms() {
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: "/opt/data/a.png，这张就是"
            ).map(\.path),
            ["/opt/data/a.png"]
        )
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: "See /opt/data/a.png."
            ).map(\.path),
            ["/opt/data/a.png"]
        )
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: "图（/opt/data/a.png）在这"
            ).map(\.path),
            ["/opt/data/a.png"]
        )
    }

    /// 段内带 #L 锚点：边界判定跳过锚点原文再看
    /// 后一字符
    func testWordCandidateWithAnchor() {
        let text = "看这张 /opt/data/a.png#L12，好"
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(in: text)
                .map(\.path),
            ["/opt/data/a.png"]
        )
    }

    /// 同段两张：都收、出现序、重复只收一次
    func testMultipleAndDedupInParagraph() {
        let text = "两张：/opt/data/a.png、/opt/data/b.webp，还有 /opt/data/a.png"
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(in: text)
                .map(\.path),
            ["/opt/data/a.png", "/opt/data/b.webp"]
        )
    }

    /// 先段内词、后独立成行：只收一条且升级为独
    /// 立行标记（App 据此在确证后摘行）
    func testStandaloneUpgradeAfterWordMention() {
        let text = """
        先看 /opt/data/a.png 这张。

        /opt/data/a.png
        """
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(in: text),
            [
                FileRefDetector.InlineImageRef(
                    path: "/opt/data/a.png",
                    isStandaloneLine: true
                ),
            ]
        )
    }

    // MARK: - 不收的形态（§129 的门不许松）

    /// 根外图片路径：设备/系统/用户目录——天然取
    /// 不回来，不收（与 §129 文件牌同判）
    func testOutsideRootImagesRejected() {
        for text in [
            "图在 /Users/me/Pictures/a.png 这里",
            "图在 /tmp/a.png 这里",
            "/var/mobile/Media/a.png",
        ] {
            XCTAssertEqual(
                FileRefDetector.inlineImageCandidates(in: text),
                [],
                text
            )
        }
    }

    /// 紧贴汉字（无分隔）不算单独成词
    func testGluedToCJKRejected() {
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: "图在/opt/data/a.png里"
            ),
            []
        )
    }

    /// 路径后紧跟下划线续接的是更长词元的一部分
    func testUnderscoreContinuationRejected() {
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: "备份名 /opt/data/a.png_old 说明"
            ),
            []
        )
    }

    /// .bak 收尾的整体不是图片（防把 a.png.bak
    /// 截成 a.png）
    func testBakSuffixNotTruncated() {
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: "备份在 /opt/data/a.png.bak 里"
            ),
            []
        )
    }

    /// 代码围栏内是字面量，不收
    func testFencedPathRejected() {
        let text = """
        示例：
        ```
        /opt/data/a.png
        ```
        """
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(in: text),
            []
        )
    }

    /// MEDIA: 标记行归 §136 的 MediaMarker 管，
    /// 本口不重复收（scan 的冒号护栏天然跳过）
    func testMediaMarkerLineNotDoubled() {
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: "MEDIA:/opt/data/a.png"
            ),
            []
        )
    }

    /// excluding 生效：已由 remoteImagePaths /
    /// MEDIA 行承接的路径不再重复收
    func testExcludedPathsSkipped() {
        let text = "/opt/data/a.png"
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(
                in: text, excluding: ["/opt/data/a.png"]
            ),
            []
        )
    }

    // MARK: - 非图片文件（回归 §129，本口不碰）

    /// 非图片文件独立成行：不进图片候选；成牌链
    /// （detectStandaloneAnchored）原样命中
    func testNonImageStandaloneStaysChipChain() {
        let text = """
        报告好了：

        /opt/data/report.pdf
        """
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(in: text),
            []
        )
        XCTAssertEqual(
            FileRefDetector.detectStandaloneAnchored(in: text)
                .map(\.path),
            ["/opt/data/report.pdf"]
        )
    }

    /// 非图片文件段内提及：图片候选不收、成牌口
    /// 也不收（§129 行内提及纯文本，回归钉死）
    func testNonImageMidParagraphStaysText() {
        let text = "文件在 /opt/data/report.pdf 里面，你看看"
        XCTAssertEqual(
            FileRefDetector.inlineImageCandidates(in: text),
            []
        )
        XCTAssertEqual(
            FileRefDetector.detectStandaloneAnchored(in: text),
            []
        )
    }

    /// 图片文件段内提及也不许走成牌口（App 层排
    /// 除增补的 Core 侧对照）：成牌口只认独立成
    /// 行——段内图片由本口承接、牌链不重复出牌
    func testImageMidParagraphNotStandaloneAnchored() {
        let text = "截图存好了：/opt/data/shots/a.png，你看看"
        XCTAssertEqual(
            FileRefDetector.detectStandaloneAnchored(in: text),
            []
        )
    }

    // MARK: - 摘行口径

    /// 摘行只摘独立行：同路径的段内提及原样保留
    func testStrippingKeepsParagraphMention() {
        let text = """
        先看 /opt/data/a.png 这张。

        /opt/data/a.png
        """
        XCTAssertEqual(
            FileRefDetector.strippingStandaloneLines(
                in: text, paths: ["/opt/data/a.png"]
            ),
            "先看 /opt/data/a.png 这张。"
        )
    }

    /// 空路径集＝原文直回；不在集内的行不摘
    func testStrippingNoopCases() {
        let text = "/opt/data/a.png"
        XCTAssertEqual(
            FileRefDetector.strippingStandaloneLines(
                in: text, paths: []
            ),
            text
        )
        XCTAssertEqual(
            FileRefDetector.strippingStandaloneLines(
                in: text, paths: ["/opt/data/other.png"]
            ),
            text
        )
    }

    /// 围栏内的独立行不摘（字面量）
    func testStrippingSkipsFence() {
        let text = """
        ```
        /opt/data/a.png
        ```
        """
        XCTAssertEqual(
            FileRefDetector.strippingStandaloneLines(
                in: text, paths: ["/opt/data/a.png"]
            ),
            text
        )
    }

    // MARK: - 粘连形（CI 首轮实证：§116 扩过的路径
    // 字符集含中文标点，列表句里两条绝对路径会被
    // 正则粘成一条词元，须在标点＋/ 处拆回）

    func testGluedStandaloneLineTwoImages() {
        let refs = FileRefDetector.inlineImageCandidates(
            in: "/opt/data/a.png、/opt/data/b.webp"
        )
        XCTAssertEqual(
            refs.map(\.path),
            ["/opt/data/a.png", "/opt/data/b.webp"]
        )
        XCTAssertTrue(refs.allSatisfy(\.isStandaloneLine))
    }

    func testGluedMixedLineOnlyImageCollected() {
        // 粘着的非图片不收、图片照收（独立行标记）
        let refs = FileRefDetector.inlineImageCandidates(
            in: "/opt/data/report.pdf、/opt/data/b.png"
        )
        XCTAssertEqual(refs.map(\.path), ["/opt/data/b.png"])
        XCTAssertEqual(refs.first?.isStandaloneLine, true)
    }

    func testGluedStrippingNeedsAllConfirmed() {
        let text = "两张都发了\n\n/opt/data/a.png、/opt/data/b.webp"
        XCTAssertEqual(
            FileRefDetector.strippingStandaloneLines(
                in: text,
                paths: ["/opt/data/a.png", "/opt/data/b.webp"]
            ),
            "两张都发了"
        )
        // 只确证一张：整行保留（另一张的路径不许凭
        // 空消失，§129 降级口径）
        XCTAssertEqual(
            FileRefDetector.strippingStandaloneLines(
                in: text, paths: ["/opt/data/a.png"]
            ),
            text
        )
    }
}
