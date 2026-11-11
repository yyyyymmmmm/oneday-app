import Foundation

/// §157（2026-11-11）解析记忆盒：按字符串键缓存纯函
/// 数结果，有界 LRU 淘汰，带命中／未命中计数。
///
/// 出处与定因：聊天页行视图在滚动与流式期会反复对
/// 同一正文求值，而块解析（MarkdownParser）、行内
/// runs（InlineRunBuilder，内含 Foundation 的
/// AttributedString(markdown:) 全量解析）与代码高亮
/// 词法（CodeHighlight）三处入口此前零记忆化——每次
/// body 求值全量重跑。外部实证同向：Tactic Remote
/// 冻结复盘（markdown 解析＋富文本重建是真贵、修法
/// 即解析加 LRU 缓存）、SwiftyChat（解析在 init 算
/// 好缓存、布局期只跑廉价合并）、WWDC25-306（卡顿
/// 两形＝长 body × 不必要的更新）。诊断全文见
/// oneday-design-review/chat-scroll-diagnosis-
/// 20261111.md 病因 A/B。
///
/// 三个入口都是纯函数（同入参恒同出参），记忆化不
/// 改变任何输出，只把重复求值从「再算一遍」变「查
/// 表」。计数器即验收代理指标：同文第二次求值起命
/// 中、未命中不再增长（MarkdownParseMemoTests 断
/// 言）。@unchecked Sendable 的依据：全部可变状态
/// 只在 NSLock 内读写；compute 在锁外执行（避免持
/// 锁做贵活），并发下同键偶发重复计算结果恒等、无
/// 害。recency 用数组维护 LRU 序，命中时一次线性
/// 搬移——容量上限 1024 条，成本远低于一次解析
public final class ParseMemoBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Value] = [:]
    private var recency: [String] = []
    private let capacity: Int
    private var hitTotal = 0
    private var missTotal = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public func value(
        for key: String, compute: () -> Value
    ) -> Value {
        lock.lock()
        if let cached = values[key] {
            hitTotal += 1
            if let index = recency.firstIndex(of: key) {
                recency.remove(at: index)
                recency.append(key)
            }
            lock.unlock()
            return cached
        }
        missTotal += 1
        lock.unlock()

        let computed = compute()

        lock.lock()
        if values[key] == nil {
            values[key] = computed
            recency.append(key)
            while values.count > capacity, let oldest = recency.first {
                recency.removeFirst()
                values[oldest] = nil
            }
        }
        let result = values[key] ?? computed
        lock.unlock()
        return result
    }

    public func metrics() -> (hits: Int, misses: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (hitTotal, missTotal)
    }

    public func resetMetrics() {
        lock.lock()
        hitTotal = 0
        missTotal = 0
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    public func removeAll() {
        lock.lock()
        values.removeAll()
        recency.removeAll()
        lock.unlock()
    }
}

/// 三个解析入口的记忆盒单例（模块内共用）。容量按
/// 结果体积定：块解析结果最重 256 条、行内 runs 按
/// 段落计条数多给 1024、高亮词元 256——与 §149 已
/// 落 attributed-string 缓存 256 条的量级同轨
enum MarkdownParseMemos {
    static let blocks = ParseMemoBox<[MarkdownBlock]>(capacity: 256)
    static let runs = ParseMemoBox<[InlineRun]>(capacity: 1024)
    static let codeTokens = ParseMemoBox<[CodeToken]>(capacity: 256)
}

/// §157 验收代理指标读面：单测断言「同文重复求值
/// 未命中不增长、命中增长」，将来 Instruments 真机
/// 对照亦可先读此账判断缓存是否在工作
public enum MarkdownParseMetrics {
    public struct Snapshot: Equatable {
        public var blockHits: Int
        public var blockMisses: Int
        public var runHits: Int
        public var runMisses: Int
        public var tokenHits: Int
        public var tokenMisses: Int
    }

    public static func snapshot() -> Snapshot {
        let blocks = MarkdownParseMemos.blocks.metrics()
        let runs = MarkdownParseMemos.runs.metrics()
        let tokens = MarkdownParseMemos.codeTokens.metrics()
        return Snapshot(
            blockHits: blocks.hits, blockMisses: blocks.misses,
            runHits: runs.hits, runMisses: runs.misses,
            tokenHits: tokens.hits, tokenMisses: tokens.misses
        )
    }

    public static func reset() {
        MarkdownParseMemos.blocks.resetMetrics()
        MarkdownParseMemos.runs.resetMetrics()
        MarkdownParseMemos.codeTokens.resetMetrics()
    }
}
