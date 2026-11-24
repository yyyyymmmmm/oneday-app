import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 连接页引导小包（2026-11-21，§335）的设备条件帧：
/// 分叉首屏（ConnectView 欢迎面）与通知权限段
/// （NotificationGuideView）在深色＋最大字号
/// （AX5＋粗体）两态下装配取帧。
///
/// 断言口径沿 §327 先例（AttachmentPanelFitAssem-
/// blyTests 沿革注）：App 测试窗口内 SwiftUI 无障碍
/// 标签集实测为空集（§303 首轮实证），在场断言不
/// 用 AX 标签面——标签集只采集打印留档；在场与条
/// 件帧证据走尺寸对账：内容高落内容构成推出的下
/// 限带、深色帧与浅色帧同高（只换色不改版）、AX
/// 帧实际生长（动态字号真到达版面、不被钉死字号
/// 吞掉——本包两面全部走文本样式档、无写死字号）。
@MainActor
final class ConnectGuideDeviceConditionTests: XCTestCase {

    /// 与既有组装探针同款设备窗（安全区覆写 59/34）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: UIWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    // MARK: - 装配

    private func assemble<V: View>(
        _ view: V, dark: Bool, boldAX: Bool
    ) -> UIHostingController<AnyView> {
        window?.rootViewController = nil
        window?.isHidden = true
        let host = UIHostingController(rootView: AnyView(view))
        let win = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        if dark {
            win.overrideUserInterfaceStyle = .dark
            host.overrideUserInterfaceStyle = .dark
        }
        if boldAX {
            host.traitOverrides.legibilityWeight = .bold
            host.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraLarge
            win.traitOverrides.legibilityWeight = .bold
            win.traitOverrides.preferredContentSizeCategory =
                .accessibilityExtraExtraLarge
        }
        window = win
        win.rootViewController = host
        win.makeKeyAndVisible()
        win.layoutIfNeeded()
        spinRunLoop(seconds: 2)
        win.layoutIfNeeded()
        return host
    }

    private func assembleConnectView(
        dark: Bool, boldAX: Bool
    ) {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        _ = assemble(
            ConnectView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container),
            dark: dark, boldAX: boldAX
        )
    }

    private func assembleNotificationSegment(
        dark: Bool, boldAX: Bool
    ) -> UIHostingController<AnyView> {
        assemble(
            NotificationGuideView(
                state: .notDetermined,
                onRequest: {}, onOpenSettings: {}, onAdvance: {}
            )
            .environment(\.locale, AppLocale.uiLocale),
            dark: dark, boldAX: boldAX
        )
    }

    // MARK: - 取数（与组装探针同口径）

    /// 标签集只作留档倾卸（§327 口径：测试窗口内
    /// 恒为空集，不作断言依据）
    private func collectAccessibilityLabels(
        in view: UIView
    ) -> [String] {
        var out: [String] = []
        if let label = view.accessibilityLabel {
            out.append(label)
        }
        if let elements = view.accessibilityElements {
            for element in elements {
                if let elementView = element as? UIView {
                    out.append(
                        contentsOf: collectAccessibilityLabels(
                            in: elementView
                        )
                    )
                } else if let object = element as? NSObject,
                          let label = object.accessibilityLabel {
                    out.append(label)
                }
            }
        }
        for sub in view.subviews {
            out.append(contentsOf: collectAccessibilityLabels(in: sub))
        }
        return out
    }

    /// 连接页滚动内容高（HostingScrollView 的
    /// contentSize；版面构成与 AX 生长的读数点）
    private func scrollContentHeight() -> CGFloat? {
        guard let window else { return nil }
        var found: UIScrollView?
        func walk(_ view: UIView) {
            if found != nil { return }
            if view is UIScrollView,
               String(describing: type(of: view))
                   .contains("HostingScrollView"),
               view.frame.width > 400 {
                found = view as? UIScrollView
                return
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        return found?.contentSize.height
    }

    private func segmentFitHeight(
        _ host: UIHostingController<AnyView>
    ) -> CGFloat {
        host.sizeThatFits(
            in: CGSize(
                width: 402, height: CGFloat.greatestFiniteMagnitude
            )
        ).height
    }

    // MARK: - 分叉首屏两帧

    /// 深色帧：内容高落构成下限带（页头＋演示卡＋
    /// 分叉双钮＋细字的构成高，缺任何一块都会掉出
    /// 带），且与浅色同高——深色只换色不改版
    func testWelcomeForkDarkFrame() {
        assembleConnectView(dark: false, boldAX: false)
        let lightHeight = scrollContentHeight() ?? 0
        assembleConnectView(dark: true, boldAX: false)
        let darkHeight = scrollContentHeight() ?? 0
        XCTAssertGreaterThan(
            lightHeight, 550,
            "浅色帧内容高 \(lightHeight) 掉出构成下限带"
        )
        XCTAssertEqual(
            darkHeight, lightHeight, accuracy: 2,
            "深色帧内容高与浅色不对账：\(lightHeight)→\(darkHeight)"
                + "（深色不许改版）"
        )
        add(XCTAttachment(string:
            "forkDark lightH=\(lightHeight) darkH=\(darkHeight)"
            + " labels=\(collectAccessibilityLabels(in: window))"))
    }

    /// 最大字号帧：AX5＋粗体下内容高实际生长（分叉
    /// 两钮与细字全走文本样式档的回归守卫）
    func testWelcomeForkAccessibilitySizeFrame() {
        assembleConnectView(dark: false, boldAX: false)
        let baseHeight = scrollContentHeight() ?? 0
        XCTAssertGreaterThan(baseHeight, 0, "基线帧滚动内容高缺席")
        assembleConnectView(dark: false, boldAX: true)
        let axHeight = scrollContentHeight() ?? 0
        XCTAssertGreaterThan(
            axHeight, baseHeight,
            "AX 帧内容未生长：\(baseHeight)→\(axHeight)"
                + "（动态字号未到达分叉版面）"
        )
        add(XCTAttachment(string:
            "forkAX baseH=\(baseHeight) axH=\(axHeight)"))
    }

    // MARK: - 通知权限段两帧

    /// 深色帧：未决定态段面拟合高落构成下限带（球
    /// ＋标题＋用途先行＋两用途＋主钮＋跳过＋细字），
    /// 且与浅色同高
    func testNotificationSegmentDarkFrame() {
        let lightHost = assembleNotificationSegment(
            dark: false, boldAX: false
        )
        let lightFit = segmentFitHeight(lightHost)
        let darkHost = assembleNotificationSegment(
            dark: true, boldAX: false
        )
        let darkFit = segmentFitHeight(darkHost)
        XCTAssertGreaterThan(
            lightFit, 400,
            "浅色帧通知段拟合高 \(lightFit) 掉出构成下限带"
        )
        XCTAssertEqual(
            darkFit, lightFit, accuracy: 1,
            "深色帧通知段拟合高与浅色不对账："
                + "\(lightFit)→\(darkFit)（深色不许改版）"
        )
        add(XCTAttachment(string:
            "notifDark lightH=\(lightFit) darkH=\(darkFit)"
            + " labels=\(collectAccessibilityLabels(in: window))"))
    }

    /// 最大字号帧：段面拟合高实际生长
    func testNotificationSegmentAccessibilitySizeFrame() {
        let baseHost = assembleNotificationSegment(
            dark: false, boldAX: false
        )
        let baseFit = segmentFitHeight(baseHost)
        XCTAssertGreaterThan(baseFit, 0, "基线帧通知段拟合高缺席")
        let axHost = assembleNotificationSegment(
            dark: false, boldAX: true
        )
        let axFit = segmentFitHeight(axHost)
        XCTAssertGreaterThan(
            axFit, baseFit,
            "AX 帧通知段未生长：\(baseFit)→\(axFit)"
                + "（动态字号未到达权限段版面）"
        )
        add(XCTAttachment(string:
            "notifAX baseH=\(baseFit) axH=\(axFit)"))
    }
}
