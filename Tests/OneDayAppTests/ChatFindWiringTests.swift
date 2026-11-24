import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §503（对话内查找全件修复）装配钉：会话状态机
/// 的落点目标被原生面收敛落点真消费（治 D9「触
/// 发器只写不读」）、着色施加真落到呈现串属性上。
/// 判定本身（命中/起点/环绕）在 Core ChatFind-
/// Tests；落点机装配与 ChatSearchFocusAssembly-
/// Tests 同台
@MainActor
final class ChatFindWiringTests: XCTestCase {
    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!
    private var ids: [UUID] = []

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        let root = UIViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        // 0.51.0 修复轮（C 簇根因）：本台按逐行 sec-
        // tion 构造拼索引路径，而单 section 旗缺省为
        // 开（ChatListSingleSectionFeature）——擦除后
        // 的模拟器无存量键即走单 section、本台查询全
        // 落空。经产品测试覆盖口钉死逐行构造（与
        // ChatSwapStep3 两套同式）；落点消费行为与构
        // 造无关、照旧全验
        list.testSingleSectionOverride = false
        list.handle = listHandle
        list.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        listHandle.controller = list
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        window = win
        controller = list
        handle = listHandle
    }

    private func apply(_ rows: [ChatNativeRow]) {
        controller?.apply(
            rows: rows,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: 8,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: 54)
            ),
            arrowView: AnyView(Color.clear)
        )
        window?.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(description: "drain \(seconds)")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    private func makeRows(count: Int) -> [ChatNativeRow] {
        if ids.count != count {
            ids = (0..<count).map { _ in UUID() }
        }
        return (0..<count).map { index in
            ChatNativeRow(
                key: "r\(index)", entryID: ids[index],
                revision: ChatNativeRowRevision(
                    parts: [.text("row \(index)")]
                ),
                height: 60,
                makeView: {
                    AnyView(
                        Text("row")
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    )
                }
            )
        }
    }

    /// 目标行屏上位置（行顶距视口顶）
    private func shownPosition(of index: Int) -> CGFloat? {
        let cv = controller.collectionView
        guard let attrs = cv.layoutAttributesForItem(
            at: IndexPath(item: 0, section: index)
        ) else { return nil }
        return attrs.frame.minY - cv.contentOffset.y
    }

    /// 让目标行进入布局备出区：合成布局只为视口附
    /// 近行备布局属性，远行在 focusEntry 读属性前先
    /// 驱视口到目标区（与 ChatSearchFocusAssembly-
    /// Tests 手动 setContentOffset 同式装配前提）——
    /// 落点本身仍由产品收敛环施工、断言照旧量产品
    /// 落点；不先备出，收敛环首拍读不到属性即弃权
    private func materialize(_ index: Int) {
        controller.collectionView.scrollToItem(
            at: IndexPath(item: 0, section: index),
            at: .centeredVertically, animated: false
        )
        window?.layoutIfNeeded()
    }

    /// 目标行屏上位置（等布局物化＋落稳版）：固定
    /// drain 赌布局物化在 27.2 运行时下不再成立
    /// （0.51.0 修复轮判读 C 簇）——poll-until 非 nil
    /// 且连续两读同值（收敛环落稳），未物化时顺手
    /// 再驱视口；超时返回最后一读／nil、由调用方
    /// 照常判
    private func polledShownPosition(
        of index: Int, timeout: TimeInterval = 10
    ) -> CGFloat? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGFloat?
        while true {
            if let shown = shownPosition(of: index) {
                if let last, abs(last - shown) < 0.5 {
                    return shown
                }
                last = shown
            } else if Date() < deadline {
                materialize(index)
            }
            if Date() >= deadline { return last }
            drain(0.3)
        }
    }

    /// 期望落点：顶内边距＋topGap
    private var expectedLanding: CGFloat {
        controller.collectionView.contentInset.top
            + SearchFocusConvergence.topGap
    }

    // MARK: - 触发被消费＋点亮赋值源

    /// 重算落座返回的目标（＝点亮 findHighlight-
    /// EntryID 的赋值源、currentMatchID 同值）以
    /// applyFindTarget 的同一调用喂消费端——目标
    /// 行真停到顶留位：触发被消费、非只写不读
    func testSessionStartTargetIsConsumedByFocus() throws {
        assemble()
        apply(makeRows(count: 40))
        drain(1.2)
        var session = ChatFindSession()
        let target = session.recompute(
            matches: [ids[3], ids[10], ids[20]], startIndex: 1
        )
        XCTAssertEqual(target, ids[10])
        XCTAssertEqual(session.currentMatchID, target)
        materialize(10)
        handle.focusEntry(try XCTUnwrap(target))
        drain(1.0)
        let shown = try XCTUnwrap(polledShownPosition(of: 10))
        XCTAssertEqual(
            shown, expectedLanding, accuracy: 2,
            "查找落点须停在顶留位，实测 \(shown) 期望 \(expectedLanding)"
        )
    }

    /// 翻页返回的下一目标同样被消费（环绕到首条
    /// 后落点跟随）
    func testSessionNextTargetIsConsumedByFocus() throws {
        assemble()
        apply(makeRows(count: 40))
        drain(1.2)
        var session = ChatFindSession()
        _ = session.recompute(
            matches: [ids[5], ids[25]], startIndex: 0
        )
        let next = try XCTUnwrap(session.moveNext())
        XCTAssertEqual(next, ids[25])
        materialize(25)
        handle.focusEntry(next)
        drain(1.0)
        let shown = try XCTUnwrap(polledShownPosition(of: 25))
        XCTAssertEqual(
            shown, expectedLanding, accuracy: 2,
            "翻页落点须停在顶留位，实测 \(shown) 期望 \(expectedLanding)"
        )
        // 环绕回首条
        let wrapped = try XCTUnwrap(session.moveNext())
        XCTAssertEqual(wrapped, ids[5])
        materialize(5)
        handle.focusEntry(wrapped)
        drain(1.0)
        let shownBack = try XCTUnwrap(polledShownPosition(of: 5))
        XCTAssertEqual(
            shownBack, expectedLanding, accuracy: 2,
            "环绕落点须停在顶留位，实测 \(shownBack) 期望 \(expectedLanding)"
        )
    }

    // MARK: - 着色施加

    /// 呈现串副本上全部命中区间真带背景色、区间
    /// 外无背景；入参本体不被改写（缓存实例安全）
    func testFindHighlightAppliesBackgroundToOccurrences() {
        let base = NSAttributedString(
            string: "Foo bar FOO baz",
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        let colored = SelectableInlineText.applyingFindHighlight(
            to: base, query: "foo", color: .systemYellow
        )
        XCTAssertFalse(colored === base)
        var backgrounds: [NSRange] = []
        colored.enumerateAttribute(
            .backgroundColor, in: NSRange(
                location: 0, length: colored.length
            )
        ) { value, range, _ in
            if value != nil { backgrounds.append(range) }
        }
        XCTAssertEqual(
            backgrounds.map { [$0.location, $0.length] },
            [[0, 3], [8, 3]]
        )
        // 本体无背景属性（着色只落副本）
        var baseHasBackground = false
        base.enumerateAttribute(
            .backgroundColor, in: NSRange(
                location: 0, length: base.length
            )
        ) { value, _, _ in
            if value != nil { baseHasBackground = true }
        }
        XCTAssertFalse(baseHasBackground)
    }

    /// 无命中/空查询 → 原串同一实例返回（不触发
    /// updateUIView 的无谓重设）
    func testFindHighlightWithoutMatchReturnsOriginal() {
        let base = NSAttributedString(string: "plain text")
        XCTAssertTrue(
            SelectableInlineText.applyingFindHighlight(
                to: base, query: "zzz", color: .systemYellow
            ) === base
        )
        XCTAssertTrue(
            SelectableInlineText.applyingFindHighlight(
                to: base, query: "  ", color: .systemYellow
            ) === base
        )
    }
}
