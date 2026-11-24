import Foundation

/// 消息来源（D4，DESIGN §349）：联网搜索/抓取结果里的
/// 一条来源（标题＋URL）。**呈现层派生值，不落盘**——
/// 工具行原文（经 ToolCard.result 到手）是唯一数据源，
/// 本模型每次由 WebSourceExtractor 现提：不进 ToolCard
/// 落盘字段、不建第二数据源，历史会话回放同路自动补
/// 出（见 TurnSourceAggregation）。
public struct MessageSource: Codable, Equatable, Sendable, Identifiable {
    public let title: String
    public let url: String

    public var id: String { url }

    /// 展示用主机名（剥 www. 前缀）；URL 解析不出
    /// 主机时为空串（呈现层据此只出标题）
    public var host: String {
        guard let host = URLComponents(string: url)?.host,
              !host.isEmpty else { return "" }
        return host.hasPrefix("www.")
            ? String(host.dropFirst(4)) : host
    }

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// 联网工具结果 → 来源提取（D4，DESIGN §349）：断链
/// 定位（d4-citation-probe-20261122）实证——来源数
/// 据完整躺在工具行里（web_search 的 data.web[]、
/// web_extract 的 results[]），只是从未被提取。本提
/// 取器在 ToolCard 拼装之后消费卡面 result 文本（已
/// 过 ToolResultUnwrap 剥包裹的 pretty JSON），把两
/// 种形态提成来源模型；提取失败/非 JSON/非联网工具
/// 一律回空集，呈现回落旧形态、行为不变。
public enum WebSourceExtractor {
    /// 单轮来源上限（呈现清单口径，Perplexity 式回答
    /// 级清单的常态量级；超限按原序截断）
    public static let maxSources = 10

    /// 联网工具判据（与 ToolCardClassifier 的原生名
    /// 单源同口径：Hermes 原生工具名恒为此二名）
    public static func isWebTool(_ toolName: String) -> Bool {
        toolName == "web_search" || toolName == "web_extract"
    }

    /// 单卡提取：只认 web_search / web_extract 两名；
    /// 其余工具（哪怕结果形态相像）恒空——来源语义
    /// 只属于联网检索/抓取
    public static func sources(from card: ToolCard) -> [MessageSource] {
        guard isWebTool(card.toolName),
              let result = card.result else { return [] }
        return sources(fromResultText: result, toolName: card.toolName)
    }

    public static func sources(
        fromResultText text: String, toolName: String
    ) -> [MessageSource] {
        guard isWebTool(toolName),
              let object = jsonObject(from: text) else { return [] }
        return extract(from: object, toolName: toolName)
    }

    /// 一轮内多卡聚合（呈现层按轮调用）：按 url 去重
    /// 保序；同一 url 在 search 与 extract 各出现一次
    /// 时标题以 search 为准（报告 §5.4：extract 是
    /// 「打开某页」、search 标题是检索侧标题口径）；
    /// 总量封顶 maxSources
    public static func aggregate(cards: [ToolCard]) -> [MessageSource] {
        var ordered: [MessageSource] = []
        var indexByKey: [String: Int] = [:]
        var searchTitled = Set<String>()
        for card in cards where isWebTool(card.toolName) {
            for source in sources(from: card) {
                let key = dedupKey(for: source.url)
                if let existing = indexByKey[key] {
                    if card.toolName == "web_search",
                       !searchTitled.contains(key) {
                        ordered[existing] = MessageSource(
                            title: source.title,
                            url: ordered[existing].url
                        )
                        searchTitled.insert(key)
                    }
                } else {
                    indexByKey[key] = ordered.count
                    ordered.append(source)
                    if card.toolName == "web_search" {
                        searchTitled.insert(key)
                    }
                    if ordered.count >= maxSources {
                        return ordered
                    }
                }
            }
        }
        return ordered
    }

    // MARK: - 形态解析

    private static func extract(
        from dict: [String: Any], toolName: String
    ) -> [MessageSource] {
        // MCP 形态 {"result": "<json string>"} 防御递归
        // （ToolResultUnwrap 通常已剥净，此处兜底直喂
        // 原文的调用面）
        if let inner = dict["result"] as? String,
           let innerDict = jsonObject(from: inner) {
            return extract(from: innerDict, toolName: toolName)
        }
        if toolName == "web_search" {
            // 失败的检索不产出来源（success 缺失按存量
            // 形态放行——官方形态恒带 success）
            if (dict["success"] as? Bool) == false { return [] }
            guard let data = dict["data"] as? [String: Any],
                  let web = data["web"] as? [[String: Any]]
            else { return [] }
            // position 是检索序：全有值时按它定序（解
            // 析层 pretty JSON 按键序重排过数组外的字
            // 段、数组本体不动，此处只对显式乱序样本
            // 负责）；缺位者以原序殿后（sorted 稳定）
            let sorted = web.sorted {
                position(of: $0) < position(of: $1)
            }
            return cap(dedup(sorted.compactMap { source(from: $0) }))
        }
        // web_extract：{"results": [{url, title, content, error}]}
        guard let results = dict["results"] as? [[String: Any]]
        else { return [] }
        return cap(dedup(results.compactMap { entry in
            // 抓取失败的行不是来源（error 非空即失败，
            // 与样本形态同口径）
            if let error = entry["error"] as? String,
               !error.isEmpty { return nil }
            return source(from: entry)
        }))
    }

    private static func source(
        from entry: [String: Any]
    ) -> MessageSource? {
        guard let url = (entry["url"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty, URL(string: url) != nil
        else { return nil }
        let rawTitle = (entry["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 标题缺失回落主机名（清单行总要有可读名）；
        // 主机也解析不出时以 URL 原文充名
        let fallback = MessageSource(title: "", url: url).host
        let title = rawTitle.isEmpty
            ? (fallback.isEmpty ? url : fallback) : rawTitle
        return MessageSource(title: title, url: url)
    }

    private static func position(of entry: [String: Any]) -> Int {
        (entry["position"] as? NSNumber)?.intValue ?? Int.max
    }

    private static func jsonObject(
        from text: String
    ) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(
                with: data
              ),
              let dict = object as? [String: Any] else { return nil }
        return dict
    }

    /// 去重键：原文去首尾空白＋剥单个尾斜杠（同页的
    /// 根路径写法差异不算两条）；键仅内部比对用，
    /// 呈现恒用首见原文
    static func dedupKey(for url: String) -> String {
        var key = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasSuffix("/"), key.count > 1 {
            key.removeLast()
        }
        return key
    }

    private static func dedup(
        _ sources: [MessageSource]
    ) -> [MessageSource] {
        var seen = Set<String>()
        return sources.filter {
            seen.insert(dedupKey(for: $0.url)).inserted
        }
    }

    private static func cap(
        _ sources: [MessageSource]
    ) -> [MessageSource] {
        Array(sources.prefix(maxSources))
    }
}

/// 按轮聚合（D4，DESIGN §349）：呈现序条目 → 「定稿
/// 助手条目下标 → 该轮来源清单」。轮的边界是 user
/// 条目（列表头天然是轮首）；轮内全部联网卡的来源
/// 汇成一份、挂轮内**最后一个**有正文的助手条目
/// （定稿）；系统锚定/空行等 other 条目不重置轮、
/// 不承接来源。纯函数：输入是呈现拼装层的条目抽象
/// （App 侧把 ChatEntry 逐条映射进来），输出供呈
/// 现层按条目 id 回填——来源不落盘、每次拼装现算，
/// 与工具行单源恒一致。
public enum TurnSourceAggregation {
    public struct SegmentItem: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// user 条目：轮边界
            case userMessage
            /// 有正文的助手条目：定稿候选
            case assistantMessage
            /// 工具卡条目（card 须在场）
            case toolCard
            /// 不参与：不重置、不承接
            case other
        }

        public let kind: Kind
        public let card: ToolCard?

        public init(kind: Kind, card: ToolCard? = nil) {
            self.kind = kind
            self.card = card
        }
    }

    public static func sourcesByAssistantIndex(
        items: [SegmentItem]
    ) -> [Int: [MessageSource]] {
        var result: [Int: [MessageSource]] = [:]
        var cards: [ToolCard] = []
        var lastAssistant: Int?
        func flush() {
            guard let lastAssistant else { return }
            let sources = WebSourceExtractor.aggregate(cards: cards)
            if !sources.isEmpty {
                result[lastAssistant] = sources
            }
        }
        for (index, item) in items.enumerated() {
            switch item.kind {
            case .userMessage:
                flush()
                cards = []
                lastAssistant = nil
            case .toolCard:
                if let card = item.card {
                    cards.append(card)
                }
            case .assistantMessage:
                lastAssistant = index
            case .other:
                break
            }
        }
        flush()
        return result
    }
}
