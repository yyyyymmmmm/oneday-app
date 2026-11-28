import Foundation

/// 装配层真值断言（§271，第 72 条）：成对定界符完
/// 整性核查——源文中成对闭合的 `**`／`~~`／反引号
/// 必须被行内解析完整消费，装配产出的可见文本里
/// 只许留下源文未闭合（按口径字面呈现）的那一份。
/// 任一不符即装配链在劈／吞定界符（第 74 条病型：
/// 整形在解析前插零宽符劈开段尾闭合对，呈现为开
/// 标记字面＋无闭合＋无样式）。本核查是纯函数：
/// 用于测试原始 Markdown 与行内输出。块解析后的
/// 转义表示不能当作原文审计。未闭合标记字面呈
/// 现是既定降级、不算违规。
public enum MarkdownDelimiterAudit {
    /// 违规清单（空＝通过）：逐定界符比对「源文未
    /// 闭合应留字面数」与「产出可见文本字面残留数」
    /// （产出先剥 U+2060 整形符——它是排版绑定、
    /// 非内容字，与保真测试同口径）
    public static func violations(
        source: String, runs: [InlineRun]
    ) -> [String] {
        // 可见文本只数非代码 run：代码内容里的定界
        // 符是字面内容（源文扫描同口径遮罩代码段，
        // 两边一致）；代码 run 文本本身不含其定界
        // 符（已被解析消费）
        let visible = runs.filter { !$0.code }
            .map(\.text).joined()
            .replacingOccurrences(
                of: TextShaping.wordJoiner, with: ""
            )
        var problems: [String] = []
        for delimiter in ["**", "~~"] {
            let expected = unpairedPairCount(
                in: source, delimiter: delimiter
            )
            let actual = occurrences(of: delimiter, in: visible)
            if actual != expected {
                problems.append(
                    "\(delimiter) 字面残留 \(actual) 处、"
                        + "源文未闭合应留 \(expected) 处"
                )
            }
        }
        let expectedTicks = unpairedBacktickCount(in: source)
        let actualTicks = visible.filter { $0 == "`" }.count
        if actualTicks != expectedTicks {
            problems.append(
                "` 字面残留 \(actualTicks) 个、"
                    + "源文未闭合应留 \(expectedTicks) 个"
            )
        }
        return problems
    }

    // MARK: - 源文扫描（代码段先行遮罩）

    /// 代码段区间（字符下标）：反引号串开、等长串
    /// 闭（CommonMark 口径）；未闭合的开串不算代码
    /// 段（其反引号字面计入未闭合数）
    private static func codeSpans(
        in chars: [Character]
    ) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var index = 0
        while index < chars.count {
            guard chars[index] == "`" else {
                index += 1
                continue
            }
            var openEnd = index
            while openEnd < chars.count, chars[openEnd] == "`" {
                openEnd += 1
            }
            let length = openEnd - index
            var scan = openEnd
            var closed: Range<Int>?
            while scan < chars.count {
                if chars[scan] == "`" {
                    var runEnd = scan
                    while runEnd < chars.count,
                          chars[runEnd] == "`" {
                        runEnd += 1
                    }
                    if runEnd - scan == length {
                        closed = index..<runEnd
                        break
                    }
                    scan = runEnd
                } else {
                    scan += 1
                }
            }
            if let closed {
                spans.append(closed)
                index = closed.upperBound
            } else {
                index = openEnd
            }
        }
        return spans
    }

    /// 未闭合反引号个数：不在任何代码段内的反引号
    /// 串，其每个反引号都字面呈现
    private static func unpairedBacktickCount(
        in source: String
    ) -> Int {
        let chars = Array(source)
        let spans = codeSpans(in: chars)
        var count = 0
        for (index, character) in chars.enumerated()
        where character == "`" {
            if !spans.contains(where: { $0.contains(index) }) {
                count += 1
            }
        }
        return count
    }

    /// 未闭合定界符对数（`**`／`~~`）：代码段内不
    /// 计（代码字面）；顺序配对——开标记须紧跟非空
    /// 白、闭标记须紧贴非空白（侧翼口径，与解析层
    /// 对「2 ** 3 ** 4」类空格环绕写法的字面判定
    /// 一致）；配不上对的开标记计 1 个未闭合
    private static func unpairedPairCount(
        in source: String, delimiter: String
    ) -> Int {
        let chars = Array(source)
        let spans = codeSpans(in: chars)
        func inCode(_ index: Int) -> Bool {
            spans.contains { $0.contains(index) }
        }
        let pair = Array(delimiter)
        // 候选位：定界符两字都不在代码段内
        var candidates: [Int] = []
        var index = 0
        while index + 1 < chars.count {
            if chars[index] == pair[0], chars[index + 1] == pair[1],
               !inCode(index), !inCode(index + 1) {
                candidates.append(index)
                index += 2
            } else {
                index += 1
            }
        }
        var unpaired = 0
        var cursor = 0
        while cursor < candidates.count {
            let open = candidates[cursor]
            // 开标记侧翼：后一字非空白
            let openFlanked = open + 2 < chars.count
                && !chars[open + 2].isWhitespace
            guard openFlanked else {
                unpaired += 1
                cursor += 1
                continue
            }
            // 找下一个可作闭标记的候选（前一字非空白）
            var closer: Int?
            var probe = cursor + 1
            while probe < candidates.count {
                let candidate = candidates[probe]
                if candidate > open + 2,
                   !chars[candidate - 1].isWhitespace {
                    closer = probe
                    break
                }
                probe += 1
            }
            if let closer {
                cursor = closer + 1
            } else {
                unpaired += 1
                cursor += 1
            }
        }
        return unpaired
    }

    private static func occurrences(
        of needle: String, in haystack: String
    ) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(
            of: needle, range: searchRange
        ) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }
}
