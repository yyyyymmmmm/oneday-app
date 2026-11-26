import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §293（原生重建 R2）原生承载真实装配回归（续
/// R1 装配壳、同窗同座）：行内容全是真实生产视
/// 图（MarkdownText／ToolCardView／Streaming-
/// BlockText），禁用固定高占位行作证据：
/// ⑦直播区逐项入快照——思考/工具/封存段/打开段
/// 各自独立 item、帧序与间距单源 24（施工图
/// §3.1 #9–11）；
/// ⑧块闭合单渲染（H4 的机器判据，蓝图 §6.2
/// ⑤）：93 事故原文（4640 段 A／4643 段 B＋工
/// 具边界）按确定性序列注入——闭合前 A 只在打
/// 开段 item 的渲染树、封段后 A 只在封存段
/// item、B 只在打开段 item，任一段文字在任一帧
/// 只出现在一个 item 内；
/// ⑨键盘跟随装配（§302 回 §194 形态，代 H8 引
/// 导线版）：键盘通知驱动舱常量——静息回落座、
/// willShow 后舱底＝通知帧顶、willChangeFrame
/// 时长 0 逐帧跟随、动画中段 presentation 帧在
/// 途对账、willHide 回座；同一解析点组装的
/// KeyboardFrameUpdate 供数（top/时长/曲线原
/// 值、hide 后 nil）同拍断言；引导线全程不动
/// （驱动者是通知的直证）；底 inset 仍＝舱实
/// 测帧派生（R2 口径不变）；
/// ⑩流式跟随：跟随命令（生产链同口）后打开段
/// 逐拍生长，距底恒达标、末行→舱顶恒 24——落
/// 点只认真实布局、收敛后钉底（H6）。
@MainActor
final class ChatNativeListR2AssemblyTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874
    private let composerHeight: CGFloat = 54
    private let fedTopInset: CGFloat = 122
    private let bottomMargin: CGFloat = 16
    private let bottomPadding: CGFloat = 8
    private let targetGap: CGFloat = 24

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

    private func composerContent() -> AnyView {
        AnyView(
            Rectangle()
                .fill(Color.gray)
                .frame(height: composerHeight)
        )
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
            composerView: composerContent(),
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

    private func composerTopInWindow() throws -> CGFloat {
        let host = try XCTUnwrap(
            controller.composerHost,
            "舱子托管应已装配"
        )
        return host.view.convert(
            host.view.bounds, to: nil
        ).minY
    }

    // MARK: - 真实行内容（生产视图、非占位）

    private func bubble<Content: View>(
        _ content: Content
    ) -> AnyView {
        AnyView(
            content
                .padding(
                    .horizontal, OneDayMetrics.bubblePaddingH
                )
                .padding(
                    .vertical, OneDayMetrics.bubblePaddingV
                )
                .background(
                    RoundedRectangle(
                        cornerRadius:
                            OneDayMetrics.assistantBubbleCorner
                    )
                    .fill(Palette.bubbleFill)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    private func settledRow(
        _ key: String, _ text: String
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(parts: [.text(text)]),
            makeView: { self.bubble(MarkdownText(text)) }
        )
    }

    private func streamRow(
        _ key: String, _ text: String, version: Int
    ) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            revision: ChatNativeRowRevision(parts: [.text(text), .count(version)]),
            makeView: {
                // §409 步 D：StreamingBlockText 已
                // 退役，流式行替身改落定同款
                // MarkdownText（本 harness 只验装配
                // 与修订换装、不验块沉淀）
                self.bubble(MarkdownText(text))
            }
        )
    }

    private func toolRow() -> ChatNativeRow {
        let card = ToolCard(
            id: "tool-colorize-1",
            toolName: "colorize_image",
            category: .vision,
            title: "彩色化图片",
            summary: "photo.png",
            result: "已生成彩色化结果",
            resultFailed: false
        )
        return ChatNativeRow(
            key: "live-tool-colorize-1",
            entryID: nil,
            revision: ChatNativeRowRevision(parts: [.text(card.id)]),
            makeView: { AnyView(ToolCardView(card: card)) }
        )
    }

    // MARK: - 视图树文本采集（⑧判据面）

    /// 直接遍历一棵视图树、收集实际文本载体
    /// （UITextView／UILabel／UITextField）的
    /// 正文。量测通道定版（⑧采集修复，§294.1
    /// 后续）：此前经 accessibility 采集串量
    /// 测——UIHostingConfiguration 托管内容在
    /// 该通道下漏采（尾块计数 0）与重采（同段
    /// 两份）并存，且无障碍元素树懒生成、时序
    /// 口径在本仓三轮 CI 实证时有时无（ChatRe-
    /// liabilityOfflineTests 既有判语）。改走
    /// 视图树遍历：只读真实载体、每载体只取一
    /// 个文本源（同一载体的 text 与 attribu-
    /// tedText 是同一内容、只取其一，防同段在
    /// 单 cell 内重复计数），全程不触 acces-
    /// sibility 运行时；按 cell 遍历即按 item
    /// 归属计数
    private func renderTexts(in view: UIView) -> [String] {
        var out: [String] = []
        func walk(_ v: UIView) {
            if let textView = v as? UITextView {
                if let text = textView.text,
                   !text.isEmpty {
                    out.append(text)
                } else if let attributed =
                    textView.attributedText?.string,
                    !attributed.isEmpty {
                    out.append(attributed)
                }
            }
            if let label = v as? UILabel {
                if let text = label.text,
                   !text.isEmpty {
                    out.append(text)
                } else if let attributed =
                    label.attributedText?.string,
                    !attributed.isEmpty {
                    out.append(attributed)
                }
            }
            if let field = v as? UITextField,
               let text = field.text, !text.isEmpty {
                out.append(text)
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return out
    }

    /// 一个 cell 的全部可达文本拼成的整串
    private func renderText(in view: UIView) -> String {
        renderTexts(in: view).joined()
    }

    /// 含标记文本的可见 cell 数（同帧渲染树口径）
    private func cellsContaining(_ marker: String) -> Int {
        controller.collectionView.visibleCells.filter {
            cell in
            renderText(in: cell).contains(marker)
        }.count
    }

    // MARK: - ⑦ 直播逐项入快照

    func testLiveItemsOccupySeparateItems() throws {
        assemble()
        let rows = [
            settledRow("entry-1", "落定的一条助手回复。"),
            toolRow(),
            streamRow(
                "stream-u1#seg0",
                "封存段的内容，已经定稿不再变化。",
                version: 1
            ),
            streamRow(
                "stream-u1",
                "打开段正在生成，尾巴还在长。",
                version: 1
            ),
        ]
        apply(rows: rows)
        drain()
        let cv = controller.collectionView
        XCTAssertEqual(
            cv.numberOfSections, rows.count,
            "直播逐项须各自成行（§329 一行一 section、非整段一块）"
        )
        var frames: [CGRect] = []
        for index in rows.indices {
            frames.append(try frame(at: index))
        }
        for index in rows.indices {
            XCTAssertGreaterThan(
                frames[index].height, 30,
                "行 \(index) 高度应来自真实排版而非占位"
            )
        }
        for index in 0..<(rows.count - 1) {
            let gap = frames[index + 1].minY
                - frames[index].maxY
            XCTAssertEqual(
                gap, OneDayMetrics.spacingL, accuracy: 1.0,
                "直播 item \(index)→\(index + 1) 间距须＝单源 24，实测 \(gap)"
            )
        }
    }

    // MARK: - ⑧ 块闭合单渲染（93 原文回放）

    func testBlockClosureKeepsSegmentInExactlyOneItem() throws {
        assemble()
        // 93 事故原文（服务端落库定稿，见
        // stream-segment-carryover-20261115.md）：
        // A＝4640 段、B＝4643 段，中间隔一次工具调用
        let segmentA =
            "好，我换个更可靠的方式——用 Replicate 的公开 DeOldify 模型，不需要 API key 的那种，或者直接调一个免费的彩色化服务。"
        let segmentBPartial =
            "好，我直接用 colorize.cc 或 DeepAI 的免费接口，不需要注册。先试"
        let segmentB =
            "好，我直接用 colorize.cc 或 DeepAI 的免费接口，不需要注册。先试 DeepAI。"

        // 第一拍：A 已闭合、B 在尾块——同属打开段
        // 一个 item（A 只在该 item 的前缀渲染里）
        apply(rows: [
            streamRow(
                "stream-u1",
                segmentA + "\n\n" + segmentBPartial,
                version: 1
            ),
        ])
        drain()
        XCTAssertEqual(
            controller.collectionView.numberOfSections,
            1,
            "闭合前须为打开段单行（前缀＋尾块同行内分工）"
        )
        print(
            "R2-⑧ 第一拍渲染树："
                + controller.collectionView.visibleCells
                    .map { renderText(in: $0) }
                    .joined(separator: " | ")
        )
        XCTAssertEqual(
            cellsContaining("DeOldify"), 1,
            "闭合前 A 须只出现在打开段 item 一处渲染树"
        )
        XCTAssertEqual(
            cellsContaining("colorize.cc"), 1,
            "闭合前 B 须只出现在打开段 item 一处渲染树"
        )

        // 第二拍：工具边界封段——A 移入封存段
        // item、工具卡成 item、B 续写打开段 item。
        // 同帧互斥：A 只在封存段、B 只在打开段
        apply(rows: [
            streamRow(
                "stream-u1#seg0", segmentA, version: 1
            ),
            toolRow(),
            streamRow("stream-u1", segmentB, version: 2),
        ])
        drain()
        XCTAssertEqual(
            controller.collectionView.numberOfSections,
            3,
            "封段后须为封存段/工具/打开段三行"
        )
        XCTAssertEqual(
            cellsContaining("DeOldify"), 1,
            "封段后 A 须只出现在封存段 item 一处（同帧两份＝叠字构造形态）"
        )
        XCTAssertEqual(
            cellsContaining("colorize.cc"), 1,
            "封段后 B 须只出现在打开段 item 一处"
        )
        print(
            "R2-⑧ 第二拍渲染树："
                + controller.collectionView.visibleCells
                    .map { renderText(in: $0) }
                    .joined(separator: " | ")
        )
        // 互斥直证：封存段 cell 不含 B、打开段 cell
        // 不含 A
        let cells = controller.collectionView.visibleCells
        let sealedCell = try XCTUnwrap(
            cells.first {
                renderText(in: $0).contains("DeOldify")
            },
            "封存段 cell 须在场"
        )
        XCTAssertFalse(
            renderText(in: sealedCell)
                .contains("colorize.cc"),
            "封存段渲染树不许含打开段文字"
        )
        let tailCell = try XCTUnwrap(
            cells.first {
                renderText(in: $0).contains("colorize.cc")
            },
            "打开段 cell 须在场"
        )
        XCTAssertFalse(
            renderText(in: tailCell).contains("DeOldify"),
            "打开段渲染树不许残留已封段文字"
        )
    }

    // MARK: - ⑨ 键盘跟随装配（§302 回 §194 形态）

    /// 键盘通知投递（与 R1 装配 seatComposer 同
    /// 式）：投的即生产驱动本体——结束帧＋动画
    /// 参数原值；安全区模拟已退役（定因报告
    /// §七.4：模拟只验约束成立、不验跟随）
    private func postKeyboard(
        name: Notification.Name, top: CGFloat,
        duration: Double
    ) {
        NotificationCenter.default.post(
            name: name, object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: CGRect(
                        x: 0, y: top, width: windowW,
                        height: windowH - top
                    )),
                UIResponder.keyboardAnimationDurationUserInfoKey:
                    NSNumber(value: duration),
                UIResponder.keyboardAnimationCurveUserInfoKey:
                    NSNumber(value: 7),
            ]
        )
    }

    private func composerBottomInWindow() throws
        -> CGFloat
    {
        let host = try XCTUnwrap(
            controller.composerHost, "舱子托管应已装配"
        )
        return host.view.convert(
            host.view.bounds, to: nil
        ).maxY
    }

    /// 动画中段采样：动画窗内逐 30ms 读舱宿主的
    /// presentation 帧底（窗口坐标），命中「严格
    /// 在起讫之间」的在途样本即返回（动画由通知
    /// 参数驱动、presentation 帧即中段真帧）。
    /// 节拍以 expectation＋asyncAfter 推进（与
    /// drain 同式，§302.1 续作）：wait 正常泵主运
    /// 行循环、显示链接得以推进动画；旧式 RunLoop
    /// 切片自旋在无输入源时即时返回、饿死动画推
    /// 进，采样恒读起点值（首轮实证）
    private func pollMidAnimationBottom(
        from: CGFloat, to: CGFloat
    ) -> CGFloat? {
        let deadline = Date().addingTimeInterval(0.45)
        while Date() < deadline {
            let beat = expectation(description: "midAnimBeat")
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.03
            ) { beat.fulfill() }
            wait(for: [beat], timeout: 5)
            if let host = controller.composerHost,
               let presentation = host.view.layer
                .presentation() {
                let bottom = controller.view.convert(
                    CGPoint(
                        x: 0, y: presentation.frame.maxY
                    ),
                    to: nil
                ).y
                if bottom < from - 2, bottom > to + 2 {
                    return bottom
                }
            }
        }
        return nil
    }

    func testComposerSoftWrapAndAttachmentGrowAboveKeyboard() throws {
        assemble()
        apply(rows: [])
        let focus = ComposerFocusHandle()
        func composer(_ text: String, attachment: Bool = false) -> AnyView {
            AnyView(
                VStack(spacing: 0) {
                    if attachment {
                        Text("notes.txt").frame(height: 36)
                    }
                    ChatView.ComposerBarLayout(draft: text) {
                        Color.clear.frame(width: 30, height: 30)
                        ComposerTextView(
                            text: .constant(text), focusHandle: focus,
                            onFocusChange: { _ in }, caretColor: .systemBlue
                        )
                        Color.clear.frame(width: 30, height: 30)
                    }
                }
            )
        }
        let keyboardTop: CGFloat = 541
        controller.applyComposer(view: composer("测试"))
        drain(0.15)
        postKeyboard(
            name: UIResponder.keyboardWillShowNotification,
            top: keyboardTop, duration: 0
        )
        drain(0.5)
        let initialTop = try composerTopInWindow()
        let initialInset = handle.bottomInset
        XCTAssertEqual(try composerBottomInWindow(), keyboardTop, accuracy: 1)
        XCTAssertEqual(initialInset, windowH - initialTop + bottomMargin, accuracy: 1)

        let narrowWidth = ComposerLayout.textWidth(
            forContainerWidth: windowW + ComposerLayout.inputBarChrome
        )
        var draft = "测试"
        while ComposerTextMetrics.lineCount(for: draft, width: narrowWidth) == 1 {
            draft += "字"
        }
        controller.applyComposer(view: composer(draft))
        drain(0.15)
        let wrappedTop = try composerTopInWindow()
        XCTAssertLessThan(wrappedTop, initialTop - 20)
        XCTAssertEqual(try composerBottomInWindow(), keyboardTop, accuracy: 1)
        XCTAssertEqual(handle.bottomInset - initialInset, initialTop - wrappedTop, accuracy: 1)

        controller.applyComposer(view: composer(draft, attachment: true))
        drain(0.15)
        XCTAssertEqual(try composerTopInWindow(), wrappedTop - 36, accuracy: 1)
        XCTAssertEqual(try composerBottomInWindow(), keyboardTop, accuracy: 1)
        XCTAssertEqual(handle.bottomInset - initialInset, initialTop - wrappedTop + 36, accuracy: 1)
    }

    func testComposerNotificationFollowAndSnapshotFeed()
        throws
    {
        assemble()
        // 供数记录口：控制器与舱常量同一解析点组
        // 装的 KeyboardFrameUpdate 全量留档——底
        // 栏键盘态退场（ChatView .toolbar 藏坞）
        // 的唯一输入即此包的 topInWindow，本例验
        // 其供数面
        var updates: [KeyboardFrameUpdate] = []
        controller.onKeyboardFrameChange = {
            updates.append($0)
        }
        let rows = [
            settledRow("only", "只有一条短回复的会话。")
        ]
        apply(rows: rows)
        drain()
        let cv = controller.collectionView
        // 静息座位：本壳无坞（裸装配）→回落窗口安
        // 全区底（生产装配恒有坞、走坞实测顶，回
        // 落式与 §194 同）；舱底窗口值与回落式同值
        let restBottom = windowH
            - window.safeAreaInsets.bottom
        let restMeasured = try composerBottomInWindow()
        XCTAssertEqual(
            restMeasured, restBottom,
            accuracy: 1.0,
            "静息舱底须＝回落座 \(restBottom)，实测 "
                + "\(restMeasured)"
        )
        // 派生直证：底 inset＝（列表帧底−舱顶）窗
        // 口实测＋单点边距，无第二来源（R2 口径）
        let frameInWindow = controller.view.convert(
            controller.view.bounds, to: nil
        )
        let host = try XCTUnwrap(
            controller.composerHost, "舱子托管应已装配"
        )
        let hostInWindow = host.view.convert(
            host.view.bounds, to: nil
        )
        let expectedRest = frameInWindow.maxY
            - hostInWindow.minY + bottomMargin
        XCTAssertEqual(
            cv.contentInset.bottom, expectedRest,
            accuracy: 1.0,
            "底 inset 须＝舱实测帧派生 \(expectedRest)，实测 \(cv.contentInset.bottom)"
        )
        // 引导线基线：记其当前帧——后续通知驱动
        // 舱移动全程它不许动（舱动即通知驱动的结
        // 构直证；引导线只采样不驱动，§302）
        let guideTopAtRest = controller.view
            .keyboardLayoutGuide.layoutFrame.minY

        // 升起：willShow（帧顶 541／时长 0.25／曲
        // 线 7）→舱底落通知帧顶、供数同拍同值
        postKeyboard(
            name: UIResponder.keyboardWillShowNotification,
            top: 541, duration: 0.25
        )
        drain(0.6)
        let shownBottom = try composerBottomInWindow()
        XCTAssertEqual(
            shownBottom, 541,
            accuracy: 1.0,
            "升起后舱底须＝通知帧顶 541，实测 "
                + "\(shownBottom)"
        )
        XCTAssertEqual(
            updates.last?.topInWindow, 541,
            "供数 top 须＝通知帧顶 541，实测 "
                + "\(String(describing: updates.last?.topInWindow))"
        )
        XCTAssertEqual(
            updates.last?.duration, 0.25,
            "供数时长须＝通知原值 0.25"
        )
        XCTAssertEqual(
            updates.last?.curveRawValue, 7,
            "供数曲线须＝通知原值 7"
        )
        XCTAssertEqual(
            controller.view.keyboardLayoutGuide
                .layoutFrame.minY,
            guideTopAtRest, accuracy: 0.5,
            "引导线须全程未动（驱动者是通知不是它）"
        )
        // inset 随舱帧派生同步：恒等式复核（舱顶
        // 487→inset 403）
        let hostTopAfterShow = try composerTopInWindow()
        XCTAssertEqual(
            cv.contentInset.bottom,
            frameInWindow.maxY - hostTopAfterShow
                + bottomMargin,
            accuracy: 1.0,
            "升起后底 inset 须随舱帧派生，实测 \(cv.contentInset.bottom)"
        )
        // 短内容末行→舱顶在键盘位仍 24
        let last = try frame(at: 0)
        let lastInWindow = cv.convert(last, to: nil)
        XCTAssertEqual(
            hostTopAfterShow - lastInWindow.maxY,
            targetGap, accuracy: 1.0,
            "键盘位下末行底→舱顶须 24±1，实测 "
                + "\(hostTopAfterShow - lastInWindow.maxY)"
        )

        // 中段帧逐帧对账：willChangeFrame 时长 0
        // 逐事件给中间帧顶，舱底逐值立即跟随（交
        // 互式消散的逐帧形态）
        for top in [640.0, 580.0, 541.0] {
            postKeyboard(
                name: UIResponder
                    .keyboardWillChangeFrameNotification,
                top: top, duration: 0
            )
            window.layoutIfNeeded()
            let frameBottom = try composerBottomInWindow()
            XCTAssertEqual(
                frameBottom, top,
                accuracy: 1.0,
                "逐帧跟随：帧顶 \(top) 时舱底须同值，实测 "
                    + "\(frameBottom)"
            )
            XCTAssertEqual(
                updates.last?.topInWindow, top,
                "逐帧供数 top 须同值 \(top)"
            )
        }

        // 动画中段帧对账：自 541 以 0.5s 动画移向
        // 474——中段 presentation 帧须严格在途（非
        // 瞬跳、非未动），落定后舱底＝474
        postKeyboard(
            name: UIResponder
                .keyboardWillChangeFrameNotification,
            top: 474, duration: 0.5
        )
        let mid = pollMidAnimationBottom(
            from: 541, to: 474
        )
        XCTAssertNotNil(
            mid,
            "动画中段须采到在途帧（起 541→讫 474 之间）"
        )
        drain(0.8)
        let settledBottom = try composerBottomInWindow()
        XCTAssertEqual(
            settledBottom, 474,
            accuracy: 1.0,
            "动画落定后舱底须＝474，实测 "
                + "\(settledBottom)"
        )

        // 收起：willHide→舱回静息座、供数报 nil
        // （isKeyboardUp 源头恢复假值、底栏归位）
        postKeyboard(
            name: UIResponder.keyboardWillHideNotification,
            top: windowH, duration: 0.25
        )
        drain(0.6)
        let backBottom = try composerBottomInWindow()
        XCTAssertEqual(
            backBottom, restBottom,
            accuracy: 1.0,
            "收起后舱底须回静息座 \(restBottom)，实测 "
                + "\(backBottom)"
        )
        XCTAssertNil(
            updates.last?.topInWindow,
            "收起后供数 top 须 nil（藏坞解除）"
        )
    }

    // MARK: - 台账 182：静息锚 convert 读法

    /// 静息锚认坞的渲染真值：坞祖先容器带 −40
    /// 纵向变换（TabView 内部带变换容器的同型失
    /// 真——旧 layoutSpaceMinY 累加口径读布局顶
    /// 791、舱底随之压进坞渲染面 40pt，正是真机
    /// 「带附件时输入舱被底栏压住」的同构复现）
    /// 时，舱底须＝convert 渲染顶 751；呈现离散
    /// 重解析入口调用后读数不坏
    func testRestingAnchorUsesConvertedDockTop() throws {
        assemble()
        let dockContainer = UIView(
            frame: CGRect(
                x: 0, y: 0, width: windowW, height: windowH
            )
        )
        dockContainer.transform = CGAffineTransform(
            translationX: 0, y: -40
        )
        let bar = UITabBar(
            frame: CGRect(
                x: 0, y: windowH - 83,
                width: windowW, height: 83
            )
        )
        dockContainer.addSubview(bar)
        controller.view.superview?.addSubview(dockContainer)
        window.layoutIfNeeded()

        apply(rows: [settledRow("only", "只有一条短回复的会话。")])
        drain()
        let renderedDockTop = windowH - 83 - 40
        let bottom = try composerBottomInWindow()
        XCTAssertEqual(
            bottom, renderedDockTop, accuracy: 1.0,
            "舱底须＝坞渲染顶 \(renderedDockTop)（convert 口径），"
                + "实测 \(bottom)；若为 \(windowH - 83) 即累加旧口径回潮"
        )
        // 呈现重解析入口：调用后同拍重算、读数不变坏
        handle.reresolveAnchorsAfterPresentation()
        window.layoutIfNeeded()
        let afterResolve = try composerBottomInWindow()
        XCTAssertEqual(
            afterResolve, renderedDockTop, accuracy: 1.0,
            "重解析后舱底须仍＝坞渲染顶，实测 \(afterResolve)"
        )
    }

    // MARK: - ⑩ 流式跟随钉底（H6）

    func testStreamingGrowthKeepsBottomPin() throws {
        assemble()
        let settled = settledRow(
            "u1", "帮我把这张老照片上色。"
        )
        let stages = [
            "好的，我先看一下照片内容。",
            "好的，我先看一下照片内容。\n\n照片里是一张全家福，背景是老屋的院子，人物衣着是七十年代的样式。",
            "好的，我先看一下照片内容。\n\n照片里是一张全家福，背景是老屋的院子，人物衣着是七十年代的样式。\n\n我先做一版温和的彩色化：肤色按自然暖调、衣着保留原布料的明暗关系、天空与院墙只做轻微提亮，避免把老照片修成新照片的质感。",
        ]
        for (index, text) in stages.enumerated() {
            // 跟随命令与生产链同口：流式增量经跟随
            // 闸放行后由 ChatView 下达贴底命令，本处
            // 以句柄命令同式复现其拍位
            if index > 0 {
                controller.scrollToBottom(animated: false)
            }
            apply(rows: [
                settled,
                streamRow(
                    "stream-u1", text, version: index + 1
                ),
            ])
            drain(1.0)
            XCTAssertLessThanOrEqual(
                handle.latestDistance, 2.5,
                "生长第 \(index + 1) 拍后距底须达标（收敛后钉底），实测 \(handle.latestDistance)"
            )
            let last = try frame(at: 1)
            let lastInWindow = controller.collectionView
                .convert(last, to: nil)
            let gap = try composerTopInWindow()
                - lastInWindow.maxY
            XCTAssertEqual(
                gap, targetGap, accuracy: 1.5,
                "生长第 \(index + 1) 拍后末行底→舱顶须 24，实测 \(gap)"
            )
        }
    }
}
