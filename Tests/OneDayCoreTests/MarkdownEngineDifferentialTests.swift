import XCTest
@testable import OneDayCore

/// §417（#13 Markdown 换底）差分语料套：新旧双核
/// 对同一语料集的块产物与 runs 产物逐项比对。
/// 放行口径：差异只许出现在签收表登记的条目上
///（signedBlockDiffIDs／signedRunDiffIDs），未登
/// 记差异＝红；每次运行把全量差分报告附到测试结果。
/// 签收表正本见
/// oneday-design-review/md-swap-diff-signoff-
/// 20261123.md。语料构成：现行三套钉测＋行内套
/// 的全部 fixture、边角集、Hermes 风格真实文档、
/// 程序生成变体与一篇 ≥20KB 长文，合计 ≥100 篇
final class MarkdownEngineDifferentialTests: XCTestCase {

    // MARK: - 签收表（差分三分类后登记，逐条对应签收表 D 编号）

    /// 块级允许差异的语料 id（分类见签收表）
    private let signedBlockDiffIDs: Set<String> = [
        "edge-tilde-fence",
        "edge-indented-code",
        "edge-ref-link-def",
        "edge-list-multipara",
        "edge-list-item-code",
        "edge-quote-lazy",
        "edge-hardbreak-spaces",
        "edge-hardbreak-backslash",
        "edge-entity",
        "edge-angle-autolink",
    ]

    /// 行内允许差异的语料 id（分类见签收表）
    private let signedRunDiffIDs: Set<String> = [
        "inl-image-empty-alt",
        "inl-strong-in-link",
        "inl-hardbreak",
    ]

    // MARK: - 引擎分派

    private func withEngine<T>(
        legacy: Bool, _ body: () -> T
    ) -> T {
        let previous = MarkdownEngine.usesLegacyParser
        MarkdownEngine.usesLegacyParser = legacy
        defer { MarkdownEngine.usesLegacyParser = previous }
        return body()
    }

    // MARK: - 块级差分

    func testBlockDifferentialCorpus() {
        XCTAssertGreaterThanOrEqual(
            Self.blockCorpus.count, 100,
            "语料须 ≥100 篇，实际 \(Self.blockCorpus.count)"
        )
        var report = "# §417 块级差分报告（count=\(Self.blockCorpus.count)）\n"
        var unsigned: [String] = []
        for entry in Self.blockCorpus {
            let legacy = withEngine(legacy: true) {
                MarkdownParser.parse(entry.source)
            }
            let current = withEngine(legacy: false) {
                MarkdownParser.parse(entry.source)
            }
            let legacyText = Self.describe(legacy)
            let currentText = Self.describe(current)
            if legacyText != currentText {
                let signed = signedBlockDiffIDs.contains(entry.id)
                report += """

                ## \(entry.id) [\(signed ? "已签收" : "未签收")]
                --- 旧核 ---
                \(legacyText)
                --- 新核 ---
                \(currentText)

                """
                if !signed { unsigned.append(entry.id) }
            }
        }
        attachReport(report, name: "mdswap-diff-blocks.txt")
        XCTAssertTrue(
            unsigned.isEmpty,
            "未签收的块级差异：\(unsigned)"
        )
    }

    // MARK: - 行内差分

    func testInlineDifferentialCorpus() {
        var report = "# §417 行内差分报告（count=\(Self.inlineCorpus.count)）\n"
        var unsigned: [String] = []
        for entry in Self.inlineCorpus {
            let legacy = withEngine(legacy: true) {
                InlineRunBuilder.runs(for: entry.source)
            }
            let current = withEngine(legacy: false) {
                InlineRunBuilder.runs(for: entry.source)
            }
            let legacyText = Self.describe(legacy)
            let currentText = Self.describe(current)
            if legacyText != currentText {
                let signed = signedRunDiffIDs.contains(entry.id)
                report += """

                ## \(entry.id) [\(signed ? "已签收" : "未签收")]
                源：\(entry.source)
                --- 旧核 ---
                \(legacyText)
                --- 新核 ---
                \(currentText)

                """
                if !signed { unsigned.append(entry.id) }
            }
        }
        attachReport(report, name: "mdswap-diff-runs.txt")
        XCTAssertTrue(
            unsigned.isEmpty,
            "未签收的行内差异：\(unsigned)"
        )
    }

    // MARK: - 性能门

    /// 全链（parse＋装配 segments，含 runs 与整形）
    /// 中位耗时：新核不劣于旧核 110%（施工图放行
    /// 口径）。每轮清备忘后整语料跑一遍、取 5 轮
    /// 中位；备忘稳态两代同为查表、不列门。
    /// 性能语料剔除 edge-tilde-fence 一篇（双臂同
    /// 剔）：旧核在该篇上装配断言必崩（~~~ 围栏被
    /// 旧分段层当删除线吞、与审计口径冲突——旧核
    /// 既有缺陷，探针逐篇实证，见签收表五·补），
    /// 旧核全链根本跑不完、无中位可比；该篇的块
    /// 级差分覆盖不变。剔后 128 篇仍 ≥100
    func testPerformanceGate() {
        let perfCorpus = Self.blockCorpus.filter {
            $0.id != "edge-tilde-fence"
        }
        let reps = 5
        func medianChainTime(legacy: Bool) -> Double {
            var times: [Double] = []
            for _ in 0..<reps {
                MarkdownParseMemos.blocks.removeAll()
                MarkdownParseMemos.runs.removeAll()
                let start = CFAbsoluteTimeGetCurrent()
                withEngine(legacy: legacy) {
                    for entry in perfCorpus {
                        _ = MarkdownMessageAssembler.segments(
                            for: entry.source
                        )
                    }
                }
                times.append(CFAbsoluteTimeGetCurrent() - start)
            }
            return times.sorted()[reps / 2]
        }
        let legacyMedian = medianChainTime(legacy: true)
        let currentMedian = medianChainTime(legacy: false)
        print(
            "§417 性能门：旧核中位 \(legacyMedian)s、"
                + "新核中位 \(currentMedian)s、比值 "
                + "\(currentMedian / legacyMedian)"
        )
        attachReport(
            "# §417 性能门（全链中位，语料 \(perfCorpus.count) 篇×5 轮）\n"
                + "旧核 \(legacyMedian)s\n新核 \(currentMedian)s\n"
                + "比值 \(currentMedian / legacyMedian)（门限 1.10）\n",
            name: "mdswap-perf.txt"
        )
        XCTAssertLessThanOrEqual(
            currentMedian, legacyMedian * 1.10,
            "新核全链中位劣于旧核 110%：旧 \(legacyMedian)s 新 \(currentMedian)s"
        )
    }

    // MARK: - 产物规范形描述

    static func describe(_ blocks: [MarkdownBlock]) -> String {
        blocks.map { block in
            switch block {
            case .paragraph(let text):
                return "P«\(escape(text))»"
            case .heading(let text, let level):
                return "H\(level)«\(escape(text))»"
            case .code(let code, let language):
                return "CODE[\(language ?? "-")]«\(escape(code))»"
            case .blockquote(let lines):
                return "Q[" + lines.map {
                    "\($0.depth):\(escape($0.text))"
                }.joined(separator: " | ") + "]"
            case .list(let items):
                return "L[" + items.map { item in
                    let marker: String
                    switch item.marker {
                    case .bullet: marker = "•"
                    case .ordered(let n): marker = "\(n)."
                    case .task(let c): marker = c ? "[x]" : "[ ]"
                    }
                    return "\(item.level)\(marker)\(escape(item.text))"
                }.joined(separator: " | ") + "]"
            case .table(let header, let alignments, let rows):
                let align = alignments.map { alignment -> String in
                    switch alignment {
                    case .left: return "L"
                    case .center: return "C"
                    case .right: return "R"
                    }
                }.joined()
                return "T[\(align)]«"
                    + header.map { escape($0) }
                        .joined(separator: ",")
                    + "»{"
                    + rows.map {
                        $0.map { escape($0) }
                            .joined(separator: ",")
                    }.joined(separator: " / ")
                    + "}"
            case .divider:
                return "HR"
            }
        }.joined(separator: "\n")
    }

    static func describe(_ runs: [InlineRun]) -> String {
        runs.map { run in
            var flags = ""
            if run.strong { flags += "S" }
            if run.emphasis { flags += "E" }
            if run.code { flags += "C" }
            if run.strikethrough { flags += "D" }
            if let link = run.link {
                flags += "<\(link.absoluteString)>"
            }
            return "«\(escape(run.text))»\(flags)"
        }.joined(separator: " | ")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "⏎")
    }

    private func attachReport(_ report: String, name: String) {
        let attachment = XCTAttachment(string: report)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 语料条目

    struct CorpusEntry {
        let id: String
        let source: String
    }
}

// MARK: - 块级语料

extension MarkdownEngineDifferentialTests {

    static let blockCorpus: [CorpusEntry] = fixtureCorpus
        + edgeCorpus + documentCorpus + generatedCorpus

    /// 现行三套钉测的全部块级 fixture（原文照录）
    static let fixtureCorpus: [CorpusEntry] = [
        CorpusEntry(id: "fx-plain", source: "你好，世界"),
        CorpusEntry(id: "fx-multiline", source: "第一行\n第二行"),
        CorpusEntry(id: "fx-headings", source: "# 一\n## 二\n### 三\n#### 四\n##### 五\n###### 六"),
        CorpusEntry(id: "fx-heading-nospace", source: "#话题不是标题"),
        CorpusEntry(id: "fx-heading-seven", source: "####### 太深了"),
        CorpusEntry(id: "fx-heading-closing", source: "## 标题 ##"),
        CorpusEntry(id: "fx-code-lang", source: "```python\nprint(1)\n```"),
        CorpusEntry(id: "fx-code-nolang", source: "```\nplain\n```"),
        CorpusEntry(id: "fx-code-unclosed", source: "前文\n```swift\nlet a = 1"),
        CorpusEntry(id: "fx-code-verbatim", source: "```\n# 不是标题\n- 不是列表\n```"),
        CorpusEntry(id: "fx-quote-merge", source: "> 第一句\n> 第二句"),
        CorpusEntry(id: "fx-quote-nested", source: "> 外层\n>> 内层"),
        CorpusEntry(id: "fx-quote-split", source: "> 甲\n\n> 乙"),
        CorpusEntry(id: "fx-list-bullet", source: "- 苹果\n- 香蕉"),
        CorpusEntry(id: "fx-list-ordered", source: "1. 第一\n2. 第二"),
        CorpusEntry(id: "fx-list-nested", source: "- 父\n  - 子\n    - 孙"),
        CorpusEntry(id: "fx-list-task", source: "- [ ] 没做\n- [x] 做了"),
        CorpusEntry(id: "fx-list-continuation", source: "- 第一项\n  续行内容"),
        CorpusEntry(id: "fx-list-loose", source: "- 甲\n\n- 乙"),
        CorpusEntry(id: "fx-ordered-nointerrupt", source: "回顾一下\n2024. 是重要的一年"),
        CorpusEntry(id: "fx-ordered-interrupt", source: "步骤如下\n1. 先做这个"),
        CorpusEntry(id: "fx-hr-dashes", source: "---"),
        CorpusEntry(id: "fx-hr-stars", source: "***"),
        CorpusEntry(id: "fx-hr-underscores", source: "___"),
        CorpusEntry(id: "fx-hr-spaced", source: "- - -"),
        CorpusEntry(id: "fx-two-dashes", source: "--"),
        CorpusEntry(id: "fx-table-basic", source: "| 名称 | 数量 |\n| --- | ---: |\n| 苹果 | 3 |\n| 香蕉 | 5 |"),
        CorpusEntry(id: "fx-table-align", source: "| A | B | C |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |"),
        CorpusEntry(id: "fx-table-noouter", source: "A | B\n--- | ---\n1 | 2"),
        CorpusEntry(id: "fx-table-pad", source: "| A | B |\n| --- | --- |\n| 1 |\n| 1 | 2 | 3 |"),
        CorpusEntry(id: "fx-table-half", source: "| 名称 | 数量 |\n| --- |"),
        CorpusEntry(id: "fx-table-mismatch", source: "| A | B |\n| --- |"),
        CorpusEntry(id: "fx-table-escaped-pipe", source: "| A |\n| --- |\n| a \\| b |"),
        CorpusEntry(id: "fx-mixed", source: "# 标题\n正文一段。\n\n- 列表项\n\n> 引用\n\n---"),
        CorpusEntry(id: "fx-memo-probe", source: "# §167 探针标题\n\n探针正文一段，带 **粗体** 与 `代码`。\n\n- 探针甲\n- 探针乙"),
        CorpusEntry(id: "fx-memo-structure", source: "# 标题一\n\n正文一段\n\n- 甲\n- 乙\n"),
        CorpusEntry(id: "fx-assembler-merge", source: "第一段\n\n第二段"),
        CorpusEntry(id: "fx-assembler-heading", source: "前文\n\n## 小节标题\n\n后文"),
        CorpusEntry(id: "fx-assembler-list", source: "说明：\n\n- 甲\n- 乙\n  - 嵌套\n1. 第一"),
        CorpusEntry(id: "fx-assembler-inline", source: "这段有 **重点** 和 `代码` 片段"),
        CorpusEntry(id: "fx-assembler-taskdivert", source: "前文\n\n- [ ] 待办一\n- [x] 已办二\n\n后文"),
        CorpusEntry(id: "fx-assembler-mixedtask", source: "- 普通项\n- [ ] 任务项"),
        CorpusEntry(id: "fx-assembler-split", source: "前段\n\n> 引用一行\n\n```\nlet x = 1\n```\n\n| 列一 | 列二 |\n| --- | --- |\n| 甲 | 乙 |\n\n---\n\n后段"),
        CorpusEntry(id: "fx-assembler-afterlist", source: "- 只有一项\n\n紧随段落"),
        CorpusEntry(id: "fx-fixture-table", source: "| 方案 | 能力 | 极客友好度 |\n|------|------|-----------|\n| iOS 快捷指令 | 只能在设备上跑，不能远程调用 | ✗ 封闭生态 |\n| OneDay | iOS 设备能力 + MCP 开放协议 + 可自建 Agent | ✓ 开放、可控、可扩展 |"),
        CorpusEntry(id: "fx-empty", source: ""),
        CorpusEntry(id: "fx-only-newlines", source: "\n\n"),
    ]

    /// 边角集（施工图登记项＋旧状态机特有口径逐项）
    static let edgeCorpus: [CorpusEntry] = [
        CorpusEntry(id: "edge-setext-equals", source: "集合标题一\n==="),
        CorpusEntry(id: "edge-setext-dash", source: "小节标题\n---\n后续正文"),
        CorpusEntry(id: "edge-setext-dash-para", source: "前文一行\n标题行\n---"),
        CorpusEntry(id: "edge-hr-after-para-blank", source: "正文一段\n\n---\n\n下一段"),
        CorpusEntry(id: "edge-tilde-fence", source: "~~~\nlet x = 1\n~~~"),
        CorpusEntry(id: "edge-indented-code", source: "    let x = 1\n    print(x)"),
        CorpusEntry(id: "edge-heading-empty", source: "#"),
        CorpusEntry(id: "edge-heading-space-only", source: "## "),
        CorpusEntry(id: "edge-heading-marks", source: "## **粗**标题与 `代码`"),
        CorpusEntry(id: "edge-code-info-words", source: "```swift linenums\nlet a = 1\n```"),
        CorpusEntry(id: "edge-code-upper-lang", source: "```SWIFT\nlet a = 1\n```"),
        CorpusEntry(id: "edge-code-blank-inside", source: "```\n第一行\n\n第三行\n```"),
        CorpusEntry(id: "edge-code-interrupt", source: "前文\n```\ncode\n```\n后文"),
        CorpusEntry(id: "edge-ordered-start3", source: "3. 第三\n4. 第四"),
        CorpusEntry(id: "edge-ordered-nonseq", source: "1. 甲\n3. 乙"),
        CorpusEntry(id: "edge-ordered-paren", source: "1) 第一\n2) 第二"),
        CorpusEntry(id: "edge-list-multipara", source: "- 第一项\n\n  第二段落续写\n- 第二项"),
        CorpusEntry(id: "edge-list-item-code", source: "- 项一\n\n  ```\n  code\n  ```\n- 项二"),
        CorpusEntry(id: "edge-list-mixed-blank", source: "- 无序甲\n\n1. 有序乙"),
        CorpusEntry(id: "edge-quote-list", source: "> - 甲\n> - 乙"),
        CorpusEntry(id: "edge-quote-code", source: "> ```\n> let x = 1\n> ```"),
        CorpusEntry(id: "edge-quote-heading", source: "> # 引用标题\n> 正文"),
        CorpusEntry(id: "edge-quote-blank-inside", source: "> 甲\n>\n> 乙"),
        CorpusEntry(id: "edge-quote-lazy", source: "> 甲第一行\n乙第二行"),
        CorpusEntry(id: "edge-quote-table", source: "> | A | B |\n> | --- | --- |\n> | 1 | 2 |"),
        CorpusEntry(id: "edge-quote-deep", source: "> 一层\n>> 二层\n>>> 三层"),
        CorpusEntry(id: "edge-html-block", source: "<div class=\"note\">\n原始内容\n</div>"),
        CorpusEntry(id: "edge-html-adjacent", source: "<br>\n紧随的正文一行"),
        CorpusEntry(id: "edge-html-blank-after", source: "<div>\n块\n</div>\n\n独立段落"),
        CorpusEntry(id: "edge-table-marks", source: "| 名称 | 说明 |\n| --- | --- |\n| **粗**项 | 带 `代码` 与 [链接](https://example.com) |"),
        CorpusEntry(id: "edge-table-after-para", source: "对比如下\n| A | B |\n| --- | --- |\n| 1 | 2 |"),
        CorpusEntry(id: "edge-ref-link-def", source: "见[文档][ref]说明\n\n[ref]: https://example.com/doc"),
        CorpusEntry(id: "edge-hardbreak-spaces", source: "第一行  \n第二行"),
        CorpusEntry(id: "edge-hardbreak-backslash", source: "第一行\\\n第二行"),
        CorpusEntry(id: "edge-entity", source: "鱼 &amp; 熊掌 &lt;不可&gt; 兼得"),
        CorpusEntry(id: "edge-escaped-stars", source: "字面 \\*星号\\* 不是斜体"),
        CorpusEntry(id: "edge-angle-autolink", source: "地址 <https://example.com/a> 在此"),
        CorpusEntry(id: "edge-list-task-caps", source: "- [X] 大写完成\n- [ ] 未完"),
        CorpusEntry(id: "edge-list-plus-marker", source: "+ 甲\n+ 乙"),
        CorpusEntry(id: "edge-list-star-marker", source: "* 甲\n* 乙"),
        CorpusEntry(id: "edge-nested-quote-in-list", source: "- 项\n  > 引用行"),
        CorpusEntry(id: "edge-heading-atx-trailing", source: "### 标题   "),
        CorpusEntry(id: "edge-para-with-pipes", source: "命令 a | b | c 的输出"),
        CorpusEntry(id: "edge-strike-para", source: "结论是~~旧方案~~，改走**新方案**"),
        CorpusEntry(id: "edge-multiline-quote-para", source: "> 长引用第一行\n> 长引用第二行\n\n回应正文"),
    ]

    /// Hermes 风格真实文档（聊天长文／技能文档／动态帖／表格报告）
    static let documentCorpus: [CorpusEntry] = [
        CorpusEntry(id: "doc-status-report", source: """
        ## 巡检结论

        三个节点状态如下，**整体可用**：

        | 节点 | 状态 | 延迟 |
        | --- | --- | ---: |
        | xray-1 | 正常 | 42ms |
        | xray-2 | 正常 | 57ms |
        | xray-3 | 异常 | - |

        异常节点已自动切换，处理记录见 `node-failover.log`。

        - 已完成流量统计
        - 已更新证书（剩余 89 天）
        - [ ] 人工复核 xray-3 的握手日志
        """),
        CorpusEntry(id: "doc-long-analysis", source: """
        # 关于列表渲染的分析

        先说结论：**卡顿不在滚动本身，在滚动时还在算**。

        ## 三个证据

        1. 高度是现场量测的，没有缓存
        2. 图片解码在主线程
        3. 新消息进来整表重建

        > 大厂的做法是先排版、后贴图——数据定型，
        > 呈现只搬运。这是 Telegram 列表的公开实现。

        ## 对照表

        | 做法 | 我们 | Telegram |
        | --- | --- | --- |
        | 高度 | 现场量 | 预排缓存 |
        | 更新 | 整表重建 | 增量追加 |
        | 解码 | 主线程 | 后台队列 |

        细节见 [诊断报告](https://example.com/report) 与附件。
        """),
        CorpusEntry(id: "doc-skill-doc", source: """
        # 技能：文件归档

        ## 触发条件

        用户说「归档」或给出文件路径时触发。

        ## 步骤

        1. 读取文件元信息
        2. 按规则分类
           - 文档类进 `Docs/`
           - 图片类进 `Pics/`
        3. 移动并回读验证

        ```bash
        mv "$src" "$dst" && ls -la "$dst"
        ```

        - [ ] 归档前确认目标目录存在
        - [x] 归档后必须回读
        """),
        CorpusEntry(id: "doc-feed-post", source: """
        今天把阳台的花换了盆。

        ![阳台](https://example.com/pic.jpg)

        顺手记一下浇水节奏：**三天一次**，夏天另算。详见[园艺笔记](https://example.com/notes)。
        """),
        CorpusEntry(id: "doc-code-answer", source: """
        问题在 `ChatView.swift` 的 `send()`：提交前要先过发件箱。

        ```swift
        func send() {
            guard !text.isEmpty else { return }
            outbox.enqueue(text)
        }
        ```

        要点：

        - 幂等键用 `client_message_id`
        - 失败**不要**删条目，原位标红
        - 重试上限 3 次，间隔 2s / 4s / 8s
        """),
        CorpusEntry(id: "doc-meeting", source: """
        ## 周会纪要

        参会：三方已确认。

        ### 决议

        - [x] 部署包 1.6.0 本周上线
        - [ ] APNs 等付费账号到位再议
        - [ ] 电表读数下周复核

        ### 数据

        | 项 | 上周 | 本周 |
        | --- | ---: | ---: |
        | 收录 | 148 | 151 |
        | 报错 | 3 | 1 |
        """),
        CorpusEntry(id: "doc-troubleshoot", source: """
        排查顺序：

        1. 先看日志：`tail -f ~/build/agent-test.log`
        2. 再看通道：kick 前双读判闲
        3. 最后才动代码

        > 注意：不要在通道忙时覆写 test-cmd.sh，
        > 会把在跑的验证杀掉（有过实证）。

        如果还不行，把 `.ips` 崩溃日志发我。
        """),
        CorpusEntry(id: "doc-changelog", source: """
        ## 0.50.102 更新

        - §407 预排版步骤 1：发送预定高
        - 占位行定高，生成中不再跳行
        - 文件行封面定高

        ---

        ## 0.50.101 更新

        - 底栏图标官方导出翻正
        - 冒烟门重做
        """),
        CorpusEntry(id: "doc-quote-reply", source: """
        你问的原文是：

        > 文件这些都和人家的一样啊！
        > 图标是咋样的，整体怎么显示的？

        答：图标抄 TG 的状态圆，机制也抄 TG——
        标题全名一行、副行只留大小、进度长在行里。
        """),
        CorpusEntry(id: "doc-mixed-cjk", source: """
        Mixed 混排 sample：iOS 26 的 `UIHostingConfiguration` 与
        SwiftUI 混排时，**不要**在 body 里做重活。See the
        [HIG](https://developer.apple.com/design/human-interface-guidelines)
        for details.

        - 第一项 item one
        - 第二项 item two，含 3 * 5 = 15 的算式
        - file_name_with_underscores 不应被斜体化
        """),
        CorpusEntry(id: "doc-table-heavy", source: """
        | 方案 | 工期 | 风险 | 备注 |
        | :--- | ---: | :---: | --- |
        | A 现行模型 | 12–20 人日 | 中 | 病在高度真源 |
        | B 行渲染原生化 | 35–55 人日 | 高 | 容器保留 |
        | C 搬地基 | 90+ 人日 | 最高 | 回滚不成立 |

        结论：选 A＋简化模型。
        """),
        CorpusEntry(id: "doc-nested-deep", source: """
        - 一级
          - 二级
            - 三级
              1. 有序嵌套
              2. 第二项
          - 二级回
        - 一级二

        收尾段落。
        """),
    ]

    /// 程序生成变体（模板×参数）＋长文
    static let generatedCorpus: [CorpusEntry] = {
        var entries: [CorpusEntry] = []
        for index in 0..<24 {
            let source = """
            ## 生成报告 \(index)

            第 \(index) 轮采样完成，**指标正常**，样本数 \(100 + index * 7)。

            - 条目甲 \(index)
            - 条目乙，含 `code-\(index)` 片段
            - [ ] 待办 \(index)

            | 列 | 值 |
            | --- | ---: |
            | 采样 | \(index) |
            | 误差 | 0.\(index) |

            ```python
            print("round \(index)")
            ```

            > 引文 \(index)：数据定型，呈现搬运。
            """
            entries.append(CorpusEntry(
                id: "gen-report-\(index)", source: source
            ))
        }
        let section = """
        ## 小节标题

        正文一段，带 **粗体**、*斜体*、`行内代码` 与
        [链接](https://example.com/doc) 若干，还有一串
        数字 13800138000 与时间 13:00 保持完整。

        - 列表项一
        - 列表项二，含 ~~删除线~~ 片段

        | 名称 | 数量 |
        | --- | ---: |
        | 苹果 | 3 |

        """
        let longSource = (0..<40).map { _ in section }.joined()
        entries.append(CorpusEntry(
            id: "long-20k", source: longSource
        ))
        return entries
    }()
}

// MARK: - 行内语料

extension MarkdownEngineDifferentialTests {

    static let inlineCorpus: [CorpusEntry] = [
        CorpusEntry(id: "inl-plain", source: "今天天气不错"),
        CorpusEntry(id: "inl-strong", source: "这是**重点**部分"),
        CorpusEntry(id: "inl-emphasis", source: "这是*斜体*部分"),
        CorpusEntry(id: "inl-strong-emphasis", source: "***粗斜***"),
        CorpusEntry(id: "inl-code-literal", source: "运行 `**not bold**` 命令"),
        CorpusEntry(id: "inl-link", source: "看[文档](https://example.com/a)这里"),
        CorpusEntry(id: "inl-strike-strong", source: "~~删掉**这段**~~保留"),
        CorpusEntry(id: "inl-unclosed-strong", source: "这是**没闭合"),
        CorpusEntry(id: "inl-mixed", source: "先**加粗**再`code`和[链接](https://a.b/c)最后*斜*"),
        CorpusEntry(id: "inl-adjacent-links", source: "[甲](https://a.b)[乙](https://a.b)"),
        CorpusEntry(id: "inl-probe", source: "§167 runs 探针 **加粗探针** 与 [链接](https://example.com/probe157)"),
        CorpusEntry(id: "inl-phone", source: "有问题打我电话 13800138000"),
        CorpusEntry(id: "inl-code-tail", source: "配置文件是 `config.yaml`"),
        CorpusEntry(id: "inl-link-tail", source: "详情参见[官方文档](https://example.com/guide)"),
        CorpusEntry(id: "inl-bold-punct", source: "这是**设备能力**。"),
        CorpusEntry(id: "inl-strike-tail", source: "结论是~~旧方案~~"),
        CorpusEntry(id: "inl-unclosed-title", source: "这是**没闭合的小标题"),
        CorpusEntry(id: "inl-code-delims", source: "字面量 `**not bold**` 照原样"),
        CorpusEntry(id: "inl-fixture-excerpt", source: "详见[官方文档](https://example.com/docs)与 `config.yaml` 配置，~~旧入口~~已下线"),
        CorpusEntry(id: "inl-image-alt", source: "前 ![替代文本](https://example.com/p.png) 后"),
        CorpusEntry(id: "inl-image-empty-alt", source: "前 ![](https://example.com/p.png) 后"),
        CorpusEntry(id: "inl-image-in-link", source: "[![图](https://example.com/p.png)](https://example.com)"),
        CorpusEntry(id: "inl-bare-url", source: "访问 https://example.com/x 看看"),
        CorpusEntry(id: "inl-www-url", source: "站点 www.example.com 在此"),
        CorpusEntry(id: "inl-angle-link", source: "地址 <https://example.com/a> 在此"),
        CorpusEntry(id: "inl-ref-link", source: "见[文档][ref]与[简写][]两处"),
        CorpusEntry(id: "inl-link-title", source: "[文档](https://example.com \"标题\")在此"),
        CorpusEntry(id: "inl-inline-html", source: "前面 <b>粗</b> 后面"),
        CorpusEntry(id: "inl-entity", source: "鱼 &amp; 熊掌"),
        CorpusEntry(id: "inl-underscore-word", source: "file_name_here 不斜体"),
        CorpusEntry(id: "inl-underscore-em", source: "这是 _斜体_ 段"),
        CorpusEntry(id: "inl-double-underscore", source: "这是 __粗体__ 段"),
        CorpusEntry(id: "inl-math-stars", source: "算式 3 * 5 * 2 在此"),
        CorpusEntry(id: "inl-nested-em", source: "**外层 *内层* 继续**"),
        CorpusEntry(id: "inl-strike-code", source: "~~删 `code` 段~~保留"),
        CorpusEntry(id: "inl-code-backtick", source: "代码 ``a`b`` 在此"),
        CorpusEntry(id: "inl-unclosed-strike", source: "半截~~还没写完"),
        CorpusEntry(id: "inl-single-tilde", source: "大约 ~5 个"),
        CorpusEntry(id: "inl-unclosed-code", source: "半截 `代码没闭合"),
        CorpusEntry(id: "inl-strong-in-link", source: "[**粗**链接](https://example.com)"),
        CorpusEntry(id: "inl-link-in-strong", source: "**[链接](https://example.com)粗**"),
        CorpusEntry(id: "inl-emoji-marks", source: "结论 🎉 **通过** 了"),
        CorpusEntry(id: "inl-softbreak", source: "第一行\n第二行"),
        CorpusEntry(id: "inl-hardbreak", source: "第一行  \n第二行"),
        CorpusEntry(id: "inl-empty-link", source: "空链[]()在此"),
        CorpusEntry(id: "inl-mailto", source: "邮箱 [邮我](mailto:a@b.com) 谢谢"),
        CorpusEntry(id: "inl-bare-email", source: "有事邮 a@b.com 找我"),
        CorpusEntry(id: "inl-bare-domain", source: "站点 example.com 在此"),
        CorpusEntry(id: "inl-escaped-stars", source: "字面 \\*星号\\* 不是斜体"),
    ]
}
