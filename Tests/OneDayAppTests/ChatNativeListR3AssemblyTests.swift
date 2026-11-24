import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §325（B 档退役）单渲染路径装配回归——本文件
/// 前身为 R3 原生散文 cell 装配（⑪双形态对拍／
/// ⑫原生 cell 本体／⑬混合行集间距）：双 cell 形
/// 态整套退役后三例的断言对象不复存在，随形态
/// 一并退役；本文件改守 B 档验收门（类名沿用、
/// CI 对账不断链）：
/// ⑪′单路径结构断言——含散文/引用/结构段的落
/// 定行全体物化为同一种托管 cell（reuseID 单
/// 一），facet 只影响行内呈现、不决定 cell 类；
/// ⑫′多遍 apply 稳定性——同段对话同修订连过三
/// 遍 apply：帧逐值不动、间隙恒 24±1；一行动修
/// 订（正文变长）后只有该行高生长、其余行高逐
/// 值不变、间隙仍 24±1（无可见高度跳变的结构
/// 证据，代旧「滚动多遍」盲区）；
/// ⑬′修订值结构化派生——ChatNativeRowRevision
/// .entry 对条目全字段敏感：remoteFilePathsData
/// （§320 病灶字段）/正文/发送态任一变修订必
/// 变，全同则逐值相等；环境侧（分隔/点亮/样式
/// 键）同入账；
/// ⑭′键盘引导线重验（新宿主结构）——通知帧顶
/// 驱动舱落位成立的同时，keyboardLayoutGuide
/// 在本宿主（SwiftUI 托管内嵌）仍停静息值、不
/// 追踪通知帧：引导线换代不成立的模拟器结构证
/// 据（真机终验归用户清单），kbSnapshot 分发
/// 层据此不退役（见 §325 报告）。
@MainActor
final class ChatNativeListR3AssemblyTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874
    private let composerHeight: CGFloat = 54
    private let fedTopInset: CGFloat = 122
    private let bottomMargin: CGFloat = 16
    private let bottomPadding: CGFloat = 8

    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        window = UIWindow(
            frame: CGRect(
                x: 0, y: 0, width: windowW, height: windowH
            )
        )
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()

        handle = ChatNativeListHandle()
        controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        root.view.layoutIfNeeded()
    }

    private func apply(rows: [ChatNativeRow]) {
        controller.apply(
            rows: rows,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: bottomPadding,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: fedTopInset,
            bottomMargin: bottomMargin,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: composerHeight)
            ),
            arrowView: AnyView(Color.clear)
        )
        window.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval = 1.2) {
        let exp = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window.layoutIfNeeded()
    }

    private func frame(at index: Int) throws -> CGRect {
        let attrs = controller.collectionView
            .layoutAttributesForItem(
                at: IndexPath(item: 0, section: index)
            )
        return try XCTUnwrap(attrs).frame
    }

    private func cell(at index: Int) -> UICollectionViewCell? {
        controller.collectionView.cellForItem(
            at: IndexPath(item: 0, section: index)
        )
    }

    // MARK: - 真实行内容（生产视图、非占位）

    /// §329：测试侧拟合量高——行高改 .absolute 回
    /// 喂后手搓行须自带高：以独立托管控制器对行
    /// 视图在列表内容宽（屏宽−左右 inset）下量拟
    /// 合高（旧框架自适应在测试侧的等价物；生产
    /// 行走高度合成器、不经本路）
    private func fittedHeight(_ view: AnyView) -> CGFloat {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(
            in: CGSize(
                width: windowW
                    - OneDayMetrics.pageGutter * 2,
                height: .greatestFiniteMagnitude
            )
        ).height
    }

    private func fittedRow(
        key: String,
        revision: ChatNativeRowRevision,
        makeView: @escaping () -> AnyView
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: revision,
            height: fittedHeight(makeView()),
            makeView: makeView
        )
    }

    private func hostedRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        fittedRow(
            key: key,
            revision: ChatNativeRowRevision(
                parts: [.text(text)]
            )
        ) {
            AnyView(
                MarkdownText(text)
                    .padding(
                        .horizontal,
                        OneDayMetrics.bubblePaddingH
                    )
                    .padding(
                        .vertical,
                        OneDayMetrics.bubblePaddingV
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
            )
        }
    }

    // MARK: - ⑪′ 全体行单形态（托管 cell 单一 reuseID）

    func testAllRowsMaterializeAsHostingCells() throws {
        assemble()
        let rows = [
            hostedRow(
                "r1",
                "普通散文一行——R3 时代这类行会下沉原生 cell。"
            ),
            hostedRow(
                "r2",
                "带引用的回复。\n\n> 引用一行，facet 在席。\n\n引用之后再接一段正文收尾。"
            ),
            hostedRow(
                "r3",
                "带结构段的回复。\n\n```swift\nlet x = 1\n```\n\n代码块之后还有正文。"
            ),
            hostedRow("r4", "最后一条短回复。"),
        ]
        apply(rows: rows)
        drain()
        for index in rows.indices {
            let itemCell = try XCTUnwrap(
                cell(at: index),
                "行 \(index) 须物化出 cell"
            )
            XCTAssertEqual(
                itemCell.reuseIdentifier,
                "ChatNativeHostingCell",
                "行 \(index) 须为唯一托管形态（单渲染路径），实得 \(String(describing: itemCell.reuseIdentifier))"
            )
            XCTAssertGreaterThan(
                try frame(at: index).height, 30,
                "行 \(index) 高须来自真实排版"
            )
        }
    }

    // MARK: - ⑫′ 多遍 apply：间隙恒定＋未变行帧稳定

    func testMultiPassApplyKeepsSpacingAndStableFrames()
        throws
    {
        assemble()
        let base = [
            hostedRow("m1", "第一条助手回复，内容不长。"),
            hostedRow("m2", "第二条，长度中等的一行回复。"),
            hostedRow("m3", "第三条收尾。"),
        ]
        apply(rows: base)
        drain()
        var firstFrames: [CGRect] = []
        for index in base.indices {
            firstFrames.append(try frame(at: index))
        }
        // 同修订连过两遍：帧逐值不动（无重配、无跳变）
        for _ in 0..<2 {
            apply(rows: base)
            drain(0.6)
            for index in base.indices {
                let now = try frame(at: index)
                XCTAssertEqual(
                    now, firstFrames[index],
                    "同修订重过 apply 后行 \(index) 帧须逐值不变，\(firstFrames[index]) → \(now)"
                )
            }
        }
        // 中间行正文变长（修订随之变）：只有该行生长
        let grown = [
            base[0],
            hostedRow(
                "m2",
                "第二条，长度中等的一行回复。\n\n现在它多了一整段：多遍 apply 之后行高收敛只许发生在真正变了的行身上，未变的行帧若跟着漂移，就是用户在 .65 真机上看到的间隙异常那一族。"
            ),
            base[2],
        ]
        apply(rows: grown)
        drain()
        let grownFrame1 = try frame(at: 1)
        XCTAssertGreaterThan(
            grownFrame1.height, firstFrames[1].height + 20,
            "变长行须按新内容生长，\(firstFrames[1].height) → \(grownFrame1.height)"
        )
        XCTAssertEqual(
            try frame(at: 0).height, firstFrames[0].height,
            accuracy: 0.5,
            "未变行（首行）高不许随邻行变化漂移"
        )
        XCTAssertEqual(
            try frame(at: 2).height, firstFrames[2].height,
            accuracy: 0.5,
            "未变行（末行）高不许随邻行变化漂移"
        )
        for index in 0..<(grown.count - 1) {
            let gap = try frame(at: index + 1).minY
                - frame(at: index).maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 2.0,
                "多遍 apply 后行 \(index)→\(index + 1) 间隙须 24±2，实测 \(gap)"
            )
        }
    }

    // MARK: - ⑬′ 修订值结构化派生（全字段敏感）

    func testEntryRevisionDerivedFromAllModelFields()
        throws
    {
        let entry = ChatEntry(
            role: "user", content: "能不能看到", thread: nil
        )
        func revision() -> ChatNativeRowRevision {
            ChatNativeRowRevision.entry(
                entry,
                dividerText: nil,
                highlighted: false,
                styleKey: "style-a"
            )
        }
        let base = revision()
        XCTAssertEqual(
            base, revision(),
            "同条目同环境连算两遍修订须逐值相等（派生确定性）"
        )
        // §320 病灶字段：文件回填落盘
        entry.remoteFilePathsData =
            try JSONEncoder().encode(["/opt/data/a.xlsx"])
        XCTAssertNotEqual(
            base, revision(),
            "remoteFilePathsData 变（文件回填）修订必须变——手折哈希漏折此项即 §320 病灶"
        )
        let withFile = revision()
        // 正文变
        entry.content = "能不能看到这个文件"
        XCTAssertNotEqual(withFile, revision())
        // 发送态变
        entry.sendFailed = true
        XCTAssertNotEqual(withFile, revision())
        // 环境侧：分隔/点亮/样式键任一变
        let envChanged = ChatNativeRowRevision.entry(
            entry,
            dividerText: "今天 09:41",
            highlighted: false,
            styleKey: "style-a"
        )
        XCTAssertNotEqual(revision(), envChanged)
        let styleChanged = ChatNativeRowRevision.entry(
            entry,
            dividerText: nil,
            highlighted: false,
            styleKey: "style-b"
        )
        XCTAssertNotEqual(revision(), styleChanged)
    }

    // MARK: - ⑭′ 引导线重验：通知驱动成立、引导线不追踪

    func testKeyboardGuideDoesNotTrackOnCurrentHost()
        throws
    {
        assemble()
        apply(rows: [hostedRow("only", "只有一条短回复。")])
        drain()
        let guideAtRest = try XCTUnwrap(
            controller.testKeyboardGuideTopInWindow,
            "入窗后引导线采样须有值"
        )
        // 投递生产驱动本体（willShow＋帧顶 545＋时长 0）
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: CGRect(
                        x: 0, y: 545, width: windowW,
                        height: windowH - 545
                    )),
                UIResponder.keyboardAnimationDurationUserInfoKey:
                    NSNumber(value: 0),
                UIResponder.keyboardAnimationCurveUserInfoKey:
                    NSNumber(value: 7),
            ]
        )
        window.layoutIfNeeded()
        drain(0.6)
        // 通知路成立：舱底＝帧顶 545（舱顶 491）
        let host = try XCTUnwrap(
            controller.composerHost, "舱子托管应已装配"
        )
        let composerBottom = host.view.convert(
            host.view.bounds, to: nil
        ).maxY
        XCTAssertEqual(
            composerBottom, 545, accuracy: 1.0,
            "通知帧顶须驱动舱底＝545（§302 路成立），实测 \(composerBottom)"
        )
        // 引导线不追踪：仍停静息值、与帧顶 545 无关
        let guideAfter = try XCTUnwrap(
            controller.testKeyboardGuideTopInWindow
        )
        XCTAssertEqual(
            guideAfter, guideAtRest, accuracy: 0.5,
            "引导线在本宿主仍停静息值（不追踪）——重验不成立的结构证据，实测 \(guideAtRest) → \(guideAfter)"
        )
        XCTAssertGreaterThan(
            abs(guideAfter - 545), 100,
            "引导线位置须与通知帧顶显著无关，实测 \(guideAfter)"
        )
    }
    // MARK: - ⑮′ 长历史滚动收敛压测（§325.2 崩溃除根门）

    /// 220 行混合行集：普通文本行＋长代码行＋文件
    /// 行（生产 FileChip 本体、回填在席形态）——复
    /// 刻 .66 真机崩溃场景（上滑翻长历史）的行型谱
    private func longHistoryRows(
        count: Int = 220
    ) -> [ChatNativeRow] {
        let appState = AppState()
        return (0..<count).map { i in
            if i % 10 == 7 {
                let path = "/opt/data/report-\(i).xlsx"
                return fittedRow(
                    key: "h\(i)",
                    revision: ChatNativeRowRevision(
                        parts: [
                            .text("file-\(i)"), .text(path),
                        ]
                    )
                ) {
                    AnyView(
                        VStack(
                            alignment: .leading,
                            spacing: 8
                        ) {
                            MarkdownText(
                                "第 \(i) 份报表已经生成，见附件。"
                            )
                            FileChip(path: path) {}
                        }
                        .padding(
                            .horizontal,
                            OneDayMetrics.bubblePaddingH
                        )
                        .padding(
                            .vertical,
                            OneDayMetrics.bubblePaddingV
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .environment(appState)
                    )
                }
            }
            if i % 10 == 5 {
                return hostedRow(
                    "h\(i)",
                    "长回复 \(i)。\n\n```swift\nlet value = \(i)\nprint(value)\n```\n\n代码之后还有一段较长的正文，用来拉开行高差异、让滚动路径覆盖多种行高收敛形态。这一段继续补充文字直到它明显比短行高出一截。"
                )
            }
            return hostedRow(
                "h\(i)",
                "历史消息 \(i)，长度随序号略有变化。"
            )
        }
    }

    /// §325.2 第一验收门：220 行长历史多遍 apply＋
    /// 自底向顶连续滚动模拟（.66 崩溃场景）全程不
    /// 陷断言（跑完即第一重证据）、布局 pass 数有界
    /// （section 重建计数）、间隙 24±2、文件牌在
    /// 席、稳态强制布局帧逐值不动（自适应收敛/拟
    /// 合幂等的结构证据）；末段切
    /// .enabledIncludingConstraints 对照同组断言，
    /// 两档 pass 数打印入日志作守卫 3③ 定档证据
    func testLongHistoryScrollConvergesWithoutLayoutRecursion()
        throws
    {
        assemble()
        let rows = longHistoryRows()
        apply(rows: rows)
        drain(1.5)
        let cv = controller.collectionView
        XCTAssertGreaterThan(
            cv.contentSize.height, 6000,
            "220 行混合行集内容高须成规模，实测 \(cv.contentSize.height)"
        )
        // 同修订重复 apply：不得再触发 section 重建
        let passesBeforeRepeat =
            controller.testSectionProviderCallCount
        apply(rows: rows)
        apply(rows: rows)
        drain(0.8)
        XCTAssertEqual(
            controller.testSectionProviderCallCount,
            passesBeforeRepeat,
            "同修订重复 apply 不得触发 section 重建（pass 数有界），\(passesBeforeRepeat) → \(controller.testSectionProviderCallCount)"
        )
        // 连续滚动模拟：以用户拖动态进入（落点意图
        // 消、与真机手势同式），自底向顶 30 步
        controller.scrollViewWillBeginDragging(cv)
        let maxOffset = max(
            0, cv.contentSize.height - cv.bounds.height
        )
        let steps = 30
        let passesBeforeScroll =
            controller.testSectionProviderCallCount
        for step in 0...steps {
            let y = maxOffset
                * CGFloat(steps - step) / CGFloat(steps)
            cv.contentOffset = CGPoint(x: 0, y: y)
            window.layoutIfNeeded()
        }
        let scrollPasses =
            controller.testSectionProviderCallCount
            - passesBeforeScroll
        XCTAssertLessThanOrEqual(
            scrollPasses, steps,
            "滚动全程 section 重建须有界（≤每步一次），实测 \(scrollPasses)/\(steps) 步"
        )
        controller.scrollViewDidEndDragging(
            cv, willDecelerate: false
        )
        drain(0.6)
        // 间隙抽样（首/中/尾，全程滚过已物化）：24±2
        for index in [10, 110, 210] {
            let gap = try frame(at: index + 1).minY
                - frame(at: index).maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 2.0,
                "长历史行 \(index) 间隙须 24±2，实测 \(gap)"
            )
        }
        // 文件牌在席：滚到文件行（107）须物化、行高
        // 含牌面段（与相邻短文本行差分 ≥30）
        let fileIndex = 107
        let fileFrame = try frame(at: fileIndex)
        cv.contentOffset = CGPoint(
            x: 0, y: max(0, fileFrame.minY - 100)
        )
        window.layoutIfNeeded()
        drain(0.5)
        let fileCell = try XCTUnwrap(
            cell(at: fileIndex),
            "文件行滚入视口须物化出 cell（文件牌在席）"
        )
        XCTAssertEqual(
            fileCell.reuseIdentifier,
            "ChatNativeHostingCell"
        )
        let shortFrame = try frame(at: 106)
        XCTAssertGreaterThan(
            fileFrame.height, shortFrame.height + 30,
            "文件行高须含文件牌段，文件行 \(fileFrame.height) vs 短行 \(shortFrame.height)"
        )
        // 收敛终局（生产档 .enabled）：稳态强制布局
        // ×3——contentSize 与采样帧逐值不动、零
        // section 重建（拟合幂等/无振荡的结构证据；
        // 任一行型不幂等会在此以具体行号现形）
        let steadySize = cv.contentSize
        let steadyFrames = try (0..<8).map {
            try frame(at: 100 + $0)
        }
        let passesBeforeIdle =
            controller.testSectionProviderCallCount
        for _ in 0..<3 { window.layoutIfNeeded() }
        XCTAssertEqual(
            cv.contentSize.height, steadySize.height,
            accuracy: 0.5,
            "稳态重复布局 contentSize 不得漂移（自适应收敛证据）"
        )
        for (offset, before) in steadyFrames.enumerated() {
            XCTAssertEqual(
                try frame(at: 100 + offset), before,
                "稳态重复布局下行 \(100 + offset) 帧须逐值不变（无振荡）"
            )
        }
        XCTAssertEqual(
            controller.testSectionProviderCallCount,
            passesBeforeIdle,
            "稳态强制布局不得触发 section 重建"
        )
        // 档位对照（守卫 3③）：切最激进档重跑收敛
        // 断言——同行集内容高须与生产档一致、稳态
        // 同样幂等；两档 pass 数打印作定档证据
        controller.testSelfSizingInvalidation =
            .enabledIncludingConstraints
        let passesBeforeAlt =
            controller.testSectionProviderCallCount
        apply(rows: rows)
        drain(1.2)
        XCTAssertEqual(
            cv.contentSize.height, steadySize.height,
            accuracy: 1.5,
            "两档下同行集内容高须一致（定档互证），生产档 \(steadySize.height) vs 激进档 \(cv.contentSize.height)"
        )
        let altFrames = try (0..<8).map {
            try frame(at: 100 + $0)
        }
        for _ in 0..<3 { window.layoutIfNeeded() }
        for (offset, before) in altFrames.enumerated() {
            XCTAssertEqual(
                try frame(at: 100 + offset), before,
                "激进档稳态下行 \(100 + offset) 帧须逐值不变"
            )
        }
        let altPasses =
            controller.testSectionProviderCallCount
            - passesBeforeAlt
        print(
            "BTIER-PASSES repeat=\(passesBeforeRepeat) scroll=\(scrollPasses) altTier=\(altPasses)"
        )
    }
}

