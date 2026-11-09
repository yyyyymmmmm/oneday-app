import Foundation

/// 日志行的人话三行结构（0.3.8，基线补遗哲学条「数据先
/// 翻译连审计都不例外」）：日志/活动/任务记录上屏一律
/// 三行——人话动作（标题）＋白话说明（副行）＋策略·时
/// 间（脚注行），原始字段（ISO 时间戳、级别英文 token、
/// 模块名）退到脚注/详情，不许整行原文 mono 直出（卡
/// 12/日志页 0.3.7 前形态）。解析是纯函数：认不出结构
/// 时整行作标题、脚注只给「日志」，不编造。
public struct LogEntryDisplay: Equatable, Sendable {
    /// 人话动作：消息首句（截断 60 字）
    public let headline: String
    /// 白话说明：首句之后的余文（截断 120 字），无则 nil
    public let detail: String?
    /// 脚注：级别中文 · 时间（HH:mm:ss），缺项省略
    public let meta: String

    public init(headline: String, detail: String?, meta: String) {
        self.headline = headline
        self.detail = detail
        self.meta = meta
    }
}

public enum LogDisplay {
    private static let levelWords: [(token: String, label: String)] = [
        ("CRITICAL", "严重"), ("ERROR", "错误"), ("WARN", "警告"),
        ("WARNING", "警告"), ("INFO", "信息"), ("DEBUG", "调试"),
    ]

    public static func parse(_ rawLine: String) -> LogEntryDisplay {
        var rest = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // 行首 ISO 时间戳 → 脚注时间（HH:mm:ss）
        var time: String?
        if let first = rest.split(separator: " ", maxSplits: 1).first,
           first.contains("T"), first.first?.isNumber == true {
            let token = String(first)
            if let tIndex = token.firstIndex(of: "T") {
                let tail = token[token.index(after: tIndex)...]
                let clock = tail.prefix { $0.isNumber || $0 == ":" }
                if clock.count >= 5 { time = String(clock) }
            }
            rest = rest.dropFirst(token.count)
                .trimmingCharacters(in: .whitespaces)
        }

        // 级别 token（可带方括号/冒号）→ 中文脚注
        var level: String?
        var tokens = rest.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        if let index = tokens.firstIndex(where: { token in
            let bare = token.trimmingCharacters(
                in: CharacterSet(charactersIn: "[]:")
            ).uppercased()
            return levelWords.contains { $0.token == bare }
        }) {
            let bare = tokens[index].trimmingCharacters(
                in: CharacterSet(charactersIn: "[]:")
            ).uppercased()
            level = levelWords.first { $0.token == bare }?.label
            tokens.remove(at: index)
            rest = tokens.joined(separator: " ")
        }

        // 模块名（形如 gateway.run: 的首 token）退脚注
        var module: String?
        if let first = rest.split(separator: " ", maxSplits: 1).first,
           first.hasSuffix(":"), first.contains("."),
           !first.contains("：") {
            module = String(first.dropLast())
            rest = rest.dropFirst(first.count)
                .trimmingCharacters(in: .whitespaces)
        }

        // 标题＝首句，余文＝说明
        let message = rest.isEmpty ? rawLine : rest
        let (headline, detail) = splitHeadline(message)

        var metaParts: [String] = []
        if let level { metaParts.append(level) }
        if let time { metaParts.append(time) }
        if let module { metaParts.append(module) }
        return LogEntryDisplay(
            headline: headline,
            detail: detail,
            meta: metaParts.isEmpty ? "日志" : metaParts.joined(separator: " · ")
        )
    }

    /// 首句切分：中文句号/英文句点加空格/破折号为界；
    /// 无界则整段为标题（超长截断）
    private static func splitHeadline(_ message: String) -> (String, String?) {
        let separators = ["。", " — ", " – "]
        for sep in separators {
            if let range = message.range(of: sep) {
                let head = String(message[..<range.lowerBound])
                let tail = String(message[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !head.isEmpty {
                    return (truncate(head, 60), tail.isEmpty ? nil : truncate(tail, 120))
                }
            }
        }
        if let range = message.range(of: ". ") {
            let head = String(message[..<range.lowerBound])
            let tail = String(message[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            if head.count >= 8, !tail.isEmpty {
                return (truncate(head, 60), truncate(tail, 120))
            }
        }
        return (truncate(message, 60), nil)
    }

    private static func truncate(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
