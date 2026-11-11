import Foundation
import XCTest
@testable import OneDayCore

/// §136 MEDIA: 图片标记拆分钉测（用户 2026-11-11
/// 16:18 真机报障：智能体拍了云电脑截图、回复里
/// 只剩一行 `MEDIA:/…webp` 原文、图没出来）：摘
/// 行判据（独立成行＋图片扩展名＋下载根内）与保
/// 留判据（非图片/根外/行内/围栏内一律原文不动）
/// 逐项钉死防漂移。存在性三分判定在 App 层
/// FileMetadataStore 同源 §129，不在本组。
final class MediaMarkerTests: XCTestCase {

    // MARK: - 报障同形与位置

    /// 生产实证同形：段中一行 MEDIA 截图路径，前
    /// 后都是正文——行摘除、两段正文都在、路径命中
    func testScreenshotShapeMidText() {
        let split = MediaMarker.split(in: """
        拍好了，这是云电脑当前的全屏画面：Chrome 开在 Google 新标签页。

        MEDIA:/opt/data/cache/images/img_6c34d74cde74.webp

        如果你想要的是别的「拍照」，跟我说一声。
        """)
        XCTAssertEqual(
            split.imagePaths,
            ["/opt/data/cache/images/img_6c34d74cde74.webp"]
        )
        XCTAssertFalse(split.text.contains("MEDIA:"))
        XCTAssertTrue(split.text.contains("拍好了，这是云电脑当前的"))
        XCTAssertTrue(split.text.contains("如果你想要的是别的"))
    }

    /// 段首命中：标记在第一行，正文从第二行起
    func testMarkerAtStart() {
        let split = MediaMarker.split(in: """
        MEDIA:/opt/data/cache/images/a.png
        这是刚截的图。
        """)
        XCTAssertEqual(
            split.imagePaths, ["/opt/data/cache/images/a.png"]
        )
        XCTAssertEqual(split.text, "这是刚截的图。")
    }

    /// 整条消息只有一行标记：正文摘空、图照出
    /// （气泡不渲染由 App 层按 text 空＋paths 非
    /// 空判，本组只钉拆分产出）
    func testMarkerOnlyMessage() {
        let split = MediaMarker.split(
            in: "MEDIA:/opt/data/cache/images/only.jpg"
        )
        XCTAssertEqual(
            split.imagePaths, ["/opt/data/cache/images/only.jpg"]
        )
        XCTAssertEqual(split.text, "")
    }

    // MARK: - 多张

    /// 多张连发：连续三行标记全摘、出现序保持
    func testConsecutiveMarkersKeepOrder() {
        let split = MediaMarker.split(in: """
        三张图：
        MEDIA:/opt/data/cache/images/1.png
        MEDIA:/opt/data/cache/images/2.png
        MEDIA:/opt/data/cache/images/3.png
        看第二张右下角。
        """)
        XCTAssertEqual(
            split.imagePaths,
            [
                "/opt/data/cache/images/1.png",
                "/opt/data/cache/images/2.png",
                "/opt/data/cache/images/3.png",
            ]
        )
        XCTAssertEqual(split.text, "三张图：\n看第二张右下角。")
    }

    /// 散布＋重复：同一路径出现两次只收一次（图
    /// 片行按路径作 id，重复会撞）
    func testScatteredMarkersDedupe() {
        let split = MediaMarker.split(in: """
        MEDIA:/opt/data/cache/images/a.png
        中间一段话。
        MEDIA:/opt/data/cache/images/b.gif
        MEDIA:/opt/data/cache/images/a.png
        """)
        XCTAssertEqual(
            split.imagePaths,
            [
                "/opt/data/cache/images/a.png",
                "/opt/data/cache/images/b.gif",
            ]
        )
        XCTAssertEqual(split.text, "中间一段话。")
    }

    /// 摘行后空行收拾：标记行夹在两个空行之间摘
    /// 除，不留三连空行把段落撑散
    func testBlankRunsCollapsedAfterRemoval() {
        let split = MediaMarker.split(in: """
        第一段。


        MEDIA:/opt/data/cache/images/a.png


        第二段。
        """)
        XCTAssertEqual(split.text, "第一段。\n\n第二段。")
    }

    // MARK: - 保留判据（坏路径三档与其余不动形态）

    /// 坏路径一档：非图片扩展名的 MEDIA: 行是文
    /// 件投递语义、归文件牌链——原文不动、不摘
    func testNonImageMediaLineUntouched() {
        let text = "结果文件：\nMEDIA:/opt/data/reports/周报.pdf"
        let split = MediaMarker.split(in: text)
        XCTAssertTrue(split.imagePaths.isEmpty)
        XCTAssertEqual(split.text, text)
    }

    /// 坏路径二档：根外路径（设备路径）天然取不
    /// 回来，与 §129 同判——原文不动
    func testOutOfRootMediaLineUntouched() {
        let text = "MEDIA:/var/mobile/Containers/Data/a.png"
        let split = MediaMarker.split(in: text)
        XCTAssertTrue(split.imagePaths.isEmpty)
        XCTAssertEqual(split.text, text)
    }

    /// 坏路径三档：相对路径、无扩展名、路径后带
    /// 说明文字（整行不恰是标记）——全不动
    func testMalformedMediaLinesUntouched() {
        for text in [
            "MEDIA:images/a.png",
            "MEDIA:/opt/data/cache/images/noext",
            "MEDIA:/opt/data/cache/images/a.png 这是说明",
            "MEDIA:",
        ] {
            let split = MediaMarker.split(in: text)
            XCTAssertTrue(split.imagePaths.isEmpty, text)
            XCTAssertEqual(split.text, text)
        }
    }

    /// 行内嵌着写的 MEDIA: 不是标记（须独占一行）
    func testInlineMediaMentionUntouched() {
        let text = "协议里写成 MEDIA:/opt/data/cache/images/a.png 这样。"
        let split = MediaMarker.split(in: text)
        XCTAssertTrue(split.imagePaths.isEmpty)
        XCTAssertEqual(split.text, text)
    }

    /// 代码围栏内的 MEDIA 行是字面量，不摘；围栏
    /// 外的正常标记照常命中
    func testMarkerInsideCodeFenceUntouched() {
        let split = MediaMarker.split(in: """
        写法示例：
        ```
        MEDIA:/opt/data/cache/images/example.png
        ```
        MEDIA:/opt/data/cache/images/real.png
        """)
        XCTAssertEqual(
            split.imagePaths, ["/opt/data/cache/images/real.png"]
        )
        XCTAssertTrue(
            split.text.contains(
                "MEDIA:/opt/data/cache/images/example.png"
            )
        )
    }

    /// 图＋文件混合：图片标记摘除出图，非图片标
    /// 记行留在正文原样
    func testMixedImageAndFileMarkers() {
        let split = MediaMarker.split(in: """
        MEDIA:/opt/data/cache/images/a.png
        MEDIA:/opt/data/docs/说明.pdf
        """)
        XCTAssertEqual(
            split.imagePaths, ["/opt/data/cache/images/a.png"]
        )
        XCTAssertEqual(
            split.text, "MEDIA:/opt/data/docs/说明.pdf"
        )
    }

    // MARK: - 基线

    /// 无标记的普通正文逐字原样返回（快筛路径）
    func testPlainTextPassthrough() {
        let text = "今天动态已更新，/opt/data 路径写在行内也不动。"
        let split = MediaMarker.split(in: text)
        XCTAssertEqual(split.text, text)
        XCTAssertTrue(split.imagePaths.isEmpty)
    }

    /// 扩展名大小写不敏感（isImagePath 既有口径）
    func testUppercaseExtensionMatches() {
        let split = MediaMarker.split(
            in: "MEDIA:/opt/data/cache/images/A.WEBP"
        )
        XCTAssertEqual(
            split.imagePaths, ["/opt/data/cache/images/A.WEBP"]
        )
    }
}
