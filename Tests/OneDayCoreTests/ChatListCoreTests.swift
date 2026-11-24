import XCTest
@testable import OneDayCore

/// 换代包 3·承载层 Core 钉测（DESIGN §257）：锚点
/// 捕获/恢复、供数新旧对拍（蓝图 B7 门）、行高组
/// 合模型、承载开关缺省。全部纯函数、无 UIKit。
final class ChatListCoreTests: XCTestCase {

    private let idA = UUID()
    private let idB = UUID()
    private let idC = UUID()

    private func sampleFrames() -> [ChatListAnchor.RowFrame] {
        // 三行：A[0,100) B[124,200) C[224,300)（行距 24）
        ChatRowHeightModel.frames(
            ids: [idA, idB, idC],
            heights: [100, 76, 76],
            rowSpacing: 24
        ).frames
    }

    // MARK: - 锚点捕获

    func testCaptureHitsRowAndRecordsIntraOffset() {
        let anchor = ChatListAnchor.capture(
            frames: sampleFrames(), viewportTop: 150
        )
        XCTAssertEqual(anchor?.entryID, idB)
        XCTAssertEqual(anchor?.intraEntryOffset ?? -1, 26, accuracy: 0.001)
        XCTAssertEqual(anchor?.atBottom, false)
    }

    func testCaptureInSpacingGapBelongsToNextRow() {
        // 110 落在 A 底边（100）与 B 顶边（124）的行距带内
        let anchor = ChatListAnchor.capture(
            frames: sampleFrames(), viewportTop: 110
        )
        XCTAssertEqual(anchor?.entryID, idB)
        XCTAssertEqual(anchor?.intraEntryOffset ?? -1, 0, accuracy: 0.001)
    }

    func testCaptureBeyondLastRowReturnsNil() {
        XCTAssertNil(
            ChatListAnchor.capture(
                frames: sampleFrames(), viewportTop: 400
            )
        )
        XCTAssertNil(
            ChatListAnchor.capture(frames: [], viewportTop: 0)
        )
    }

    func testCaptureAboveFirstRowClampsToFirstRow() {
        let anchor = ChatListAnchor.capture(
            frames: sampleFrames(), viewportTop: -40
        )
        XCTAssertEqual(anchor?.entryID, idA)
        XCTAssertEqual(anchor?.intraEntryOffset ?? -1, 0, accuracy: 0.001)
    }

    // MARK: - 锚点恢复

    func testRestoreRecomputesOffsetAfterHeightsAboveChange() {
        // 锚 B、条内偏移 26；恢复时 A 行高从 100 涨到
        // 160（产物落盘修正）——裸 offset 会错位 60，
        // 锚恢复须按新帧表把 B 的新顶边算进去
        let newFrames = ChatRowHeightModel.frames(
            ids: [idA, idB, idC],
            heights: [160, 76, 76],
            rowSpacing: 24
        ).frames
        let anchor = ChatListAnchor(
            entryID: idB, intraEntryOffset: 26, atBottom: false
        )
        let offset = ChatListAnchor.restoredOffsetY(
            frames: newFrames,
            anchor: anchor,
            contentOriginY: 16,
            topInset: 122,
            bottomInset: 197,
            contentHeight: 16 + 312 + 24 * 2 + 8,
            viewportHeight: 300
        )
        // B 新顶边（纯系）＝160＋24＝184；offset＝
        // 16＋184＋26−122＝104
        XCTAssertEqual(offset ?? -1, 104, accuracy: 0.001)
    }

    func testRestoreDeletedEntryReturnsNil() {
        let anchor = ChatListAnchor(
            entryID: UUID(), intraEntryOffset: 0, atBottom: false
        )
        XCTAssertNil(
            ChatListAnchor.restoredOffsetY(
                frames: sampleFrames(),
                anchor: anchor,
                contentOriginY: 16,
                topInset: 122,
                bottomInset: 197,
                contentHeight: 324,
                viewportHeight: 700
            )
        )
    }

    func testRestoreBottomAnchorGoesToMaxOffset() {
        let offset = ChatListAnchor.restoredOffsetY(
            frames: sampleFrames(),
            anchor: .bottom,
            contentOriginY: 16,
            topInset: 122,
            bottomInset: 197,
            contentHeight: 2000,
            viewportHeight: 700
        )
        XCTAssertEqual(offset ?? -1, 2000 + 197 - 700, accuracy: 0.001)
    }

    func testRestoreClampsToTopRestWhenContentShort() {
        // 内容总高＋inset 不足一屏：合法域塌到顶静止位
        let anchor = ChatListAnchor(
            entryID: idC, intraEntryOffset: 10, atBottom: false
        )
        let offset = ChatListAnchor.restoredOffsetY(
            frames: sampleFrames(),
            anchor: anchor,
            contentOriginY: 16,
            topInset: 122,
            bottomInset: 197,
            contentHeight: 324,
            viewportHeight: 700
        )
        XCTAssertEqual(offset ?? 0, -122, accuracy: 0.001)
    }

    // MARK: - 供数对拍（B7）

    func testSupplyFormulasAgreeOnGroundTruth() {
        // 规范状态：H=3000 T=122 B=197 V=700 s=1500
        let legacy = ChatScrollSupply.legacyDistance(
            contentHeight: 3000 + 122 + 197,
            offsetY: 1500,
            containerHeight: 700
        )
        let uiKit = ChatScrollSupply.uiKitDistance(
            contentHeight: 3000,
            offsetY: 1500 - 122,
            viewportHeight: 700,
            bottomInset: 197
        )
        XCTAssertEqual(legacy, 1119, accuracy: 0.001)
        XCTAssertEqual(uiKit, legacy, accuracy: 0.001)
    }

    func testReplaySequencesIdenticalAcrossTrace() {
        // 轨迹：在底→缓离底（带内保持）→远离底→事实
        // 信号救回在底→几何回底
        let trace: [ChatScrollSupply.CanonicalState] = [
            .init(contentHeight: 3000, topInset: 122,
                  bottomInset: 197, viewportHeight: 700,
                  travel: 2619, contentEndVisible: false), // 距底 0
            .init(contentHeight: 3000, topInset: 122,
                  bottomInset: 197, viewportHeight: 700,
                  travel: 2569, contentEndVisible: false), // 距底 50（≤7? 否，50>7 且 <176 → 保持）
            .init(contentHeight: 3000, topInset: 122,
                  bottomInset: 197, viewportHeight: 700,
                  travel: 2300, contentEndVisible: false), // 距底 319 → 离底
            .init(contentHeight: 3000, topInset: 122,
                  bottomInset: 197, viewportHeight: 700,
                  travel: 2300, contentEndVisible: true),  // 事实可见 → 在底
            .init(contentHeight: 3000, topInset: 122,
                  bottomInset: 197, viewportHeight: 700,
                  travel: 2619, contentEndVisible: false), // 距底 0 → 在底
            .init(contentHeight: 3400, topInset: 122,
                  bottomInset: 197, viewportHeight: 700,
                  travel: 2619, contentEndVisible: false), // 内容长高、距底 400 → 离底
        ]
        let replay = ChatScrollSupply.replayNearBottom(trace: trace)
        XCTAssertTrue(replay.distancesMatch)
        XCTAssertEqual(replay.legacy, replay.uiKit)
        XCTAssertEqual(
            replay.legacy,
            [true, true, false, true, true, false]
        )
    }

    // MARK: - 落定序列对拍（R2 供数换源门）

    /// 规范化状态速记：距底由 travel 反推（distance
    /// ＝H＋T＋B−V−travel）
    private func settleState(
        distance: Double,
        contentHeight: Double = 3000,
        bottomInset: Double = 70,
        contentEndVisible: Bool = false
    ) -> ChatScrollSupply.CanonicalState {
        let topInset: Double = 122
        let viewport: Double = 788
        return ChatScrollSupply.CanonicalState(
            contentHeight: contentHeight,
            topInset: topInset,
            bottomInset: bottomInset,
            viewportHeight: viewport,
            travel: contentHeight + topInset + bottomInset
                - viewport - distance,
            contentEndVisible: contentEndVisible
        )
    }

    func testSettleSequenceParityLandingEpisode() {
        // 落定回合：距底 120→60→25→8→3 逐拍收敛，
        // 末拍 ≤7 判 settled；两路序列逐点相等
        let trace = [120.0, 60, 25, 8, 3].map {
            settleState(distance: $0)
        }
        let replay = ChatScrollSupply.replaySettleSequence(
            trace: trace
        )
        XCTAssertTrue(replay.distancesMatch)
        XCTAssertEqual(replay.legacy, replay.uiKit)
        XCTAssertEqual(
            replay.legacy,
            [.continue, .continue, .continue, .continue,
             .settled]
        )
    }

    func testSettleSequenceParityKeyboardGrowthEpisode() {
        // 键盘升起回合（R2 键盘换代的供数形态）：底
        // inset 70→345 逐拍生长、行程同拍跟进、距底
        // 恒 0——首拍即 settled，两路同值
        let trace: [ChatScrollSupply.CanonicalState] = [
            settleState(distance: 0, bottomInset: 70),
            settleState(distance: 0, bottomInset: 150),
            settleState(distance: 0, bottomInset: 250),
            settleState(distance: 0, bottomInset: 345),
        ]
        let replay = ChatScrollSupply.replaySettleSequence(
            trace: trace
        )
        XCTAssertTrue(replay.distancesMatch)
        XCTAssertEqual(replay.legacy, replay.uiKit)
        XCTAssertEqual(replay.legacy, [.settled])
    }

    func testSettleSequenceParityUserLeavesEpisode() {
        // 用户离底回合：距底 40→300→320（停在远
        // 处）——第二拍判 exhausted、不拽回
        let trace = [40.0, 300, 320].map {
            settleState(distance: $0)
        }
        let replay = ChatScrollSupply.replaySettleSequence(
            trace: trace
        )
        XCTAssertTrue(replay.distancesMatch)
        XCTAssertEqual(replay.legacy, replay.uiKit)
        XCTAssertEqual(
            replay.legacy, [.continue, .exhausted]
        )
    }

    func testSettleSequenceParityRestickEpisode() {
        // 复贴回合：距底 60→58（运动）→58（停稳、
        // 未达标）触发唯一一次 restick，续回合 2 落定
        let trace = [60.0, 58, 58, 2].map {
            settleState(distance: $0)
        }
        let replay = ChatScrollSupply.replaySettleSequence(
            trace: trace
        )
        XCTAssertTrue(replay.distancesMatch)
        XCTAssertEqual(replay.legacy, replay.uiKit)
        XCTAssertEqual(
            replay.legacy,
            [.continue, .continue, .restick, .settled]
        )
    }

    // MARK: - 行高组合模型

    private func baseInput(
        textTotal: Double?,
        textCount: Int = 2,
        structural: Int = 0,
        measured: Double? = nil,
        divider: Bool = false
    ) -> ChatRowHeightModel.Input {
        ChatRowHeightModel.Input(
            textTotalHeight: textTotal,
            textSegmentCount: textCount,
            structuralSegmentCount: structural,
            measuredContentHeight: measured,
            hasDivider: divider,
            bubblePaddingV: 13,
            segmentSpacing: 8,
            dividerHeight: 18,
            dividerSpacing: 8,
            lineHeightFloor: 21,
            provisionalHeight: 64
        )
    }

    func testRowHeightComposesProductChromeAndSegments() {
        // 文本 100（2 段）＋结构 1 段 48＋段间 2×8
        // ＝内容 164；＋内边距 26＝190
        let height = ChatRowHeightModel.rowHeight(
            baseInput(textTotal: 100, structural: 1)
        )
        XCTAssertEqual(height, 164 + 26, accuracy: 0.001)
    }

    func testRowHeightAddsDividerBlock() {
        let height = ChatRowHeightModel.rowHeight(
            baseInput(textTotal: 40, textCount: 1, divider: true)
        )
        XCTAssertEqual(height, 40 + 26 + 18 + 8, accuracy: 0.001)
    }

    func testEmptyTextFallsToLineHeightFloor() {
        // 包 2 口径差：空文本产物高 0 → 下限兜底
        let height = ChatRowHeightModel.rowHeight(
            baseInput(textTotal: 0, textCount: 1)
        )
        XCTAssertEqual(height, 21 + 26, accuracy: 0.001)
    }

    func testMeasuredOverridesComposition() {
        let height = ChatRowHeightModel.rowHeight(
            baseInput(textTotal: 100, structural: 3, measured: 333)
        )
        XCTAssertEqual(height, 333 + 26, accuracy: 0.001)
    }

    func testMissingProductFallsToProvisional() {
        let height = ChatRowHeightModel.rowHeight(
            baseInput(textTotal: nil, divider: true)
        )
        XCTAssertEqual(height, 64, accuracy: 0.001)
    }

    func testFramesLayoutSkipsTrailingSpacing() {
        let (frames, total) = ChatRowHeightModel.frames(
            ids: [idA, idB], heights: [50, 60], rowSpacing: 24
        )
        XCTAssertEqual(frames.map(\.y), [0, 74])
        XCTAssertEqual(total, 134, accuracy: 0.001)
    }

    // MARK: - 承载开关


}
