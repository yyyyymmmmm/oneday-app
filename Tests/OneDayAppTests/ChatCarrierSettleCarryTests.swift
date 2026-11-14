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
/// Size.height − 24
@MainActor
final class ChatCarrierSettleCarryTests: XCTestCase {

    private var window: UIWindow!
    private var controller: ChatListCarrierViewController!

    private let layout = ChatCarrierLayout(
        horizontalPadding: 20, topPadding: 16,
        bottomPadding: 8, rowSpacing: 24,
        arrowTrailing: 16, arrowSize: 44
    )

    override func setUp() async throws {
        try await super.setUp()
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        controller = ChatListCarrierViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        spinRunLoop(seconds: 0.2)
    }

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        controller = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
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
            topInset: 0, bottomInset: 0, bottomSpace: 0,
            keyboardAnimationDuration: 0,
            keyboardAnimationCurveRaw: 0, arrowView: nil
        )
    }

    private var contentRowHeight: CGFloat {
        controller.scrollView.contentSize.height - 24
    }

    func testSettleCarryKeepsMeasuredHeightAcrossVersionChange() {
        // 流式期：估算 100、量实 180（托管测得）
        apply(fixedRow(
            version: 1, estimated: 100, viewHeight: 180,
            carry: false))
        spinRunLoop(seconds: 0.3)
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 落定帧：同键、版本变、带旗、新内容实高
        // 260、估算 90——apply 同步帧高须仍按量实
        // 180 连续（不回落估算 90、不抢跳 260）
        apply(fixedRow(
            version: 2, estimated: 90, viewHeight: 260,
            carry: true))
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 托管重测的异步回填到达后纠偏到新量实
        spinRunLoop(seconds: 0.3)
        XCTAssertEqual(contentRowHeight, 260, accuracy: 0.6)
    }

    func testVersionChangeWithoutCarryDropsToEstimate() {
        apply(fixedRow(
            version: 1, estimated: 100, viewHeight: 180,
            carry: false))
        spinRunLoop(seconds: 0.3)
        XCTAssertEqual(contentRowHeight, 180, accuracy: 0.6)

        // 无旗：版本变即弃量实、回估算 90（包 3
        // 既有口径不许被留高旗误伤）
        apply(fixedRow(
            version: 2, estimated: 90, viewHeight: 260,
            carry: false))
        XCTAssertEqual(contentRowHeight, 90, accuracy: 0.6)
    }
}
