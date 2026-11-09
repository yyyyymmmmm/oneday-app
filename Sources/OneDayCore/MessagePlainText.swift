import Foundation

/// Markdown → 可读纯文本（0.4.1，聊天页长按「复制／
/// 选择／分享」的文本口径）：助手消息存的是 Markdown
/// 源，复制出去要剥掉标记符号、留可读文本；用户消息
/// 不走本函数（原文即纯文本）。
///
/// 口径（逐行处理＋行内正则，与 MarkdownText 的块级
/// 分割同源——围栏代码块／标题／段落三类）：
/// - 围栏行（```）删除，围栏内代码原文逐字保留
/// - 标题行去掉 # 前缀；引用行去掉 > 前缀
/// - 链接 [文本](url) → 文本（url）；图片 ![alt](url)
///   → alt；行内代码 `x` → x；粗体 **x**/__x__ → x；
///   斜体 *x* → x（成对标记才剥，落单符号保留防误伤）
/// - 分隔线行（---/***/___）整行删除
/// 目标是「可读」不是「无损」：结构信息（列表层级等）
/// 不保留，代码与正文一字不改
public enum MessagePlainText {
    public static func make(from markdown: String) -> String {
        var inFence = false
        var output: [String] = []
        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine
                .trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence {
                output.append(rawLine)
                continue
            }
            if isHorizontalRule(trimmed) { continue }
            var line = rawLine
            line = stripHeadingPrefix(line)
            line = stripBlockquotePrefix(line)
            line = stripInline(line)
            output.append(line)
        }
        return output.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
    }

    private static func stripHeadingPrefix(_ line: String) -> String {
        var text = line
        while text.hasPrefix("#") { text.removeFirst() }
        // 只剥「# 后带空格」的标题前缀：# 后紧跟正文的
        // 行（如 #话题）在上面 while 里会被误剥——以原
        // 行首字符判定：原行是 "# " / "## " 形态才生效
        guard line.hasPrefix("#"), text.hasPrefix(" ") else { return line }
        return String(text.dropFirst())
    }

    private static func stripBlockquotePrefix(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        var stripped = false
        while text.hasPrefix(">") {
            text.removeFirst()
            stripped = true
            if text.hasPrefix(" ") { text.removeFirst() }
        }
        return stripped ? text : line
    }

    /// 行内标记剥离：图片→链接→行内代码→粗体→斜体，
    /// 顺序恒定（图片语法含链接语法，先图片后链接）
    private static func stripInline(_ line: String) -> String {
        var text = line
        text = replace(text, pattern: #"!\[([^\]]*)\]\([^)]*\)"#) { $0[1] }
        text = replace(text, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) {
            "\($0[1])（\($0[2])）"
        }
        text = replace(text, pattern: #"`([^`]+)`"#) { $0[1] }
        text = replace(text, pattern: #"\*\*([^*]+)\*\*"#) { $0[1] }
        text = replace(text, pattern: #"__([^_]+)__"#) { $0[1] }
        text = replace(text, pattern: #"\*([^*]+)\*"#) { $0[1] }
        return text
    }

    /// 正则替换小工具：闭包收到捕获组数组（[0] 是全
    /// 匹配），返回替换文本；正则非法时原样返回
    private static func replace(
        _ text: String,
        pattern: String,
        using transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { return text }
        let fullRange = NSRange(text.startIndex..., in: text)
        var result = ""
        var lastEnd = text.startIndex
        for match in regex.matches(in: text, range: fullRange) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[lastEnd..<range.lowerBound]
            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                if let groupRange = Range(match.range(at: index), in: text) {
                    groups.append(String(text[groupRange]))
                } else {
                    groups.append("")
                }
            }
            result += transform(groups)
            lastEnd = range.upperBound
        }
        result += text[lastEnd...]
        return result
    }
}
