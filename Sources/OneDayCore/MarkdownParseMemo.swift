import Foundation

/// §167（2026-11-11）解析记忆盒：按字符串键缓存纯函
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
/// 害。字典定位节点，链表维护访问顺序，命中和淘汰都为 O(1)。
public final class ParseMemoBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private final class Entry {
        let key: String
        let value: Value
        weak var older: Entry?
        var newer: Entry?

        init(key: String, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private var entries: [String: Entry] = [:]
    private var oldest: Entry?
    private var newest: Entry?
    private let capacity: Int
    private var hitTotal = 0
    private var missTotal = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// 种入（§417）：同批解析顺手产出的等价结果预
    /// 先入盒（如块解析时从同一棵树直产的行内
    /// runs），后续查表直接命中。种入不是查表——
    /// 不计命中／未命中；已有键不覆盖（纯函数同键
    /// 同值，先到为准）；容量与 LRU 淘汰同 value
    public func seed(_ value: Value, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard entries[key] == nil else { return }
        insert(value, for: key)
    }

    public func value(
        for key: String, compute: () -> Value
    ) -> Value {
        lock.lock()
        if let entry = entries[key] {
            hitTotal += 1
            if newest !== entry {
                unlink(entry)
                append(entry)
            }
            lock.unlock()
            return entry.value
        }
        missTotal += 1
        lock.unlock()

        let computed = compute()

        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[key] {
            return entry.value
        }
        insert(computed, for: key)
        return computed
    }

    private func insert(_ value: Value, for key: String) {
        let entry = Entry(key: key, value: value)
        entries[key] = entry
        append(entry)
        if entries.count > capacity, let oldest {
            unlink(oldest)
            entries.removeValue(forKey: oldest.key)
        }
    }

    private func unlink(_ entry: Entry) {
        if let older = entry.older {
            older.newer = entry.newer
        } else {
            oldest = entry.newer
        }
        if let newer = entry.newer {
            newer.older = entry.older
        } else {
            newest = entry.older
        }
        entry.older = nil
        entry.newer = nil
    }

    private func append(_ entry: Entry) {
        if let newest {
            newest.newer = entry
            entry.older = newest
        } else {
            oldest = entry
        }
        newest = entry
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
        return entries.count
    }

    public func removeAll() {
        lock.lock()
        entries.removeAll()
        oldest = nil
        newest = nil
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

/// §167 验收代理指标读面：单测断言「同文重复求值
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
