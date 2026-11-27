import OneDayCore
import OneDayDesign
import SwiftUI

/// 反应浮排会话（DESIGN §343／§346）：一次长按
/// 一份——呈现时刻组装的菜单数据（ChatView.
/// makeData 单源产物）、挂载点全局帧（快照原位对
/// 齐的定位原点）、阶段状态机。投递只经本类：状
/// 态机放行（deliverReaction/deliverAction）才调
/// data.onPickReaction／条目自带 action，错序点
/// 按（收起后残留点按等）不双投
@MainActor
final class ReactionBarSession: ObservableObject, Identifiable {
    let id = UUID()
    let entryID: UUID
    let data: ChatRowActionSheetData
    /// 长按挂载点在屏幕（.global）坐标系的帧
    let sourceFrame: CGRect
    /// 用户消息（右对齐气泡）：药丸排右缘对齐帧右缘
    let alignsTrailing: Bool

    private(set) var machine = ReactionBarStateMachine()

    init(
        entryID: UUID,
        data: ChatRowActionSheetData,
        sourceFrame: CGRect,
        alignsTrailing: Bool
    ) {
        self.entryID = entryID
        self.data = data
        self.sourceFrame = sourceFrame
        self.alignsTrailing = alignsTrailing
        // 会话只在浮排序由成立时创建（开关开＋可反
        // 应已由 ChatView.messageMenu 路由单点裁
        // 定），进场即 bar 阶段（三层同呈）
        machine.longPress(canReact: true)
    }

    var phase: ReactionBarPhase { machine.phase }

    /// 点药丸：状态机放行才投递、返回 true（视图
    /// 层据此关浮排）；阶段不合返回 false、不投递
    func pick(_ emoji: String) -> Bool {
        guard machine.pickReaction() == .deliverReaction
        else { return false }
        data.onPickReaction(emoji)
        return true
    }

    /// 点动作卡条目：状态机放行才执行条目自带
    /// action（与系统菜单同一闭包路由）、返回
    /// true；阶段不合返回 false、不执行
    func pickAction(_ item: ChatRowActionItem) -> Bool {
        guard machine.pickAction() == .deliverAction
        else { return false }
        item.action()
        return true
    }
}

/// 反应药丸浮排（DESIGN §343／§346）：Message-
/// Reactions.palette 全集单排陈列＋排尾「＋」全
/// 集入口；自己的现反应以 primaryTint 底色标出
/// （与 ChatReactionViews 悬挂 pill 的 own 段同
/// 口径）；面色/描边/影与悬挂 pill 同族（Palette.
/// surface＋pageBG 描边）。每枚带 VoiceOver 标
/// 签：未点走「反应：%@」、已点走悬挂 pill 既有
/// 口径「你的反应：%@，点按撤回」（点按语义同为
/// toggle 撤回——ChatView.toggleReaction 单点收
/// 口）。「＋」开系统半页 sheet 呈 ReactionEmoji-
/// Catalog.morePalette 网格，选中经同一 onPick
/// 投递路落反应（sheet 关净后才投递、防两面同拍
/// 打架）
struct ReactionFloatingBarView: View {
    let ownEmoji: String?
    let onPick: (String) -> Void
    var onOpenMore: (() -> Void)? = nil

    @State private var showsAllEmojis = false
    @State private var pendingPick: String?

    /// 单枚药丸边长（视觉 40＋排布凑点按面）
    static let pillSide: CGFloat = 40
    /// 浮排整体宽（palette 全集＋「＋」一格＋左右
    /// 内边距 6×2）
    static var barWidth: CGFloat {
        CGFloat(MessageReactions.palette.count + 1)
            * pillSide + 12
    }
    /// 浮排整体高（药丸 40＋纵向内边距 4×2）
    static let barHeight: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MessageReactions.palette, id: \.self) { emoji in
                Button {
                    onPick(emoji)
                } label: {
                    Text(emoji)
                        // P2-01 登记保留：反应 emoji 为内容层字形定点（非界面文字、不随 Dynamic Type 缩放）
                        .font(.system(size: 20))
                        .frame(
                            width: Self.pillSide,
                            height: Self.pillSide
                        )
                        .background(
                            emoji == ownEmoji
                                ? Palette.primaryTint
                                : Color.clear,
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(for: emoji))
            }
            plusButton
        }
        .padding(.horizontal, 6)
        .padding(.vertical, OneDayMetrics.spacingXS)
        .glassEffect(.regular, in: Capsule())
        .sheet(
            isPresented: $showsAllEmojis,
            onDismiss: deliverPendingPick
        ) {
            ReactionEmojiPickerView(ownEmoji: ownEmoji) { emoji in
                pendingPick = emoji
                showsAllEmojis = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    /// 「＋」全集入口（Muse 同位：排右端独立圆面）
    private var plusButton: some View {
        Button {
            if let onOpenMore {
                onOpenMore()
            } else {
                showsAllEmojis = true
            }
        } label: {
            ZStack {
                Circle().fill(Palette.pageBG)
                Image(systemName: "plus")
                    .font(.system(size: FrameworkIcon.actionGlyphSize, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 34, height: 34)
            .frame(
                width: Self.pillSide,
                height: Self.pillSide
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("更多反应"))
    }

    /// 半页选中先暂存、sheet 关净再投递（投递即关
    /// 整个呈现，两面同拍收起会打架）；取消半页
    /// （pendingPick 为空）不投递、浮排仍在场
    private func deliverPendingPick() {
        guard let emoji = pendingPick else { return }
        pendingPick = nil
        onPick(emoji)
    }

    private func label(for emoji: String) -> String {
        emoji == ownEmoji
            ? L10n.format("你的反应：%@，点按撤回", emoji)
            : L10n.format("反应：%@", emoji)
    }
}

/// 反应全集半页（DESIGN §346）：ReactionEmoji-
/// Catalog.morePalette 网格陈列；自己的现反应以
/// primaryTint 底色标出（与药丸同口径）；选中即
/// 回调（投递时序由浮排的 sheet onDismiss 收口）
struct ReactionEmojiPickerView: View {
    let ownEmoji: String?
    let onPick: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 44), spacing: OneDayMetrics.spacingXS)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("全部反应"))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, OneDayMetrics.spacingM)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXS)
            ScrollView {
                LazyVGrid(columns: columns, spacing: OneDayMetrics.spacingXS) {
                    ForEach(
                        ReactionEmojiCatalog.morePalette,
                        id: \.self
                    ) { emoji in
                        Button {
                            onPick(emoji)
                        } label: {
                            Text(emoji)
                                // P2-01 登记保留：反应 emoji 为内容层字形定点（非界面文字、不随 Dynamic Type 缩放）
                                .font(.system(size: 26))
                                .frame(width: 44, height: 44)
                                .background(
                                    emoji == ownEmoji
                                        ? Palette.primaryTint
                                        : Color.clear,
                                    in: Circle()
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(for: emoji))
                    }
                }
                .padding(OneDayMetrics.spacingSM)
            }
        }
    }

    private func label(for emoji: String) -> String {
        emoji == ownEmoji
            ? L10n.format("你的反应：%@，点按撤回", emoji)
            : L10n.format("反应：%@", emoji)
    }
}

/// 动作卡（DESIGN §346）：与药丸排同呈的自绘动
/// 作面——条目/顺序/图标/危险色逐项走 ChatRow-
/// ActionSheetData.actionItems() 单源（图标随项
/// 自带 systemImage、危险项 isDestructive 走
/// Palette.danger）；卡面与药丸同族（Palette.
/// surface＋pageBG 描边＋同款影）。行高 44（HIG
/// 点按面）、宽＝视口宽 ×0.625（Muse 量测约六成
/// 屏宽）
struct ReactionActionCardView: View {
    let items: [ChatRowActionItem]
    let onPick: (ChatRowActionItem) -> Void

    static let rowHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 6
    static let widthFraction: CGFloat = 0.625

    static func cardSize(
        itemCount: Int, viewportWidth: CGFloat
    ) -> CGSize {
        CGSize(
            width: viewportWidth * widthFraction,
            height: verticalPadding * 2
                + rowHeight * CGFloat(itemCount)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onPick(item)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: FrameworkIcon.fileGlyphSize))
                            .frame(width: 24)
                        Text(item.title)
                            .font(.rowTitle)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(
                        item.isDestructive
                            ? Palette.danger
                            : Palette.ink
                    )
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(height: Self.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.buttonCorner, style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.buttonCorner, style: .continuous
            )
            .strokeBorder(Palette.pageBG, lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
    }
}

/// 浮排动画参数表（DESIGN §471，照抄 Exyte
/// Chat MessageMenu.swift 源码 A 级原文——W6 换
/// Exyte 承载后由其状态机原生执行同一套，过渡
/// 期在自绘浮排上同值实现、参数不返工）：
/// 基准时长 D＝0.3s；三段时序点 0／0.33D／0.66D
/// ——背景先行 .easeInOut(D) 淡入、消息就位
/// .easeInOut(D×1.33≈0.4)、药丸/动作卡 .bouncy
/// (D) 于 0.33D 后入场；收起药丸/卡/快照
/// .snappy(D×0.66≈0.2)、背景延迟 0.33D 后
/// .easeOut(D) 淡出。背景双层参数同出 Exyte 原
/// 文：.ultraThinMaterial＋.primary.opacity(0.1)
enum ReactionBarMotion {
    /// 基准时长 D（Exyte animationDuration 默认）
    static let duration: CGFloat = 0.3
    /// 段间时序点 0.33D（Exyte 状态机 original/
    /// ready 推进点同值）
    static var stageDelay: CGFloat { duration / 3 }
    static var backgroundIn: Animation {
        .easeInOut(duration: duration)
    }
    static var messageIn: Animation {
        .easeInOut(duration: duration * 1.33)
    }
    static var chromeIn: Animation {
        .bouncy(duration: duration)
    }
    static var chromeOut: Animation {
        .snappy(duration: duration * 0.66)
    }
    static var backgroundOut: Animation {
        .easeOut(duration: duration)
            .delay(duration / 3)
    }
    /// 收起全程（背景淡出走完）后才摘会话的等待：
    /// 0.33D 延迟＋D 淡出，留 0.02 余量
    static var dismissalTotal: CGFloat {
        duration / 3 + duration + 0.02
    }
}

/// 浮排布局产物（DESIGN §346／§440）：药丸原点／
/// 动作卡原点与尺寸／快照可见带（帧全局坐标、定
/// 义呈现哪段内容）／快照落位顶（屏幕坐标、定义
/// 画在哪——整摞平移与顶锚时与可见带原位不同，
/// §440 分开两量）＋两端裁切标记（视图层据此挂
/// 渐隐 mask）
struct ReactionBarLayout: Equatable {
    var barOrigin: CGPoint
    var cardOrigin: CGPoint
    var cardSize: CGSize
    var snapshotVisibleRect: CGRect
    var snapshotPlacementY: CGFloat
    var clipsTop: Bool
    var clipsBottom: Bool
}

/// 浮排定位（纯函数）：
/// - barOrigin（§343 第一步）：只按消息框＋屏幕
///   尺寸算——优先上方（间距 8）、上方不足改下
///   方；横向按气泡对齐后夹进屏幕 8pt 安全边。
///   本函数逐值保留作回归锚（短消息在安全区内时
///   与 layout 的纵向结果一致）
/// - layout（§346 立、§386 改纵向求解、§440
///   再改判）：入参补安全区视口矩形，一次算齐
///   药丸/动作卡/快照带。§440 契约＝整摞锚定＋
///   预览完整呈现：快照带只被视口裁（§346/§386
///   「减层占位取最长段」是预览截断源头、退役），
///   药丸恒贴带上、卡恒贴带下，整摞刚体平移进
///   视口；整摞高过视口时药丸钉顶、卡钉底、带
///   取顶锚（自帧顶向下、底端裁切）。§386 的药
///   丸独立锚定＋卡从属求解（C1–C4）随之退役
enum ReactionBarPlacement {
    /// 层间与对消息的统一间距（现行 8pt 口径）
    static let gap: CGFloat = 8

    static func barOrigin(
        sourceFrame: CGRect,
        alignsTrailing: Bool,
        screenSize: CGSize
    ) -> CGPoint {
        let width = ReactionFloatingBarView.barWidth
        var x = alignsTrailing
            ? sourceFrame.maxX - width
            : sourceFrame.minX
        x = min(
            max(x, 8),
            max(8, screenSize.width - width - 8)
        )
        let above = sourceFrame.minY - 8
            - ReactionFloatingBarView.barHeight
        let y = above >= 8 ? above : sourceFrame.maxY + 8
        return CGPoint(x: x, y: y)
    }

    static func layout(
        sourceFrame: CGRect,
        alignsTrailing: Bool,
        viewport: CGRect,
        itemCount: Int
    ) -> ReactionBarLayout {
        let barW = ReactionFloatingBarView.barWidth
        let barH = ReactionFloatingBarView.barHeight
        let cardSize = ReactionActionCardView.cardSize(
            itemCount: itemCount,
            viewportWidth: viewport.width
        )
        let cardH = cardSize.height
        let safeTop = viewport.minY
        let safeBottom = viewport.maxY

        // 横向：药丸按气泡对齐、卡左对齐消息左缘，
        // 各自夹进视口左右 8pt（§386 口径不变）
        var barX = alignsTrailing
            ? sourceFrame.maxX - barW
            : sourceFrame.minX
        barX = min(
            max(barX, viewport.minX + gap),
            max(
                viewport.minX + gap,
                viewport.maxX - gap - barW
            )
        )
        var cardX = sourceFrame.minX
        cardX = min(
            max(cardX, viewport.minX + gap),
            max(
                viewport.minX + gap,
                viewport.maxX - gap - cardSize.width
            )
        )

        // 快照切片：帧∩视口——只被视口裁，不再被
        // 药丸/卡占位段切分（§440 改判本体）
        let sliceTop = max(sourceFrame.minY, safeTop)
        let sliceBottom = min(sourceFrame.maxY, safeBottom)
        let sliceHeight = max(0, sliceBottom - sliceTop)

        var barY: CGFloat
        var cardY: CGFloat
        var placementY: CGFloat
        var visibleHeight = sliceHeight
        if sliceHeight <= 0 {
            // 帧整出视口（极端贴边行）：快照不出
            // （高 0），药丸钉顶、卡钉底兜底
            barY = safeTop
            cardY = safeBottom - cardH
            placementY = sliceTop
        } else if barH + gap + sliceHeight + gap + cardH
            <= viewport.height {
            // 整摞装得下：刚体平移进视口（先保顶
            // 再保底，装得下时两保不冲突——平移后
            // 另一端自动在界内）
            var dy: CGFloat = 0
            let barY0 = sliceTop - gap - barH
            if barY0 < safeTop {
                dy = safeTop - barY0
            }
            let cardY0 = sliceBottom + gap
            if cardY0 + dy + cardH > safeBottom {
                dy = safeBottom - cardH - cardY0
            }
            barY = barY0 + dy
            cardY = cardY0 + dy
            placementY = sliceTop + dy
        } else {
            // 整摞高过视口：药丸钉视口顶、卡钉视
            // 口底，切片取顶锚带（自帧可见顶向下
            // 取满带高、底端裁切渐隐）
            barY = safeTop
            cardY = safeBottom - cardH
            placementY = barY + barH + gap
            visibleHeight = max(
                0,
                min(
                    sliceHeight,
                    cardY - gap - placementY
                )
            )
        }
        let visible = CGRect(
            x: sourceFrame.minX,
            y: sliceTop,
            width: sourceFrame.width,
            height: visibleHeight
        )
        return ReactionBarLayout(
            barOrigin: CGPoint(x: barX, y: barY),
            cardOrigin: CGPoint(x: cardX, y: cardY),
            cardSize: cardSize,
            snapshotVisibleRect: visible,
            snapshotPlacementY: placementY,
            clipsTop: sliceTop
                > sourceFrame.minY + 0.5,
            clipsBottom: sliceTop + visibleHeight
                < sourceFrame.maxY - 0.5
        )
    }
}

// MARK: - 原生 UIContextMenuInteraction 菜单构建器（#28）

/// iOS 17+ 原生上下文菜单构建器：将快捷表态药丸排收敛至 `UIMenu(options: .displayAsPalette)`
/// 并与标准动作条目合并为一个原生 `UIMenu`，供 `ChatNativeList` 长按复用。
@MainActor
enum ReactionContextMenuBuilder {
    static func makeMenu(
        data: ChatRowActionSheetData,
        canReact: Bool
    ) -> UIMenu {
        var children: [UIMenuElement] = []
        if canReact {
            let emojiActions = MessageReactions.palette.map { emoji in
                UIAction(
                    title: emoji,
                    state: emoji == data.ownReaction ? .on : .off
                ) { _ in
                    data.onPickReaction(emoji)
                }
            }
            let paletteMenu = UIMenu(
                title: "",
                options: [.displayInline, .displayAsPalette],
                children: emojiActions
            )
            children.append(paletteMenu)
        }
        let standardActions = data.actionItems().map { item in
            UIAction(
                title: item.title,
                image: UIImage(systemName: item.systemImage),
                attributes: item.isDestructive ? .destructive : []
            ) { _ in
                item.action()
            }
        }
        if !standardActions.isEmpty {
            children.append(
                UIMenu(title: "", options: .displayInline, children: standardActions)
            )
        }
        return UIMenu(title: "", children: children)
    }
}
