import SwiftUI
import XCTest
@testable import OneDayApp

/// 第 82 条钉测：流式尾块叠字修复（定因
/// gen4-stream-overlap-diagnosis-20261115——动画作用
/// 域泄漏：.animation(streamIn, value:) 挂在被
/// TokenFlow 落位的词元视图整体上，换行边界词元的
/// 原点翻动被 120ms easeOut 插值成纵向滑移）。
///
/// 三组断言：
/// ① 动画作用域（源码守护，与 ChatCarrierEdgeEffect-
/// Tests 同式：截取有限片段、去注释后核结构）——被
/// 落位的视图（StreamingTokenView）自身不挂动画修饰，
/// 入场动画只许出现在其内部视觉层、且只以 shown 为
/// 值；旧形态（动画直挂 ForEach 词元链）两条皆红。
/// 第 104 条续订：入场只许 opacity（blur 已退役）、
/// 调度层不许再有逐词元错开机器（整批计划单点）。
/// ② TokenFlowArranger 缓存语义（纯值引擎）——纯追
/// 加命中前缀复用、宽度变/前缀尺寸变失效重排；任何
/// 增量路径的排版结果必须与无缓存整表排版逐点相等
/// （不许陈旧排版）。
/// ③ 打字动画开关落位（第 104 条）：外观页「回复
/// 呈现」节持有、键走 Core 单一事实源。
final class StreamingTokenScopeTests: XCTestCase {

    // MARK: - ① 动画作用域源码守护

    private func streamingTextSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot.appendingPathComponent(
            "Sources/OneDayApp/StreamingText.swift"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 被 TokenFlow 落位的那一层（ForEach 词元链）不许
    /// 出现 .animation( ——落位视图带动画修饰即第 82 条
    /// 病根形态，位置变更会被动画事务接管
    func testPlacedTokenLayerCarriesNoAnimationModifier() throws {
        let raw = try streamingTextSource()
        let flowRange = try XCTUnwrap(
            raw.range(of: "TokenFlow(spacing:")
        )
        // 片段严格截在 TokenFlow 收尾（.accessibilityElement
        // 是其后第一个修饰）——不许用定长前缀，否则会够到
        // StreamingTokenView 本体内部的合法 .animation( 假红
        let tail = raw[flowRange.lowerBound...]
        let endRange = try XCTUnwrap(
            tail.range(of: ".accessibilityElement")
        )
        let segment = String(tail[..<endRange.lowerBound])
        let code = Self.stripComments(segment)
        XCTAssertTrue(
            code.contains("StreamingTokenView("),
            "TokenFlow 的词元子视图必须是 StreamingTokenView"
        )
        XCTAssertTrue(
            code.contains("StreamingCaret()"),
            "片段应覆盖 TokenFlow 全部子视图（守护范围自检）"
        )
        XCTAssertFalse(
            code.contains(".animation("),
            "被落位的词元层不许挂 .animation 修饰（第 82 条病根）"
        )
    }

    /// 入场动画只许活在 StreamingTokenView 内部视觉层：
    /// opacity 与 .animation(streamIn, value: shown)
    /// 同处一层，值只许是 shown（浓淡），不许掺入任何
    /// 与位置/序号挂钩的量。第 104 条：blur 已随逐词
    /// 元错开一并退役——视觉层不许再出现 .blur(
    func testEntranceAnimationConfinedToTokenVisualLayer() throws {
        let raw = try streamingTextSource()
        let typeRange = try XCTUnwrap(
            raw.range(of: "struct StreamingTokenView")
        )
        let segment = String(
            raw[typeRange.lowerBound...].prefix(3_000)
        )
        let code = Self.stripComments(segment)
        XCTAssertFalse(
            code.contains(".blur("),
            "第 104 条：入场 blur 已退役，视觉层不许再挂 .blur("
        )
        XCTAssertTrue(code.contains(".opacity("), "视觉层应承载 opacity")
        XCTAssertTrue(
            code.contains(".animation("),
            "入场动画应收在视觉层内部"
        )
        XCTAssertTrue(
            code.contains("MotionTokens.streamIn"),
            "入场动画仍走 MotionTokens.streamIn 定版档"
        )
        XCTAssertTrue(
            code.contains("value: shown"),
            "动画值只许是 shown（入场浓淡），位置永不进动画事务"
        )
    }

    /// 第 104 条：入场调度不许再有逐词元错开机器——
    /// reconcile 只许按 Core 入场计划整批显形：文件
    /// 内不许出现延时排程（Task.sleep）、不许出现旧
    /// 退化档记账（noBlur）；计划入口与打字动画键的
    /// 消费必须在场
    func testEntranceSchedulingHasNoStaggerMachinery() throws {
        let code = Self.stripComments(try streamingTextSource())
        XCTAssertFalse(
            code.contains("Task.sleep"),
            "逐词元错开的延时排程已退役"
        )
        XCTAssertFalse(
            code.contains("noBlur"),
            "大批量退化档记账已退役"
        )
        XCTAssertTrue(
            code.contains("StreamingEntrance.plan("),
            "入场必须经 Core 计划单点裁定"
        )
        XCTAssertTrue(
            code.contains("StreamingTypewriterFeature.defaultsKey"),
            "打字动画开关必须以 Core 键消费"
        )
    }

    /// §503 改判：第 104 条的打字动画开关随「回复
    /// 呈现」整节退役——外观页不再有该节与两开关
    /// 写口；聊天页入场计划恒传 true（定死常开），
    /// 流式回滚开关（ChatStreamingFeature）在
    /// ChatView 与 Core 均不存在
    func testTypewriterSwitchRetired503() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appearanceURL = root
            .appendingPathComponent(
                "Sources/OneDayApp/AppearanceView.swift")
        let appearance = Self.stripComments(
            try String(contentsOf: appearanceURL, encoding: .utf8))
        XCTAssertFalse(appearance.contains("replyPresentationSection"))
        XCTAssertFalse(appearance.contains("StreamingTypewriterFeature"))
        XCTAssertFalse(appearance.contains("ChatStreamingFeature"))
        XCTAssertFalse(appearance.contains("打字动画"))
        let chatURL = root
            .appendingPathComponent(
                "Sources/OneDayApp/ChatView.swift")
        let chat = Self.stripComments(
            try String(contentsOf: chatURL, encoding: .utf8))
        XCTAssertFalse(chat.contains("ChatStreamingFeature"))
        XCTAssertTrue(chat.contains("typewriterEnabled: true"))
        let streaming = Self.stripComments(try streamingTextSource())
        XCTAssertFalse(
            streaming.contains("\"chat.streaming.typewriter\""),
            "键名字面量只许出现在 Core 定义处"
        )
    }

    // MARK: - ② 排版引擎缓存语义

    /// 词元统一 10×21（行高 21 与诊断帧证据同值），
    /// 末位是光标替身：尺寸恒定、位置随追加移位
    private func token(_ width: CGFloat = 10) -> CGSize {
        CGSize(width: width, height: 21)
    }
    private var caret: CGSize { CGSize(width: 9, height: 16) }

    private func fresh(
        _ sizes: [CGSize], width: CGFloat, spacing: CGFloat = 5
    ) -> (size: CGSize, origins: [CGPoint]) {
        var arranger = TokenFlowArranger()
        return arranger.arrange(
            sizes: sizes, width: width, spacing: spacing
        )
    }

    /// 命中：纯追加（新词元插在光标之前）时词元前缀
    /// 原点逐点复用、续排起点恰在分界处，且结果与无
    /// 缓存整表排版逐点相等
    func testAppendOnlyGrowthReusesPrefixOrigins() {
        var arranger = TokenFlowArranger()
        let first = [token(), token(), token(), token(), token(), caret]
        let firstResult = arranger.arrange(
            sizes: first, width: 45, spacing: 5
        )
        XCTAssertEqual(arranger.lastResumeIndex, 0)

        var second = first
        second.insert(contentsOf: [token(), token()], at: 5)
        let secondResult = arranger.arrange(
            sizes: second, width: 45, spacing: 5
        )
        XCTAssertEqual(
            arranger.lastResumeIndex, 5,
            "续排起点应在词元前缀与光标替身的分界（5）"
        )
        XCTAssertEqual(
            Array(secondResult.origins.prefix(5)),
            Array(firstResult.origins.prefix(5)),
            "已排词元原点必须逐点复用、不许翻动"
        )
        let expected = fresh(second, width: 45)
        XCTAssertEqual(secondResult.origins, expected.origins)
        XCTAssertEqual(secondResult.size, expected.size)
    }

    /// 命中：序列全等时整表复用（续排起点＝全长）
    func testIdenticalSequenceFullyReused() {
        var arranger = TokenFlowArranger()
        let sizes = [token(), token(24), token(), caret]
        _ = arranger.arrange(sizes: sizes, width: 45, spacing: 5)
        let again = arranger.arrange(
            sizes: sizes, width: 45, spacing: 5
        )
        XCTAssertEqual(arranger.lastResumeIndex, sizes.count)
        XCTAssertEqual(again.origins, fresh(sizes, width: 45).origins)
    }

    /// 失效：行宽变 → 自首词元整表重排，结果与无缓存
    /// 排版逐点相等
    func testWidthChangeInvalidatesCache() {
        var arranger = TokenFlowArranger()
        let sizes = [token(), token(), token(), token(), caret]
        _ = arranger.arrange(sizes: sizes, width: 100, spacing: 5)
        let narrowed = arranger.arrange(
            sizes: sizes, width: 30, spacing: 5
        )
        XCTAssertEqual(
            arranger.lastResumeIndex, 0,
            "行宽变必须整表重排、不许复用旧行宽的原点"
        )
        let expected = fresh(sizes, width: 30)
        XCTAssertEqual(narrowed.origins, expected.origins)
        XCTAssertEqual(narrowed.size, expected.size)
    }

    /// 失效：前缀内部尺寸变（拉丁词元合并变宽）→ 自
    /// 首个不一致处续排，其前原点复用、其后按新尺寸
    /// 重排，结果与无缓存排版逐点相等
    func testPrefixSizeChangeResumesAtDivergence() {
        var arranger = TokenFlowArranger()
        let before = [token(), token(), token(), caret]
        let beforeResult = arranger.arrange(
            sizes: before, width: 45, spacing: 5
        )
        let after = [token(), token(26), token(), caret]
        let afterResult = arranger.arrange(
            sizes: after, width: 45, spacing: 5
        )
        XCTAssertEqual(
            arranger.lastResumeIndex, 1,
            "应在首个尺寸不一致处（序号 1）续排"
        )
        XCTAssertEqual(
            afterResult.origins.first, beforeResult.origins.first,
            "不一致处之前的原点仍逐点复用"
        )
        let expected = fresh(after, width: 45)
        XCTAssertEqual(afterResult.origins, expected.origins)
        XCTAssertEqual(afterResult.size, expected.size)
    }

    /// 全程等价：模拟一轮真实流式（逐拍追加＋中途一
    /// 次词元合并变宽＋光标替身全程垫尾），每拍结果都
    /// 与无缓存整表排版逐点相等——缓存永不给陈旧排版
    func testIncrementalStreamMatchesSingleShotEveryBeat() {
        var arranger = TokenFlowArranger()
        var sizes: [CGSize] = [caret]
        let beats: [[CGSize]] = [
            [token()],
            [token(), token()],
            [token(), token(), token(), token()],
            // 拉丁合并：第 2 词元由 10 变 34（词长成形）
            [token(), token(34), token(), token()],
            [token(), token(34), token(), token(), token(), token()],
        ]
        for beat in beats {
            sizes = beat + [caret]
            let incremental = arranger.arrange(
                sizes: sizes, width: 45, spacing: 5
            )
            let expected = fresh(sizes, width: 45)
            XCTAssertEqual(
                incremental.origins, expected.origins,
                "增量排版与整表排版不一致（拍：\(sizes.count) 元）"
            )
            XCTAssertEqual(incremental.size, expected.size)
        }
    }

    // MARK: - 源码守护工具（与 ChatCarrierEdgeEffectTests 同式）

    private static func stripComments(_ source: String) -> String {
        var result = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false
        var escaped = false

        func peekNext() -> Character? {
            let next = source.index(after: index)
            guard next < source.endIndex else { return nil }
            return source[next]
        }

        while index < source.endIndex {
            let character = source[index]
            let next = peekNext()
            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    result.append(character)
                }
                index = source.index(after: index)
                continue
            }
            if inBlockComment {
                if character == "*", next == "/" {
                    inBlockComment = false
                    index = source.index(index, offsetBy: 2)
                    continue
                }
                index = source.index(after: index)
                continue
            }
            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = source.index(after: index)
                continue
            }
            if character == "/", next == "/" {
                inLineComment = true
                index = source.index(index, offsetBy: 2)
                continue
            }
            if character == "/", next == "*" {
                inBlockComment = true
                index = source.index(index, offsetBy: 2)
                continue
            }
            if character == "\"" {
                inString = true
            }
            result.append(character)
            index = source.index(after: index)
        }
        return result
    }
}
