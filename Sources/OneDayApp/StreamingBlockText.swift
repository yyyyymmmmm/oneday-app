import OneDayCore
import OneDayDesign
import SwiftUI

/// §247（2026-11-14，换代包 4）流式块级呈现：
/// 流式正文按 Core 切块分两段呈现——已闭合块走
/// 落定同路渲染（MarkdownText，块内容冻结、渲染
/// 结果与落定形态一致），只有未闭合的尾块走逐词
/// 渐显（StreamingText）。蓝图 §1.4 的呈现落法：
/// blur/渐显只作用于尾块新增词元，TokenFlow 的
/// 全文 arrange 就此退役（组件本身留给尾块尺
/// 度）；块闭合的那一拍，该块由尾块呈现切换为
/// 前缀渲染——切换点与产物冻结同点（同一块切分
/// 事实），落定不过是尾块也闭合的终态，故落定
/// 前后呈现同构、无整树换装。
///
/// 段间口径：外层段距取 spacingSM，与 Mark-
/// downText 内部段距同值——闭合前缀的末段与尾
/// 块的衔接距和落定后同一位置的段距一致，落定
/// 帧不因呈现拼合方式产生段距跳变
struct StreamingBlockText: View {
    let text: String

    var body: some View {
        let blocks = StreamingBlockSegmenter.blocks(for: text)
        let prefix = StreamingBlockSegmenter
            .closedPrefix(of: blocks)
        let tail = StreamingBlockSegmenter
            .tailSource(of: blocks)
        VStack(
            alignment: .leading,
            spacing: OneDayMetrics.spacingSM
        ) {
            if !prefix.isEmpty {
                MarkdownText(prefix)
            }
            StreamingText(tail)
        }
    }
}
