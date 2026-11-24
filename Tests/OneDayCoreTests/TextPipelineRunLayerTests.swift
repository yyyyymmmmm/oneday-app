import XCTest
@testable import OneDayCore

/// §271（第 72 条文本管线根治）：整形后移 run 层
/// 的回归钉。病根（第 74 条定因）：旧序「先整形、
/// 后解析」把 U+2060 插在解析前的原文里，段尾闭
/// 合定界符对／链接目标／代码闭合反引号／数字串
/// 都可能被从中劈开（§247 文本层守卫只堵同字对
/// 一孔）。本套钉死 run 层口径：解析先行、整形只
/// 落普通文本 run 的字间、代码与数字串豁免；装配
/// 真值断言（成对定界符完整性）与表格呈现口径
/// （列宽封顶／>4 列降级）同包钉死。
final class TextPipelineRunLayerTests: XCTestCase {

    private func proseRuns(for text: String) -> [InlineRun] {
        let segments = MarkdownMessageAssembler.segments(for: text)
        guard segments.count == 1,
              case .prose(let paragraphs) = segments[0] else {
            XCTFail("样本应装配为单一 prose 段：\(segments)")
            return []
        }
        return paragraphs.flatMap(\.runs)
    }

    private func visible(_ runs: [InlineRun]) -> String {
        runs.map(\.text).joined().replacingOccurrences(
            of: TextShaping.wordJoiner, with: ""
        )
    }

    // MARK: - shapeRuns 本体（台账 200 件四退役：恒原文直入）

    func testShapeRunsReturnsRunsVerbatim() {
        // 台账 200 件四：整形退役——run 文本恒原样，
        // 不再插入 U+2060（旧断言「尾部绑定」作废）
        let shaped = TextShaping.shapeRuns(
            InlineRunBuilder.plainRuns("服务器一切正常")
        )
        XCTAssertEqual(shaped.map(\.text).joined(), "服务器一切正常")
        let punct = TextShaping.shapeRuns(
            InlineRunBuilder.plainRuns("已经处理完了。")
        )
        XCTAssertEqual(
            punct.map(\.text).joined(), "已经处理完了。"
        )
    }

    func testShapeRunsAppliesPerLine() {
        // 台账 200 件四：多行同理恒原样返回
        let shaped = TextShaping.shapeRuns(
            InlineRunBuilder.plainRuns("第一行文字\n第二行")
        )
        XCTAssertEqual(
            shaped.map(\.text).joined(),
            "第一行文字\n第二行"
        )
    }

    // MARK: - 数字串豁免（第 72 条④，T4 探针同根）

    func testShapeRunsNeverSplitsDigitRuns() {
        // 电话在行尾：旧文本层整形把连接符插进末两
        // 位数字之间（探针实见 1380013800⁠0），检测
        // 令牌断裂；run 层口径下整行数字串逐字不动
        let phone = TextShaping.shapeRuns(
            InlineRunBuilder.plainRuns("有问题打我电话 13800138000")
        )
        XCTAssertEqual(
            phone.map(\.text).joined(), "有问题打我电话 13800138000"
        )
        // 时间同面（探针实见 13:0⁠0）
        let time = TextShaping.shapeRuns(
            InlineRunBuilder.plainRuns("开始时间 13:00")
        )
        XCTAssertEqual(time.map(\.text).joined(), "开始时间 13:00")
    }

    func testAssembledPhoneNumberStaysIntact() {
        let runs = proseRuns(for: "有问题打我电话 13800138000")
        XCTAssertTrue(
            runs.map(\.text).joined().contains("13800138000"),
            "装配后电话号码被整形符劈开：\(runs)"
        )
    }

    // MARK: - 代码 run 保真

    func testInlineCodeAtTailStaysPristine() {
        // 旧文本层整形把连接符插进闭合反引号内侧、
        // 代码 run 文本带符；run 层口径下代码逐字
        let runs = proseRuns(for: "配置文件是 `config.yaml`")
        let codeRuns = runs.filter(\.code)
        XCTAssertEqual(codeRuns.count, 1)
        XCTAssertEqual(codeRuns.first?.text, "config.yaml")
        XCTAssertEqual(visible(runs), "配置文件是 config.yaml")
    }

    // MARK: - 链接目标不被整形污染

    func testLinkAtTailKeepsCleanURL() {
        // 段尾链接：旧整形按句末标点口径绑 3 字形、
        // 连接符正落进 URL 目标文本里；run 层口径
        // 下 URL 属性逐字干净
        let runs = proseRuns(
            for: "详情参见[官方文档](https://example.com/guide)"
        )
        let linkRuns = runs.filter { $0.link != nil }
        XCTAssertEqual(linkRuns.count, 1)
        XCTAssertEqual(
            linkRuns.first?.link?.absoluteString,
            "https://example.com/guide"
        )
        XCTAssertEqual(visible(runs), "详情参见官方文档")
    }

    // MARK: - 定界符完整性（已完成消息路）

    func testBoldBeforeClosingPunctuationParses() {
        let runs = proseRuns(for: "这是**设备能力**。")
        XCTAssertTrue(
            runs.contains {
                $0.strong && visible([$0]) == "设备能力"
            },
            "粗体段未成 strong run：\(runs)"
        )
        XCTAssertEqual(visible(runs), "这是设备能力。")
    }

    func testStrikethroughAtTailParses() {
        let runs = proseRuns(for: "结论是~~旧方案~~")
        XCTAssertTrue(
            runs.contains {
                $0.strikethrough && visible([$0]) == "旧方案"
            },
            "删除线段未成 strikethrough run：\(runs)"
        )
        XCTAssertEqual(visible(runs), "结论是旧方案")
    }

    func testUnclosedDelimiterStaysLiteralByDesign() {
        // 未闭合标记字面呈现是既定降级口径（模型把
        // ** 当小标题左饰的形态），装配不改字、断
        // 言不报违规
        let source = "这是**没闭合的小标题"
        let runs = proseRuns(for: source)
        XCTAssertEqual(visible(runs), source)
        XCTAssertTrue(
            MarkdownDelimiterAudit.violations(
                source: source, runs: runs
            ).isEmpty
        )
    }

    // MARK: - 真值断言本体

    func testAuditCatchesLiteralPairedDelimiters() {
        // 人造坏装配：成对 ** 原样字面进 runs
        let broken = [InlineRun(text: "**标题**")]
        XCTAssertFalse(
            MarkdownDelimiterAudit.violations(
                source: "**标题**", runs: broken
            ).isEmpty
        )
        let brokenStrike = [InlineRun(text: "结论~~旧方案~~")]
        XCTAssertFalse(
            MarkdownDelimiterAudit.violations(
                source: "结论~~旧方案~~", runs: brokenStrike
            ).isEmpty
        )
        let brokenCode = [InlineRun(text: "运行 `ls` 看看")]
        XCTAssertFalse(
            MarkdownDelimiterAudit.violations(
                source: "运行 `ls` 看看", runs: brokenCode
            ).isEmpty
        )
    }

    func testAuditPassesOnAssembledFixtureExcerpts() {
        // fixture（用户 2026-11-14 粘贴长文）的关
        // 键构造逐段过断言：粗体／代码／链接／删除
        // 线／纯文本标题行混排
        let excerpts = [
            "它暴露的 53 个工具（camera_capture、compose_sms、contacts_search 等），任何支持 MCP 的 AI Agent 都能调",
            "答案是能——不是模拟点击，是真的调 iOS Camera API 和 Message Composer API。",
            "一、它解决了一个长期死锁",
            "写操作必确认：发短信、发邮件、拍照，全是\"预填 → 你确认 → 系统执行\"",
            "详见[官方文档](https://example.com/docs)与 `config.yaml` 配置，~~旧入口~~已下线",
        ]
        for excerpt in excerpts {
            let runs = proseRuns(for: excerpt)
            XCTAssertTrue(
                MarkdownDelimiterAudit.violations(
                    source: excerpt, runs: runs
                ).isEmpty,
                "断言误报：\(excerpt)"
            )
        }
    }

    func testAuditIgnoresDelimitersInsideCodeSpan() {
        // 代码段内的 ** 是字面内容、不参与配对
        let source = "字面量 `**not bold**` 照原样"
        let runs = proseRuns(for: source)
        XCTAssertTrue(
            runs.contains { $0.code && $0.text == "**not bold**" }
        )
        XCTAssertTrue(
            MarkdownDelimiterAudit.violations(
                source: source, runs: runs
            ).isEmpty
        )
    }

    // MARK: - 表格呈现口径

    func testTableModeThreshold() {
        XCTAssertEqual(
            MarkdownTablePresentation.mode(columnCount: 3), .grid
        )
        XCTAssertEqual(
            MarkdownTablePresentation.mode(columnCount: 4), .grid
        )
        XCTAssertEqual(
            MarkdownTablePresentation.mode(columnCount: 5), .list
        )
    }

    func testTableListEntriesPairHeaderAndValues() {
        let entries = MarkdownTablePresentation.listEntries(
            header: ["方案", "能力", "友好度"],
            rows: [
                ["OneDay", "设备能力 + MCP", "✓ 开放"],
                ["快捷指令", "只能在设备上跑"],
            ]
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(
            entries[0][1],
            MarkdownTablePresentation.ListEntry(
                label: "能力", value: "设备能力 + MCP"
            )
        )
        // 行短于表头：缺位补空串、不造数据
        XCTAssertEqual(entries[1][2].value, "")
    }

    func testFixtureTableAssemblesAsGridTable() {
        // fixture 的 3 列长文表：装配仍为表格段、
        // 呈现口径为 Grid（列宽封顶折行由视图层按
        // Core maxColumnWidth 落）
        let table = """
            | 方案 | 能力 | 极客友好度 |
            |------|------|-----------|
            | iOS 快捷指令 | 只能在设备上跑，不能远程调用 | ✗ 封闭生态 |
            | OneDay | iOS 设备能力 + MCP 开放协议 + 可自建 Agent | ✓ 开放、可控、可扩展 |
            """
        let segments = MarkdownMessageAssembler.segments(for: table)
        guard segments.count == 1,
              case .table(let header, _, let rows) = segments[0]
        else {
            XCTFail("fixture 表格应装配为单一 table 段：\(segments)")
            return
        }
        XCTAssertEqual(header.count, 3)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(
            MarkdownTablePresentation.mode(
                columnCount: header.count
            ),
            .grid
        )
        XCTAssertGreaterThan(MarkdownTablePresentation.maxColumnWidth, 0)
    }
}
