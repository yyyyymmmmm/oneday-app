import NukeUI
import OneDayDesign
import OneDayCore
import Photos
import QuickLook
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ChatView 覆盖层、交互修饰器与辅助控制器（#33 模块化拆分）
#if canImport(UIKit)
import UIKit
#endif

/// 聊天页：本地会话（SwiftData）＋ /v1/chat/completions 流式。
/// 上下文取当前会话最近 20 条；停止生成保留已生成的半截回复。
/// v2 视觉（docs/DESIGN-V2.md §3.5）：用户是浅染气泡、输入区
/// 是浮空胶囊，流式光标是本页的签名细节。助手消息形态三度
/// 易稿：v2 定为裸排（学 ChatGPT/Claude），0.2.5 按用户真机
/// 对照 Muse 推翻改浅灰软填充泡（DESIGN-V4 §9 追记），
/// 2026-11-13 割裂感 A 止血档再改判回落面（散文直落大面、
/// 异构件才成卡，见 assistantBubble 注），填充泡口径一度
/// 作废；2026-11-14 §225 用户点选三项全改恢复气泡（中性
/// 浅灰容器＋纯文字内容，A1 撤泡口径作废，见 §225.2）。
/// 0.1.3 导航（§7）：会话历史改左侧抽屉（顶栏左键＋左缘手势
/// 唤出），顶栏中 = 会话名＋模型名副题，右 = 新建会话。

/// 距底原始读数匣（§199）：滚动几何回调逐帧写、
/// 落定评估（R4 事件化后为事件到场即读）的原始距
/// 底——旧形态
/// 存 @State，滚动中读数逐帧变、等值守卫挡不住，
/// 等于每帧触发一次全页 body 重跑（审计 §2.1 的放
/// 大器一半）。改存引用匣：写不触发任何视图失效，
/// 读到的恒是读时点的最新值——消费者（落定评估
/// 与同点打点）在读时点上与旧 @State
/// 读数逐字相等，判定阈值与语义零变更，只降回写
/// 频次（§199 包 1 第三件）。经 @State 持实例（初
/// 值只用一次），跨 body 重建恒为同一匣
final class BottomDistanceRecorder {
    var latest: CGFloat = 0
    /// 内容末端（栈尾锚）是否完整落在可视区内（手感
    /// A 档事实信号，见 Core BottomFactCalibration
    /// 注）：由尾锚自身的几何回调写本匣——与 latest
    /// 同纪律，写不失效任何视图，只在派生点与评估
    /// 点被读；切线程时由线程切换路清零，防旧线程
    /// 的末端事实误校新线程首帧
    var contentEndVisible = false
    /// 列表容器高（与 latest 同源的几何读数）：喂尾
    /// 锚事实回调判「完整可见」的视口高——@State 的
    /// listViewportHeight 只供内容栈撑满，两处同源
    /// 不分叉，本匣是事实回调的读口
    var containerHeight: CGFloat = 0
    /// 列表底 inset 实值（adjustedContentInset.
    /// bottom 的同拍读数）：喂尾锚回调的有效视口
    /// 判定——视口高须扣除本带（＝输入舱遮挡带，
    /// 尾锚落在带内不算「在屏可读」）；与 latest
    /// 同纪律、写不失效任何视图
    var bottomInset: CGFloat = 0
}

/// P2 架构解耦：对话内查找状态机控制器。
/// 将原本散落在 ChatView 中的 6 个 @State 查找属性与防抖/导航/高亮生命周期收归独立可观测控制器，
/// 避免查找输入高频刷新触发 ChatView 顶层状态膨胀。
@MainActor
@Observable
final class ChatFindController {
    var isPresented = false
    var query = ""
    var session = ChatFindSession()
    var highlightEntryID: UUID?
    var huntToken: UUID?
    var huntedKey: String?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedQuery: String? {
        ChatFind.normalizedQuery(query)
    }

    func open() {
        isPresented = true
    }

    func clearMatches() {
        var next = session
        next.reset()
        session = next
        highlightEntryID = nil
        huntedKey = nil
    }

    func close() {
        isPresented = false
        query = ""
        huntToken = nil
        clearMatches()
    }

    func highlightQuery(for entryID: UUID) -> String? {
        guard isPresented, session.matches.contains(entryID) else { return nil }
        return normalizedQuery
    }

    func applyTarget(_ targetID: UUID, focus: (UUID) -> Void) {
        highlightEntryID = targetID
        focus(targetID)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if self?.highlightEntryID == targetID {
                self?.highlightEntryID = nil
            }
        }
    }

    func moveNext(focus: (UUID) -> Void) {
        var next = session
        guard let target = next.moveNext() else { return }
        session = next
        applyTarget(target, focus: focus)
    }

    func movePrevious(focus: (UUID) -> Void) {
        var next = session
        guard let target = next.movePrevious() else { return }
        session = next
        applyTarget(target, focus: focus)
    }
}



/// 原生面行菜单承载开关（§330，0.50.70 热修题
/// 2；§332 换代；台账 187 再换代）：原生面动作
/// 面改由控制器长按识别器承载（ChatNative-
/// List），托管内容内的 SwiftUI 长按须在本面关
/// 闭——两承载同挂会双出面、且 SwiftUI 承载正
/// 是 .69 真机长按全灭的当事层。仅原生面行构
/// 造点置 false；gen3 面无此环境值、默认 true
/// 消息长按菜单挂载（0.4.1 立制；台账 200 拆
/// 换，2026-11-21 用户拍板）：回归系统上下文菜
/// 单——0.4.1 旧制本就是系统 contextMenu，台账
/// 187 改自绘动作面（自家长按识别器＋hitTest
/// 分工＋自绘 sheet）后长按在真机与测试环境双
/// 双失灵，拍板整套退役：本修饰符只挂菜单数
/// 据，识别/呈面/消失全归系统。
/// §265 挂载面纪律不变：只许落在非文本层——气
/// 泡背景层（背景＋内边距带）与行内铬件（图片
/// 卡/文件牌/交付项/引用块/状态行）；不许挂行
/// 内容根。§471 口径变更：「文本区长按归
/// UITextView 原生选字」作废——列表态正文关
/// 直接选字，长按一切落点归菜单/浮排，选字只
/// 从菜单「选择」行进入（141/142 承载本体不动）。
/// 动作集单源不变：呈现时刻经 makeData 组装
/// （ChatView.actionSheetData）——反应走「添加
/// 反应」子菜单，动作项走 actionItems() 逐项搬
/// 家。反应排沿革：台账 187 起走菜单顶部内联
/// ControlGroup，0.50.79 真机被系统拆成逐行陈
/// 列（首行三枚、余者各占一整行）、形态全毁，
/// 0.50.80 热修改子菜单原生陈列；Muse 式浮排
/// 反应条（预览上方独立药丸）另包施工
struct MessageMenuModifier: ViewModifier {
    let isEnabled: Bool
    /// 反应浮排挂钩（DESIGN §343）：非 nil＝本挂载
    /// 点长按先走浮排（开关开＋本条可反应，路由在
    /// ChatView.messageMenu 单点裁定）；nil＝纯系
    /// 统菜单形态（0.50.80 口径逐字不变）
    var floatingBarHook: ((CGRect) -> Void)? = nil
    /// 浮排在场时本条菜单摘除（长按竞速护栏：自家
    /// 手势 0.35s 先行呈浮排并置本旗、系统识别器
    /// 约 0.5s 拍到时无菜单可呈，杜绝双面同呈；浮
    /// 排关后自动复位。VoiceOver 呈菜单走系统路
    /// 径、不经触摸长按，摘除只在浮排在场期间、
    /// 与其互斥不亏入口）
    var menuSuppressed: Bool = false
    /// 呈现时刻组装菜单数据（动作集单源）
    let makeData: () -> ChatRowActionSheetData

    /// 测试装配钉：浮排序由是否在本修饰符生效
    var usesFloatingBar: Bool { floatingBarHook != nil }

    /// 挂载点全局帧（背景 GeometryReader 发布、长
    /// 按触发时刻读——快照原位对齐的定位原点）
    @State private var mountFrame: CGRect = .zero

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            if let floatingBarHook {
                floatingBarBody(content, hook: floatingBarHook)
            } else {
                content.contextMenu { menuContent() }
            }
        } else {
            content
        }
    }

    /// 浮排形态：系统菜单照旧在位（VoiceOver 与未
    /// 触发浮排时的完整入口），另加同位长按手势
    /// （0.35s、与既有手势同时识别不夺触摸——行
    /// 级仲裁〔右滑 pan/滚动/选字〕一律不碰）＋挂
    /// 载帧发布
    @ViewBuilder
    private func floatingBarBody(
        _ content: Content,
        hook: @escaping (CGRect) -> Void
    ) -> some View {
        Group {
            if menuSuppressed {
                content
            } else {
                content.contextMenu { menuContent() }
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            mountFrame = frame
        }
        .simultaneousGesture(
            LongPressGesture(
                minimumDuration: 0.35, maximumDistance: 10
            ).onEnded { _ in
                hook(mountFrame)
            }
        )
    }

    /// 系统菜单内容（单源，两形态共用）：反应走
    /// 「添加反应」子菜单、动作走 actionItems()
    /// 逐项搬家
    @ViewBuilder
    private func menuContent() -> some View {
        let data = makeData()
        if data.canReact {
            Menu {
                ForEach(
                    MessageReactions.palette,
                    id: \.self
                ) { emoji in
                    Button {
                        data.onPickReaction(emoji)
                    } label: {
                        if emoji == data.ownEmoji {
                            Label(
                                emoji,
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(emoji)
                        }
                    }
                }
            } label: {
                Label(
                    "添加反应",
                    systemImage: MessageActionSymbols
                        .react
                )
            }
        }
        ForEach(data.actionItems()) { item in
            Button(
                role: item.isDestructive
                    ? .destructive : nil
            ) {
                item.action()
            } label: {
                Label(
                    item.title,
                    systemImage: item.systemImage
                )
            }
        }
    }
}

/// 挂载点帧发布键（DESIGN §343）：MessageMenu-
/// Modifier 的背景 GeometryReader 发布其在
/// .global 的帧、修饰符自身在背景子树内订阅
/// （订阅点不罩内容子树，嵌套挂载点的帧不串扰）
struct MessageMenuFrameKey: PreferenceKey {
    nonisolated static let defaultValue: CGRect = .zero
    static func reduce(
        value: inout CGRect, nextValue: () -> CGRect
    ) {
        value = nextValue()
    }
}

/// 右滑引用（0.36.19 立；0.36.26 §95 按生产同
/// 构整件重做）：气泡向右滑，横向拖动显出回复箭
/// 头，拖动途中过线即触发引用——与长按菜单「回
/// 复」同一动作（beginReply），两路并存不互斥
/// （长按是静止按压、右滑是横向拖动，形态不重
/// 叠）。
///
/// 数值口径（沿 §95 定版、Stream 参数单源）：判
/// 定全走 Core SwipeReplyMotion——起滑 30/途中
/// 触发 60/显示封顶 90；起始点排除区（行内自有
/// 横向交互的子区——代码块/表格的横向滚动区）
/// 经 PreferenceKey 发布其在命名坐标空间内的
/// 帧，起始点落在其中则整段忽略。
///
/// 识别层沿革：0.36.26–§264 是 Stream 同构的
/// SwiftUI `.simultaneousGesture(DragGesture)`
/// （0.36.20–0.36.23 的 UIKit 探针桥四轮真机全
/// 灭后退役，P-15）。§265（换代包 5）按用户
/// 2026-11-14 亲令大厂机制③换代：双审计定性
/// simultaneousGesture 的跟踪消耗文本视图触摸
/// 序列、双击选字被截流——识别改走 UIKit 识别
/// 器桥（SwipeReplyPanBridge：UIPanGesture-
/// Recognizer 装宿主滚动视图，方向门＝识别器
/// 子类 began 前位移锁（换代包 8）＋纵滚
/// require(toFail:) 让行），本修饰符只持拖动
/// 状态、经桥的两条回调消费位移/收尾。与桥时
/// 代（0.36.20）的差别：装配走 ScrollViewTap-
/// Dismiss 已验的 ascend 寻面、判据只两条明路
/// （速度门＋失败依赖）、数值口径零自创。
/// 箭头在内容左缘下层：随显形进度淡入/缩放，
/// 越线转武装态，且触发与触觉在越线同一刻发
/// 生（途中触发，不等松手）；松手只做回位
/// §199：internal（原 private）——选字计数证死/回归
/// 测试须装配生产原物验证结构身份，不许在测试侧复
/// 制一份同形修饰符充数
struct SwipeReplyModifier: ViewModifier {
    let isEnabled: Bool
    /// 选区抑制（141/142 根治）：pan 回调时刻直读
    /// （账本选区在场即抑制）——不经 body 重算、
    /// 不翻结构，托管视图零换代（与 OB selecting
    /// 态只切手势 enabled 同构）。默认不抑制
    var isSuppressed: () -> Bool = { false }
    let onReply: () -> Void

    @State private var dragOffset: CGFloat = 0
    /// 整段拖动只触发一次（越线当场置位、松手复位）
    @State private var hasTriggered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            ZStack(alignment: .leading) {
                replyArrow
                content
                    // 命中域＝整条消息容器（Stream
                    // 行同款 contentShape）：行内空
                    // 区起手也能拖（§265 后命中圈定
                    // 由桥的 shouldReceive 按行帧判，
                    // 本 contentShape 只管行内 SwiftUI
                    // 命中形态、语义不变）
                    .contentShape(Rectangle())
                    // §265：UIKit 识别器桥挂行内容
                    // background（零尺寸语义外的全帧
                    // 背景视图、isUserInteractionEna-
                    // bled=false 不夺命中；识别器本
                    // 体装在宿主滚动视图上，见
                    // SwipeReplyPanBridge）
                    .background {
                        SwipeReplyPanInstaller(
                            onPanChanged: { translationX in
                                handlePanChanged(translationX)
                            },
                            onPanEnded: {
                                handlePanEnded()
                            }
                        )
                    }
                    .offset(
                        x: SwipeReplyMotion.displayOffset(
                            for: dragOffset
                        )
                    )
            }
        } else {
            content
        }
    }

    /// 桥回调·拖动中：只消费横向位移写 offset
    /// （判定走 Core 单源）；越线当场触发＋触觉
    /// （整段只一次）。起始点排除已由桥在 sho-
    /// uldBegin 判死（识别器根本不开始），本处
    /// 不再复查
    /// 选区抑制在场时整段不消费：位移归零待命
    /// （拖选字手柄的横移不许把行拖出引用位）
    private func handlePanChanged(_ translationX: CGFloat) {
        if isSuppressed() {
            if dragOffset != 0 { dragOffset = 0 }
            return
        }
        let newOffset = SwipeReplyMotion.dragOffset(
            translationWidth: translationX,
            currentOffset: dragOffset
        )
        dragOffset = newOffset
        if !hasTriggered,
           SwipeReplyMotion.shouldTrigger(
               offset: newOffset
           ) {
            hasTriggered = true
            // 轻触觉（动效宪法表 D，impact
            // .light 落点不变）：与引用落定同
            // 一因果链，只震这一次
            Haptics.impact(.light)
            onReply()
        }
    }

    /// 桥回调·收尾：松手/取消/失败同口——复位触
    /// 发标记、动画回位、不再判触发。选区抑制在
    /// 场时同样只复位（抑制中不判触发，见
    /// handlePanChanged）
    private func handlePanEnded() {
        hasTriggered = false
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.swap,
                reduceMotion: reduceMotion
            )
        ) {
            dragOffset = 0
        }
    }

    /// 左缘回复箭头：显形进度驱动透明度与缩放，过
    /// 线武装态换主色盘（Palette.primaryPale＋onPri-
    /// mary 箭头——2026-11-15 第 85 条 BC-1 同类收
    /// 口：onPrimary 的配对面恒是 primaryPale，旧
    /// primary 盘暗档实算 2.33）——武装与触发同刻
    /// （途中触发口径）
    private var replyArrow: some View {
        let progress = SwipeReplyMotion.revealProgress(
            offset: dragOffset
        )
        let armed = SwipeReplyMotion.shouldTrigger(
            offset: dragOffset
        )
        return Image(systemName: MessageActionSymbols.reply)
            .font(.system(size: FrameworkIcon.inlineGlyphSize, weight: .semibold))
            .foregroundStyle(
                armed ? Palette.onPrimary : Palette.inkSecondary
            )
            .frame(width: 30, height: 30)
            .background(
                armed ? Palette.primaryPale : Palette.fieldFill,
                in: Circle()
            )
            .opacity(progress)
            .scaleEffect(0.6 + 0.4 * progress)
            .padding(.leading, OneDayMetrics.spacingXS)
            .accessibilityHidden(true)
    }
}

extension View {
    /// 标记右滑引用排除区：本视图区域内的横滑归
    /// 它自己的横向交互（代码块/表格横滚），不触
    /// 发本行右滑引用。形态沿革：0.36.26 §95 初版
    /// 为背景 GeometryReader 在命名坐标空间经偏
    /// 好键发布帧、行修饰符 @State 收集——行内协
    /// 商型构件兼作手势仲裁、布局期反哺状态，与
    /// 列表行「尺寸确定」通则相悖（大厂差距审计
    /// G-07）；2026-11-23 收口改贴 UIKit 标记视图
    /// （SwipeReplyExcludedMarker），帧由识别器
    /// 桥在判定时刻自 cell 视图层级直算，行内不
    /// 再有布局反哺点
    func swipeReplyExcluded() -> some View {
        background { SwipeReplyExcludedMarker() }
    }
}

/// D3 编辑武装目标（DESIGN §352）：值快照、不持
/// SwiftData 对象（与 SelectionPayload 同律）
struct EditSentTarget {
    let entryID: UUID
    let rowID: Int
}

/// D3 待确认发稿快照（DESIGN §352）：send() 起手
/// 的快照四件（正文/附件/引用两槽）整包暂存，确
/// 认与取消都不回读发送舱现值
struct EditSendDraft {
    let text: String
    let attachments: [PendingAttachment]
    let quote: MessageQuote?
    let feedQuote: FeedPostQuote?
    let sourceQuote: SourceQuote?
}

/// D3 编辑横幅槽（DESIGN §352；0.50.88 自 composerCard
/// 抽出独立成型）：武装条件在本槽内求值，宿主卡的组
/// 合类型不随编辑态多一层条件包装（真机启动崩溃热修，
/// 见 DESIGN §354）。形态与引用块同位同式：横幅本体
/// （铅笔＋一行说明＋尾 ✕ 取消——解武装清舱、原条目
/// 无损）＋发丝分隔线同进同出
struct EditSentBannerSlot: View {
    let isArmed: Bool
    let onCancel: () -> Void

    var body: some View {
        if isArmed {
            VStack(spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "pencil")
                        .font(.system(size: FrameworkIcon.miniGlyphSize, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                    Text("正在编辑较早的一条消息")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: FrameworkIcon.miniGlyphSize, weight: .semibold))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 28, height: 28)
                            .frame(
                                width: OneDayMetrics.minTapTarget,
                                height: OneDayMetrics.minTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    .accessibilityLabel("取消编辑")
                }
                .padding(.horizontal, OneDayMetrics.spacingSM)
                .padding(.vertical, OneDayMetrics.spacingS)
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, OneDayMetrics.spacingSM)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }
}

/// 「选择」sheet 载荷（0.4.1）
struct SelectionPayload: Identifiable {
    let id = UUID()
    let text: String
}

/// 分享载荷（§330）：原生面 UIKit 行菜单的「分
/// 享」动作落点——ShareLink 是 SwiftUI 视图、
/// UIKit 菜单内无处安放，改经本状态口开系统分
/// 享单（与 gen3 面 ShareLink 同为系统分享件、
/// 同载荷）
struct MessageSharePayload: Identifiable {
    let id = UUID()
    let text: String
}

/// 系统分享单承载（§330）：UIActivityViewCon-
/// troller 薄包装，与 FilesView 的 FileShare-
/// Sheet 同式（彼以文件 URL、本以消息纯文本）
struct MessageShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}

/// 「选择」承载页（0.4.1 立、§152 升级）：整条消息
/// 的纯文本在系统 sheet 里跨段划选任意部分——气
/// 泡内选字粒度是单个文本块（§152.3），跨块任意
/// 选段的口子保留在本页。0.4.1 时本页用 SwiftUI
/// Text＋.textSelection（iOS 26 下只有整段菜单），
/// §152 起换 SelectableInlineText（UITextView 真
/// 选段：双击选词／拖柄扩选／系统编辑菜单），与气
/// 泡内同源同口径
struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SelectableInlineText(
                    paragraphs: [.plain(text)],
                    textStyle: .body,
                    foreground: Palette.bodyInk
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OneDayMetrics.pageGutter)
            }
            .navigationTitle("选择文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .fullscreenPopBridge()
    }
}

/// 待发附件（0.2.1）：图片已统一转 JPEG（见 appendImage）；
/// 文件只存名与数据——直发未开放，发送时如实提示（见 send()）
/// §410：选文件接入的汇总产物——后台读盘段
/// （ChatView.loadPickedFilesSync）与主线入条段之间
/// 传递；名单与 FileIntake 汇总函数一一对应
struct PickedFilesLoadOutcome: Sendable {
    var accepted: [PickedFilePayload] = []
    var oversized: [String] = []
    var unreadable: [String] = []
    var transcoded: [String] = []
    var undecodable: [String] = []
}

/// §410：单个已接入文件的上传载荷（转码后字节）
struct PickedFilePayload: Sendable {
    let name: String
    let data: Data
}

struct PendingAttachment: Identifiable {
    let id = UUID()

    enum Kind {
        case image(Data)
        case file(name: String, data: Data)
    }

    let kind: Kind

    var imageData: Data? {
        if case .image(let data) = kind { return data }
        return nil
    }

    var fileName: String? {
        if case .file(let name, _) = kind { return name }
        return nil
    }

    /// 文件真发送载荷（0.36.29）：名＋数据成对取，
    /// 上传与拼装只认它，不再只取名字
    var filePayload: (name: String, data: Data)? {
        if case .file(let name, let data) = kind {
            return (name, data)
        }
        return nil
    }
}

/// 文件上传失败（0.36.29）：点名文件＋人话原因，
/// send 整条拦下时拼报错文案用，不静默吞单个文件
struct FileUploadFailure: Error {
    let fileName: String
    let reason: String
}

/// 系统相机包装：模拟器无相机，入口在附件菜单里已按可用性禁用
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ controller: UIImagePickerController, context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                parent.onImage(data)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

/// 三点指示：已受理未出字时的等待信号（iMessage
/// 输入指示器形态，§426 缺陷四按参照口径落数：
/// 点径 8、点距 4、周期 1.4s、错峰 0.22s、透明
/// 度 0.3↔1.0 正弦脉动；Reduce Motion 时静止）。
/// 0.2.5 起随助手消息一同入泡。相位函数为钉测
/// 读口（测动画状态、不测像素）
struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let dotDiameter: CGFloat = 8
    static let dotSpacing: CGFloat = 4
    static let cycleDuration: Double = 1.4
    static let stagger: Double = 0.22

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: Self.dotSpacing) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Palette.inkMuted)
                        .frame(
                            width: Self.dotDiameter,
                            height: Self.dotDiameter
                        )
                        .opacity(
                            Self.opacity(
                                at: t, index: index,
                                reduceMotion: reduceMotion
                            )
                        )
                }
            }
        }
        .accessibilityLabel("正在生成")
    }

    /// 逐点透明度：正弦波错峰——第 i 点相位滞后
    /// i×stagger 秒，波形平方收峰（亮段短、暗段
    /// 长，与参照指示器的呼吸感同族）
    static func opacity(
        at t: TimeInterval, index: Int, reduceMotion: Bool
    ) -> Double {
        if reduceMotion { return 0.6 }
        let speed = 2 * Double.pi / cycleDuration
        let wave = sin(
            t * speed - Double(index) * stagger * speed
        )
        return 0.3 + 0.7 * max(0, wave) * max(0, wave)
    }
}

/// 流式光标已移至 StreamingText.swift（与流式渐显组件
/// 同文件，文末词元同流排布）。

