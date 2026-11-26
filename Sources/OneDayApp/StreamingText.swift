import OneDayCore
import OneDayDesign
import SwiftUI

/// 流式呈现（0.3.0 初版为逐词元 blur 渐显，DESIGN-V4
/// §14 条 4；2026-11-16 第 104 条到达减法改版）：入场
/// 计划由 Core StreamingEntrance 单点裁定——首批整批
/// 直显（指示器同拍换装、不留光标药丸帧），后续批次
/// 整批同拍单次轻渐显（opacity、MotionTokens.streamIn
/// 120ms，无 blur、无逐词元错开）；「打字动画」开关
/// （chat.streaming.typewriter，设置→外观）关或
/// Reduce Motion 时全程直显，Reduce Motion 优先。
/// 已入场字符静止不重演。落盘后的成品消息改走
/// MarkdownText 静态渲染，本组件只活在流式进行中。
///
/// 词元口径：CJK 逐字成元（任意位置可断行）、拉丁字母
/// 按词成元（词不拆断）；词元以 TokenFlow 换行布局排
/// 布，流式光标作为末尾词元同流排布。
///
/// 历史纪律（0.3.2，DESIGN-V4 §17）：入场动画统一走
/// MotionTokens.streamIn＋resolved 出口；断线重连的
/// 全量补发不被动画扣留（审查 M-2/E-4）——第 104 条
/// 下由「换代首批直显」承接。
///
/// 动画作用域（第 82 条，2026-11-15）：入场动画只许
/// 动 opacity（初版含 blur、第 104 条退役），词元
/// 位置永不进动画事务——动画收在 StreamingTokenView
/// 内部视觉层，被 TokenFlow 落位的视图自身不挂动画。
/// 定因与帧证据见
/// gen4-stream-overlap-diagnosis-20261115.md（旧形态
/// 动画挂在被落位视图整体上，换行边界词元的原点翻
/// 动被插值成纵向滑移＝真机叠字）。
struct StreamingText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 打字动画开关（第 104 条）：设置→外观「回复
    /// 呈现」节写、本组件读；缺省开。关＝全程直显
    @AppStorage(StreamingTypewriterFeature.defaultsKey)
    private var typewriterEnabled = true

    /// 词元稳定身份（原生重建 R2／H4，叠字静态定案
    /// 候选②的处置）：身份＝（代次，文内字符偏移）。
    /// 字符偏移是内容地址——文本追加时既有词元的偏
    /// 移恒不变（分词的前缀性质：追加只许末尾拉丁词
    /// 元原地生长或新增词元），与数组下标的「第几个」
    /// 在文本被替换时指错对象本质不同。代次在文本非
    /// 延续（封段后尾段重置／重连换文／回退）时 +1：
    /// 旧代次的入场记账与在途延时任务一并作废，不许
    /// 按旧身份给新词元点入场
    private struct TokenKey: Hashable {
        let generation: Int
        let offset: Int
    }

    /// 词元切片：视图身份取字符偏移（内容地址），
    /// TokenFlow 按序落位、身份只管动画记账对位
    private struct TokenSlice: Identifiable {
        let text: String
        let offset: Int
        var id: Int { offset }
    }

    @State private var visible: Set<TokenKey> = []
    @State private var generation = 0
    @State private var lastText = ""

    /// 文本延续判定：新文本以上拍文本为前缀＝同代
    /// 次追加；否则（替换/回退）＝换代。渲染拍（本
    /// 属性）与事件拍（onChange 推进存储代次）用同
    /// 一规则、两处同值，不分叉
    private static func isContinuation(
        from old: String, to new: String
    ) -> Bool {
        new.hasPrefix(old)
    }

    /// 本拍代次：存储代次＋（与 lastText 比对的换代
    /// 增量）——onChange 落账前后的两拍读数一致
    private var displayGeneration: Int {
        generation
            + (Self.isContinuation(from: lastText, to: text)
                ? 0 : 1)
    }

    /// 词元切分（同步派生）：分词结果与其文内字符
    /// 偏移——词元全序拼接恒等于原文（分词的完备
    /// 性），偏移由累加词元长得出、是内容真值
    private static func slices(
        for text: String
    ) -> [TokenSlice] {
        var result: [TokenSlice] = []
        var offset = 0
        for token in tokenize(text) {
            result.append(
                TokenSlice(text: token, offset: offset)
            )
            offset += token.count
        }
        return result
    }

    var body: some View {
        // 词元每拍由当前 text 同步派生、不经 @State
        // 滞后（R2／H4）：块闭合的那一拍，前缀（父
        // 级 MarkdownText）与本尾块由同一份文本同拍
        // 换代——旧形态 @State 词元晚一拍更新，闭合
        // 块在两层各出现一份是构造必然（叠字定案候
        // 选③）；同步派生后尾块词元同拍消失，构造上
        // 不存在同帧两份。滞后的只剩入场记账（visi-
        // ble），它只管浓淡、不管有无
        let gen = displayGeneration
        let slices = Self.slices(for: text)
        return TokenFlow(spacing: OneDayMetrics.tokenFlowSpacing) {
            ForEach(slices) { slice in
                // 第 82 条：被 TokenFlow 落位的是
                // StreamingTokenView——它自身不挂动画，
                // 入场动画收在其内部视觉层（见该类型注）
                StreamingTokenView(
                    token: slice.text,
                    shown: visible.contains(
                        TokenKey(
                            generation: gen,
                            offset: slice.offset
                        )
                    )
                )
            }
            StreamingCaret()
                .padding(.leading, OneDayMetrics.spacingMicro)
        }
        // 0.43.0（A11Y-V3）：流式呈现对 VO 合并为整段
        // 文本元素——词元是视觉动画单位、逐个可达只
        // 会把一句话的朗读切碎；标签直读全文（text
        // 状态），流式中焦点停留时按系统节奏刷新，
        // 完成播报另有 S6 通道。视觉零变化
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onChange(of: text, initial: true) { _, newText in
            reconcile(newText)
        }
    }

    /// 入场记账对账（文本每变一拍）：推进代次、清
    /// 旧代次账、按入场计划（Core StreamingEntrance）
    /// 给未入场词元显形。渐显任务带代次校验——在途
    /// 期间文本被替换（代次已进）则任务作废，不许把
    /// 旧身份的入场点到新词元头上
    private func reconcile(_ newText: String) {
        let delta = Self.isContinuation(
            from: lastText, to: newText
        ) ? 0 : 1
        let newGeneration = generation + delta
        generation = newGeneration
        lastText = newText
        visible = visible.filter {
            $0.generation == newGeneration
        }
        let pending = Self.slices(for: newText).filter {
            !visible.contains(
                TokenKey(
                    generation: newGeneration,
                    offset: $0.offset
                )
            )
        }
        guard !pending.isEmpty else { return }
        let keys = pending.map {
            TokenKey(
                generation: newGeneration, offset: $0.offset
            )
        }
        // 第 104 条到达减法：计划单点裁定——首批
        // （本代次尚无已显词元，含指示器换装拍与换
        // 代重发）整批直显；开关关／Reduce Motion
        // 直显；其余批次整批同拍渐显（一个任务翻
        // 全批、无逐词元错开）。旧词元保持已入场
        let plan = StreamingEntrance.plan(
            typewriterEnabled: typewriterEnabled,
            reduceMotion: reduceMotion,
            isFirstBatchOfGeneration: visible.isEmpty
        )
        switch plan {
        case .instant:
            visible.formUnion(keys)
        case .batchFade:
            Task {
                guard self.generation == newGeneration
                else { return }
                self.visible.formUnion(keys)
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

/// 词元视觉层（第 82 条）：TokenFlow 落位的就是本视
/// 图，它自身不挂任何动画修饰——父 Layout 赋予的
/// origin 变更永远直跳、不进动画事务。入场动画只
/// 挂在 body 内的 Text 上：动画域仅限本视图内部的
/// 视觉属性，够不到外层落位。
///
/// 病根回溯（gen4-stream-overlap-diagnosis-20261115）：
/// 旧形态把 .animation(streamIn, value:) 直接挂在被
/// 落位的词元视图上——该修饰的语义是「值变时本视
/// 图一切可动画属性一并过渡」，TokenFlow 每拍重排
/// 时换行边界词元的原点翻动被 120ms easeOut 插值
/// 成纵向滑移、压住本行字形（真机叠字）。落定字形
/// 与行中追加字的观感（只有浓淡、无位移）由本分层
/// 保持。
///
/// 第 104 条：入场只剩 opacity 一项——blur 随逐词
/// 元错开一并退役（到达瞬间动画叠加的用户实报），
/// 显形节奏由 reconcile 的整批计划决定，本层只管
/// 单次浓淡过渡
private struct StreamingTokenView: View {
    let token: String
    /// 已入场（visible 含本词元序号）
    let shown: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(token)
            // 0.4.4（§29）：流式行与落盘正文同
            // 口径＋bodyInk 炭灰；§263（组版
            // 0.50.53 顺延 §282）：正文基准升
            // .body（17pt），流式同源跟随、
            // 落盘不跳字号
            .font(.body)
            .foregroundStyle(Palette.bodyInk)
            .opacity(shown ? 1 : 0)
            .animation(
                MotionTokens.resolved(
                    MotionTokens.streamIn,
                    reduceMotion: reduceMotion
                ),
                value: shown
            )
    }
}

/// 词元换行布局：左到右排布、满行换行，行距可定。
/// sizeThatFits 与 placeSubviews 共用同一排布算法，
/// 尺寸与落位不会打架
///
/// 第 82 条：排布经 TokenFlowArranger 缓存——贪心逐
/// 行落位下，词元 i 的原点只取决于它之前的词元尺
/// 寸与行宽，追加永不翻动前缀原点；缓存按（行宽＋
/// 间距＋尺寸序列）记账，纯追加只续排尾部。失效口
/// 径：行宽变、或已排前缀任一词元尺寸变（分词重组、
/// 字号环境变都会改尺寸）→ 自首个不一致处起重排，
/// 不给陈旧排版（与流式卡顿定因的「全量重排」同账）
struct TokenFlow: Layout {
    var spacing: CGFloat = OneDayMetrics.tokenFlowSpacing

    func makeCache(subviews: Subviews) -> TokenFlowArranger {
        TokenFlowArranger()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TokenFlowArranger
    ) -> CGSize {
        cache.arrange(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: proposal.width ?? .greatestFiniteMagnitude,
            spacing: spacing
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TokenFlowArranger
    ) {
        let result = cache.arrange(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            width: bounds.width,
            spacing: spacing
        )
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

/// TokenFlow 排版引擎（纯值形态，可单测）：贪心逐行
/// 落位＋前缀缓存。缓存键＝（行宽，间距，已排尺寸序
/// 列）；命中形态有二——全等（整表复用）与共享前缀
/// （自首个尺寸不一致处、或纯追加的尾部续排，前缀
/// 原点逐点复用）。行宽/间距变、或前缀尺寸变 → 对
/// 应位置起重排（lastResumeIndex 记本次续排起点：
/// 0＝自首词元重排）。排版结果只由尺寸序列决定，
/// 与子视图身份无关——末尾光标这类「位置会移、尺
/// 寸恒定」的子视图在序列里只是一个普通元素，前缀
/// 比对在它处自然分界、词元前缀照常复用
struct TokenFlowArranger {
    /// 落完一个词元后的游标（续排的衔接状态）
    private struct Cursor: Equatable {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
    }

    private var cachedWidth: CGFloat?
    private var cachedSpacing: CGFloat = 0
    private var cachedSizes: [CGSize] = []
    private var cachedOrigins: [CGPoint] = []
    private var cursors: [Cursor] = []
    /// 最近一次 arrange 的续排起点（诊断/测试读数）
    private(set) var lastResumeIndex = 0

    mutating func arrange(
        sizes: [CGSize], width: CGFloat, spacing: CGFloat
    ) -> (size: CGSize, origins: [CGPoint]) {
        var resume = 0
        var cursor = Cursor()
        var origins: [CGPoint] = []
        if cachedWidth == width, cachedSpacing == spacing {
            let limit = min(cachedSizes.count, sizes.count)
            var prefix = 0
            while prefix < limit,
                  cachedSizes[prefix] == sizes[prefix] {
                prefix += 1
            }
            if prefix > 0 {
                resume = prefix
                origins = Array(cachedOrigins.prefix(prefix))
                cursor = cursors[prefix - 1]
            }
        }
        var nextCursors = Array(cursors.prefix(resume))
        for index in resume..<sizes.count {
            let size = sizes[index]
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += cursor.lineHeight + spacing
                cursor.lineHeight = 0
            }
            origins.append(CGPoint(x: cursor.x, y: cursor.y))
            cursor.lineHeight = max(cursor.lineHeight, size.height)
            cursor.x += size.width
            cursor.maxX = max(cursor.maxX, cursor.x)
            nextCursors.append(cursor)
        }
        let total = CGSize(
            width: cursor.maxX,
            height: cursor.y + cursor.lineHeight
        )
        cachedWidth = width
        cachedSpacing = spacing
        cachedSizes = sizes
        cachedOrigins = origins
        cursors = nextCursors
        lastResumeIndex = resume
        return (total, origins)
    }
}

/// Phase 6.3：iOS 18+ 原生 `TextRenderer` 流式轻渐显渲染器，
/// 用于单 `Text` 零子视图开销场景（保留 `StreamingText`/`TokenFlow` 兼容既有单测）。
struct StreamingFadeTextRenderer: TextRenderer {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var copy = context
            copy.opacity = max(0.0, min(1.0, progress))
            copy.draw(line)
        }
    }
}

/// 流式光标（Phase 6.2）：改用系统原生 `PhaseAnimator` 替代 `TimelineView` 周期轮询，
/// 由 CoreAnimation 直接驱动、Reduce Motion 时静止。
struct StreamingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            caretShape.opacity(1)
        } else {
            PhaseAnimator([true, false]) { bright in
                caretShape.opacity(bright ? 1 : 0.15)
            } animation: { _ in
                .easeInOut(duration: 0.45)
            }
        }
    }

    private var caretShape: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Palette.primary)
            .frame(width: 7, height: 16)
            .accessibilityHidden(true)
    }
}
