import OneDayDesign
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §318 盲区堵漏（诊断 drawer-broken-diagnosis-
/// 20261117.md §2「为何 CI 没拦住」）：.64 的抽屉
/// 命名测试一律用桩内容根（EmptyView 系），只断言
/// transform 与显示原点——真 DrawerView 的安全区
/// 消费（身份行 .safeAreaBar 顶注册靠安全区顶定
/// 位、底条 .safeAreaBar 靠安全区底落位）从未被
/// 任何断言覆盖，A-21 清零
/// 误伤因此全程绿灯。本套件以**真 DrawerView**（经
/// 容器 drawerBuilder 注入、与生产桥 apply() 同款
/// 环境）装配进真 DrawerContainerController＋设备
/// 窗（402×874、安全区覆写顶 59／底 34，与诊断真
/// 机同口径），断言渲染几何：
/// - 名单 ScrollView 的 adjustedContentInset.top
///   ＝108——量测口径经两轮实测定案：名单平台视
///   图帧全幅（帧顶 0）、顶注册栏高 49 经平台调
///   整层到达（adjusted＝49＋59＝108）；宿主清零
///   时调整层归零、adjusted 回 49。栏高沿革：初
///   定 72（adjusted 131，手排空程 contentMar-
///   gins）→2026-11-21 抽屉样板对齐包随身份行
///   顶距改 56→2026-11-22 抽屉量测对齐包两步：
///   身份行改 .safeAreaBar(edge: .top) 顶注册
///   （栏高 56 与旧空程逐点恒等）、手排空程退
///   役；同包 B 项页头改只留名字大标题后栏高改
///   49（顶 spacingSM 12＋题行高 29＋底 spacingS
///   8），另由 contentInset.top＝0 断言钉住「注
///   册而非空程」（见第二测）。页头是顶注册栏的
///   内容、栏自安全区顶起（题自排顶距 spacingSM
///   12 ⟹ 题顶 59＋12＝71），故本值达标 ⟺ 派生
///   到达 DrawerView 本体。
/// - 底条搜索字段中心 y＝810：底条内容底缘停在安
///   全区线之上 4pt（距屏底 34＋4＝38，诊断 §8 口
///   径），胶囊高 52 居中于条内 → 中心距屏底 64；
///   清零态整条下沉 34、中心移至 844，必红。
/// - 面板不透明量测：真 DrawerView 单独装宿主、背
///   后垫纯红，开态渲染采样面板空区像素——实色面
///   只可能落 chatSurface 双档（#FCFCFC 或纯黑，
///   通道差 ≤6）；thinMaterial 透红时呈粉灰、通道
///   差数十，必红（§318 材质定案的量测留证）。
@MainActor
final class DrawerSafeAreaRealRootTests: XCTestCase {

    /// 与诊断真机同口径的设备窗（402×874、安全区
    /// 覆写 top 59／bottom 34；R4 装配套件同款）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    private var appState: AppState!
    private var container: ModelContainer!
    /// §184：容器租约——见 SwiftDataTestMount
    private var swiftDataMount = SwiftDataTestMount()

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
    }

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        container = nil
        appState = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 真 DrawerView 本体（与生产桥 apply() 同款环
    /// 境逐项注入）
    private func makeDrawerView(width: CGFloat) -> AnyView {
        let appState = appState!
        let modelContext = container.mainContext
        return AnyView(
            DrawerView(
                width: width,
                currentTab: .chat,
                onSelectTab: { _ in },
                onClose: {},
                onOpenChannel: { _ in }
            )
            .environment(appState)
            .environment(\.modelContext, modelContext)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .boldTextMapping()
        )
    }

    /// 与生产桥 apply() 同款装配：真 DrawerView 经
    /// drawerBuilder 注入（环境逐项同桥）、内容侧替
    /// 身（桥级先例 DrawerBridgeHarness 同形态）
    private func assembleDrawerController() -> DrawerContainerController {
        let controller = DrawerContainerController()
        controller.drawerBuilder = { width in
            self.makeDrawerView(width: width)
        }
        controller.contentRoot = AnyView(Text("content替身"))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return controller
    }

    /// 台账 201 接缝剖面专用装配：容器与几何全走
    /// 生产本体，两侧内容用不透明同色面（chat-
    /// Surface）替身——剖面测的是面板面＋影带＋卡
    /// 面三者的亮度关系，真机三面同为 252（规格
    /// §1 横扫口径）；真 DrawerView 的面板实色已
    /// 由 §318 像素测单独证明（testDrawerPanelIs-
    /// OpaqueSolidOverSaturatedBackdrop），本测不
    /// 重复。替身的另一理由（2026-11-22 探针三轮
    /// 实测）：容器装配下真 DrawerView 的宿主层不
    /// 进进程内光栅（layer.render 与 drawHierar-
    /// chy 均采到透明），简单色面替身可光栅、且不
    /// 改变被测的容器层几何与阴影成像
    private func assembleSeamProbeController() -> DrawerContainerController {
        let controller = DrawerContainerController()
        controller.drawerBuilder = { _ in
            AnyView(Palette.chatSurface.ignoresSafeArea())
        }
        controller.contentRoot = AnyView(
            Palette.chatSurface.ignoresSafeArea()
        )
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return controller
    }

    private func findAll<T: UIView>(
        _ type: T.Type, in view: UIView
    ) -> [T] {
        var found: [T] = []
        if let hit = view as? T { found.append(hit) }
        for sub in view.subviews {
            found.append(contentsOf: findAll(type, in: sub))
        }
        return found
    }

    /// 真 DrawerView 装配下：名单顶＝安全区顶、底条
    /// 搜索字段中心落位达标（§318 F1 回归钉）
    func testRealDrawerViewConsumesHostSafeArea() throws {
        let controller = assembleDrawerController()
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)

        let drawerHostView = try XCTUnwrap(
            controller.view.subviews.first,
            "容器首子视图应为抽屉宿主"
        )
        XCTAssertFalse(drawerHostView.isHidden, "开态抽屉宿主应可见")

        // 名单安全区消费：宿主派生经平台调整层到达
        // （见文件头注）——adjusted＝49（顶注册栏
        // 高）＋59（宿主安全区顶）＝108；栏高沿革
        // 见文件头注（72→56→顶注册恒等→B 项页头
        // 改版 49）
        let scrollViews = findAll(UIScrollView.self, in: drawerHostView)
        let list = try XCTUnwrap(
            scrollViews.max(by: {
                $0.frame.height < $1.frame.height
            }),
            "真 DrawerView 内未找到名单 ScrollView"
        )
        XCTAssertEqual(
            list.adjustedContentInset.top, 108, accuracy: 2,
            "名单 adjustedContentInset.top 应为 108（顶注册栏高 49＋宿主安全区 59）；"
                + "实测 adjusted=\(list.adjustedContentInset.top)、"
                + "contentInset.top=\(list.contentInset.top)、"
                + "帧顶=\(list.convert(list.bounds, to: window).minY)"
                + "——宿主安全区派生若被清零 adjusted 回 49"
        )

        // 底条落位：搜索字段（底条三件中的平台视图）
        // 中心距屏底应 64（安全区 34＋条内底距 4＋行
        // 盒半高 26——2026-11-21 样板对齐包后控件 45
        // 居中于 52 行盒、字段中心与行盒中心同线，
        // 落位与改前同值；样板实测中心距屏底 64.2）
        let fields = findAll(UITextField.self, in: drawerHostView)
        let searchField = try XCTUnwrap(
            fields.first, "底条内未找到搜索 TextField"
        )
        let fieldFrameInWindow = searchField.convert(
            searchField.bounds, to: window
        )
        XCTAssertEqual(
            fieldFrameInWindow.midY, 874 - 64, accuracy: 3,
            "底条搜索字段中心应距屏底 64（落位 38＋半高 26）；"
                + "实测中心 \(fieldFrameInWindow.midY)——清零态整条下沉 34 至 844"
        )
    }

    /// 2026-11-22 抽屉量测对齐包机制钉：名单顶距由
    /// 页头顶注册（.safeAreaBar）发放、不是手排空
    /// 程——手排 contentMargins 会落进名单自身的
    /// contentInset.top（旧形态实测＝56），注册形态
    /// contentInset.top 应为 0 而 adjusted 仍 108
    /// （栏高 49＋宿主 59）。若有人把顶注册改回
    /// contentMargins，本测必红
    func testTopInsetComesFromBarRegistrationNotMargins() throws {
        let controller = assembleDrawerController()
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)

        let drawerHostView = try XCTUnwrap(
            controller.view.subviews.first,
            "容器首子视图应为抽屉宿主"
        )
        let scrollViews = findAll(UIScrollView.self, in: drawerHostView)
        let list = try XCTUnwrap(
            scrollViews.max(by: {
                $0.frame.height < $1.frame.height
            }),
            "真 DrawerView 内未找到名单 ScrollView"
        )
        XCTAssertEqual(
            list.contentInset.top, 0, accuracy: 0.5,
            "名单 contentInset.top 应为 0（顶距走顶注册栏、非手排空程）；"
                + "实测 contentInset.top=\(list.contentInset.top)、"
                + "adjusted=\(list.adjustedContentInset.top)"
        )
        XCTAssertEqual(
            list.adjustedContentInset.top, 108, accuracy: 2,
            "名单 adjustedContentInset.top 应仍为 108（顶注册栏高 49＋宿主安全区 59）；"
                + "实测 adjusted=\(list.adjustedContentInset.top)"
        )
    }

    /// 台账 201 像素验收（规格 drawer-card-edge-
    /// shadow-20261122.md §4）：开态静帧渲染后横扫
    /// 接缝剖面——主面卡左缘柔影必须真渲染出来：
    /// 带外（接缝 −50pt）≥250、向接缝单调渐暗、
    /// 贴边（−2pt）落 223–235、内容侧（＋5pt）
    /// ≥250、角区暗带跟随弧线。数值断言（opacity/
    /// 半径）全绿而像素无影正是本项立项原因，本测
    /// 只认像素
    func testOpenDrawerSeamShadowProfile() throws {
        let controller = assembleSeamProbeController()
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)

        let buffer = try XCTUnwrap(
            renderWindowBuffer(), "窗口渲染采样失败"
        )
        // 渲染自检：面板远区（100, 437）与内容区
        // （390, 437）都应是 252 同色面——任一为 0
        // 即出图链断裂、剖面数字不作数
        XCTAssertGreaterThanOrEqual(
            sampleRed(buffer, at: CGPoint(x: 100, y: 437)), 250,
            "渲染自检失败：面板远区应 ≥250，实测 "
                + "\(sampleRed(buffer, at: CGPoint(x: 100, y: 437)))"
                + "（scale \(buffer.scale)、缓冲 \(buffer.width)×\(buffer.height)）"
        )
        XCTAssertGreaterThanOrEqual(
            sampleRed(buffer, at: CGPoint(x: 390, y: 437)), 250,
            "渲染自检失败：内容远区应 ≥250，实测 "
                + "\(sampleRed(buffer, at: CGPoint(x: 390, y: 437)))"
        )
        let seam = controller.travel
        let midY: CGFloat = 437
        func r(at dx: CGFloat, y: CGFloat) -> Int {
            // 三行中位数抗杂点（面板空态面平、影带
            // 纵向一致）
            let rows = [y - 6, y, y + 6].map {
                sampleRed(buffer, at: CGPoint(x: seam + dx, y: $0))
            }.sorted()
            return rows[1]
        }
        var profile: [String] = []
        for dx in stride(from: -60, through: 10, by: 5) {
            profile.append("\(Int(dx)):\(r(at: CGFloat(dx), y: midY))")
        }
        let profileText = profile.joined(separator: " ")
        XCTAssertGreaterThanOrEqual(
            r(at: -50, y: midY), 250,
            "带外 −50pt 应 ≥250（干净）；剖面 \(profileText)"
        )
        var previous = 256
        for dx in [-50, -40, -30, -20, -12, -6, -2] {
            let value = r(at: CGFloat(dx), y: midY)
            XCTAssertLessThanOrEqual(
                value, previous + 3,
                "剖面应在 \(dx)pt 处不回亮（前值 \(previous)、"
                    + "本值 \(value)）；剖面 \(profileText)"
            )
            previous = value
        }
        let edge = r(at: -2, y: midY)
        XCTAssertTrue(
            (223...235).contains(edge),
            "贴边 −2pt 应落 223–235；实测 \(edge)；剖面 \(profileText)"
        )
        XCTAssertGreaterThanOrEqual(
            r(at: 5, y: midY), 250,
            "内容侧 ＋5pt 应 ≥250；剖面 \(profileText)"
        )
        // 角区（y＝26、卡顶弧带内）：弧心在（接缝
        // ＋54.5, 56.5），该行卡边右移至接缝 ＋9.2
        // ——＋14 处应已是内容面（≥250；中部行卡边
        // 在接缝 0、两行卡边差即弧线跟随的证据）；
        // 弧外侧仍同向渐暗（靠弧边更暗）
        XCTAssertGreaterThanOrEqual(
            r(at: 14, y: 26), 250,
            "角区 ＋14pt 应为内容面 ≥250（弧跟随）；实测 "
                + "\(r(at: 14, y: 26))"
        )
        XCTAssertLessThan(
            r(at: -12, y: 26), r(at: -40, y: 26),
            "角区应同向渐暗（靠弧边更暗）：−12 处 "
                + "\(r(at: -12, y: 26))、−40 处 \(r(at: -40, y: 26))"
        )
    }

    /// §351 深色接缝三段台阶（像素验收）：深色开
    /// 态接缝应呈 Muse 量测的三段——抽屉面
    /// #000000 → 中间带 #191919（卡面横向内缩
    /// 16pt 露出前景底色、带全高恒定）→ 卡面
    /// #2C2C2E。装配同剖面替身口径（两侧不透明
    /// 色面：抽屉侧 chatSurface 深档 #000、内容
    /// 侧 bubbleFill 深档 #2C2C2E＝用户截图卡面
    /// 采样值）；外观走父级 setOverrideTrait-
    /// Collection（裸窗 overrideUserInterface-
    /// Style 不达根 trait，见 DrawerContainer-
    /// ControllerTests 同注）
    func testOpenDrawerDarkSeamThreeBands() throws {
        let controller = DrawerContainerController()
        controller.drawerBuilder = { _ in
            AnyView(Palette.chatSurface.ignoresSafeArea())
        }
        controller.contentRoot = AnyView(
            Palette.bubbleFill.ignoresSafeArea()
        )
        let parent = UIViewController()
        parent.view.frame = window.bounds
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.addChild(controller)
        parent.view.addSubview(controller.view)
        controller.view.frame = parent.view.bounds
        controller.didMove(toParent: parent)
        parent.setOverrideTraitCollection(
            UITraitCollection(userInterfaceStyle: .dark),
            forChild: controller)
        controller.setDrawer(true, animated: false)
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)

        let buffer = try XCTUnwrap(
            renderWindowBuffer(), "窗口渲染采样失败"
        )
        func r(at point: CGPoint) -> Int {
            let rows = [-6, 0, 6].map {
                sampleRed(
                    buffer,
                    at: CGPoint(x: point.x, y: point.y + CGFloat($0)))
            }.sorted()
            return rows[1]
        }
        let seam = controller.travel
        let midY: CGFloat = 437
        // 渲染自检：抽屉远区应 ≈0（出图链断裂时
        // 数字不作数）
        XCTAssertLessThanOrEqual(
            r(at: CGPoint(x: 100, y: midY)), 6,
            "渲染自检失败：深色抽屉远区应 ≈0，实测 "
                + "\(r(at: CGPoint(x: 100, y: midY)))")
        // 第一段：抽屉面（接缝 −40）≈#000000
        XCTAssertLessThanOrEqual(
            r(at: CGPoint(x: seam - 40, y: midY)), 6,
            "抽屉面应 ≈#000000，实测 "
                + "\(r(at: CGPoint(x: seam - 40, y: midY)))")
        // 第二段：中间带（接缝 +8、带心）落 25±6
        let band = r(at: CGPoint(x: seam + 8, y: midY))
        XCTAssertTrue(
            (19...31).contains(band),
            "中间带应落 #191919 带（19–31）；实测 \(band)")
        // 中间带全高：上/下两处同带
        for y: CGFloat in [200, 700] {
            let v = r(at: CGPoint(x: seam + 8, y: y))
            XCTAssertTrue(
                (19...31).contains(v),
                "中间带 y=\(Int(y)) 应同落 #191919 带；实测 \(v)")
        }
        // 第三段：卡面（接缝 +24、已过 16pt 带）
        // ≈#2C2C2E（44±6）
        let card = r(at: CGPoint(x: seam + 24, y: midY))
        XCTAssertTrue(
            (38...50).contains(card),
            "卡面应落 #2C2C2E 带（38–50）；实测 \(card)")
    }

    /// §318 材质定案量测：面板实色零透出（背后纯红
    /// 不得混入面板空区采样）
    func testDrawerPanelIsOpaqueSolidOverSaturatedBackdrop() throws {
        let host = UIHostingController(
            rootView: ZStack(alignment: .leading) {
                Color.red
                DrawerView(
                    width: 301.5,
                    currentTab: .chat,
                    onSelectTab: { _ in },
                    onClose: {},
                    onOpenChannel: { _ in }
                )
                .environment(appState)
                .environment(\.modelContext, container.mainContext)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .boldTextMapping()
            }
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.6)

        // 采样点：面板右下空区（空库名单无行、底条之
        // 上），x 290 在面板内（宽 301.5）、离右缘留
        // 量避开滚动指示器带
        let pixel = try XCTUnwrap(
            samplePixel(in: window, at: CGPoint(x: 290, y: 700)),
            "窗口渲染采样失败"
        )
        let spread = max(pixel.r, pixel.g, pixel.b)
            - min(pixel.r, pixel.g, pixel.b)
        let isLightSolid = abs(pixel.r - 252) <= 10
            && abs(pixel.g - 252) <= 10 && abs(pixel.b - 252) <= 10
        let isDarkSolid = pixel.r <= 10 && pixel.g <= 10 && pixel.b <= 10
        XCTAssertTrue(
            (isLightSolid || isDarkSolid) && spread <= 6,
            "面板空区采样应为 chatSurface 实色（浅 252 或深 0、通道差 ≤6）；"
                + "实测 RGB=(\(pixel.r),\(pixel.g),\(pixel.b))——"
                + "若呈粉灰（R 独大）即材质透出了背后纯红"
        )
    }

    /// 窗口渲染像素缓冲（一次渲染、多次采样，供
    /// 剖面横扫用）。出图走 layer.render：本套件的
    /// 容器装配（自定义容器控制器＋transform 位移
    /// 层）下 drawHierarchy 首跑曾整幅全 0（2026-
    /// 11-22 探针首轮实测），layer 树渲染与模型值
    /// 同步、阴影同在层树内成像
    private func renderWindowBuffer()
        -> (raw: [UInt8], width: Int, height: Int, scale: CGFloat)?
    {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &raw, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (raw, width, height, image.scale)
    }

    /// 缓冲单点 R 通道采样（越界回 255）
    private func sampleRed(
        _ buffer: (raw: [UInt8], width: Int, height: Int, scale: CGFloat),
        at point: CGPoint
    ) -> Int {
        let px = Int(point.x * buffer.scale)
        let py = Int(point.y * buffer.scale)
        guard px >= 0, px < buffer.width,
              py >= 0, py < buffer.height else { return 255 }
        return Int(buffer.raw[(py * buffer.width + px) * 4])
    }

    /// 窗口渲染单点采样（窗口点 → 图像像素按 scale
    /// 换算；行序按 CGImage 绘制惯例自顶向下）
    private func samplePixel(
        in window: UIWindow, at point: CGPoint
    ) -> (r: Int, g: Int, b: Int)? {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(
                in: window.bounds, afterScreenUpdates: true
            )
        }
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &raw, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let px = Int(point.x * image.scale)
        let py = Int(point.y * image.scale)
        guard px >= 0, px < width, py >= 0, py < height else {
            return nil
        }
        let offset = (py * width + px) * 4
        return (
            r: Int(raw[offset]), g: Int(raw[offset + 1]),
            b: Int(raw[offset + 2])
        )
    }
}
