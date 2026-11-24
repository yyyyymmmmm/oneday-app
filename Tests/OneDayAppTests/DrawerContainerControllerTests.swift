import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 抽屉容器（§156）真机打不开的复现/回归组（热修
/// 诊断用）：控制器裸装进窗口，只验开合呈现位移；
/// 干扰组分别复现「动画中布局往返」与「动画中宿主
/// 根视图重赋值」两种生产环境干扰，定位动画被谁摁死。
@MainActor
final class DrawerContainerControllerTests: XCTestCase {
    private var window: UIWindow!
    private var controller: DrawerContainerController!

    override func setUp() async throws {
        try await super.setUp()
        controller = DrawerContainerController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        controller = nil
        try await super.tearDown()
    }

    /// 前景层＝容器 view 的第二个子视图（底层抽屉宿
    /// 主第一、前景第二，viewDidLoad 装配序）；位移只
    /// 读它的 transform.tx（呈现口唯一写口）
    private var foregroundTx: CGFloat {
        let subviews = controller.view.subviews
        guard subviews.count >= 2 else { return -1 }
        return subviews[1].transform.tx
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    func testTravelEstablishedFromLayout() {
        // §313 单源 DrawerCardGeometry.travel、无 cap；
        // 占比 2026-11-21 样板对齐包改 0.79（现行版
        // 截图实测 317pt/402pt，见 DrawerCardGeometry
        // .travelWidthFraction 注）
        XCTAssertEqual(controller.travel, 393 * 0.79, accuracy: 0.5)
    }

    /// 抽屉宿主视图＝容器 view 的第一个子视图（底层
    /// drawerHost，viewDidLoad 装配序）
    private var drawerTx: CGFloat {
        let subviews = controller.view.subviews
        guard subviews.count >= 1 else { return .nan }
        return subviews[0].transform.tx
    }

    /// §313 锁步（第 78 条 D1）：抽屉层与前景同一刚
    /// 性平移——合态抽屉恒在 −travel（藏于主面之后、
    /// 首次布局后即成立）、开态归 0、关回 −travel；
    /// 动画路径 model 值同口径（动画闭包以目标值调
    /// applyOffset、双层同拍落位）
    func testDrawerLayerLockstepsWithForeground() {
        XCTAssertEqual(drawerTx, -controller.travel, accuracy: 0.5)
        XCTAssertEqual(foregroundTx, 0, accuracy: 0.5)
        controller.setDrawer(true, animated: false)
        XCTAssertEqual(drawerTx, 0, accuracy: 0.5)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 0.5)
        controller.setDrawer(false, animated: false)
        XCTAssertEqual(drawerTx, -controller.travel, accuracy: 0.5)
        controller.setDrawer(true, animated: true)
        XCTAssertEqual(
            drawerTx, 0, accuracy: 0.5,
            "打开动画起始拍抽屉 model 位移应已落目标值（与前景同拍提交）")
        spinRunLoop(seconds: 3.5)
        XCTAssertEqual(drawerTx, 0, accuracy: 1.0)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
    }

    func testInstantOpenAppliesFullTravel() {
        controller.setDrawer(true, animated: false)
        XCTAssertTrue(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 0.5)
    }

    /// 裸动画：无任何干扰，弹簧动画必须自己走完到
    /// travel（真机症状是停在约 9.5% travel）。
    /// §313 注（历史）：慢阻尼定版（1.4/ζ 1.2）时本
    /// 类等待曾放宽到 3.5s；§322 换快档定版
    /// （§351 定版 response 0.27/ζ 0.90、模型全程
    /// 落定 ≈0.24s；§322 档 0.35/0.85 落定 ≈0.41s
    /// 转沿革）
    /// 后等待收回 2.0s——仍留约 5 倍余量防 CI 时序
    /// 抖动，但慢档若回潮（落定 ≈1.5s＋animator 收
    /// 尾）会逼近本界、不再无声放行
    func testAnimatedOpenCompletesWithoutInterference() {
        controller.setDrawer(true, animated: true)
        spinRunLoop(seconds: 2.0)
        XCTAssertTrue(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
    }

    /// 干扰甲：动画途中反复触发容器布局往返（生产
    /// 里 SwiftUI 桥更新/宿主重排可引发）
    func testAnimatedOpenSurvivesLayoutPasses() {
        controller.setDrawer(true, animated: true)
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            spinRunLoop(seconds: 0.05)
        }
        spinRunLoop(seconds: 2.5)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
    }

    /// 干扰乙：动画途中反复重赋值两个宿主的根视图
    /// （生产里桥 apply() 每次 ContentView 求值都做）
    func testAnimatedOpenSurvivesRootViewChurn() {
        controller.drawerBuilder = { _ in AnyView(Text("drawer")) }
        controller.setDrawer(true, animated: true)
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline {
            controller.contentRoot = AnyView(Text("content"))
            spinRunLoop(seconds: 0.05)
        }
        spinRunLoop(seconds: 2.5)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
    }

    func testAnimatedCloseReturnsToZero() {
        controller.setDrawer(true, animated: false)
        controller.setDrawer(false, animated: true)
        spinRunLoop(seconds: 2.0)
        XCTAssertFalse(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, 0, accuracy: 1.0)
    }

    /// 直接测生产折叠件的 TupleView：五条导航必须同列，
    /// 不能被 GridRow 拆成五个 cell。不能只验壳层 tx。
    func testExpandedNavigationChildrenStayInOneColumn() throws {
        let frames = DrawerLayoutMeasurements()
        let root = DrawerCollapsibleContent(collapsed: false) {
            measuredDrawerRow(0)
            measuredDrawerRow(1)
            measuredDrawerRow(2)
            measuredDrawerRow(3)
            measuredDrawerRow(4)
        }
        .frame(width: 310, alignment: .leading)
        .coordinateSpace(name: "drawer-layout-test")
        .onPreferenceChange(DrawerRowFramesKey.self) { value in
            Task { @MainActor in frames.rows = value }
        }
        let host = UIHostingController(rootView: root)
        window.rootViewController = host
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.5)
        XCTAssertEqual(frames.rows.count, 5)
        for index in 0..<5 {
            let rect = try XCTUnwrap(frames.rows[index])
            XCTAssertEqual(rect.minX, 0, accuracy: 1)
            XCTAssertEqual(rect.width, 310, accuracy: 1)
            if index > 0 {
                let previous = try XCTUnwrap(frames.rows[index - 1])
                XCTAssertGreaterThanOrEqual(rect.minY, previous.maxY - 1)
            }
        }
    }

    func testCollapsedNavigationConsumesNoHeight() {
        let host = UIHostingController(rootView:
            DrawerCollapsibleContent(collapsed: true) {
                measuredDrawerRow(0)
                measuredDrawerRow(1)
            }
        )
        let size = host.sizeThatFits(in: CGSize(width: 310, height: 700))
        XCTAssertEqual(size.height, 0, accuracy: 1)
    }

    /// ForEach 多条旁聊也需要堆叠，不只修写死的导航行。
    func testExpandedThreadRowsAccumulateHeightAtNarrowWidth() {
        let host = UIHostingController(rootView:
            DrawerCollapsibleContent(collapsed: false) {
                ForEach(0..<6) { index in measuredDrawerRow(index) }
            }
        )
        let size = host.sizeThatFits(in: CGSize(width: 253, height: 700))
        XCTAssertLessThanOrEqual(size.width, 254)
        XCTAssertEqual(size.height, 6 * 54, accuracy: 1)
    }
}

private struct DrawerRowFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(
        value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor
private final class DrawerLayoutMeasurements {
    var rows: [Int: CGRect] = [:]
}

@MainActor
private func measuredDrawerRow(_ index: Int) -> some View {
    Color.clear
        .frame(height: 54)
        .overlay(alignment: .leading) { Text("导航 \(index)") }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DrawerRowFramesKey.self,
                    value: [index: proxy.frame(in: .named("drawer-layout-test"))]
                )
            }
        }
}

extension DrawerContainerControllerTests {
    /// 显示原点口径：transform.tx 是 model 值、被布局
    /// 补偿时照样达标，必须直验前景的实际显示原点
    /// （frame getter 按 center/bounds/transform 合成）
    private var foregroundDisplayedOriginX: CGFloat {
        let subviews = controller.view.subviews
        guard subviews.count >= 2 else { return -1 }
        return subviews[1].frame.origin.x
    }

    func testAnimatedOpenDisplayedOriginReachesTravel() {
        controller.setDrawer(true, animated: true)
        spinRunLoop(seconds: 3.5)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
        XCTAssertEqual(
            foregroundDisplayedOriginX, controller.travel, accuracy: 1.0,
            "model 位移达标但显示原点未达：位移被几何补偿吃掉"
        )
    }

    /// §186.8 补修 A（Codex 异源复核）：关闭动画起
    /// 始帧起内容必须保持不可点、命中不得落进内容
    /// 宿主，直到落定才恢复——修复前 animator 闭包
    /// 在起始拍以目标值 applyOffset(0) 把交互同步置
    /// true，呈现层还在移动（透传/命中按 model 值与
    /// 布局快照帧走），点会落进正在移动的内容
    /// §186.11：在途证据改 setDrawer 返回的同步瞬
    /// 间三合取（presentation 探针废弃，断言映射账
    /// 见 DESIGN §186.11）
    func testAnimatedCloseKeepsContentUntouchableUntilSettled() {
        controller.contentRoot = AnyView(Color.red)
        controller.view.layoutIfNeeded()
        controller.setDrawer(true, animated: false)
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "开态内容应不可点")
        controller.setDrawer(false, animated: true)
        // 在途三合取（同步瞬间、不泵 runloop）：
        // ①model 位移已落目标值——动画已提交（动画
        // 闭包在启动拍同步写 model；提交前读到的应
        // 是开态 travel、与本断言互斥）
        XCTAssertEqual(
            foregroundTx, 0, accuracy: 0.5,
            "关闭动画起始拍 model 位移应已落目标值（动画已提交）")
        // ②hitTest 打在显示几何（开态）下属于内容的
        // 中心点：呈现还停在旧几何、命中不得入内容
        // 宿主（与 ComposerGuideHostTests 关闭途中
        // 同步 hitTest 同源）
        let center = CGPoint(x: 196, y: 426)
        let midHit = controller.view.hitTest(center, with: nil)
        XCTAssertFalse(
            isInContentHost(midHit),
            "关闭动画在途命中穿进了内容宿主")
        // ③内容交互门已关——瞬时路径会在同一拍跑完
        // finishSettle 并按终值 0 把门开回，故同步瞬
        // 间门关只在 animator 在途时成立；飞行全程
        // 门的写口只有 applyOffset（animator 在途恒
        // 关）与落定 finishSettle（映射账见 §186.11）
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "关闭动画起始帧内容即恢复可点（呈现层还在移动）")
        spinRunLoop(seconds: 3.5)
        XCTAssertEqual(foregroundTx, 0, accuracy: 1.0)
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, true,
            "落定后内容应恢复可点")
        let settledHit = controller.view.hitTest(center, with: nil)
        XCTAssertTrue(
            isInContentHost(settledHit),
            "落定后命中应回到内容")
    }

    /// §186.8 补修 A（开向）：打开动画起始帧内容即
    /// 不可点、落定后保持（窄条承接点按）
    /// §186.11：在途证据改同步三合取（同关向，断言
    /// 映射账见 DESIGN §186.11）
    func testAnimatedOpenDisablesContentFromFirstFrame() {
        controller.contentRoot = AnyView(Color.red)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, true,
            "关态落定内容应可点")
        controller.setDrawer(true, animated: true)
        // 在途三合取（同步瞬间、不泵 runloop）：
        // ①model 位移已落目标值——动画已提交（提交
        // 前 model 停在 0、与本断言互斥；替代原
        // presentation 非 nil 的提交见证）
        XCTAssertEqual(
            foregroundTx, controller.travel, accuracy: 0.5,
            "打开动画起始拍 model 位移应已落目标值（动画已提交）")
        // ②hitTest 打在前景 model 位移后的屏内窄条
        // （显示几何下仍属内容的区域）：门若在起始
        // 拍误开、此点必穿入内容宿主
        let sliverPoint = CGPoint(x: controller.travel + 40, y: 426)
        let midHit = controller.view.hitTest(sliverPoint, with: nil)
        XCTAssertFalse(
            isInContentHost(midHit),
            "打开动画在途命中穿进了内容宿主")
        // ③内容交互门已关（飞行全程门写口唯一性同
        // 关向，见 §186.11）
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "打开动画起始帧内容应即刻不可点")
        spinRunLoop(seconds: 3.5)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
        XCTAssertEqual(
            contentHostView?.isUserInteractionEnabled, false,
            "开态落定后内容仍不可点")
    }

    /// 内容宿主视图（viewDidLoad 装配序：前景为容器
    /// 第二子、其内投影层第一子/裁切层第二子（台账
    /// 201 双层结构）、内容宿主在裁切层内）
    private var contentHostView: UIView? {
        let subviews = controller.view.subviews
        guard subviews.count >= 2,
              subviews[1].subviews.count >= 2 else { return nil }
        return subviews[1].subviews[1].subviews.first
    }

    private func isInContentHost(_ view: UIView?) -> Bool {
        guard let host = contentHostView else { return false }
        var node = view
        while let current = node {
            if current === host { return true }
            node = current.superview
        }
        return false
    }

    /// 动画途中强制真实布局（改窗口宽→容器 bounds 变
    /// →viewDidLayoutSubviews 必触发）：布局往返不得
    /// 改写已承诺的开合显示位置
    func testAnimatedOpenSurvivesMidFlightResize() {
        controller.setDrawer(true, animated: true)
        spinRunLoop(seconds: 0.15)
        window.frame = CGRect(x: 0, y: 0, width: 403, height: 852)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.15)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 3.5)
        XCTAssertTrue(controller.semanticPresented)
        XCTAssertEqual(foregroundTx, controller.travel, accuracy: 1.0)
        XCTAssertEqual(
            foregroundDisplayedOriginX, controller.travel, accuracy: 1.0,
            "动画途中布局往返后显示原点未达 travel：frame 重设在 transform 下反解 center 吃掉位移"
        )
    }

    /// §202 K1/K2 边缘几何（§351 刚体口径改版）：
    /// 三层未变换几何钉前景全幅（bounds/center 恒
    /// 定、开合全程不变），旧帧几何改由 transform
    /// 等价呈现——派生 frame（transform 绕中心作
    /// 用后的包围盒）与旧 clip 帧逐值一致（开态
    /// y＝2、高 −4、半径 54.5）；内容宿主 model
    /// 帧恒全幅（旧 −2 反向补偿改由裁切层 trans-
    /// form 承担、内容视觉位置不变）；合态回全
    /// 幅；开态改窗口尺寸后内嵌保持（resize 回
    /// 归）。阴影：§313「自动成影、路径恒 nil」经
    /// §351 定因改显式路径（开态非 nil、关态清
    /// 除）、定值 radius 18/x −4、浅色开态 opa-
    /// city 0.22 不变；台账 201 双层结构不变（投
    /// 影层与裁切层同 bounds/center/transform/半
    /// 径锁步）；像素成影本体由 DrawerSafeArea-
    /// RealRootTests 的接缝剖面测把守（数值断言
    /// 不单独作绿）
    func testOpenStateClipGeometryInsetsRadiusAndShadowPath() {
        window.overrideUserInterfaceStyle = .light
        let foreground = controller.view.subviews[1]
        let shadow = foreground.subviews[0]
        let clip = foreground.subviews[1]
        let content = clip.subviews[0]
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        // 未变换几何：三层全幅钉死
        XCTAssertEqual(clip.bounds, foreground.bounds)
        XCTAssertEqual(content.bounds, foreground.bounds)
        XCTAssertEqual(shadow.bounds, foreground.bounds)
        XCTAssertEqual(clip.center, CGPoint(x: 196.5, y: 426))
        XCTAssertEqual(content.center, clip.center)
        XCTAssertEqual(shadow.center, clip.center)
        // 派生呈现几何与旧帧口径逐值等价（浅色横移
        // 0、纵向 scaleY＝848/852）
        XCTAssertEqual(clip.frame.origin.x, 0, accuracy: 0.5)
        XCTAssertEqual(clip.frame.origin.y, 2, accuracy: 0.5)
        XCTAssertEqual(clip.frame.width, 393, accuracy: 0.5)
        XCTAssertEqual(clip.frame.height, 852 - 4, accuracy: 0.5)
        XCTAssertEqual(clip.transform.d, 848.0 / 852.0, accuracy: 0.0001)
        XCTAssertEqual(clip.transform.tx, 0, accuracy: 0.001)
        XCTAssertEqual(content.frame, foreground.bounds)
        XCTAssertEqual(content.transform, .identity)
        XCTAssertEqual(clip.layer.cornerRadius, 54.5, accuracy: 0.5)
        // 投影层锁步：同几何同 transform 同半径
        XCTAssertEqual(shadow.frame, clip.frame)
        XCTAssertEqual(shadow.transform, clip.transform)
        XCTAssertEqual(shadow.layer.cornerRadius, 54.5, accuracy: 0.5)
        XCTAssertNil(foreground.layer.shadowPath)
        XCTAssertNil(clip.layer.shadowPath)
        // §351 显式阴影路径：开态非 nil、包围盒＝
        // 投影层 bounds（局部坐标全幅圆角矩形）
        XCTAssertNotNil(shadow.layer.shadowPath)
        if let box = shadow.layer.shadowPath?.boundingBoxOfPath {
            XCTAssertEqual(box.width, 393, accuracy: 0.5)
            XCTAssertEqual(box.height, 852, accuracy: 0.5)
        }
        XCTAssertEqual(shadow.layer.shadowRadius, 18, accuracy: 0.5)
        XCTAssertEqual(shadow.layer.shadowOffset.width, -4, accuracy: 0.5)
        XCTAssertEqual(shadow.layer.shadowOffset.height, 0, accuracy: 0.5)
        XCTAssertEqual(
            shadow.layer.shadowOpacity, 0.22, accuracy: 0.01,
            "浅色开态柔影峰值（§202 定值、D4 浅色保留口径）")
        XCTAssertEqual(
            clip.layer.shadowOpacity, 0, accuracy: 0.01,
            "裁切层本体不再挂影（台账 201 双层结构）")

        window.frame = CGRect(x: 0, y: 0, width: 852, height: 393)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(clip.frame.origin.y, 2, accuracy: 0.5)
        XCTAssertEqual(clip.frame.height, 393 - 4, accuracy: 0.5)
        XCTAssertEqual(clip.bounds.height, 393, accuracy: 0.5)

        controller.setDrawer(false, animated: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(clip.frame, foreground.bounds)
        XCTAssertEqual(content.frame, foreground.bounds)
        XCTAssertEqual(clip.transform, .identity)
        XCTAssertEqual(shadow.layer.shadowOpacity, 0, accuracy: 0.01)
        XCTAssertNil(
            shadow.layer.shadowPath,
            "关态阴影路径应清除（§351）")
    }

    /// §313 深色阴影归零（第 78 条 D4）：深色外观下
    /// 开态投影层阴影 opacity 恒 0（Muse 深色帧段
    /// 无可量测阴影）；切回浅色恢复 0.22（trait 变
    /// 化经唯一呈现口重派生）。台账 201：阴影载体
    /// 自 clip 层迁投影层（前景第一子）、断言随迁。
    /// 注：宿主单测的裸窗
    /// overrideUserInterfaceStyle 不达根控制器 trait
    /// （两轮实测：赋值＋泵 runloop 后容器 trait 仍
    /// 读旧值、阴影按浅色落 0.22），故本例改走父级
    /// setOverrideTraitCollection 子级覆写——UIKit
    /// 确定性通道；生产窗（真场景根控制器）的外观
    /// 传播走系统 trait 树、同一 traitCollection 读口
    func testDarkStyleClearsDrawerShadow() {
        let parent = UIViewController()
        parent.view.frame = window.bounds
        window.rootViewController = parent
        parent.addChild(controller)
        parent.view.addSubview(controller.view)
        controller.view.frame = parent.view.bounds
        controller.didMove(toParent: parent)
        parent.setOverrideTraitCollection(
            UITraitCollection(userInterfaceStyle: .dark),
            forChild: controller)
        // 台账 201：前景第一子＝投影层（阴影载体）
        let shadow = controller.view.subviews[1].subviews[0]
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(
            shadow.layer.shadowOpacity, 0, accuracy: 0.01,
            "深色开态阴影应归零")
        // §351 深色接缝中间层：卡面（裁切层）横移
        // 16 露出前景底色、内容宿主反向抵消；前景
        // 底色深档解析＝#191919（25/255）
        let foreground = controller.view.subviews[1]
        let clip = foreground.subviews[1]
        let content = clip.subviews[0]
        XCTAssertEqual(clip.transform.tx, 16, accuracy: 0.5)
        XCTAssertEqual(shadow.transform.tx, 16, accuracy: 0.5)
        XCTAssertEqual(content.transform.tx, -16, accuracy: 0.5)
        let backdrop = foreground.backgroundColor?.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotNil(backdrop)
        if let backdrop {
            var r: CGFloat = 0, g: CGFloat = 0
            var b: CGFloat = 0, a: CGFloat = 0
            backdrop.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(r, 25.0 / 255.0, accuracy: 0.01)
            XCTAssertEqual(g, 25.0 / 255.0, accuracy: 0.01)
            XCTAssertEqual(b, 25.0 / 255.0, accuracy: 0.01)
        }
        parent.setOverrideTraitCollection(
            UITraitCollection(userInterfaceStyle: .light),
            forChild: controller)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(
            shadow.layer.shadowOpacity, 0.22, accuracy: 0.01,
            "切回浅色后阴影应按当前 offset 重派生恢复")
        XCTAssertEqual(
            clip.transform.tx, 0, accuracy: 0.5,
            "切回浅色后卡面横移应归零（无中间层）")
    }
}

extension DrawerContainerControllerTests {
    // MARK: - §323 场景门（采集半＋shouldBegin 接线）

    /// 左缘手势＝容器 view 第三子（edgeView）上的唯
    /// 一识别器（viewDidLoad 装配序）
    private var edgePanRecognizer: UIGestureRecognizer {
        controller.view.subviews[2].gestureRecognizers![0]
    }

    func testSceneScanHelpersReadHierarchyFacts() {
        // 空层级：无拖动、深度恒 1、无编辑
        let plain = UIView()
        XCTAssertFalse(
            DrawerContainerController.hierarchyHasDraggingScrollView(plain))
        XCTAssertEqual(
            DrawerContainerController.hierarchyMaxNavigationDepth(plain), 1)
        XCTAssertFalse(
            DrawerContainerController.hierarchyHasEditingList(plain))
        // 静止滚动视图不算 dragging（门 C 只认拖动态）
        let scroll = UIScrollView()
        plain.addSubview(scroll)
        XCTAssertFalse(
            DrawerContainerController.hierarchyHasDraggingScrollView(plain))
        // 深层导航：嵌套两层、取最大值
        let nav = UINavigationController(
            rootViewController: UIViewController())
        nav.pushViewController(UIViewController(), animated: false)
        let wrapper = UIView()
        wrapper.addSubview(nav.view)
        plain.addSubview(wrapper)
        XCTAssertEqual(
            DrawerContainerController.hierarchyMaxNavigationDepth(plain), 2)
        // 编辑态列表（深嵌同样命中）
        let table = UITableView()
        table.isEditing = true
        wrapper.addSubview(table)
        XCTAssertTrue(
            DrawerContainerController.hierarchyHasEditingList(plain))
    }

    func testSceneGateBlocksEdgePanInDeepNavigation() {
        // 无场景阻碍：左缘手势放行
        XCTAssertTrue(
            controller.gestureRecognizerShouldBegin(edgePanRecognizer))
        // 内容宿主里出现深层导航栈 → 门 D 挡下开手势
        let nav = UINavigationController(
            rootViewController: UIViewController())
        nav.pushViewController(UIViewController(), animated: false)
        contentHostView?.addSubview(nav.view)
        XCTAssertFalse(
            controller.gestureRecognizerShouldBegin(edgePanRecognizer))
        // 非左缘识别器不归场景门管（恒放行）
        XCTAssertTrue(
            controller.gestureRecognizerShouldBegin(
                UIPanGestureRecognizer()))
    }

    func testSceneGateBlocksEdgePanWhileEditing() {
        XCTAssertTrue(
            controller.gestureRecognizerShouldBegin(edgePanRecognizer))
        let table = UITableView()
        table.isEditing = true
        contentHostView?.addSubview(table)
        XCTAssertFalse(
            controller.gestureRecognizerShouldBegin(edgePanRecognizer))
    }
}
