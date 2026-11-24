import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 顶簇带面构造断言（2026-11-22 带面改版，取代
/// §327 背板时代的 TopBarBackingPlateTests）：
/// §327 不透明背板（Palette.chatSurface 实色、
/// 窗口顶→顶簇底全带）已整件退役——用户真机反
/// 馈「顶栏实色块又在、朦胧感没了」。改后断言：
/// ①控制器子视图恒只含顶簇宿主一层：带内无任
/// 何自绘垫层（背板/材质片/色片同禁），静止透
/// 明、滚动朦胧归 §213 系统滚动边缘效果；
/// ②内容链缺席（未报实测高）时结构不变——无
/// 板即无裸板，「实心白块」物理上不再可能（原
/// 入席闸门的结构等价物）；
/// ③顶簇落点不退（§195）：静止/宿主帧下移补
/// 偿场景顶簇顶恒为窗口顶安全区；
/// ④树内契约在内容缺席/入席两态都成立。
@MainActor
final class TopBarBandFaceTests: XCTestCase {

    /// 设备窗口（与 EdgeEffectRegistrationTests
    /// 同式：覆写真机安全区顶 62／底 34）
    private final class BandDeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        }
    }

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true }
        windows = []
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// barHeight 传 nil＝不喂实测高：模拟内容链
    /// 缺席帧（空根停留/量测未达），供结构断言用
    private func mountTopHost(
        topOffset: CGFloat, barHeight: CGFloat?
    ) -> (BandDeviceWindow, TopBarGuideHostController) {
        let window = BandDeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        windows.append(window)
        let wrapper = UIViewController()
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints =
            false
        wrapper.view.addSubview(container)
        let host = TopBarGuideHostController()
        wrapper.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints =
            false
        container.addSubview(host.view)
        host.didMove(toParent: wrapper)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(
                equalTo: wrapper.view.leadingAnchor),
            container.trailingAnchor.constraint(
                equalTo: wrapper.view.trailingAnchor),
            container.topAnchor.constraint(
                equalTo: wrapper.view.topAnchor,
                constant: topOffset),
            container.bottomAnchor.constraint(
                equalTo: wrapper.view.bottomAnchor),
            host.view.leadingAnchor.constraint(
                equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(
                equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(
                equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(
                equalTo: container.bottomAnchor),
        ])
        window.rootViewController = wrapper
        window.makeKeyAndVisible()
        if let barHeight {
            host.updateBarContentHeight(barHeight)
        }
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)
        window.layoutIfNeeded()
        return (window, host)
    }

    // MARK: - ① 带内单层：无任何自绘垫层

    func testBandContainsOnlyClusterHost() throws {
        let (window, host) = mountTopHost(
            topOffset: 0, barHeight: 52
        )
        let bar = host.traceBarView

        // 控制器子视图恰一层＝顶簇宿主本体；带内
        // 不许再垫背板/材质片/色片（§327 退役口径）
        let subviews = host.view.subviews
        XCTAssertEqual(
            subviews.count, 1,
            "带内须只剩顶簇宿主一层，实得 \(subviews.count) 层"
        )
        XCTAssertTrue(
            subviews.first === bar,
            "唯一子视图须是顶簇宿主本体"
        )

        // 顶簇落点不退（§195）：顶＝窗口顶安全区 62
        let barFrame = bar.convert(bar.bounds, to: window)
        print("TOPBAR-BAND bar=\(barFrame)")
        XCTAssertEqual(
            barFrame.minY, 62, accuracy: 1,
            "顶簇顶须为窗口顶安全区 62，实得 \(barFrame.minY)"
        )
    }

    // MARK: - ② 内容链缺席：结构不变、无裸板可呈

    /// 故障帧复刻：控制器已装配、内容链未交付
    /// （未报任何实测高——空根停留/量测未达同
    /// 形）——带内仍只有透明宿主一层：原入席闸
    /// 门防的「只剩实心白块」自此是结构不可能，
    /// 不是运行时 hidden 巧合
    func testBandStructureUnchangedWhenContentAbsent() {
        let (_, host) = mountTopHost(
            topOffset: 0, barHeight: nil
        )
        let subviews = host.view.subviews
        XCTAssertEqual(
            subviews.count, 1,
            "内容缺席时带内仍须只有顶簇宿主一层，实得 "
                + "\(subviews.count) 层"
        )
        XCTAssertTrue(subviews.first === host.traceBarView)

        // 首个实测高到达后结构同样不变（无层入席）
        host.updateBarContentHeight(52)
        XCTAssertEqual(
            host.view.subviews.count, 1,
            "实测高到达不许带来任何新层，实得 "
                + "\(host.view.subviews.count) 层"
        )
        XCTAssertTrue(
            host.view.subviews.first === host.traceBarView
        )
    }

    // MARK: - ③ 宿主帧下移：顶簇补偿落点不退

    func testShiftedHostFrameStillLandsClusterAtSafeArea()
        throws
    {
        let (window, host) = mountTopHost(
            topOffset: 49, barHeight: 52
        )
        let bar = host.traceBarView
        let barFrame = bar.convert(bar.bounds, to: window)
        print("TOPBAR-BAND-SHIFTED bar=\(barFrame)")
        XCTAssertEqual(
            barFrame.minY, 62, accuracy: 1,
            "宿主下移 49 时顶簇须补偿回安全区 62，实得 "
                + "\(barFrame.minY)"
        )
        XCTAssertEqual(
            host.view.subviews.count, 1,
            "补偿场景带内仍须只有顶簇宿主一层"
        )
    }

    // MARK: - ④ 树内契约（2026-11-20 立，2026-11-22 改版）

    /// 契约在内容缺席态成立：带内单层/安全区纪
    /// 律两条全过——「内容缺席时无裸块」是装配
    /// 不变量、不是单点行为巧合
    func testAssemblyContractHoldsWhenContentAbsent() {
        let (_, host) = mountTopHost(
            topOffset: 0, barHeight: nil
        )
        XCTAssertEqual(
            host.assemblyContractViolations(), [],
            "内容缺席态装配契约须成立"
        )
    }

    /// 契约在内容入席后仍成立（宿主下移补偿场景
    /// 同验）
    func testAssemblyContractHoldsAfterFirstMeasure() {
        let (_, host) = mountTopHost(
            topOffset: 49, barHeight: 52
        )
        XCTAssertEqual(
            host.assemblyContractViolations(), [],
            "内容入席后装配契约须成立"
        )
    }
}
