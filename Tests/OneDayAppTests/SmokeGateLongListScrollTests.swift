import Foundation
import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import OneDayApp

/// 冒烟门·长会话内容侧（横扫 A-1/A-4 同类：CI 恒走
/// 演示种子短会话、长列表是生产真形态的系统性漏网）。
/// 2026-11-23 按现行面重写（DESIGN §401）：承载已换
/// ChatNativeList（UICollectionView＋DiffableData-
/// Source＋增量喂入，§374），旧例的 SwiftUI 几何回
/// 读（滚动锚点＋气泡内滚文本桥＋AX 三通道）随承载
/// 整件退役；本例改在 UIKit 层取真值——contentOffset
/// 双向实测＋序号映射（按 collection 结构累加，与
/// section 构造开关无关）＋首/末可见 cell 帧相交。
///
/// 严格断言（两件套）：
/// 1. 偏移双向：显式滚底后 offset≈当刻 max（容差
///    2pt）；滚顶后 offset≈-inset.top（容差 2pt）。
/// 2. 序号两端：顶时最小可见序号==0、底时最大可见
///    序号==totalRows-1；且首/末序号 cell 帧与列表
///    可见框真相交（不靠「文本必在树里」这类懒生成
///    口径——托管 cell 文本通道无保证，正文普查只打
///    印作证据）。
/// 旧例的 inset 台阶轮询与回底箭头 AX 激活保留为
/// **登记哨**（只打印）：台阶断言已于第十轮定因退
/// 役（定案 smoke-feed-link-diagnosis-20261115.md
/// §五：装配差异、产品喂入环无罪），箭头端到端由
/// UITests 的 testSmokeBackToBottomArrowEndToEnd
/// 真手势覆盖；登记值逐轮累积供主线复核，不许复活
/// 为断言粉饰、也不许删除留痕。
@MainActor
final class SmokeGateLongListScrollTests: XCTestCase {

    private final class SmokeWindow: UIWindow {
        var hostingController: UIHostingController<AnyView>?

        override func layoutSubviews() {
            super.layoutSubviews()
            if let hostingController {
                hostingController.view.frame = bounds
            }
        }
    }

    private var window: SmokeWindow?
    private var swiftDataMount = SwiftDataTestMount()

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// 自旋主 runloop 等条件（异步装配/布局需真帧推进）
    private func spin(
        until condition: () -> Bool, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(
                mode: .default,
                before: Date().addingTimeInterval(0.05)
            )
        }
        return condition()
    }

    /// 找正文列表：挂窗视图层级里 contentSize 最高的
    /// UICollectionView（抽屉/输入区无此量级）
    private func findList() -> UICollectionView? {
        guard let root = window?.rootViewController?.view else {
            return nil
        }
        var best: UICollectionView?
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            if let cv = view as? UICollectionView {
                if best == nil
                    || cv.contentSize.height
                        > (best?.contentSize.height ?? 0)
                {
                    best = cv
                }
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }

    /// 序号映射（构造无关）：序号＝前序 section 的
    /// item 数累加＋本 section 内 item
    private func ordinal(
        of indexPath: IndexPath, in cv: UICollectionView
    ) -> Int {
        var sum = indexPath.item
        for section in 0..<indexPath.section {
            sum += cv.numberOfItems(inSection: section)
        }
        return sum
    }

    private func totalRows(in cv: UICollectionView) -> Int {
        (0..<cv.numberOfSections).reduce(0) {
            $0 + cv.numberOfItems(inSection: $1)
        }
    }

    private func indexPath(
        forOrdinal target: Int, in cv: UICollectionView
    ) -> IndexPath? {
        var rest = target
        for section in 0..<cv.numberOfSections {
            let count = cv.numberOfItems(inSection: section)
            if rest < count {
                return IndexPath(item: rest, section: section)
            }
            rest -= count
        }
        return nil
    }

    private func visibleOrdinals(
        in cv: UICollectionView
    ) -> [Int] {
        cv.indexPathsForVisibleItems
            .map { ordinal(of: $0, in: cv) }
            .sorted()
    }

    /// cell 帧（窗坐标）与列表可见框（窗坐标）相交
    private func cellFrameIntersectsList(
        _ cv: UICollectionView, ordinal target: Int
    ) -> Bool {
        guard let ip = indexPath(forOrdinal: target, in: cv),
            let cell = cv.cellForItem(at: ip)
        else { return false }
        let cellFrame = cell.convert(cell.bounds, to: nil)
        let listFrame = cv.convert(cv.bounds, to: nil)
        return cellFrame.intersects(listFrame)
    }

    /// 动态滚底：增量喂入下 maxOffset 随 materialize
    /// 增长，循环重算目标直至 offset 贴住当刻 max
    private func settleAtBottom(
        _ cv: UICollectionView, timeout: TimeInterval = 8
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let maxOffset = max(
                -cv.adjustedContentInset.top,
                cv.contentSize.height + cv.adjustedContentInset.bottom
                    - cv.bounds.height
            )
            cv.setContentOffset(
                CGPoint(x: 0, y: maxOffset), animated: false
            )
            cv.layoutIfNeeded()
            let nowMax = max(
                -cv.adjustedContentInset.top,
                cv.contentSize.height + cv.adjustedContentInset.bottom
                    - cv.bounds.height
            )
            if abs(cv.contentOffset.y - nowMax) <= 2 {
                return true
            }
            RunLoop.main.run(
                mode: .default,
                before: Date().addingTimeInterval(0.05)
            )
        }
        return false
    }

    private func waitForOffset(
        _ cv: UICollectionView, target: CGFloat,
        timeout: TimeInterval = 6
    ) -> Bool {
        spin(until: {
            abs(cv.contentOffset.y - target) <= 2
        }, timeout: timeout)
    }

    func testLongConversationScrollToBottomLandsWithTailVisible()
        throws
    {
        let schema = Schema(versionedSchema: CurrentChatSchema.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        swiftDataMount.retain(container)
        let context = ModelContext(container)
        let thread = ChatThread(title: "冒烟长会话")
        context.insert(thread)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<120 {
            let entry = ChatEntry(
                role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: String(
                    format: "冒烟长会话行 %03d", index
                ),
                thread: thread
            )
            entry.createdAt = base.addingTimeInterval(
                TimeInterval(index)
            )
            context.insert(entry)
            thread.entries.append(entry)
        }
        try context.save()

        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        appState.sessionLedger.designateMainThread(thread.id)

        let hosting = UIHostingController(
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
            "测试宿主应有窗口场景"
        )
        let win = SmokeWindow(windowScene: scene)
        win.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        win.rootViewController = hosting
        win.hostingController = hosting
        hosting.view.frame = win.bounds
        win.addSubview(hosting.view)
        win.makeKeyAndVisible()
        window = win

        XCTAssertTrue(
            spin(until: { self.findList() != nil }, timeout: 10),
            "聊天列表（UICollectionView）应装配进层级"
        )
        let list = try XCTUnwrap(findList())
        XCTAssertTrue(
            spin(until: {
                list.contentSize.height > list.bounds.height * 3
            }, timeout: 10),
            "120 条长会话内容高应数倍于视口（实得 "
                + "\(list.contentSize.height)/\(list.bounds.height)）"
        )
        let total = totalRows(in: list)
        print(
            "LONGLIST rows=\(total) contentH="
                + "\(list.contentSize.height) boundsH="
                + "\(list.bounds.height)"
        )
        XCTAssertGreaterThanOrEqual(
            total, 120, "列表行数应覆盖 120 条 fixture"
        )

        // 1) 显式滚底：offset 贴当刻 max＋末序号可见
        XCTAssertTrue(
            settleAtBottom(list),
            "滚底后 offset 应贴住当刻 maxOffset（实得 "
                + "\(list.contentOffset.y)）"
        )
        let bottomVisible = visibleOrdinals(in: list)
        print(
            "LONGLIST bottom offset=\(list.contentOffset.y) "
                + "visible=\(bottomVisible.first ?? -1).."
                + "\(bottomVisible.last ?? -1)"
        )
        XCTAssertEqual(
            bottomVisible.last, total - 1,
            "底时最大可见序号应为末行"
        )
        XCTAssertTrue(
            cellFrameIntersectsList(list, ordinal: total - 1),
            "末行 cell 帧应与列表可见框相交"
        )

        // 登记哨（只打印）：底 inset 基线——旧例台阶
        // 断言退役口径见文件头；逐轮留痕供主线复核
        var inset = list.adjustedContentInset.bottom
        let insetDeadline = Date().addingTimeInterval(1)
        while Date() < insetDeadline {
            RunLoop.main.run(
                mode: .default,
                before: Date().addingTimeInterval(0.1)
            )
            inset = list.adjustedContentInset.bottom
        }
        print("LONGLIST bottomInset baseline=\(inset)")

        // 2) 滚顶：offset 贴 -inset.top＋首序号可见
        let topTarget = -list.adjustedContentInset.top
        list.setContentOffset(
            CGPoint(x: 0, y: topTarget), animated: false
        )
        list.layoutIfNeeded()
        XCTAssertTrue(
            waitForOffset(list, target: topTarget),
            "滚顶后 offset 应贴住 -inset.top（实得 "
                + "\(list.contentOffset.y) vs \(topTarget)）"
        )
        let topVisible = visibleOrdinals(in: list)
        print(
            "LONGLIST top offset=\(list.contentOffset.y) "
                + "visible=\(topVisible.first ?? -1).."
                + "\(topVisible.last ?? -1)"
        )
        XCTAssertEqual(
            topVisible.first, 0, "顶时最小可见序号应为首行"
        )
        XCTAssertTrue(
            cellFrameIntersectsList(list, ordinal: 0),
            "首行 cell 帧应与列表可见框相交"
        )

        // 正文普查（只打印作证据）：可见 cell 子树里
        // 的文本通道——托管 cell 无保证，不作断言
        var census: [String] = []
        for cell in list.visibleCells {
            var stack: [UIView] = [cell]
            while let view = stack.popLast() {
                if let label = view as? UILabel,
                    let text = label.text, !text.isEmpty
                {
                    census.append(text)
                }
                stack.append(contentsOf: view.subviews)
            }
        }
        print(
            "LONGLIST census count=\(census.count) "
                + "head=\(census.first ?? "-") "
                + "tail=\(census.last ?? "-")"
        )

        // 登记哨（只打印）：inset 台阶 6 秒轮询——旧
        // 例断言退役口径见文件头；箭头 AX 激活同理只
        // 观察在场与否（端到端由 UITests 真手势例担）
        let stepDeadline = Date().addingTimeInterval(6)
        var step = 0
        while Date() < stepDeadline {
            RunLoop.main.run(
                mode: .default,
                before: Date().addingTimeInterval(0.5)
            )
            step += 1
            print(
                "LONGLIST insetStep \(step) bottom="
                    + "\(list.adjustedContentInset.bottom)"
            )
        }

        // 3) 回底复断：两件套再走一遍（滚动态稳定）
        XCTAssertTrue(
            settleAtBottom(list),
            "回底后 offset 应再次贴住 maxOffset"
        )
        XCTAssertEqual(
            visibleOrdinals(in: list).last, total - 1,
            "回底后最大可见序号应为末行"
        )
        XCTAssertTrue(
            cellFrameIntersectsList(list, ordinal: total - 1),
            "回底后末行 cell 帧应与列表可见框相交"
        )
        print(
            "LONGLIST tail offset=\(list.contentOffset.y) "
                + "contentH=\(list.contentSize.height)"
        )
    }
}
