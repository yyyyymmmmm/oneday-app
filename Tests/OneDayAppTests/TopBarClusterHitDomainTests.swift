import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §198 回归组：顶簇中央组命中域（路线 B「一个胶
/// 囊一个动作」）。前身 IdentityCapsuleHitDomain-
/// Tests 守的是已退役的双动作融域胶囊、且脚手架
/// 是 safeAreaBar 复刻（与生产 TopBarGuideHost 托
/// 管链不同构、其绿不作数——0.50.26 真机终验判红
/// 的教训之一）。本组按验收硬门重建：装配＝生产
/// 整页（RootView＋演示已连接态→DrawerContainer
/// →TabView→ChatView，与 ChatPageAssemblyRegres-
/// sionTests 同装配），胶囊与头像钮都经 ChatView
/// 的真实装配点（topBarCluster→headerBar）由真实
/// TopBarGuideHost 托管。
///
/// 不变量（任一回潮先红）：
/// ①两元素都在、都是按钮型无障碍元素，帧互不重
///   叠，横向间隔 ≥8pt（分域下限）；
/// ②胶囊只有一片玻璃、且玻璃帧覆盖胶囊全帧（含
///   padding 环）——992944a「玻璃比行帧小一圈」
///   的变窄回归守；玻璃帧亦不得外扩（宽/高 ≤帧
///   +3）——外扩即命中域外溢（动作门实测间隙点
///   被升模型面），同守；
/// ③没有任何一片玻璃同时压住头像钮帧与胶囊帧
///   （融域面退役守）；
/// ④hitTest 取点归属：胶囊域内点命中的视图只许
///   落在胶囊帧内、头像钮域内点只许落在头像钮帧
///   内、两元素间隙点不许命中任一元素帧内的视
///   图、亦不许命中覆盖该点的玻璃视图（玻璃外扩
///   时其帧含间隙点且不被任一域包含，旧断言对此
///   无感，本轮补上）。动作级派发（点→对的面升
///   起）由 TopBarSingleActionTapTests（XCUITest
///   打真 App 演示装配）守，本组只守结构与命中
///   归属。
///
/// 施工注记（2026-11-13 续工）：前四轮 CI 本组
/// 均在出判读前进程死亡（与键盘真崩／Drawer-
/// Container 同为 §184 进程死亡族签名：无断言失
/// 败、Restarting after unexpected exit）。本轮
/// 硬化：无障碍快照全程只收集一次（旧版每查一
/// 项重走全树四次，同步驱动量最重）、装配后加
/// 一拍沉降再取数、结构与命中拆成两个用例（死
/// 亡爆炸半径减半）、全程打诊断行（玻璃实帧＋
/// 每点命中视图类名/帧）使任何一轮日志都留证。
@MainActor
final class TopBarClusterHitDomainTests: XCTestCase {

    /// 与 ChatPageAssemblyRegressionTests 同口径的
    /// 设备窗：402×874、安全区覆写 top 59／bottom 34
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    /// 本用例内只收集一次的无障碍快照（见类注）
    private var snapshots: [AXSnapshot] = []

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        snapshots = []
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func assembleProductionPage() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 2.0)
        window.layoutIfNeeded()
        // 沉降一拍：外观/预热等异步链落定后再同步
        // 取数（死亡族与重入布局路径相关，先让链
        // 走完，见类注）
        spinRunLoop(seconds: 1.0)
        window.layoutIfNeeded()
        collectSnapshots()
    }

    // MARK: - 定位助手

    /// 无障碍元素快照（UIView 与 UIAccessibilityEle-
    /// ment 在 Swift 里的成员暴露不同，统一抽成值）
    private struct AXSnapshot {
        var identifier: String?
        var label: String?
        var frame: CGRect
        var traits: UIAccessibilityTraits
    }

    private func snapshot(of obj: Any) -> AXSnapshot? {
        if let view = obj as? UIView {
            return AXSnapshot(
                identifier: view.accessibilityIdentifier,
                label: view.accessibilityLabel,
                frame: view.accessibilityFrame,
                traits: view.accessibilityTraits
            )
        }
        if let element = obj as? UIAccessibilityElement {
            return AXSnapshot(
                identifier: element.accessibilityIdentifier,
                label: element.accessibilityLabel,
                frame: element.accessibilityFrame,
                traits: element.accessibilityTraits
            )
        }
        return nil
    }

    /// 递归收集无障碍元素（容器 API 下钻，含 UIHos-
    /// tingView 派发的 SwiftUI 元素），按标识去重；
    /// 每用例只走一次，结果存 snapshots 复用
    private func collectSnapshots() {
        var out: [AXSnapshot] = []
        var seen = Set<String>()
        func consider(_ obj: Any) {
            guard let snap = snapshot(of: obj) else { return }
            let key = [
                snap.identifier ?? "",
                snap.label ?? "",
                "\(snap.frame)",
            ].joined(separator: "|")
            if seen.insert(key).inserted {
                out.append(snap)
            }
        }
        func walk(_ view: UIView) {
            if view.isAccessibilityElement {
                consider(view)
            }
            let count = view.accessibilityElementCount()
            if count > 0 {
                for index in 0..<count {
                    if let element = view.accessibilityElement(at: index) {
                        consider(element)
                    }
                }
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        snapshots = out
    }

    private func elementFrame(identifier: String) -> CGRect? {
        snapshots.first { $0.identifier == identifier }?.frame
    }

    private func elementTraits(identifier: String) -> UIAccessibilityTraits? {
        snapshots.first { $0.identifier == identifier }?.traits
    }

    private func glassInteractionViews() -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            if String(describing: type(of: view))
                .contains("GlassInteraction") {
                found.append(view)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(window)
        return found
    }

    private func frameInWindow(_ view: UIView) -> CGRect {
        view.convert(view.bounds, to: window)
    }

    private func fmt(_ r: CGRect) -> String {
        String(
            format: "(%.0f,%.0f %.0fx%.0f)",
            r.minX, r.minY, r.width, r.height
        )
    }

    private func clusterFrames() throws -> (capsule: CGRect, avatar: CGRect) {
        let capsule = try XCTUnwrap(
            elementFrame(identifier: "topbar.modelCapsule"),
            "模型胶囊无障碍元素未找到"
        )
        let avatar = try XCTUnwrap(
            elementFrame(identifier: "topbar.hubAvatarButton"),
            "枢纽头像钮无障碍元素未找到"
        )
        return (capsule, avatar)
    }

    // MARK: - 关一：帧与玻璃（不变量①②③）

    func testTopBarClusterFramesAndGlass() throws {
        try assembleProductionPage()
        let (capsule, avatar) = try clusterFrames()
        let glasses = glassInteractionViews().map(frameInWindow)
        print("TOPBAR-STRUCT-BEGIN")
        print("capsule=\(fmt(capsule)) avatar=\(fmt(avatar)) "
            + "gap=\(capsule.minX - avatar.maxX)")
        for glass in glasses {
            print("glass=\(fmt(glass))")
        }
        print("TOPBAR-STRUCT-END")

        // ①都在、按钮型、帧不重叠、间隔 ≥8pt
        XCTAssertTrue(
            (elementTraits(identifier: "topbar.modelCapsule")?
                .contains(.button)) ?? false,
            "模型胶囊应为按钮型元素"
        )
        XCTAssertTrue(
            (elementTraits(identifier: "topbar.hubAvatarButton")?
                .contains(.button)) ?? false,
            "枢纽头像钮应为按钮型元素"
        )
        XCTAssertFalse(
            capsule.intersects(avatar),
            "两元素帧重叠：胶囊 \(fmt(capsule))／头像 \(fmt(avatar))"
        )
        XCTAssertLessThan(avatar.maxX, capsule.minX, "头像钮应在胶囊左侧")
        XCTAssertGreaterThanOrEqual(
            capsule.minX - avatar.maxX, 7.5,
            "两元素横向间隔应 ≥8pt（实测 "
                + "\(capsule.minX - avatar.maxX)）"
        )
        XCTAssertGreaterThanOrEqual(
            capsule.height, 36,
            "胶囊行高应含 padding 环（实测 \(capsule.height)）"
        )
        XCTAssertEqual(avatar.width, 44, accuracy: 1.5, "头像钮命中盘应为 44")
        XCTAssertEqual(avatar.height, 44, accuracy: 1.5, "头像钮命中盘应为 44")

        // ②③玻璃：覆盖全帧、不外扩、无跨域玻璃面
        let capsuleGlass = glasses.filter {
            $0.intersection(capsule).width >= capsule.width * 0.9
                && $0.intersection(capsule).height >= capsule.height * 0.9
        }
        XCTAssertEqual(
            capsuleGlass.count, 1,
            "胶囊应恰有一片覆盖其帧的玻璃（实测 \(capsuleGlass.count)）"
        )
        if let glass = capsuleGlass.first {
            XCTAssertGreaterThanOrEqual(
                glass.width, capsule.width - 2,
                "玻璃宽不得小于胶囊帧−2（变窄回归）："
                    + "玻璃 \(fmt(glass))／胶囊 \(fmt(capsule))"
            )
            XCTAssertGreaterThanOrEqual(
                glass.height, capsule.height - 2,
                "玻璃高不得小于胶囊帧−2（变窄回归）："
                    + "玻璃 \(fmt(glass))／胶囊 \(fmt(capsule))"
            )
            XCTAssertLessThanOrEqual(
                glass.width, capsule.width + 3,
                "玻璃宽不得大于胶囊帧+3（命中外扩回归，"
                    + "动作门实测间隙点被升面）："
                    + "玻璃 \(fmt(glass))／胶囊 \(fmt(capsule))"
            )
            XCTAssertLessThanOrEqual(
                glass.height, capsule.height + 3,
                "玻璃高不得大于胶囊帧+3（命中外扩回归）："
                    + "玻璃 \(fmt(glass))／胶囊 \(fmt(capsule))"
            )
        }
        for glass in glasses {
            let hitsAvatar = glass.intersection(avatar).area > 4
            let hitsCapsule = glass.intersection(capsule).area > 4
            XCTAssertFalse(
                hitsAvatar && hitsCapsule,
                "玻璃面 \(fmt(glass)) 同时压住头像钮与胶囊（融域回潮）"
            )
        }
    }

    // MARK: - 关二：hitTest 取点归属（不变量④）

    func testTopBarClusterHitAttribution() throws {
        try assembleProductionPage()
        let (capsule, avatar) = try clusterFrames()
        let glasses = glassInteractionViews()

        func describeHit(_ point: CGPoint) -> String {
            guard let hit = window.hitTest(point, with: nil) else {
                return "nil"
            }
            let kind = String(describing: type(of: hit))
            return "\(kind) \(fmt(frameInWindow(hit)))"
        }
        func isGlass(_ view: UIView) -> Bool {
            String(describing: type(of: view)).contains("GlassInteraction")
        }

        print("TOPBAR-HIT-BEGIN")
        print("capsule=\(fmt(capsule)) avatar=\(fmt(avatar))")

        func assertHit(
            _ point: CGPoint,
            inside own: CGRect?,
            outside other: CGRect?,
            _ name: String
        ) {
            print("hit \(name) at=(\(Int(point.x)),\(Int(point.y))) "
                + "-> \(describeHit(point))")
            let hit = window.hitTest(point, with: nil)
            guard let hit else {
                if own != nil {
                    XCTFail("\(name)：域内点 \(point) hitTest 返回 nil")
                }
                return
            }
            let hitFrame = frameInWindow(hit)
            if let own {
                XCTAssertTrue(
                    hitFrame.isContained(in: own.outsetBy(dx: 3, dy: 3))
                        || hitFrame.area <= 4,
                    "\(name)：点 \(point) 命中视图帧 \(fmt(hitFrame)) "
                        + "不在本域 \(fmt(own)) 内"
                )
            }
            if let other {
                XCTAssertFalse(
                    hitFrame.isContained(
                        in: other.insetBy(dx: -0.5, dy: -0.5)
                    ) && hitFrame.area > 4,
                    "\(name)：点 \(point) 命中对侧域视图帧 \(fmt(hitFrame))"
                )
                XCTAssertTrue(
                    hitFrame.intersection(other.insetBy(dx: 2, dy: 2)).isNull
                        || hitFrame.area <= 4
                        || hitFrame.contains(other),
                    "\(name)：点 \(point) 命中视图帧 \(fmt(hitFrame)) "
                        + "侵入对侧域 \(fmt(other))"
                )
            }
        }

        let capsulePoints: [CGPoint] = [
            CGPoint(x: capsule.midX, y: capsule.midY),
            CGPoint(x: capsule.minX + 6, y: capsule.midY),
            CGPoint(x: capsule.maxX - 6, y: capsule.midY),
            CGPoint(x: capsule.midX, y: capsule.minY + 3),
            CGPoint(x: capsule.midX, y: capsule.maxY - 3),
        ]
        for (index, point) in capsulePoints.enumerated() {
            assertHit(point, inside: capsule, outside: avatar, "胶囊点\(index)")
        }
        let avatarPoints: [CGPoint] = [
            CGPoint(x: avatar.midX, y: avatar.midY),
            CGPoint(x: avatar.minX + 5, y: avatar.midY),
            CGPoint(x: avatar.maxX - 5, y: avatar.midY),
            CGPoint(x: avatar.midX, y: avatar.minY + 5),
            CGPoint(x: avatar.midX, y: avatar.maxY - 5),
        ]
        for (index, point) in avatarPoints.enumerated() {
            assertHit(point, inside: avatar, outside: capsule, "头像点\(index)")
        }
        // 间隙点：不许命中任一元素帧内的视图；亦不
        // 许命中覆盖该点的玻璃视图——玻璃外扩时其
        // 帧横跨间隙点且不被任一域包含，须单独守
        let gapPoint = CGPoint(
            x: (avatar.maxX + capsule.minX) / 2, y: capsule.midY
        )
        print("hit GAP at=(\(Int(gapPoint.x)),\(Int(gapPoint.y))) "
            + "-> \(describeHit(gapPoint))")
        if let hit = window.hitTest(gapPoint, with: nil) {
            let hitFrame = frameInWindow(hit)
            for (name, domain) in [("头像", avatar), ("胶囊", capsule)] {
                XCTAssertFalse(
                    hitFrame.isContained(in: domain) && hitFrame.area > 4,
                    "间隙点命中\(name)域内视图帧 \(fmt(hitFrame))"
                )
            }
            XCTAssertFalse(
                isGlass(hit) && hitFrame.contains(gapPoint),
                "间隙点命中玻璃视图帧 \(fmt(hitFrame))"
                    + "——玻璃命中域外扩到间隙"
            )
            _ = glasses
        }
        print("TOPBAR-HIT-END")
    }
}

private extension CGRect {
    var area: CGFloat { width * height }

    func isContained(in other: CGRect) -> Bool {
        minX >= other.minX - 0.5 && minY >= other.minY - 0.5
            && maxX <= other.maxX + 0.5 && maxY <= other.maxY + 0.5
    }

    func outsetBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        insetBy(dx: -dx, dy: -dy)
    }
}
