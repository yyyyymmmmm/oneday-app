import Foundation
import XCTest
@testable import OneDayCore

/// §142 登记交付标记拆分钉测（规格 delivery-
/// registry-spec-20261111 §4/§7）：摘行判据（独
/// 立成行＋号形态合定版正则）与保留判据（坏号/
/// 行内/围栏内一律原文不动）逐项钉死防漂移。
/// 与 §136 的分工也在本组钉：MEDIA 行不归本解
/// 析管、两层串联后各摘各的。取数与降级在 App
/// 层 DeliveryStore/AssistantDeliveryItem，不在
/// 本组。
final class DeliveryMarkerTests: XCTestCase {

    private let trialID = "dlv_a6fc654739fd597ff861"
    private let imageID = "dlv_93c016547852c522bbba"
    private let docID = "dlv_db244d5043c8ed612ac8"

    // MARK: - 验收样本同形

    /// 智能体试验会话同形（delivery-registry-
    /// trial-20261111）：正文段落后独立一行标记
    /// ——行摘除、正文都在、号命中
    func testTrialShape() {
        let split = DeliveryMarker.split(in: """
        文件已登记成功，内容是标题为「登记制试验」的两行 Markdown。

        [[deliver:\(trialID)]]

        正文说明这是用于验证交付登记全链的试验文件。
        """)
        XCTAssertEqual(split.deliveryIDs, [trialID])
        XCTAssertFalse(split.text.contains("deliver:"))
        XCTAssertTrue(split.text.contains("文件已登记成功"))
        XCTAssertTrue(split.text.contains("正文说明这是"))
    }

    /// 标记在第一行：正文从第二行起
    func testMarkerAtStart() {
        let split = DeliveryMarker.split(in: """
        [[deliver:\(imageID)]]
        这是刚拍的云电脑截图。
        """)
        XCTAssertEqual(split.deliveryIDs, [imageID])
        XCTAssertEqual(split.text, "这是刚拍的云电脑截图。")
    }

    /// 整条消息只有一行标记：正文摘空（气泡不
    /// 渲染由 App 层按 text 空＋ids 非空判）
    func testMarkerOnlyMessage() {
        let split = DeliveryMarker.split(
            in: "[[deliver:\(docID)]]"
        )
        XCTAssertEqual(split.deliveryIDs, [docID])
        XCTAssertEqual(split.text, "")
    }

    /// 行首尾空白不碍事（与 §136 同口径：修剪后
    /// 整行恰好是标记即算独立成行）
    func testMarkerWithSurroundingWhitespace() {
        let split = DeliveryMarker.split(in: """
        看这个：
          [[deliver:\(docID)]]  
        """)
        XCTAssertEqual(split.deliveryIDs, [docID])
        XCTAssertEqual(split.text, "看这个：")
    }

    // MARK: - 多标记与分工

    /// 一条回复交付两份：两号按出现序都摘、正
    /// 文只剩叙述
    func testMultipleMarkersKeepOrder() {
        let split = DeliveryMarker.split(in: """
        图和文档都好了：

        [[deliver:\(imageID)]]

        [[deliver:\(docID)]]
        """)
        XCTAssertEqual(split.deliveryIDs, [imageID, docID])
        XCTAssertEqual(split.text, "图和文档都好了：")
    }

    /// 同号重复粘两行：只取一次（呈现位取首
    /// 现）、两行都摘除
    func testDuplicateMarkerDeduped() {
        let split = DeliveryMarker.split(in: """
        [[deliver:\(docID)]]

        [[deliver:\(docID)]]
        """)
        XCTAssertEqual(split.deliveryIDs, [docID])
        XCTAssertEqual(split.text, "")
    }

    /// 与 MEDIA 行共存：本解析只摘登记标记、
    /// MEDIA 行原样留在正文里；再过 §136 拆分
    /// 时图片路径照常摘出——两层各摘各的、互
    /// 不干扰（规格 §10 分工）
    func testCoexistsWithMediaMarker() {
        let source = """
        截图和文件都在这：

        MEDIA:/opt/data/cache/images/img_6c34d74cde74.webp

        [[deliver:\(docID)]]
        """
        let deliverySplit = DeliveryMarker.split(in: source)
        XCTAssertEqual(deliverySplit.deliveryIDs, [docID])
        XCTAssertTrue(deliverySplit.text.contains("MEDIA:"))
        let mediaSplit = MediaMarker.split(in: deliverySplit.text)
        XCTAssertEqual(
            mediaSplit.imagePaths,
            ["/opt/data/cache/images/img_6c34d74cde74.webp"]
        )
        XCTAssertEqual(mediaSplit.text, "截图和文件都在这：")
    }

    // MARK: - 保留判据（坏形态一律原文不动）

    /// 号短一位（19 位十六进制）：不是标记
    func testShortIDStaysText() {
        let line = "[[deliver:dlv_a6fc654739fd597ff86]]"
        let split = DeliveryMarker.split(in: line)
        XCTAssertEqual(split.deliveryIDs, [])
        XCTAssertEqual(split.text, line)
    }

    /// 号长一位（21 位）：不是标记
    func testLongIDStaysText() {
        let line = "[[deliver:dlv_a6fc654739fd597ff8611]]"
        let split = DeliveryMarker.split(in: line)
        XCTAssertEqual(split.deliveryIDs, [])
        XCTAssertEqual(split.text, line)
    }

    /// 大写十六进制：定版正则只认小写，不是标记
    func testUppercaseIDStaysText() {
        let line = "[[deliver:dlv_A6FC654739FD597FF861]]"
        let split = DeliveryMarker.split(in: line)
        XCTAssertEqual(split.deliveryIDs, [])
        XCTAssertEqual(split.text, line)
    }

    /// 非十六进制字符混入：不是标记
    func testNonHexIDStaysText() {
        let line = "[[deliver:dlv_g6fc654739fd597ff861]]"
        let split = DeliveryMarker.split(in: line)
        XCTAssertEqual(split.deliveryIDs, [])
        XCTAssertEqual(split.text, line)
    }

    /// 缺 dlv_ 前缀/缺括号/单括号：都不是标记
    func testMalformedMarkersStayText() {
        for line in [
            "[[deliver:a6fc654739fd597ff861aa]]",
            "[[deliver:\(trialID)]",
            "[deliver:\(trialID)]",
            "[[deliver:\(trialID)]]尾巴",
        ] {
            let split = DeliveryMarker.split(in: line)
            XCTAssertEqual(split.deliveryIDs, [], line)
            XCTAssertEqual(split.text, line, line)
        }
    }

    /// 行内嵌写（前后有字）：不算独立成行、不摘
    func testInlineMarkerStaysText() {
        let source = "文件在这里 [[deliver:\(docID)]] 请查收。"
        let split = DeliveryMarker.split(in: source)
        XCTAssertEqual(split.deliveryIDs, [])
        XCTAssertEqual(split.text, source)
    }

    /// 代码围栏内是字面量：不摘；围栏外的照摘
    func testMarkerInsideFenceStaysText() {
        let split = DeliveryMarker.split(in: """
        标记长这样：
        ```
        [[deliver:\(docID)]]
        ```

        [[deliver:\(imageID)]]
        """)
        XCTAssertEqual(split.deliveryIDs, [imageID])
        XCTAssertTrue(split.text.contains("[[deliver:\(docID)]]"))
    }

    /// 坏号行与正文混排：坏行原文保留、好行照
    /// 摘——一坏不连坐
    func testBadLineDoesNotBlockGoodLine() {
        let split = DeliveryMarker.split(in: """
        [[deliver:dlv_123]]

        [[deliver:\(docID)]]
        """)
        XCTAssertEqual(split.deliveryIDs, [docID])
        XCTAssertTrue(split.text.contains("[[deliver:dlv_123]]"))
        XCTAssertFalse(split.text.contains(docID))
    }

    /// 无标记消息：原文逐字返回（存量消息零扰动）
    func testNoMarkerReturnsOriginalVerbatim() {
        let source = "普通回复，没有任何标记。\n第二行 /opt/data/x.png 只是提及。"
        let split = DeliveryMarker.split(in: source)
        XCTAssertEqual(split.deliveryIDs, [])
        XCTAssertEqual(split.text, source)
    }

    // MARK: - 号形态与标记原文

    func testIsValidID() {
        XCTAssertTrue(DeliveryMarker.isValidID(trialID))
        XCTAssertTrue(
            DeliveryMarker.isValidID("dlv_0123456789abcdef0123")
        )
        XCTAssertFalse(DeliveryMarker.isValidID(""))
        XCTAssertFalse(
            DeliveryMarker.isValidID("a6fc654739fd597ff861")
        )
        XCTAssertFalse(
            DeliveryMarker.isValidID("dlv_a6fc654739fd597ff86")
        )
        XCTAssertFalse(
            DeliveryMarker.isValidID("dlv_A6FC654739FD597FF861")
        )
        XCTAssertFalse(
            DeliveryMarker.isValidID("dlv_a6fc654739fd597ff861 ")
        )
    }

    /// 查无此号时 App 层按纯文本原样显示的文本
    /// 与智能体写入的标记逐字一致（往返不变形）
    func testMarkerTextRoundTrip() {
        let line = DeliveryMarker.markerText(for: docID)
        XCTAssertEqual(line, "[[deliver:\(docID)]]")
        let split = DeliveryMarker.split(in: line)
        XCTAssertEqual(split.deliveryIDs, [docID])
    }
}

/// §142 登记元数据解码钉测：回执形状照规格 §5
/// 与部署验收实形（图 dlv_93c0…/文档 dlv_db24…
/// 两样本的字段构成）——键名/可空性/状态枚举漂
/// 移在此先红，不许等真机才发现解不开。
final class BridgeDeliveryDecodeTests: XCTestCase {

    private func decode(_ json: String) throws -> BridgeDelivery {
        try JSONDecoder().decode(
            BridgeDelivery.self, from: Data(json.utf8)
        )
    }

    /// 图片样本：宽高实测、封面两档皆有
    func testImageDeliveryDecodes() throws {
        let meta = try decode("""
        {"id": "dlv_93c016547852c522bbba", "status": "ok",
         "name": "screenshot_20261111_1709.png",
         "path": "/opt/data/screenshot_20261111_1709.png",
         "size": 68026, "mime": "image/png", "kind": "image",
         "width": 1280, "height": 800,
         "sha256": "72edc19c", "registeredAt": "2026-11-11T09:31:00Z",
         "cover": {"thumb": true, "cover": true}}
        """)
        XCTAssertEqual(meta.id, "dlv_93c016547852c522bbba")
        XCTAssertEqual(meta.status, .ok)
        XCTAssertEqual(meta.kind, "image")
        XCTAssertEqual(meta.size, 68026)
        XCTAssertEqual(
            meta.imagePixelSize, CGSize(width: 1280, height: 800)
        )
        XCTAssertTrue(meta.cover.thumb)
        XCTAssertTrue(meta.cover.cover)
    }

    /// 文档样本：无宽高、纸面封面有 cover 无 thumb
    func testDocumentDeliveryDecodes() throws {
        let meta = try decode("""
        {"id": "dlv_db244d5043c8ed612ac8", "status": "ok",
         "name": "通讯录人数口径.md",
         "path": "/opt/data/通讯录人数口径.md",
         "size": 6377, "mime": "text/markdown", "kind": "document",
         "width": null, "height": null,
         "sha256": "d3e82dfa", "registeredAt": "2026-11-11T09:31:00Z",
         "cover": {"thumb": false, "cover": true}}
        """)
        XCTAssertEqual(meta.kind, "document")
        XCTAssertNil(meta.imagePixelSize)
        XCTAssertFalse(meta.cover.thumb)
        XCTAssertTrue(meta.cover.cover)
    }

    /// 三态状态枚举都解得开；无封面文件两档皆假
    func testStatusesAndNoCoverDecode() throws {
        for (raw, expected) in [
            ("stale", BridgeDelivery.Status.stale),
            ("gone", BridgeDelivery.Status.gone),
        ] {
            let meta = try decode("""
            {"id": "dlv_a6fc654739fd597ff861", "status": "\(raw)",
             "name": "delivery-trial-20261111.md",
             "path": "/opt/data/delivery-trial-20261111.md",
             "size": 82, "mime": "text/markdown", "kind": "document",
             "width": null, "height": null,
             "sha256": "b211d5a7", "registeredAt": "2026-11-11T09:33:00Z",
             "cover": {"thumb": false, "cover": false}}
            """)
            XCTAssertEqual(meta.status, expected)
            XCTAssertFalse(meta.cover.thumb)
            XCTAssertFalse(meta.cover.cover)
        }
    }
}
