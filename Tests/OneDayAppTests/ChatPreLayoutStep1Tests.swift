import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §407（预排版层施工步骤 1：发送错行主治＋文件行
/// 定高）钉测组。判定与出处见施工图
/// chat-telegram-alignment-20261123.md 步骤 1：
/// ① 发送状态翻转不换高——同内容在 已发送/待发
///    （deliveryState=pending）/失败（sendFailed）
///    三态下合成高逐值相等（旧码：待发加一槽
///    caption1、失败扣列宽 52 并 max 44，本测红）；
/// ② 交付文件卡封面形态只认登记旗
///    meta.cover.cover——缩略图缓存播种后合成高
///    不变（旧码：封面形态三路 OR 含缓存 peek，
///    播种即翻形态，本测红）；
/// ③ 用户文件牌高对大小 facet 免疫（把守：牌高
///    只由名/菜单形态定，大小只进副行文案）；
/// ④ 量测台 measureNow 就地量测：本会话新发行
///    首趟 resolve 为兜底临界高、投单后
///    measureNow 同步量出确定高、再 resolve 即
///    命中确定高（预定高机制的端到端把守）；
/// ⑤ 结构钉测（S371 同式，源码层把守实验室复现
///    不了的喂入形态）：nativeEntryRow 的本会话
///    新行就地量测闸、send/performEditSend 的新行
///    登记、nativeRows 的占位行单行喂入、合成器
///    userEntryHeight 的状态项摘除、封面形态公式
///    两处单源、DeliveryFileCard 封面区按登记旗
///    预留（旧码逐项红）。
@MainActor
final class ChatPreLayoutStep1Tests: XCTestCase {

    private func makeComposer(
        ledger: ChatRowStateLedger =
            ChatRowStateLedger()
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ledger,
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    // MARK: - ① 状态翻转不换高

    func testUserRowHeight_sendStateFlipsKeepHeight() {
        let composer = makeComposer()
        // 长文：全列宽与旧失败列宽（−52）折行数必
        // 不同——旧失败形态在此现形；短文：待发
        // 槽在任何内容上都现形
        let contents = [
            String(repeating: "服务器状态正常", count: 30),
            "好",
        ]
        for content in contents {
            let delivered = ChatEntry(
                role: "user", content: content, thread: nil
            )
            let base = composer.entryHeight(
                delivered, dividerText: nil
            )
            let pending = ChatEntry(
                role: "user", content: content, thread: nil
            )
            pending.deliveryState = "pending"
            XCTAssertEqual(
                composer.entryHeight(
                    pending, dividerText: nil
                ),
                base,
                "待发翻转换高（内容前 10 字：\(content.prefix(10))）"
            )
            let failed = ChatEntry(
                role: "user", content: content, thread: nil
            )
            failed.sendFailed = true
            XCTAssertGreaterThan(
                composer.entryHeight(
                    failed, dividerText: nil
                ),
                base,
                "失败行应包含行内状态行与重发入口（内容前 10 字：\(content.prefix(10))）"
            )
            let pendingFailed = ChatEntry(
                role: "user", content: content, thread: nil
            )
            pendingFailed.deliveryState = "pending"
            pendingFailed.sendFailed = true
            XCTAssertEqual(
                composer.entryHeight(
                    pendingFailed, dividerText: nil
                ),
                composer.entryHeight(
                    failed, dividerText: nil
                ),
                "待发＋失败叠态只按失败行内状态行计高"
            )
        }
    }

    // MARK: - ② 封面形态只认登记旗

    private func deliveryMeta(
        id: String, path: String, cover: Bool
    ) throws -> BridgeDelivery {
        let json = """
        {"id":"\(id)","status":"ok","name":"scan.png",\
        "path":"\(path)","size":12345,"mime":"image/png",\
        "kind":"document","width":null,"height":null,\
        "sha256":null,"registeredAt":null,\
        "cover":{"thumb":false,"cover":\(cover)}}
        """
        return try JSONDecoder().decode(
            BridgeDelivery.self,
            from: Data(json.utf8)
        )
    }

    func testDeliveryFileCardHeight_coverFormIgnoresThumbnailCache()
        async throws
    {
        let composer = makeComposer()
        let run = UUID().uuidString
        let path = "/data/\(run)/scan.png"
        let metaNoCover = try deliveryMeta(
            id: "dlv-\(run)", path: path, cover: false
        )
        let clean = composer.deliveryFileCardHeight(
            metaNoCover
        )
        // 播种 §32 缩略图缓存（facet 合成条目同形：
        // 名/路径/大小/mime 与登记 meta 一致）
        let synthetic = WorkspaceFileEntry(
            name: metaNoCover.name, path: metaNoCover.path,
            isDirectory: false, size: metaNoCover.size,
            mtime: nil, mimeType: metaNoCover.mime
        )
        let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )
        let seeded = await FileThumbnailStore.shared
            .thumbnail(
                for: synthetic, targetPixelSize: 720
            ) { png }
        XCTAssertNotNil(seeded, "缩略图播种未生效")
        XCTAssertTrue(
            FileThumbnailStore.shared.hasCachedThumbnail(
                for: synthetic, targetPixelSize: 720
            ),
            "播种后缓存 peek 应命中（本测前提）"
        )
        XCTAssertEqual(
            composer.deliveryFileCardHeight(metaNoCover),
            clean,
            "封面形态被缩略图缓存翻转（登记旗 cover=false 应恒定无封面形态）"
        )
        // 登记旗为真时形态在席且同样对缓存免疫
        let metaCover = try deliveryMeta(
            id: "dlv2-\(run)", path: path, cover: true
        )
        let coverClean = composer
            .deliveryFileCardHeight(metaCover)
        XCTAssertGreaterThan(
            coverClean, clean,
            "登记旗 cover=true 应进入封面形态（148 封面区）"
        )
        XCTAssertEqual(
            composer.deliveryFileCardHeight(metaCover),
            coverClean,
            "封面形态在席时仍被缓存态改高"
        )
    }

    // MARK: - ③ 用户文件牌高对大小 facet 免疫

    func testUserFileChipHeight_ignoresSizeFacet() {
        let composer = makeComposer()
        let run = UUID().uuidString
        let small = "/a/\(run)/report.xlsx"
        let large = "/b/\(run)/report.xlsx"
        FileMetadataStore.shared.record(
            path: small, size: 10, modifiedAt: nil
        )
        FileMetadataStore.shared.record(
            path: large, size: 9_876_543,
            modifiedAt: nil
        )
        XCTAssertEqual(
            composer.fileChipHeight(path: small, width: 300),
            composer.fileChipHeight(path: large, width: 300),
            "文件牌高被大小 facet 改动（同名牌应同高）"
        )
    }

    // MARK: - ④ measureNow 就地量测端到端

    func testMeasureNow_firstFeedOfSessionSentRowIsExact() {
        let composer = makeComposer()
        let desk = ChatNativeRowMeasureDesk()
        let entry = ChatEntry(
            role: "user", content: "刚发出去的一条消息",
            thread: nil
        )
        let memoKey = composer.entryMemoKey(
            for: entry, dividerText: nil
        )
        let rowKey = "row-\(entry.id.uuidString)"
        let fallback = ChatNativeRowHeightComposer
            .fallbackHeight
        let first = desk.resolve(
            memoKey: memoKey, rowKey: rowKey,
            fallback: fallback
        )
        XCTAssertFalse(
            first.isExact, "首趟应为临界高（本测前提）"
        )
        XCTAssertEqual(first.height, fallback)
        XCTAssertTrue(first.needsJob)
        desk.collect(
            composer.makeEntryMeasureJob(
                for: entry, dividerText: nil,
                memoKey: memoKey, rowKey: rowKey
            )
        )
        let measured = desk.measureNow(rowKey: rowKey)
        XCTAssertNotNil(measured, "就地量测应回确定高")
        XCTAssertEqual(
            measured ?? -1,
            composer.entryHeight(entry, dividerText: nil),
            accuracy: 2.0,
            "就地量测高与同步合成高应对拍（整行放宽口径 2.0）"
        )
        let second = desk.resolve(
            memoKey: memoKey, rowKey: rowKey,
            fallback: fallback
        )
        XCTAssertTrue(
            second.isExact, "就地量测后再 resolve 应命中确定高"
        )
        XCTAssertEqual(second.height, measured)
    }

    // MARK: - ⑤ 结构钉测

    private func source(
        _ relativePath: String
    ) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let url = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func segment(
        _ src: String, from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(
            src.range(of: startMarker),
            "找不到段起点 \(startMarker)"
        )
        let end = try XCTUnwrap(
            src.range(
                of: endMarker,
                range: start.upperBound..<src.endIndex
            ),
            "找不到段终点 \(endMarker)"
        )
        return String(src[start.lowerBound..<end.lowerBound])
    }

    func testStructure_preLayoutStep1Shapes() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try source("Sources/OneDayApp/ChatView.swift")
        let sendChat = try source("Sources/OneDayApp/ChatView+SendAndOutbox.swift")
        let overlaysChat = try source("Sources/OneDayApp/ChatView+OverlaysAndModifiers.swift")
        let chatView = mainChat + "\n" + sendChat + "\n" + overlaysChat
        let composerSrc = try source(
            "Sources/OneDayApp/ChatNativeRowHeight.swift"
        )
        let facetsSrc = try source(
            "Sources/OneDayApp/ChatNativeRowFacets.swift"
        )
        let deliverySrc = try source(
            "Sources/OneDayApp/DeliveryViews.swift"
        )

        // 预定高：新行登记两处（send＋编辑重发）
        XCTAssertGreaterThanOrEqual(
            chatView.components(
                separatedBy: "sessionSentEntryIDs.insert"
            ).count - 1,
            2,
            "本会话新行登记应至少两处（send/performEditSend）"
        )
        // 预定高：nativeEntryRow 就地量测闸
        // §409 步 A：nativeLiveRow 本体已删，段终点
        // 锚改 kick 函数；步 C：kick 亦删，再换锚
        // fileChipStackEstimate
        let entryRowSeg = try segment(
            chatView,
            from: "private func nativeEntryRow",
            to: "private func fileChipStackEstimate"
        )
        XCTAssertTrue(
            entryRowSeg.contains("urgentHeight = rowMeasureDesk.measureNow("),
            "nativeEntryRow 缺就地量测闸（新行入列即终态高）"
        )
        XCTAssertTrue(
            entryRowSeg.contains("sessionSentEntryIDs"),
            "就地量测闸未按本会话新行收口"
        )
        // 占位行：nativeRows 单行喂入、不再逐项喂
        // 直播行
        let rowsSeg = try segment(
            chatView,
            from: "private func nativeRows()",
            to: "private func nativeEntryRow"
        )
        XCTAssertTrue(
            rowsSeg.contains("livePlaceholderRow("),
            "nativeRows 未喂入占位行"
        )
        XCTAssertFalse(
            rowsSeg.contains("nativeLiveRow(item"),
            "nativeRows 仍在逐项喂入直播行（流式逐项生长未退役）"
        )
        // 占位行高：合成器常量（不读任何阶段输入）
        XCTAssertTrue(
            composerSrc.contains("var livePlaceholderHeight"),
            "合成器缺占位行高常量 livePlaceholderHeight"
        )
        // 状态摘除：userEntryHeight 不读待发状态；
        // 失败行按收敛形态计入行内状态行与重发入口
        let userSeg = try segment(
            composerSrc,
            from: "func userEntryHeight",
            to: "func assistantEntryHeight"
        )
        XCTAssertFalse(
            userSeg.contains("isPendingSend"),
            "userEntryHeight 仍读 isPendingSend（待发进高）"
        )
        XCTAssertTrue(
            userSeg.contains("sendFailed"),
            "userEntryHeight 未计入失败行内状态行"
        )
        // 封面形态公式单源：活读与快照两处不 peek
        // 缓存
        let coverSeg = try segment(
            composerSrc,
            from: "func facetDeliveryCoverForm",
            to: "private func facetLocalImageDecoded"
        )
        XCTAssertFalse(
            coverSeg.contains("hasCachedImage"),
            "封面形态活读仍 peek 快照图缓存"
        )
        XCTAssertFalse(
            coverSeg.contains("hasCachedThumbnail"),
            "封面形态活读仍 peek 缩略图缓存"
        )
        let recordSeg = try segment(
            facetsSrc,
            from: "private static func recordDelivery",
            to: "\n}\n"
        )
        XCTAssertFalse(
            recordSeg.contains("hasCachedImage"),
            "封面形态快照仍 peek 快照图缓存"
        )
        XCTAssertFalse(
            recordSeg.contains("hasCachedThumbnail"),
            "封面形态快照仍 peek 缩略图缓存"
        )
        // 文件卡视图：封面区按登记旗预留
        let cardSeg = try segment(
            deliverySrc,
            from: "struct DeliveryFileCard",
            to: "\n}\n"
        )
        XCTAssertTrue(
            cardSeg.contains("meta.cover.cover"),
            "DeliveryFileCard 封面区未按登记旗 meta.cover.cover 预留"
        )
    }
}
