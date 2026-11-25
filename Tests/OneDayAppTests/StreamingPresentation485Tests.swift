import XCTest
@testable import OneDayApp
import OneDayCore

/// §494（2026-11-24）流式呈现接线钉：发布门与
/// 聊天页的接线点逐点钉死——增量同点喂门／封
/// 段·终态·断流三拍全量发布／直播行四守卫与
/// 流式行键／落定收尾整清／driveRun 武装与心
/// 跳／呈现视图只走块级切分不复活逐词元件。
/// 数据面行为钉在 Core 两套（StreamingBlock-
/// ProductTests／StreamingPublishGateTests）
final class StreamingPresentation485Tests: XCTestCase {

    // MARK: - 源码读取（与 ChatSimplifiedModelPinTests 同路）

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent(
                    "Sources/OneDayApp/ChatView.swift"
                ).path
            ) {
                return url
            }
        }
        XCTFail("找不到仓库根")
        return url
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    private func segment(
        _ src: String, from: String, to: String
    ) throws -> String {
        let start = try XCTUnwrap(
            src.range(of: from), "找不到段起点 \(from)"
        )
        let end = try XCTUnwrap(
            src.range(of: to, range: start.upperBound..<src.endIndex),
            "找不到段终点 \(to)"
        )
        return String(src[start.lowerBound..<end.lowerBound])
    }

    private var chatView: String {
        get throws {
            try source("Sources/OneDayApp/ChatView.swift")
        }
    }

    // MARK: - 接线钉

    /// 增量路径：装配器入账与发布门喂入必须同
    /// 点（followRunEvents 的 delta 分支内）
    func testDeltaPathFeedsPublishGate() throws {
        let follow = try segment(
            chatView,
            from: "private func followRunEvents(",
            to: "private func sealStreamSegment()"
        )
        XCTAssertTrue(follow.contains("streamAssembler.offer(delta)"))
        XCTAssertTrue(
            follow.contains("offerStreamPublish()"),
            "delta 分支须同点喂发布门")
    }

    /// 全量发布三拍：封段（sealStreamSegment 本
    /// 体）＋终态＋断流落盘前（同在 followRun-
    /// Events 本体内、共 ≥2 处）
    func testSealAndTerminalAndStreamLostFlush() throws {
        let seal = try segment(
            chatView,
            from: "private func sealStreamSegment()",
            to: "private func appendLiveToolCard"
        )
        XCTAssertTrue(
            seal.contains("flushStreamPublish()"),
            "封段拍须全量发布")
        let follow = try segment(
            chatView,
            from: "private func followRunEvents(",
            to: "private func sealStreamSegment()"
        )
        let flushCount = follow.components(
            separatedBy: "flushStreamPublish()"
        ).count - 1
        XCTAssertGreaterThanOrEqual(
            flushCount, 2,
            "终态拍与断流拍须各有一次全量发布")
    }

    /// 行集组装：直播行优先于占位行（同 if 分
    /// 支内先问直播行、回落占位行）
    func testNativeRowsPreferLiveRowOverPlaceholder() throws {
        let rows = try segment(
            chatView,
            from: "private func nativeRows()",
            to: "private func nativeEntryRow("
        )
        let liveIndex = try XCTUnwrap(
            rows.range(of: "liveStreamingRow(")?.lowerBound)
        let placeholderIndex = try XCTUnwrap(
            rows.range(of: "livePlaceholderRow(")?.lowerBound)
        XCTAssertLessThan(
            liveIndex, placeholderIndex,
            "直播行须先于占位行判定")
    }

    /// 直播行四守卫与行键/临界高口径
    func testLiveRowGuardsKeyAndProvisionalHeight() throws {
        let row = try segment(
            chatView,
            from: "private func liveStreamingRow(",
            to: "private func liveStreamRowKey()"
        )
        // 0.51.0 改钉（判读 B2）：gen4StreamingEnabled
        // 随 §503 gen4 特性退役摘除（退役已在 Streaming-
        // BlockProductTests.testStreamingFeatureRetired503
        // 落钉），令牌数组删该项，余五项不变
        for token in [
            "streamPresentationArmed",
            "livePartialEntryIDs.isEmpty",
            "liveStreamRowKey()",
            "heightIsProvisional: true",
            "StreamingLiveText.estimatedHeight(",
        ] {
            XCTAssertTrue(
                row.contains(token),
                "直播行构建缺 \(token)")
        }
    }

    /// 落定收尾：发布态整清与在飞旗同点（全部
    /// 落定出口共用 finishRunPresentation）
    func testFinishClearsPresentation() throws {
        let finish = try segment(
            chatView,
            from: "private func finishRunPresentation(",
            to: "private func requestRunStop()"
        )
        XCTAssertTrue(finish.contains("resetStreamPresentation()"))
        XCTAssertTrue(finish.contains("streamingText = nil"))
    }

    /// driveRun：武装直播行＋发布心跳在席
    func testDriveRunArmsPresentationAndTicker() throws {
        let drive = try segment(
            chatView,
            from: "private func driveRun(",
            to: "private func followRunEvents("
        )
        XCTAssertTrue(
            drive.contains("streamPresentationArmed = true"),
            "新发轮须武装直播行")
        XCTAssertTrue(
            drive.contains("tickStreamPublish()"),
            "心跳须在 driveRun 期驱动发布门排空")
    }

    /// 呈现视图：只走块级切分、逐词元件不复活
    func testLiveTextViewUsesBlockSegmenterOnly() throws {
        let view = try source(
            "Sources/OneDayApp/StreamingLiveText.swift")
        XCTAssertTrue(view.contains("StreamingBlockSegmenter"))
        XCTAssertFalse(
            view.contains("StreamingText("),
            "(b) 口径：StreamingText 逐词元件不复活")
    }
}
