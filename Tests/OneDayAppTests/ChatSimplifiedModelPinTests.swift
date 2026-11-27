import XCTest
@testable import OneDayApp
import OneDayCore

/// §409 A 组钉测（A 案简化模型，2026-11-23）：生成
/// 期只有固定高占位行、正文/思考只在累积器里累积、
/// 落定单拍换行——四件以数据面行为＋源码形态钉死：
/// A1 生成全程零高变（占位高无内容输入＋封存段不
/// 可变）；A2 落定单拍（占位在飞条件与落定清旗同
/// 源、占位与落定条目不同帧共存）；A3 半截落盘保
/// 真（装配器快照→按 persist/resume 同构重建→全
/// 文逐字同、续增量只入打开段）；A4 锚定（跟随只
/// 剩条目数变化通则、流式跟随件零残留）。
final class ChatSimplifiedModelPinTests: XCTestCase {

    // MARK: - 源码读取（与 ChatSwapStep6StructureTests 同路）

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent(
                    "Sources/OneDayApp/ChatView.swift"
                ).path
            ) {
                return url
            }
        }
        XCTFail("找不到仓库根")
        return url
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    private func segment(
        _ src: String, from: String, to: String
    ) throws -> String {
        let start = try XCTUnwrap(
            src.range(of: from), "找不到段起点 \(from)"
        )
        let end = try XCTUnwrap(
            src.range(of: to, range: start.upperBound..<src.endIndex),
            "找不到段终点 \(to)"
        )
        return String(src[start.lowerBound..<end.lowerBound])
    }

    // MARK: - A1 生成全程零高变

    /// 脚本化事件序（思考→正文→工具封段→正文→工
    /// 具→正文）逐拍断言：封存段一经封存逐字不可
    /// 变（呈现若按段成行，旧段高永不回改）；思考
    /// 累积器的 hasContent 只单向翻转一次（占位行
    /// 状态相的唯一数据面输入）；正文/思考事件对
    /// 彼此的累积零干扰
    func testA1GenerationEventsNeverMutateSealedSegments() {
        var assembler = StreamSegmentAssembler()
        var reasoning = StreamPublishGate()
        var sealedHistory: [[String]] = []
        var reasoningPhaseFlips = 0
        var lastHasContent = reasoning.hasContent

        func checkpoint() {
            sealedHistory.append(assembler.sealedSegments)
            if reasoning.hasContent != lastHasContent {
                reasoningPhaseFlips += 1
                lastHasContent = reasoning.hasContent
            }
            // 全部历史快照的封存列恒为当前封存列的
            // 前缀且逐字相等（封存段不可变）
            for past in sealedHistory {
                XCTAssertEqual(
                    Array(assembler.sealedSegments.prefix(past.count)),
                    past,
                    "封存段被后续事件改动（生成期旧行高变）"
                )
            }
        }

        reasoning.offer("思考一"); checkpoint()
        reasoning.offer("思考二"); checkpoint()
        assembler.offer("正文一段"); checkpoint()
        assembler.offer("续写"); checkpoint()
        XCTAssertEqual(assembler.sealCurrentSegment(), "正文一段续写")
        checkpoint()
        assembler.offer("正文二段"); checkpoint()
        reasoning.offer("工具间思考"); checkpoint()
        XCTAssertEqual(assembler.sealCurrentSegment(), "正文二段")
        checkpoint()
        assembler.offer("正文三段"); checkpoint()

        XCTAssertEqual(reasoningPhaseFlips, 1,
                       "思考相输入 hasContent 只许单向翻转一次")
        XCTAssertEqual(reasoning.fullText, "思考一思考二工具间思考")
        XCTAssertEqual(
            assembler.fullSegments,
            ["正文一段续写", "正文二段", "正文三段"]
        )
    }

    /// 占位行高是无输入常量：合成器源码中 live-
    /// PlaceholderHeight 的公式体不含任何内容/阶
    /// 段变量（不许读 text/contentStarted/流式态）
    func testA1PlaceholderHeightHasNoContentInputs() throws {
        let composer = try source(
            "Sources/OneDayApp/ChatNativeRowHeight.swift"
        )
        let seg = try segment(
            composer,
            from: "var livePlaceholderHeight",
            to: "// MARK: - 条目行"
        )
        XCTAssertTrue(
            seg.contains("spec(.callout)"),
            "占位行高公式应为状态文案行高＋定数内距"
        )
        for forbidden in [
            "contentStarted", "streaming", "String",
            "liveText", "reasoning",
        ] {
            XCTAssertFalse(
                seg.contains(forbidden),
                "占位行高公式含内容/阶段输入 \(forbidden)（生成期高变源）"
            )
        }
    }

    // MARK: - A2 落定单拍

    /// 占位行在飞判定与落定清旗同源：nativeRows 的
    /// 在飞判定读 sendTask/activeRunThreadID；落定
    /// 收尾（finishRunPresentation）清 activeRun-
    /// ThreadID 与 streamingText——占位消失与落定
    /// 条目入列在同一收尾拍内、无帧共存
    func testA2PlaceholderPresenceAndSettleShareInFlightFlag() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try source("Sources/OneDayApp/ChatView.swift")
        let sendChat = try source("Sources/OneDayApp/ChatView+SendAndOutbox.swift")
        let overlaysChat = try source("Sources/OneDayApp/ChatView+OverlaysAndModifiers.swift")
        let chatView = mainChat + "\n" + sendChat + "\n" + overlaysChat
        XCTAssertTrue(
            chatView.contains(
                "if sendTask != nil || activeRunThreadID != nil {"
            ),
            "占位在飞判定未按 sendTask∨activeRunThreadID 单源"
        )
        let finish = try segment(
            chatView,
            from: "private func finishRunPresentation",
            to: "private func requestRunStop"
        )
        XCTAssertTrue(
            finish.contains("streamingText = nil"),
            "落定收尾未清在飞旗 streamingText"
        )
        XCTAssertTrue(
            finish.contains("activeRunThreadID = nil"),
            "落定收尾未清在飞线程旗（占位会残留）"
        )
        // 占位行键全仓单点（占位行只许一处构造）
        XCTAssertEqual(
            chatView.components(separatedBy: "\"live-placeholder\"")
                .count - 1,
            1,
            "live-placeholder 键须单点构造"
        )
    }

    // MARK: - A3 半截落盘保真

    /// persist→resume 同构往返：装配器在任意事件
    /// 拍的快照（封存段＋打开段＋思考全文）经「按
    /// 段成条落盘→按条目序重建」后，fullSegments/
    /// mergedFullText/思考全文逐字同；恢复后续喂
    /// 增量只入打开段、封存段不双份不回流
    func testA3PersistResumeRoundTripIsByteExact() {
        var assembler = StreamSegmentAssembler()
        var reasoning = StreamPublishGate()
        reasoning.offer("已思考部分")
        assembler.offer("第一段正文")
        assembler.sealCurrentSegment()
        assembler.offer("第二段半截")
        // 落盘形态：段按序成条（persistRunPartials
        // 的 fullSegments 直读），思考走 fullText
        let persistedSegments = assembler.fullSegments
        let persistedReasoning = reasoning.fullText
        let mergedBefore = assembler.mergedFullText
        // 重建形态（resumeRunIfNeeded 同构）：末段
        // 为打开段、其余为封存段
        var restored = StreamSegmentAssembler()
        restored.restore(
            sealed: Array(persistedSegments.dropLast()),
            current: persistedSegments.last ?? ""
        )
        var restoredReasoning = StreamPublishGate()
        restoredReasoning.offer(persistedReasoning)
        XCTAssertEqual(restored.fullSegments, persistedSegments)
        XCTAssertEqual(restored.mergedFullText, mergedBefore)
        XCTAssertEqual(restoredReasoning.fullText, persistedReasoning)
        // 续增量只入打开段
        restored.offer("续写")
        XCTAssertEqual(
            restored.fullSegments,
            ["第一段正文", "第二段半截续写"]
        )
        XCTAssertEqual(restored.sealedSegments, ["第一段正文"])
    }

    // MARK: - A4 锚定

    /// 跟随通则单源：条目数变化口在场（在底＋条目
    /// 变→无动画贴底）；流式跟随件（节流闸/结算挂
    /// 账/settleStreamFollow）在 ChatView 与 Core
    /// 零残留
    func testA4FollowReducedToEntryCountRule() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try source("Sources/OneDayApp/ChatView.swift")
        let overlaysChat = try source("Sources/OneDayApp/ChatView+OverlaysAndModifiers.swift")
        let chatView = mainChat + "\n" + overlaysChat
        let seg = try segment(
            chatView,
            from: ".onChange(of: currentThread?.sortedEntries.count)",
            to: ".onChange(of: sendPinToken)"
        )
        XCTAssertTrue(seg.contains("applyBottomProximity("))
        XCTAssertTrue(seg.contains("if isNearBottom {"))
        XCTAssertTrue(seg.contains("scrollToBottom(animated: false)"))
        for retired in [
            "StreamFollowGate", "settleStreamFollow",
            "streamFollowGate", "streamFollowPending",
        ] {
            XCTAssertFalse(
                chatView.contains(retired),
                "流式跟随件 \(retired) 在 ChatView 有残留"
            )
        }
        let bottomFollow = try source(
            "Sources/OneDayCore/BottomFollow.swift"
        )
        XCTAssertFalse(
            bottomFollow.contains("StreamFollowGate"),
            "StreamFollowGate 在 Core 有残留"
        )
    }
}
