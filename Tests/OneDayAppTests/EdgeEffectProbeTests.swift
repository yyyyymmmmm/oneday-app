import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 边缘「蒙版」内容驱动定因探针（fix/edge-effect-
/// content-driven，2026-11-13）：用户 21:39 验收口
/// 径——条下无内容时条区须与页面同色不可见、有内
/// 容滚过才朦胧。本探针只取证、不断言像素：生产同
/// 构装配（落盘长会话 160 条＋真 RootView 入场景
/// 窗），双态（静止＝条下无内容／滚动＝有内容滚过
/// 条下）×双臂（生产原样／§200 三处材质底衬全隐的
/// 消融臂）×浅深两帧，对顶带、舱带、坞带与页面参
/// 考点做窗口级像素采样并倾印 EDGE-PROBE 行，供
/// 报告归因常驻可见来源（材质底衬／系统滚动边缘
/// 效果本体／页面与条背景错位）。归因后的回归断言
/// 由 EdgeEffectRegistrationTests 承接。
@MainActor
final class EdgeEffectProbeTests: XCTestCase {

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

    // MARK: - 装配（与 ChatPageDeviceConditionProbeTests 同式）

    private struct Assembly {
        var appState: AppState
        var container: ModelContainer
        var host: UIHostingController<AnyView>
    }

    private func seedLongThread(
        into container: ModelContainer, appState: AppState
    ) -> UUID {
        let context = ModelContext(container)
        let thread = ChatThread(title: "壁挂炉选型")
        context.insert(thread)
        let longParagraph = """
        但有一条必须盯死：最低输出功率。86 平米采暖只要 \
        7～9kW，如果你买的炉子最小火就是 7kW 甚至更高，它就会不停地 \
        开开关关，费气、有噪音、还伤机器。选最低输出 ≤4kW 的冷凝炉，\
        最好能到 3kW 出头，这样大部分时间它都稳在低火运行。\
        这一条比牌子重要。照单抓药，买的时候问商家这几项：\
        型式是燃气冷凝两用炉，采暖加生活热水一体。\
        额定 24kW，最低输出功率 ≤4kW。采暖水温能调到 \
        40～50°C（地暖专用低温档），最好支持室外温度补偿。
        """
        let base = Date().addingTimeInterval(-6 * 3600)
        for index in 0..<160 {
            let isUser = index % 2 == 0
            let entry = ChatEntry(
                role: isUser ? "user" : "assistant",
                content: isUser
                    ? "第 \(index / 2 + 1) 问：这个参数再确认一下。"
                    : longParagraph,
                thread: thread
            )
            entry.createdAt = base
                .addingTimeInterval(Double(index * 61))
            context.insert(entry)
        }
        thread.createdAt = base
        thread.updatedAt = base.addingTimeInterval(160 * 61)
        try? context.save()
        appState.sideChats.setLastThreadID(thread.id)
        return thread.id
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "edgeprobe-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let url = dir.appendingPathComponent("store.sqlite")
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, url: url
            )]
        )
    }

    private func assemble(
        appState: AppState, container: ModelContainer
    ) throws -> Assembly {
        let host = UIHostingController(
            rootView: AnyView(
                RootView()
                    .environment(appState)
                    .environment(\.locale, AppLocale.uiLocale)
                    .modelContainer(container)
            )
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first,
            "测试宿主无 UIWindowScene"
        )
        let win = UIWindow(windowScene: scene)
        win.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window = win
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 3.5)
        window.layoutIfNeeded()
        return Assembly(
            appState: appState, container: container, host: host
        )
    }

    // MARK: - 层级定位（同组装探针口径）

    private func frameInWindow(_ view: UIView) -> CGRect {
        view.convert(view.bounds, to: window)
    }

    private func findViews(
        _ root: UIView, where matches: (UIView) -> Bool
    ) -> [UIView] {
        var out: [UIView] = []
        if matches(root) { out.append(root) }
        for sub in root.subviews {
            out += findViews(sub, where: matches)
        }
        return out
    }

    private func findVC<T: UIViewController>(
        _ type: T.Type
    ) -> T? {
        var found: T?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? T { found = hit }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    private func chatScrollView() -> UIScrollView? {
        findViews(window) { view in
            view is UIScrollView
                && String(describing: type(of: view))
                    .contains("HostingScrollView")
                && frameInWindow(view).width > 400
        }.first as? UIScrollView
    }

    // MARK: - 像素采样

    /// 窗口位图：UIGraphics 绘制约定翻转后缓冲首行＝
    /// 图像顶行，采样坐标即窗口点坐标（乘 scale）
    private struct PixelImage {
        let width: Int
        let height: Int
        let scale: CGFloat
        private let bytes: [UInt8]
        private let bytesPerRow: Int

        init?(_ image: UIImage) {
            guard let cg = image.cgImage else { return nil }
            width = cg.width
            height = cg.height
            scale = image.scale
            bytesPerRow = width * 4
            var buffer = [UInt8](
                repeating: 0, count: bytesPerRow * height
            )
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: &buffer, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo
                    .premultipliedLast.rawValue
            ) else { return nil }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(
                cg, in: CGRect(
                    x: 0, y: 0, width: width, height: height
                )
            )
            bytes = buffer
        }

        func pixel(
            x: CGFloat, y: CGFloat
        ) -> (r: Int, g: Int, b: Int, a: Int) {
            let px = min(max(Int(x * scale), 0), width - 1)
            let py = min(max(Int(y * scale), 0), height - 1)
            let i = py * bytesPerRow + px * 4
            return (
                Int(bytes[i]), Int(bytes[i + 1]),
                Int(bytes[i + 2]), Int(bytes[i + 3])
            )
        }

        /// 某一行里最长的「近平」连续段中点（相邻采样
        /// 点逐通道差 ≤3 视为平）——条带覆平背景的区
        /// 段即此形态，控件/文字会打断它；供定位无控
        /// 件的采样列
        func flatRunCenterX(
            y: CGFloat, minRunPoints: CGFloat
        ) -> CGFloat? {
            var bestStart: CGFloat = 0
            var bestLength: CGFloat = 0
            var runStart: CGFloat = 2
            var previous = pixel(x: 2, y: y)
            var x: CGFloat = 3
            let limit: CGFloat = 402 - 2
            while x <= limit {
                let current = pixel(x: x, y: y)
                let flat = abs(current.r - previous.r) <= 3
                    && abs(current.g - previous.g) <= 3
                    && abs(current.b - previous.b) <= 3
                if !flat {
                    let length = x - runStart
                    if length > bestLength {
                        bestLength = length
                        bestStart = runStart
                    }
                    runStart = x
                }
                previous = current
                x += 1
            }
            let length = limit - runStart
            if length > bestLength {
                bestLength = length
                bestStart = runStart
            }
            guard bestLength >= minRunPoints else { return nil }
            return bestStart + bestLength / 2
        }
    }

    private func snapshot() -> PixelImage? {
        let renderer = UIGraphicsImageRenderer(
            bounds: window.bounds
        )
        let image = renderer.image { _ in
            window.drawHierarchy(
                in: window.bounds, afterScreenUpdates: true
            )
        }
        return PixelImage(image)
    }

    private func fmt(
        _ p: (r: Int, g: Int, b: Int, a: Int)
    ) -> String {
        "rgba(\(p.r),\(p.g),\(p.b),\(p.a))"
    }

    private func delta(
        _ p: (r: Int, g: Int, b: Int, a: Int),
        _ q: (r: Int, g: Int, b: Int, a: Int)
    ) -> Int {
        max(
            abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b)
        )
    }

    // MARK: - 定因主探针

    func testEdgeEffectAttributionProbe() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        _ = seedLongThread(into: container, appState: appState)
        let assembly = try assemble(
            appState: appState, container: container
        )
        _ = assembly

        let scroll = try XCTUnwrap(
            chatScrollView(), "聊天列表 HostingScrollView 缺席"
        )
        let topHost = try XCTUnwrap(
            findVC(TopBarGuideHostController.self), "顶簇宿主缺席"
        )
        let composerHost = try XCTUnwrap(
            findVC(ComposerGuideHostController.self), "舱宿主缺席"
        )
        let tabBar = try XCTUnwrap(
            findViews(window) { $0 is UITabBar }.first,
            "UITabBar 缺席"
        )
        let topBackdrop = topHost.traceBackdropView
        let composerBackdrop = composerHost.traceBackdropView
        let dockBackdrops = tabBar.subviews.filter {
            $0 is SystemDockBackdropView
        }
        print("EDGE-PROBE frames scroll="
            + "\(frameInWindow(scroll))"
            + " adjTop=\(scroll.adjustedContentInset.top)"
            + " adjBottom=\(scroll.adjustedContentInset.bottom)"
            + " contentH=\(scroll.contentSize.height)")
        print("EDGE-PROBE frames topBackdrop="
            + "\(frameInWindow(topBackdrop))"
            + " topBar=\(frameInWindow(topHost.traceBarView))")
        print("EDGE-PROBE frames composerBackdrop="
            + "\(frameInWindow(composerBackdrop))"
            + " composerHostView="
            + "\(frameInWindow(composerHost.traceComposerHostView))")
        print("EDGE-PROBE frames tabBar="
            + "\(frameInWindow(tabBar))"
            + " dockBackdrops=\(dockBackdrops.count)")
        XCTAssertFalse(dockBackdrops.isEmpty, "坞底衬缺席")

        // 采样点（窗口坐标）：带内取「近平段中点」列，
        // 静止生产帧定列后全程复用（帧位在各臂/各态间
        // 不动，列可比）
        let topFrame = frameInWindow(topBackdrop)
        let composerFrame = frameInWindow(composerBackdrop)
        let tabFrame = frameInWindow(tabBar)
        let baseImage = try XCTUnwrap(
            snapshot(), "基线快照失败"
        )
        // 朝向校准行：y=25 应见灵动岛黑段、y=867 应见
        // Home 指示条暗段——两行 R 值倾印供报告核对
        // 采样朝向/scale 映射是否成立
        var scanTop = ""
        var scanBottom = ""
        for x in stride(from: 6, through: 396, by: 15) {
            scanTop += "\(baseImage.pixel(x: CGFloat(x), y: 25).r) "
            scanBottom += "\(baseImage.pixel(x: CGFloat(x), y: 867).r) "
        }
        print("EDGE-PROBE calib rowY25 R: \(scanTop)")
        print("EDGE-PROBE calib rowY867 R: \(scanBottom)")

        let topGapX = baseImage.flatRunCenterX(
            y: topFrame.midY, minRunPoints: 24
        ) ?? 200
        let composerGapX = baseImage.flatRunCenterX(
            y: composerFrame.midY, minRunPoints: 5
        ) ?? 7
        let points: [(String, CGFloat, CGFloat)] = [
            ("pageRef", 4, 500),
            ("topBand", topGapX, topFrame.midY),
            ("belowTopBand", topGapX, topFrame.maxY + 10),
            ("composerBand", composerGapX, composerFrame.midY),
            ("dockBelowCapsule", 201, tabFrame.maxY - 5),
        ]
        print("EDGE-PROBE points topGapX=\(topGapX)"
            + " composerGapX=\(composerGapX)"
            + " topMidY=\(topFrame.midY)"
            + " composerMidY=\(composerFrame.midY)")

        let minOffset = -scroll.adjustedContentInset.top
        let maxOffset = max(
            minOffset,
            scroll.contentSize.height - scroll.bounds.height
                + scroll.adjustedContentInset.bottom
        )
        print("EDGE-PROBE offsets initial="
            + "\(scroll.contentOffset.y) min=\(minOffset)"
            + " max=\(maxOffset)")

        func setOffset(_ y: CGFloat) {
            scroll.setContentOffset(
                CGPoint(x: 0, y: y), animated: false
            )
            window.layoutIfNeeded()
            spinRunLoop(seconds: 0.8)
            window.layoutIfNeeded()
        }

        func sampleAll(arm: String, state: String) {
            guard let image = snapshot() else {
                print("EDGE-PROBE \(arm) \(state) SNAPSHOT-FAIL")
                return
            }
            var line = "EDGE-PROBE arm=\(arm) state=\(state)"
                + " offset=\(Int(scroll.contentOffset.y))"
            var values: [String: (r: Int, g: Int, b: Int, a: Int)] = [:]
            for (name, x, y) in points {
                let p = image.pixel(x: x, y: y)
                values[name] = p
                line += " \(name)=\(fmt(p))"
            }
            if let ref = values["pageRef"] {
                let dTop = values["topBand"].map {
                    delta($0, ref)
                } ?? -1
                let dComp = values["composerBand"].map {
                    delta($0, ref)
                } ?? -1
                let dDock = values["dockBelowCapsule"].map {
                    delta($0, ref)
                } ?? -1
                line += " deltaVsPage top=\(dTop)"
                    + " composer=\(dComp) dock=\(dDock)"
            }
            print(line)
        }

        // 浅色·生产臂：四态
        sampleAll(arm: "prod", state: "bottomRest")
        setOffset(minOffset)
        sampleAll(arm: "prod", state: "topRest")
        setOffset(minOffset + 140)
        sampleAll(arm: "prod", state: "topUnder")
        setOffset(maxOffset)
        setOffset(maxOffset - 140)
        sampleAll(arm: "prod", state: "bottomUnder")
        setOffset(maxOffset)

        // 浅色·消融臂（§200 三处底衬全隐）：四态同序
        topBackdrop.isHidden = true
        composerBackdrop.isHidden = true
        dockBackdrops.forEach { $0.isHidden = true }
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.5)
        sampleAll(arm: "noBackdrop", state: "bottomRest")
        setOffset(minOffset)
        sampleAll(arm: "noBackdrop", state: "topRest")
        setOffset(minOffset + 140)
        sampleAll(arm: "noBackdrop", state: "topUnder")
        setOffset(maxOffset)
        setOffset(maxOffset - 140)
        sampleAll(arm: "noBackdrop", state: "bottomUnder")
        setOffset(maxOffset)

        // 深色·生产臂：两静止态
        topBackdrop.isHidden = false
        composerBackdrop.isHidden = false
        dockBackdrops.forEach { $0.isHidden = false }
        window.overrideUserInterfaceStyle = .dark
        assembly.host.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.8)
        window.layoutIfNeeded()
        sampleAll(arm: "prodDark", state: "bottomRest")
        setOffset(minOffset)
        sampleAll(arm: "prodDark", state: "topRest")
    }
}
