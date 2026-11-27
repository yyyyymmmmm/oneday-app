import Foundation

// MARK: - 流式渲染节流与已完成块冻结协调器（#36）

/// 流式渲染快照：将长回复切分为已冻结的稳定 Markdown 段落（无需每帧重解析）
/// 与仍在增长的活跃尾部，供视图层局部重绘。
public struct StreamRenderSnapshot: Equatable, Sendable {
    public let frozenBlocks: [String]
    public let activeTail: String
    public let fullText: String
    public let isFinal: Bool

    public init(
        frozenBlocks: [String],
        activeTail: String,
        fullText: String,
        isFinal: Bool
    ) {
        self.frozenBlocks = frozenBlocks
        self.activeTail = activeTail
        self.fullText = fullText
        self.isFinal = isFinal
    }
}

/// 统一流式渲染节流协调器：
/// 1. 固定节拍（默认 33ms ≈ 30fps）合批上屏，避免逐 token 触发 SwiftUI/TextKit 重排；
/// 2. 自动识别已闭合段落边界（`\n\n` 且不在未闭合 ``` 代码围栏内），
///    将已完成块冻结缓存，流式期间只增量解析 `activeTail`。
public struct StreamRenderCoordinator: Sendable {
    public let cadenceSeconds: TimeInterval
    private var lastPublishedAt: TimeInterval?
    private var frozenBlocks: [String] = []
    private var frozenPrefixLength: Int = 0
    private var lastFullText: String = ""

    public init(cadenceSeconds: TimeInterval = 1.0 / 30.0) {
        self.cadenceSeconds = max(0.016, cadenceSeconds)
    }

    public mutating func reset() {
        lastPublishedAt = nil
        frozenBlocks = []
        frozenPrefixLength = 0
        lastFullText = ""
    }

    /// 喂入最新流式全文；若未到节拍间隔返回 `nil`（调用方保留上一帧），
    /// 到达节拍或首次产出时返回最新冻结/活跃快照。
    public mutating func ingest(
        fullText: String,
        now: TimeInterval
    ) -> StreamRenderSnapshot? {
        if let last = lastPublishedAt,
           now - last < cadenceSeconds,
           fullText != lastFullText {
            return nil
        }
        lastPublishedAt = now
        return buildSnapshot(fullText: fullText, isFinal: false)
    }

    /// 流结束时强制刷新最后一帧，将全部内容落定为终态。
    public mutating func flush(fullText: String) -> StreamRenderSnapshot {
        lastPublishedAt = nil
        return buildSnapshot(fullText: fullText, isFinal: true)
    }

    private mutating func buildSnapshot(
        fullText: String,
        isFinal: Bool
    ) -> StreamRenderSnapshot {
        // 若全文发生回退/重置（例如重试或纠偏），清空冻结缓存重新切分
        if fullText.count < frozenPrefixLength
            || !fullText.hasPrefix(String(lastFullText.prefix(frozenPrefixLength))) {
            frozenBlocks = []
            frozenPrefixLength = 0
        }
        lastFullText = fullText

        if isFinal {
            let remainder = String(fullText.dropFirst(frozenPrefixLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var finalBlocks = frozenBlocks
            if !remainder.isEmpty {
                finalBlocks.append(remainder)
            }
            frozenBlocks = finalBlocks
            frozenPrefixLength = fullText.count
            return StreamRenderSnapshot(
                frozenBlocks: finalBlocks,
                activeTail: "",
                fullText: fullText,
                isFinal: true
            )
        }

        // 在未冻结尾部中查找安全段落断点（`\n\n` 且围栏代码已闭合）
        let startIdx = fullText.index(fullText.startIndex, offsetBy: frozenPrefixLength)
        let tail = String(fullText[startIdx...])
        let (newlyFrozen, consumedCount) = Self.extractSafeFrozenBlocks(from: tail)
        if !newlyFrozen.isEmpty {
            frozenBlocks.append(contentsOf: newlyFrozen)
            frozenPrefixLength += consumedCount
        }
        let activeStart = fullText.index(fullText.startIndex, offsetBy: frozenPrefixLength)
        let activeTail = String(fullText[activeStart...])
        return StreamRenderSnapshot(
            frozenBlocks: frozenBlocks,
            activeTail: activeTail,
            fullText: fullText,
            isFinal: false
        )
    }

    /// 扫描段落双换行边界；只要当前处于 ``` 代码围栏内部就不截断，
    /// 确保代码块完整闭合后才进入冻结缓存。
    private static func extractSafeFrozenBlocks(from tail: String) -> ([String], Int) {
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3 else { return ([], 0) }

        var inFence = false
        var currentBlockLines: [Substring] = []
        var frozen: [String] = []
        var consumedChars = 0
        var pendingChars = 0

        for (idx, line) in lines.enumerated() {
            let lineLen = line.count + (idx < lines.count - 1 ? 1 : 0)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
            }
            if !inFence && trimmed.isEmpty && !currentBlockLines.isEmpty && idx < lines.count - 1 {
                let block = currentBlockLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !block.isEmpty {
                    frozen.append(block)
                }
                currentBlockLines.removeAll(keepingCapacity: true)
                consumedChars += pendingChars + lineLen
                pendingChars = 0
            } else {
                currentBlockLines.append(line)
                pendingChars += lineLen
            }
        }
        return (frozen, consumedChars)
    }
}
