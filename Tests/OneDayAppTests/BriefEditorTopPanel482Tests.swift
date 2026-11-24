import SwiftUI
import XCTest
@testable import OneDayApp

/// §487 钉测：动态简报编辑器呈现换轨（底部全屏
/// sheet → 顶部锚定覆盖面板）。几何与主题数值全抄
/// 参照录屏量测（brief-editor-presentation-audit
/// -20261124），本套钉死：①TopPanelMetrics 量测值
/// 与总占位验收带；②呈现换轨落点（sheet 退役／组
/// 件单源）；③文案简化与说明文字清零（用户
/// 2026-11-24 12:09 亲令）；④触感两接线（保存成
/// 功 success／失败 error、落位 impact 不落）。
final class BriefEditorTopPanel482Tests: XCTestCase {

    // MARK: - 源码读取（照 HapticsMatrixTests 口径）

    private func fileText(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("Sources")
            .appendingPathComponent(relative)
        guard let text = try? String(
            contentsOf: url, encoding: .utf8
        ) else {
            throw XCTSkip("\(relative) 不可达，断言跳过")
        }
        return text
    }

    private func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// 编辑器作用域（FeedBriefEditorView 起 → Kicker
    /// 扩展前）：呈现与文案断言只许在此范围内计数
    private func editorScope() throws -> String {
        let feed = try fileText("OneDayApp/FeedView.swift")
        guard let start = feed.range(
            of: "struct FeedBriefEditorView: View {"
        ), let end = feed.range(
            of: "// MARK: - Kicker", range: start.upperBound..<feed.endIndex
        ) else {
            throw XCTSkip("编辑器作用域定位失败，断言跳过")
        }
        return String(feed[start.lowerBound..<end.lowerBound])
    }

    // MARK: - 几何量测值（参照录屏逐帧实测）

    func testPanelMetricsMatchReferenceMeasurement() {
        XCTAssertEqual(TopPanelMetrics.cardTopInset, 62, accuracy: 0.5)
        XCTAssertEqual(
            TopPanelMetrics.cardHeightFraction, 0.458, accuracy: 0.001
        )
        XCTAssertEqual(TopPanelMetrics.cornerRadius, 31, accuracy: 0.5)
        XCTAssertEqual(
            TopPanelMetrics.cardHorizontalInset, 10, accuracy: 0.5
        )
        XCTAssertEqual(
            TopPanelMetrics.cardButtonGap, 10, accuracy: 0.5
        )
        XCTAssertEqual(TopPanelMetrics.buttonHeight, 47, accuracy: 0.5)
        XCTAssertEqual(TopPanelMetrics.buttonSpacing, 19, accuracy: 0.5)
        XCTAssertEqual(
            TopPanelMetrics.buttonRowHorizontalInset, 14, accuracy: 0.5
        )
        // 底层压暗 ×0.46（黑罩 0.54）／下推页顶 60.7%
        XCTAssertEqual(TopPanelMetrics.dimOpacity, 0.54, accuracy: 0.01)
        XCTAssertEqual(
            TopPanelMetrics.pushFraction, 0.607, accuracy: 0.002
        )
    }

    func testTotalOccupancyWithinAcceptanceBand() {
        // 参照实测总占位（卡顶→钮底）52.4%，验收 ±2
        // 个百分点（874pt 参照屏高）
        let fraction = TopPanelMetrics.totalOccupancyFraction(
            screenHeight: 874
        )
        XCTAssertEqual(fraction, 0.524, accuracy: 0.02)
        // 卡高单项：400pt／874pt
        XCTAssertEqual(
            TopPanelMetrics.cardHeight(screenHeight: 874),
            400, accuracy: 4
        )
    }

    // MARK: - 呈现换轨落点

    func testSheetRetiredAndPanelChained() throws {
        let feed = try fileText("OneDayApp/FeedView.swift")
        XCTAssertFalse(
            feed.contains(".sheet(isPresented: $briefEditorShown)"),
            "简报编辑器不许再走底部 sheet 呈现"
        )
        XCTAssertTrue(
            feed.contains(
                ".topAnchoredPanel(isPresented: $briefEditorShown)"
            ),
            "呈现必须挂 TopAnchoredPanel 组件单源"
        )
        XCTAssertFalse(
            feed.contains(".spring(response"),
            "弹簧参数只许在 TopAnchoredPanel 组件内定义"
        )
    }

    func testButtonsOutsideCard() throws {
        let scope = try editorScope()
        // 编辑器根 VStack：card 与 buttonRow 并列——
        // 双钮在卡外（卡下）固定，不随正文滚
        XCTAssertTrue(
            scope.contains(
                "VStack(spacing: TopPanelMetrics.cardButtonGap) {\n"
                    + "            card\n"
                    + "            buttonRow"
            ),
            "双钮必须是卡的同级行（卡外固定），不许回卡内"
        )
    }

    // MARK: - 文案简化与说明文字清零（12:09 亲令）

    func testHeaderCopyIsTwoLinesOnly() throws {
        let scope = try editorScope()
        XCTAssertTrue(scope.contains("Text(\"动态说明\")"))
        XCTAssertTrue(
            scope.contains("你的动态版块由以下指示驱动。"),
            "说明只许一句：由以下指示驱动＋编辑将应用于今后"
        )
        XCTAssertTrue(scope.contains("都将应用于今后的动态帖子。"))
        XCTAssertFalse(
            scope.contains("我的简报"),
            "旧导航标题「我的简报」已弃"
        )
    }

    func testAuxiliaryTextsRemoved() throws {
        let scope = try editorScope()
        XCTAssertFalse(
            scope.contains("保存后原样生效"),
            "保存说明 footer 是说明性文字，已删"
        )
        XCTAssertFalse(
            scope.contains("正在整理成正式简报"),
            "润色在飞弱提示是辅助文字，已删"
        )
        XCTAssertFalse(
            scope.contains("FeedBriefBoard.polishHint"),
            "润色弱提示取值已删（expandError 回执单独保留）"
        )
        // 错误回执保留（功能必需）：保存失败 briefError
        // 与上次整理失败 expandError 两行在页头件内
        XCTAssertTrue(scope.contains("store.briefError"))
        XCTAssertTrue(scope.contains("上次整理没成功"))
    }

    // MARK: - 触感接线（表 D 既有语义，只接线）

    func testSaveHapticsWiredExactlyOnce() throws {
        let scope = try editorScope()
        XCTAssertEqual(count(of: "Haptics.success()", in: scope), 1)
        XCTAssertEqual(count(of: "Haptics.error()", in: scope), 1)
        XCTAssertEqual(
            count(of: "Haptics.impact", in: scope), 1,
            "落位 impact .light（用户 2026-11-25 裁定）只许这一处"
        )
    }

    // MARK: - 页头高度实测回填（新文案）

    /// 页头（标题＋一句说明、无错误行）实测高回填
    /// 钉：卡内容宽 342pt（402 屏宽 − 卡边距 2×10
    /// − 内容内距 2×20）下，标题一行＋说明两行＋行
    /// 间距 12 ＝ 76.3pt（2026-11-24 UIHosting 实测
    /// 回填，见 DESIGN §487）；文案再改字先改本钉
    @MainActor
    func testHeaderHeightPinnedFromMeasurement() {
        let header = FeedBriefPanelHeader(
            briefError: nil, expandError: nil
        )
        let host = UIHostingController(rootView: header)
        let width = 402
            - TopPanelMetrics.cardHorizontalInset * 2
            - TopPanelMetrics.contentHorizontalInset * 2
        let size = host.sizeThatFits(
            in: CGSize(width: width, height: .infinity)
        )
        XCTAssertEqual(size.height, 76.3, accuracy: 1.5)
    }
}
