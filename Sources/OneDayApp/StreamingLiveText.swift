import OneDayCore
import OneDayDesign
import SwiftUI

/// §494（2026-11-24）流式正文块级呈现：已闭合
/// 块逐块走落定同路渲染（MarkdownText，块内容
/// 冻结、输入串不变→解析备忘恒命中、视图不重
/// 排），只有未闭合的尾块随发布快照生长重渲。
/// §247 原版 StreamingBlockText 的块级口径复
/// 原，差异两点：①尾块不再走 StreamingText 逐
/// 词元排布（(b) 拍板不复活），改 MarkdownText
/// 轻成形——解析层半截口径（未闭合围栏续渲、
/// 半截表格不成表）保证任意中间态渲染确定；
/// ②入场计划（StreamingEntrance，第 104 条）
/// 落点改为尾块整块单次轻渐显：首批直显、开
/// 关关/Reduce Motion 全程直显，其余批次尾块
/// 单次 opacity 轻渐显——块级粒度下的「整批
/// 单次」，已闭合块永不重演
///
/// 段距两级口径（与落定整段呈现逐值一致、不
/// 产生落定跳变）：装配器把连续散文块（段落／
/// 标题／列表）并成一个 prose 段、段内段距走
/// paragraphSpacing；段界与其余相邻走 spacing-
/// SM；闭合前缀末块与尾块的衔接同走两级口径
/// （台账 185）。逐块呈现以 VStack 零距＋逐块
/// 底衬补出同一间隙序列
struct StreamingLiveText: View {
    let text: String
    /// 入场计划（调用方按发布门拍数/开关/Reduce
    /// Motion 单点裁定后注入）
    let entrancePlan: StreamingEntrance.Plan
    /// 发布代次（发布门 publishCount 的镜像）：
    /// 变化即新一批到达，batchFade 时尾块轻渐显
    let publishGeneration: Int

    @State private var tailOpacity: Double = 1
    @State private var fadedGeneration: Int = 0

    var body: some View {
        let blocks = StreamingBlockSegmenter.blocks(
            for: text
        )
        let parts = Self.closedParts(of: blocks)
        let tail = StreamingBlockSegmenter.tailSource(
            of: blocks
        )
        // 末块→尾块衔接口径须知尾块类别（gap-
        // After 两级口径，台账 185）；空尾无衔接
        let tailKind = tail.isEmpty
            ? nil
            : blocks.last(where: { $0.isTail })?.kind
        VStack(alignment: .leading, spacing: 0) {
            ForEach(
                Array(parts.enumerated()),
                id: \.element.block.index
            ) { pair in
                MarkdownText(pair.element.source)
                    .padding(
                        .bottom,
                        // 无尾块时末块底衬归零（泡内
                        // 不许凭空多一段距）
                        pair.offset == parts.count - 1
                            && tail.isEmpty
                            ? 0
                            : Self.gapAfter(
                                index: pair.offset,
                                parts: parts,
                                tailKind: tailKind
                            )
                    )
            }
            if !tail.isEmpty {
                MarkdownText(tail)
                    .opacity(tailOpacity)
            }
        }
        .onAppear { notePublishGeneration() }
        .onChange(of: publishGeneration) { _, _ in
            notePublishGeneration()
        }
    }

    /// 新一批到达的入场落点：batchFade 且代次
    /// 未演过 → 尾块整块单次轻渐显（0.45→1、
    /// 0.18s easeOut）；instant 恒直显。已演代
    /// 次不重演（视图重挂载时同代次不许再闪）
    private func notePublishGeneration() {
        guard publishGeneration > fadedGeneration
        else { return }
        fadedGeneration = publishGeneration
        guard entrancePlan == .batchFade else { return }
        tailOpacity = 0.45
        withAnimation(.easeOut(duration: 0.18)) {
            tailOpacity = 1
        }
    }

    /// 直播行高估算（§247 估算起步口径）：闭
    /// 合块逐块查合成器 markdownHeight——块源
    /// 冻结、文本备忘恒命中，单拍新增成本只剩
    /// 尾块；块间隙与呈现同走两级口径。估算与
    /// 视图实高容许小差（行标临界、布局提供者
    /// 量实回填修正——与落定行同制）
    static func estimatedHeight(
        for text: String,
        composer: ChatNativeRowHeightComposer
    ) -> CGFloat {
        let blocks = StreamingBlockSegmenter.blocks(
            for: text
        )
        let parts = closedParts(of: blocks)
        let tail = StreamingBlockSegmenter.tailSource(
            of: blocks
        )
        let tailKind = tail.isEmpty
            ? nil
            : blocks.last(where: { $0.isTail })?.kind
        var total: CGFloat = 0
        for (index, part) in parts.enumerated() {
            total += composer.markdownHeight(part.source)
            total += index == parts.count - 1 && tail.isEmpty
                ? 0
                : gapAfter(
                    index: index, parts: parts,
                    tailKind: tailKind
                )
        }
        if !tail.isEmpty {
            total += composer.markdownHeight(tail)
        }
        return total
    }

    /// 闭合块分解：逐块规范源（代码块补闭合围
    /// 栏形态，空源块剔除）＋块本体。块一经闭
    /// 合其源即冻结——尾块生长、新块闭合都不
    /// 改已闭合块的源
    static func closedParts(
        of blocks: [StreamingBlock]
    ) -> [(block: StreamingBlock, source: String)] {
        blocks.compactMap { block in
            guard !block.isTail else { return nil }
            let source = StreamingBlockSegmenter
                .closedPrefix(of: [block])
            return source.isEmpty
                ? nil : (block: block, source: source)
        }
    }

    /// 块后间隙：散文相邻（两侧都可并段）＝
    /// paragraphSpacing；其余相邻＝spacingSM。
    /// 末闭合块（其后是尾块）同走此两级口径：
    /// 尾块与末块同属可并段集时，落定装配器会
    /// 把两者并入同一 prose 段、界距走 paragra-
    /// phSpacing——衔接先按 spacingSM 取值会在
    /// 落定瞬间涨 4pt（台账 185 残差）；tailKind
    /// 为 nil（无尾块）时保留 spacingSM 兜底
    static func gapAfter(
        index: Int,
        parts: [(block: StreamingBlock, source: String)],
        tailKind: StreamingBlockKind? = nil
    ) -> CGFloat {
        guard index < parts.count - 1 else {
            if let tailKind,
               parts[index].block.kind.isProseMergeable,
               tailKind.isProseMergeable {
                return OneDayMetrics.paragraphSpacing
            }
            return OneDayMetrics.spacingSM
        }
        let here = parts[index].block.kind
        let next = parts[index + 1].block.kind
        return here.isProseMergeable && next.isProseMergeable
            ? OneDayMetrics.paragraphSpacing
            : OneDayMetrics.spacingSM
    }
}
