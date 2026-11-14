import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §247（包 4）承载留高旗单测：流式行落定换代
/// 时（同键＋版本变＋带旗），落定帧行高按流式
/// 期量实连续（不回落估算）、托管重测后量实回
/// 填再纠偏；无旗行版本变仍按包 3 口径弃量实
/// 回估算。以 contentSize 为观测面（顶/底
/// padding 16/8 已知）：单行内容高＝content-
/// Size.height − 24。
///
/// 宿主形态（CI 二轮教训）：不用 UIWindow——
/// 测试宿主里窗口不布局、VC 宽度恒 0、layout-
/// Content 被守卫挡下（contentSize 恒 0）；改
/// 离屏直驱：loadViewIfNeeded＋定帧＋layout-
/// IfNeeded 触发 viewDidLayoutSubviews 定宽，
/// 量实回填的观测不用 runloop 等待——以 inset
/// 切换作同步泵（apply 在 insetChanged 时同
/// 步重跑 layoutContent、按已记量实重算帧），
/// 全程无异步等待、免宿主龟速下的 spin 超时
@MainActor
final class ChatCarrierSettleCarryTests: XCTestCase {

    private var controller: ChatListCarrierViewController!
    private var pumpInset: CGFloat = 0

    private let layout = ChatCarrierLayout(
        horizontalPadding: 20, topPadding: 16,
        bottomPadding: 8, rowSpacing: 24,
        arrowTrailing: 16, arrowSize: 44
    )

    override func setUp() async throws {
        try await super.setUp()
        controller = ChatListCarrierViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(
            x: 0, y: 0, width: 402, height: 874
        )
        controller.view.layoutIfNeeded()
        XCTAssertEqual(
            controller.scrollView.bounds.width, 402,
            accuracy: 0.6, "离屏定宽未生效")
    }

    override func tearDown() async throws {
        controller = nil
        try await super.tearDown()
    }

    private func fixedRow(
        version: Int, estimated: CGFloat, viewHeight: CGFloat,
        carry: Bool
    ) -> ChatCarrierRow {
        ChatCarrierRow(
            key: "stream-user-1",
            entryID: nil,
            version: version,
            estimatedHeight: estimated,
            keepsMeasuredHeightOnVersionChange: carry,
            makeView: {
                AnyView(
                    Color.red.frame(width: 300, height: viewHeight)
                )
            }
        )
    }

    private func apply(_ row: ChatCarrierRow) {
        controller.apply(
            rows: [row], layout: layout,
            topInset: pumpInset, bottomInset: 0, bottomSpace: 0,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0, arrowView: nil
        )
    }

    /// 同步泵：同行集换 inset 再 apply 一次——
    /// insetChanged 触发 layoutContent 同步重
    /// 算（帧高按已记量实解析），把 materialize
    /// 在上一 apply 内已同步记下的量实反映到
    /// contentSize，不靠异步重排的时序
    private func pump(_ row: ChatCarrierRow) {
        pumpInset = pumpInset == 0 ? 0.5 : 0
        apply(row)
    }

    private var contentRowHeight: CGFloat {
        controller.scrollView.contentSize.height - 24
    }

    func testSettleCarryKeepsMeasuredHeightAcrossVersionChange() {
        // 流式期：估算 100、托管量实 180——apply
        // 内 materialize 同步记量实，泵后帧高按
        // 量实落定
        let streaming = fixedRow(
            version: 1, estimated: 100, viewHeight: 180,
            carry: false)
        apply(streaming)
        pump(streaming)
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 落定帧：同键、版本变、带旗、新内容实高
        // 260、估算 90——apply 同步帧高须仍按移交
        // 的量实 180 连续（不回落估算、不抢跳新高）
        let settled = fixedRow(
            version: 2, estimated: 90, viewHeight: 260,
            carry: true)
        apply(settled)
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 托管已在落定 apply 内记下新量实 260，
        // 泵后纠偏到 260（量实回填覆盖）
        pump(settled)
        XCTAssertEqual(contentRowHeight, 260, accuracy: 0.6)
    }

    func testVersionChangeWithoutCarryDropsToEstimate() {
        let streaming = fixedRow(
            version: 1, estimated: 100, viewHeight: 180,
            carry: false)
        apply(streaming)
        pump(streaming)
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 无旗：版本变即弃量实、同步回估算 90
        // （包 3 既有口径不许被留高旗误伤）
        apply(fixedRow(
            version: 2, estimated: 90, viewHeight: 260,
            carry: false))
        XCTAssertEqual(contentRowHeight, 90, accuracy: 0.6)
    }
}
