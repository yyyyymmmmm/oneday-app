import OneDayDesign
import SwiftUI

/// 流式打字渐显（0.3.0，DESIGN-V4 §14 条 4）：流式回复
/// 的新字以 blur 6px 起、120ms 化开，同批增量内的字
/// 依次错开 30ms 入场；已入场字符静止不重演。落盘后
/// 的成品消息改走 MarkdownText 静态渲染，本组件只活
/// 在流式进行中。
///
/// 词元口径：CJK 逐字成元（任意位置可断行）、拉丁字母
/// 按词成元（词不拆断）；词元以 TokenFlow 换行布局排
/// 布，流式光标作为末尾词元同流排布。
///
/// 动效纪律（0.3.2，DESIGN-V4 §17）：入场动画统一走
/// MotionTokens.streamIn＋resolved 出口（Reduce Motion
/// 开启时整段直显、无 stagger）；stagger 批级封顶——
/// 单批增量 >8 词元时步进压缩至总时长 240ms 且退化为
/// 纯 opacity（无 blur），断线重连的全量补发不被动画
/// 扣留（审查 M-2/E-4）。
struct StreamingText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tokens: [String] = []
    @State private var visible: Set<Int> = []
    /// 大批量增量中的词元：退化为纯 opacity 入场（无 blur）
    @State private var noBlur: Set<Int> = []

    var body: some View {
        TokenFlow(spacing: OneDayMetrics.tokenFlowSpacing) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                Text(token)
                    // 0.4.4（§29）：流式行与落盘正文同
                    // 口径——16pt（.callout 语义载体）＋
                    // bodyInk 炭灰；0.3.8 第 29 条的
                    // 17 regular 角色随正文基准一并改
                    .font(.callout)
                    .foregroundStyle(Palette.bodyInk)
                    .blur(
                        radius: visible.contains(index)
                            || noBlur.contains(index) ? 0 : 6
                    )
                    .opacity(visible.contains(index) ? 1 : 0)
                    .animation(
                        MotionTokens.resolved(
                            MotionTokens.streamIn,
                            reduceMotion: reduceMotion
                        ),
                        value: visible.contains(index)
                    )
            }
            StreamingCaret()
                .padding(.leading, OneDayMetrics.spacingMicro)
        }
        .onChange(of: text, initial: true) { _, newText in
            let newTokens = Self.tokenize(newText)
            let oldCount = tokens.count
            tokens = newTokens
            let batch = newTokens.count - oldCount
            guard batch > 0 else { return }
            if batch > 8 {
                noBlur.formUnion(oldCount..<newTokens.count)
            }
            // Reduce Motion：新词元整段直显，不排 stagger
            if reduceMotion {
                visible.formUnion(oldCount..<newTokens.count)
                return
            }
            // 旧词元保持已入场；新词元按批内序号错开入场，
            // 总时长封顶 240ms（大批量时步进等比压缩）
            let step = batch > 8 ? 0.24 / Double(batch) : 0.03
            for index in oldCount..<newTokens.count {
                let delay = min(Double(index - oldCount) * step, 0.24)
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    visible.insert(index)
                }
            }
        }
    }

    /// 分词：CJK/标点逐字，拉丁与数字按连续段成词，
    /// 空白独立成元（保留断行点）
    static func tokenize(_ text: String) -> [String] {
        var result: [String] = []
        var latinRun = ""
        func flush() {
            if !latinRun.isEmpty {
                result.append(latinRun)
                latinRun = ""
            }
        }
        for character in text {
            if let scalar = character.unicodeScalars.first,
               CharacterSet.alphanumerics.contains(scalar),
               character.isASCII {
                latinRun.append(character)
            } else {
                flush()
                result.append(String(character))
            }
        }
        flush()
        return result
    }
}

/// 词元换行布局：左到右排布、满行换行，行距可定。
/// sizeThatFits 与 placeSubviews 共用同一排布算法，
/// 尺寸与落位不会打架
struct TokenFlow: Layout {
    var spacing: CGFloat = OneDayMetrics.tokenFlowSpacing

    private func arrange(
        subviews: Subviews, width: CGFloat
    ) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            lineHeight = max(lineHeight, size.height)
            x += size.width
            maxX = max(maxX, x)
        }
        return (
            CGSize(width: maxX, height: y + lineHeight), origins
        )
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(
            subviews: subviews,
            width: proposal.width ?? .greatestFiniteMagnitude
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrange(subviews: subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let origin = result.origins[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + origin.x,
                    y: bounds.minY + origin.y
                ),
                proposal: .unspecified
            )
        }
    }
}

/// 流式光标：文末的 accent 小块，0.9 秒阶梯闪烁——它是
/// 「正在生成」的活信号，也是聊天页的签名细节。Reduce
/// Motion 时静止。（0.3.0 自 ChatView 移入，与渐显组件
/// 同文件。）
struct StreamingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45)) { context in
            let on = reduceMotion
                || Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.primary)
                .frame(width: 7, height: 16)
                .opacity(on ? 1 : 0.15)
        }
        .accessibilityHidden(true)
    }
}
