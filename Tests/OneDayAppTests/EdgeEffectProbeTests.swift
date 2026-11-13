import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 边缘「蒙版」内容驱动探针＋回归断言（fix/edge-
/// effect-content-driven，2026-11-13）：用户 21:39
/// 验收口径——条下无内容时条区须与页面同色不可
/// 见、有内容滚过才朦胧。定因轮（run 43439787108，
/// §200 时代）实证：静止态色差顶带浅 4／深 39、舱
/// 带浅 14／深 19、坞带浅 4／深 19，来源＝§200 三
/// 处常驻材质底衬（消融后顶→1、坞→0；系统 .soft
/// 本体静止≈不可见、内容驱动成立）。本版为 §210
/// 修复后的回归形态：生产同构装配（落盘长会话
/// 160 条＋真 RootView 入场景窗），双态×双臂（生
/// 产／摘两注册的消融臂）×浅深两帧采样倾印 EDGE-
/// PROBE 行，并按口径数值断言——静止四点（状态栏
/// 带/顶簇间隙/舱带边缘/坞下沿）浅 ≤3–4、深 ≤8；
/// 滚动态顶簇间隙 ≤12、舱区须明显优于消融臂（基
/// 线消融同点 Δ95＝裸内容）。结构与绑定断言由
/// EdgeEffectRegistrationTests 承接。
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
        let topBar = topHost.traceBarView
        let composerBand = composerHost.traceBandView
        let topInteraction = topHost.traceEdgeInteraction
        let bandInteraction = (composerBand
            as? EdgeBandContainerView)?.traceInteraction
        // §210 端到端绑定证据：整页生产装配里两注册
        // 必须已对齐到本列表本体（锚点登记→宿主绑
        // 定的全链在此一并验）
        XCTAssertTrue(
            topInteraction.scrollView === scroll,
            "顶缘 interaction 未绑定到聊天列表"
        )
        XCTAssertTrue(
            bandInteraction?.scrollView === scroll,
            "舱带 interaction 未绑定到聊天列表"
        )
        print("EDGE-PROBE frames scroll="
            + "\(frameInWindow(scroll))"
            + " adjTop=\(scroll.adjustedContentInset.top)"
            + " adjBottom=\(scroll.adjustedContentInset.bottom)"
            + " contentH=\(scroll.contentSize.height)")
        print("EDGE-PROBE frames topBar="
            + "\(frameInWindow(topBar))")
        print("EDGE-PROBE frames composerBand="
            + "\(frameInWindow(composerBand))"
            + " composerHostView="
            + "\(frameInWindow(composerHost.traceComposerHostView))")
        print("EDGE-PROBE frames tabBar="
            + "\(frameInWindow(tabBar))")

        // 采样点（窗口坐标）：带内取「近平段中点」列，
        // 静止生产帧定列后全程复用（帧位在各臂/各态间
        // 不动，列可比）
        let topFrame = frameInWindow(topBar)
        let composerFrame = frameInWindow(composerBand)
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
            ("statusStrip", topGapX, 30),
            ("topBand", topGapX, topFrame.midY),
            ("belowTopBand", topGapX, topFrame.maxY + 10),
            ("composerMargin", 6, composerFrame.midY),
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

        @discardableResult
        func sampleAll(
            arm: String, state: String
        ) -> [String: Int] {
            guard let image = snapshot() else {
                print("EDGE-PROBE \(arm) \(state) SNAPSHOT-FAIL")
                return [:]
            }
            var line = "EDGE-PROBE arm=\(arm) state=\(state)"
                + " offset=\(Int(scroll.contentOffset.y))"
            var values: [String: (r: Int, g: Int, b: Int, a: Int)] = [:]
            for (name, x, y) in points {
                let p = image.pixel(x: x, y: y)
                values[name] = p
                line += " \(name)=\(fmt(p))"
            }
            var deltas: [String: Int] = [:]
            if let ref = values["pageRef"] {
                for name in [
                    "statusStrip", "topBand", "composerMargin",
                    "composerBand", "dockBelowCapsule",
                ] {
                    if let p = values[name] {
                        deltas[name] = delta(p, ref)
                    }
                }
                line += " deltaVsPage"
                    + " status=\(deltas["statusStrip"] ?? -1)"
                    + " top=\(deltas["topBand"] ?? -1)"
                    + " composerMargin="
                    + "\(deltas["composerMargin"] ?? -1)"
                    + " composer=\(deltas["composerBand"] ?? -1)"
                    + " dock=\(deltas["dockBelowCapsule"] ?? -1)"
            }
            print(line)
            return deltas
        }

        func gotoBottom() {
            // 落底落定：反复设偏移直到读数进 max 的
            // 2pt 内（定因轮 prod 臂 bottomRest 曾在顶
            // 位误采，本版显式落定再采）
            for _ in 0..<6 {
                setOffset(maxOffset)
                if maxOffset - scroll.contentOffset.y <= 2 {
                    break
                }
            }
        }

        var results: [String: [String: Int]] = [:]
        func record(_ arm: String, _ state: String) {
            results["\(arm)|\(state)"] = sampleAll(
                arm: arm, state: state
            )
        }

        // 浅色·生产臂：四态
        gotoBottom()
        record("prod", "bottomRest")
        setOffset(minOffset)
        record("prod", "topRest")
        setOffset(minOffset + 140)
        record("prod", "topUnder")
        gotoBottom()
        setOffset(maxOffset - 140)
        record("prod", "bottomUnder")

        // 浅色·消融臂（两注册摘除）：四态同序——顶簇
        // 与舱带退回无注册形态，内容滚过时以原锐度
        // 透出，与生产臂对照证注册在干活
        topBar.removeInteraction(topInteraction)
        if let bandInteraction {
            composerBand.removeInteraction(bandInteraction)
        }
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.5)
        gotoBottom()
        record("noBand", "bottomRest")
        setOffset(minOffset)
        record("noBand", "topRest")
        setOffset(minOffset + 140)
        record("noBand", "topUnder")
        gotoBottom()
        setOffset(maxOffset - 140)
        record("noBand", "bottomUnder")

        // 深色·生产臂：两静止态（注册先复位）
        topBar.addInteraction(topInteraction)
        if let bandInteraction {
            composerBand.addInteraction(bandInteraction)
        }
        window.overrideUserInterfaceStyle = .dark
        assembly.host.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        spinRunLoop(seconds: 0.8)
        window.layoutIfNeeded()
        gotoBottom()
        record("prodDark", "bottomRest")
        setOffset(minOffset)
        record("prodDark", "topRest")

        // MARK: 回归断言（用户 21:39 口径的数值化）

        func d(
            _ arm: String, _ state: String, _ point: String
        ) -> Int {
            results["\(arm)|\(state)"]?[point] ?? -1
        }
        // 静止态不可见·浅色：四点与页面色差小到不可辨
        for state in ["topRest", "bottomRest"] {
            XCTAssertLessThanOrEqual(
                d("prod", state, "statusStrip"), 3,
                "浅色 \(state) 状态栏带应与页面同色")
            XCTAssertLessThanOrEqual(
                d("prod", state, "topBand"), 3,
                "浅色 \(state) 顶簇间隙应与页面同色")
            XCTAssertLessThanOrEqual(
                d("prod", state, "composerMargin"), 4,
                "浅色 \(state) 舱带边缘应与页面同色")
            XCTAssertLessThanOrEqual(
                d("prod", state, "dockBelowCapsule"), 4,
                "浅色 \(state) 坞下沿应与页面同色")
        }
        // 静止态不可见·深色（§200 时代同点 39/19/19
        // ——本组即那组病的回归门）
        for state in ["topRest", "bottomRest"] {
            XCTAssertLessThanOrEqual(
                d("prodDark", state, "statusStrip"), 8,
                "深色 \(state) 状态栏带应近页面色")
            XCTAssertLessThanOrEqual(
                d("prodDark", state, "topBand"), 8,
                "深色 \(state) 顶簇间隙应近页面色")
            XCTAssertLessThanOrEqual(
                d("prodDark", state, "composerMargin"), 8,
                "深色 \(state) 舱带边缘应近页面色")
            XCTAssertLessThanOrEqual(
                d("prodDark", state, "dockBelowCapsule"), 8,
                "深色 \(state) 坞下沿应近页面色")
        }
        // 滚动态朦胧在：顶簇间隙不呈原锐度内容（被
        // 系统效果化开→近页面色）
        XCTAssertLessThanOrEqual(
            d("prod", "topUnder", "topBand"), 12,
            "滚动时顶簇间隙应被边缘效果化开")
        // 舱区：生产臂须被化开且明显优于消融臂（基
        // 线消融同点 Δ95＝裸内容透出）
        let prodCompUnder = d(
            "prod", "bottomUnder", "composerBand"
        )
        let bareCompUnder = d(
            "noBand", "bottomUnder", "composerBand"
        )
        XCTAssertLessThanOrEqual(
            prodCompUnder, 45,
            "滚动时舱后内容应被化开（生产 Δ=\(prodCompUnder)）")
        XCTAssertLessThan(
            prodCompUnder, bareCompUnder,
            "注册应优于无注册（生产 \(prodCompUnder)"
                + " vs 消融 \(bareCompUnder)）")
    }
}
