import XCTest
@testable import OneDayCore

/// §247 包 4 追加验收（2026-11-14 23:07 主线急报
/// 并入）：流式装配逐字保真回归。背景：用户截图
/// 标题行尾闭合 ** 丢失，服务端取证定案原文完
/// 整（messages.id=4539、落库正本与接口出参
/// sha256 逐字节一致，format-display-server-
/// original-20261114.md），丢字在 App 侧。本套
/// 两层钉死：
/// 1) 数据装配层——分片序列把闭合 ** 切成独立
///    小 delta（故障形态签名）喂发布闸，按视图
///    侧真实节拍（offer＋40ms ticker collectDue
///    ＋收尾 flush）装配，全文与原文逐字节一致、
///    任一中间快照恒为原文前缀；
/// 2) 呈现装配层——落定/流式共用的装配链（块
///    解析→段落整形→行内解析）对完整原文的标
///    题行须产出 strong run 且可见文本无字面 **
///    残留（整形劈定界符的回归面）
final class StreamingAssemblyFidelityTests: XCTestCase {

    // MARK: - 1) 发布闸装配逐字保真

    func testGateAssemblyIsByteExactWithTinyClosingDeltas() {
        // 分片即原文的构造源：闭合 ** 恒为独立
        // 小 delta、空行恒为独立小 delta——故障
        // 形态签名的分片序列
        let parts: [String] = [
            "好，把剩下的优势掰开说。", "\n\n",
            "**", "Muse 的剩余优势", "**", "\n\n",
            "**", "一，持久性和自主性更彻底", "**", "\n\n",
            "正文一段，带行内", "**", "重点", "**", "继续。", "\n\n",
            "**", "二，安全和审批机制更成熟", "**", "\n\n",
            "收尾段落。",
        ]
        let original = parts.joined()
        var gate = StreamPublishGate()
        var now: TimeInterval = 0
        var lastSnapshot = ""
        for (index, delta) in parts.enumerated() {
            now += 0.01
            if let snapshot = gate.offer(delta, at: now) {
                lastSnapshot = snapshot
            }
            // 视图侧 40ms ticker 的 collectDue 节拍
            if index % 4 == 3,
               let snapshot = gate.collectDue(at: now + 0.04) {
                lastSnapshot = snapshot
            }
            // 任一时刻：已发布快照恒为原文前缀、
            // 闸内全文恒等于已喂入分片的精确拼接
            XCTAssertTrue(
                original.hasPrefix(lastSnapshot),
                "中间快照不是原文前缀（装配丢/造字）")
            XCTAssertEqual(
                gate.fullText,
                parts[...index].joined(),
                "闸内全文与已喂分片不一致")
        }
        if let snapshot = gate.flush(at: now + 1) {
            lastSnapshot = snapshot
        }
        // 逐字节一致（utf8 序列直比，不走规范等价）
        XCTAssertEqual(
            Array(gate.fullText.utf8), Array(original.utf8))
        XCTAssertEqual(
            Array(lastSnapshot.utf8), Array(original.utf8))
    }

    // MARK: - 2) 呈现装配层保真

    /// 装配链可见文本：prose 段全部 run 拼字（剥
    /// U+2060 整形符后比对——整形符是排版绑定、
    /// 非内容字）
    private func assembledRuns(
        for text: String
    ) -> [InlineRun] {
        let segments = MarkdownMessageAssembler.segments(
            from: MarkdownParser.parse(text)
        )
        guard segments.count == 1,
              case .prose(let paragraphs) = segments[0] else {
            XCTFail("样本应装配为单一 prose 段：\(segments)")
            return []
        }
        return paragraphs.flatMap(\.runs)
    }

    func testSettledAssemblyKeepsClosingBoldDelimiters() {
        // 取证正本的标题行形态（standalone 粗体行
        // ＝段落）：闭合 ** 在段尾，装配后须成
        // strong、可见文本无字面 ** 残留
        for heading in [
            "Muse 的剩余优势",
            "一，持久性和自主性更彻底",
            "二，安全和审批机制更成熟",
        ] {
            let runs = assembledRuns(for: "**\(heading)**")
            let visible = runs.map(\.text).joined()
                .replacingOccurrences(
                    of: TextShaping.wordJoiner, with: "")
            XCTAssertEqual(
                visible, heading,
                "标题行可见文本被装配改动：\(visible)")
            XCTAssertTrue(
                runs.contains {
                    $0.strong
                        && $0.text.replacingOccurrences(
                            of: TextShaping.wordJoiner,
                            with: "") == heading
                },
                "标题行未产出完整 strong run：\(runs)")
        }
        // 对照：粗体不在段尾的常规段恒绿（防修法
        // 误伤正常段）
        let control = assembledRuns(for: "这是**重点**部分")
        XCTAssertTrue(control.contains { $0.strong && $0.text == "重点" })
    }

    // MARK: - 3) 整形守卫本体

    func testPrettyWrapNeverSplitsTrailingDelimiterPair() {
        // 段尾闭合对：连接符不许落在 ** 之间
        let shaped = TextShaping.prettyWrap("**标题在此**")
        XCTAssertFalse(
            shaped.contains("*\u{2060}*"),
            "整形劈开了段尾闭合 ** 对：\(shaped)")
        XCTAssertTrue(shaped.hasSuffix("**"))
        // 删除线同面
        let strike = TextShaping.prettyWrap("这段~~删除~~")
        XCTAssertFalse(strike.contains("~\u{2060}~"))
        // 常规段整形不误伤：尾部绑定照常发生
        let plain = TextShaping.prettyWrap("普通段落文字")
        XCTAssertTrue(plain.contains(TextShaping.wordJoiner))
    }
}
