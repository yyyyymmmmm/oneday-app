import OneDayCore
import UIKit
import XCTest
@testable import OneDayApp

/// 台账 189/190 根治包验收（合成层级/纯逻辑面）：
/// ① 可见胶囊定位启发式——iOS 26 浮动坞形态的
/// 合成复刻（bar 帧 402×122.3、全帧背景层＋悬
/// 浮内嵌胶囊 39pt 上内距/63pt 高）须命中胶囊
/// 本体、不命中全帧背景与窄按钮；空 bar/无合
/// 格子视图回 nil（落位回落常量链的降级口）
/// ② 诊断面数据源一行读口在无数据时不崩、格式
/// 锚点在位（ChatLagProbe 汇总/量测台积压行）
@MainActor
final class ChatRootFix189190Tests: XCTestCase {

    private func makeView(
        _ frame: CGRect, hidden: Bool = false
    ) -> UIView {
        let view = UIView(frame: frame)
        view.isHidden = hidden
        return view
    }

    func testFindDockCapsuleHitsFloatingPlatter() {
        let bar = UITabBar(
            frame: CGRect(x: 0, y: 0, width: 402, height: 122.3)
        )
        // 全帧背景层：高超上限（90）出局
        bar.addSubview(makeView(
            CGRect(x: 0, y: 0, width: 402, height: 122.3)
        ))
        // 窄按钮：宽不足出局
        bar.addSubview(makeView(
            CGRect(x: 20, y: 60, width: 60, height: 50)
        ))
        // 可见胶囊（诊断图3 实测几何：顶 39、高 63）
        let capsule = makeView(
            CGRect(x: 11, y: 39, width: 380, height: 63)
        )
        bar.addSubview(capsule)
        XCTAssertTrue(
            ChatRootViewController.findDockCapsule(in: bar)
                === capsule,
            "胶囊启发式须命中悬浮内嵌的可见坞体"
        )
    }

    func testFindDockCapsulePrefersLowestTop() {
        let bar = UITabBar(
            frame: CGRect(x: 0, y: 0, width: 402, height: 122.3)
        )
        // 上部全宽层（顶 26）与下部胶囊（顶 39）同
        // 合格时取顶更靠下者（可见坞体在帧下部）
        bar.addSubview(makeView(
            CGRect(x: 0, y: 26, width: 402, height: 50)
        ))
        let capsule = makeView(
            CGRect(x: 11, y: 39, width: 380, height: 63)
        )
        bar.addSubview(capsule)
        XCTAssertTrue(
            ChatRootViewController.findDockCapsule(in: bar)
                === capsule
        )
    }

    func testFindDockCapsuleDegradesToNil() {
        let bar = UITabBar(
            frame: CGRect(x: 0, y: 0, width: 402, height: 122.3)
        )
        XCTAssertNil(
            ChatRootViewController.findDockCapsule(in: bar),
            "空 bar 须回 nil（回落常量链）"
        )
        // 隐藏的胶囊不算可见坞体
        bar.addSubview(makeView(
            CGRect(x: 11, y: 39, width: 380, height: 63),
            hidden: true
        ))
        XCTAssertNil(
            ChatRootViewController.findDockCapsule(in: bar)
        )
    }

    func testDiagnosticsReadoutsAreWellFormed() {
        ChatLagProbe.reset()
        let lag = ChatLagProbe.summaryLine()
        XCTAssertTrue(lag.contains("feed"), lag)
        XCTAssertTrue(lag.contains("托管建"), lag)
        let backlog = ChatNativeRowMeasureDesk.backlogLine()
        XCTAssertTrue(backlog.contains("积压"), backlog)
        XCTAssertTrue(backlog.contains("就地量测"), backlog)
    }
}
