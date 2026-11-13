import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §198 包 0 · 选字链末环计数证死装置（一层审计
/// chat-page-bigfactory-audit-20261113.md §1.2）
///
/// 定因链前四环均有代码/框架语义出处，末环「选区
/// 变化→@State 写→SwipeReplyModifier 的 if/else 结
/// 构分支切换→承载 UITextView 被 dismantle→选区当
/// 场死」只有框架语义、未在运行时打点。本装置把生
/// 产原物（SelectableInlineText＋SwipeReplyModifier）
/// 按 ChatView 的真实接线装配成一行：选区回报走
/// noteTextSelection 的置位路径（在场→本行 id 入账
/// →swipeReply(for:) 的 isEnabled 翻假），程序化建
/// 立选区后普查承载文本视图的实例集合——实例被换
/// ＝make/dismantle 发生过（新实例选区必为空），实
/// 例不变且选区存活＝末环不成立。
///
/// 对照臂：isEnabled 恒真（分支不翻转），同法建立
/// 选区应全程存活——隔离「状态写本身」与「分支翻
/// 转」两个变量，防把回调链自身的扰动误记到分支头
/// 上。
///
/// 接线简化一处（如实记账）：生产 noteTextSelection
/// 的清账走 350ms 延迟，本装置对 active=false 只记
/// 账、不驱动状态——清账影响的是第二拍翻转，与第
/// 一拍「置位→翻转→拆承载」的待证命题无关。
///
/// 二轮加固（一轮 CI run 43366577019 教训）：一轮
/// 两臂均在首断言红——装配期代表物先回报一笔
/// hasSelection=false（选区未建时的初始回调），
/// 「首事件必真」断言口径错误；且主臂普查断言虽全
/// 过，无法区分「翻转已渲染而承载未拆」与「翻转根
/// 本没渲染到修饰符」两种读法。二轮改：前置断言改
/// 为事件流含 true；Harness 每次 body 求值把实际
/// 喂给修饰符的 isEnabled 记进 branchEvals（去重连
/// 续同值），主臂另断言翻转确已渲染（出现 false
/// 求值）——三读数齐备才许下证死/证伪结论。
@MainActor
final class SelectionDismantleProofTests: XCTestCase {

    private final class EventLog {
        var selectionEvents: [Bool] = []
        var branchEvals: [Bool] = []
    }

    private struct Harness: View {
        let entryID: UUID
        let log: EventLog
        let branchFollowsSelection: Bool
        @State private var activeSelectionEntryID: UUID?

        var body: some View {
            let enabled = branchFollowsSelection
                ? activeSelectionEntryID != entryID
                : true
            // 翻转渲染探针：修饰符每次实际收到的
            // isEnabled（同值连记只记一笔）
            if log.branchEvals.last != enabled {
                log.branchEvals.append(enabled)
            }
            return SelectableInlineText(
                paragraphs: [
                    .plain("alpha bravo charlie delta echo foxtrot")
                ],
                onSelectionChange: { active in
                    log.selectionEvents.append(active)
                    if branchFollowsSelection, active {
                        activeSelectionEntryID = entryID
                    }
                }
            )
            .modifier(
                SwipeReplyModifier(
                    isEnabled: enabled,
                    onReply: {}
                )
            )
            .frame(width: 320, alignment: .leading)
            .padding()
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

    private func assemble(branchFollowsSelection: Bool) -> EventLog {
        let log = EventLog()
        let host = UIHostingController(
            rootView: Harness(
                entryID: UUID(),
                log: log,
                branchFollowsSelection: branchFollowsSelection
            )
        )
        window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        spinRunLoop(seconds: 1.0)
        window.layoutIfNeeded()
        return log
    }

    private func textViews() -> [UITextView] {
        var out: [UITextView] = []
        func walk(_ view: UIView) {
            if let textView = view as? UITextView {
                out.append(textView)
            }
            for sub in view.subviews { walk(sub) }
        }
        if let root = window.rootViewController?.view {
            walk(root)
        }
        return out
    }

    /// 建立选区后 1.2s 内逐 50ms 普查：收集出现过的
    /// 全部文本视图实例（去重）并返回当前在树实例
    private func censusAfterSelection(
        on textView: UITextView
    ) -> (seen: Set<ObjectIdentifier>, live: UITextView?) {
        textView.selectedRange = NSRange(location: 0, length: 5)
        var seen = Set<ObjectIdentifier>()
        for _ in 0..<24 {
            spinRunLoop(seconds: 0.05)
            window.layoutIfNeeded()
            for view in textViews() {
                seen.insert(ObjectIdentifier(view))
            }
        }
        return (seen, textViews().first)
    }

    /// 主臂：接线与生产逐字同构（选区置位翻转本行
    /// 右滑开关）。末环若成立，承载视图必被拆换、
    /// 新视图选区为空——两条断言在修复前应双双红，
    /// 修复后双双绿
    func testSelectionSurvivesProductionWiring() throws {
        let log = assemble(branchFollowsSelection: true)
        let initial = textViews()
        XCTAssertEqual(
            initial.count, 1, "装配应恰有一台承载文本视图"
        )
        let first = try XCTUnwrap(initial.first)

        let census = censusAfterSelection(on: first)

        print(
            "PROOF main events=\(log.selectionEvents)"
                + " evals=\(log.branchEvals)"
                + " census=\(census.seen.count)"
                + " liveLen=\(census.live?.selectedRange.length ?? -1)"
        )
        XCTAssertTrue(
            log.selectionEvents.contains(true),
            "选区建立应回报在场（链第一环未动则装置无效）"
        )
        XCTAssertTrue(
            log.branchEvals.contains(false),
            "选区置位后分支翻转必须真渲染到修饰符"
                + "（isEnabled 出现 false 求值），"
                + "否则主臂与对照臂无别、装置无效"
        )
        XCTAssertEqual(
            census.seen.count, 1,
            "选区建立后承载视图实例被更换"
                + "（make/dismantle 发生）——末环实况"
        )
        XCTAssertEqual(
            census.live?.selectedRange.length, 5,
            "活着的承载视图选区应仍为 5 字（未被拆毁）"
        )
    }

    /// 对照臂：isEnabled 恒真、选区回报不驱动任何状
    /// 态。选区应全程存活、实例不变——证明装置本身
    /// 与程序化选区不杀选区，杀手只在分支翻转
    func testSelectionSurvivesConstantBranch() throws {
        let log = assemble(branchFollowsSelection: false)
        let initial = textViews()
        XCTAssertEqual(initial.count, 1)
        let first = try XCTUnwrap(initial.first)

        let census = censusAfterSelection(on: first)

        print(
            "PROOF control events=\(log.selectionEvents)"
                + " evals=\(log.branchEvals)"
                + " census=\(census.seen.count)"
                + " liveLen=\(census.live?.selectedRange.length ?? -1)"
        )
        XCTAssertTrue(log.selectionEvents.contains(true))
        XCTAssertEqual(
            log.branchEvals, [true],
            "对照臂 isEnabled 应恒真（分支从不翻转）"
        )
        XCTAssertEqual(census.seen.count, 1)
        XCTAssertEqual(census.live?.selectedRange.length, 5)
    }
}
