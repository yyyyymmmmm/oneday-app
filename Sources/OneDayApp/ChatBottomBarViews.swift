import OneDayDesign
import OneDayCore
import SwiftUI

/// 发送区三件独立结构体（§373 结构性减深，2026-11-23）：
/// 原为 ChatView 的内联成员（bottomBar/inputBar/
/// composerCard），其组合类型在 ChatView 单类型内
/// 逐层内联展开——反射类型名实测嵌套深度 52/42/35、
/// 长度 37,379/28,357/25,874 字符；0.50.92/0.50.93
/// 真机启动闪退（§371/§373）定性＝ChatView 视图类
/// 型嵌套总深度贴悬崖，单点迁层只挪元数据递归耗尽
/// 点。本批把三段子树提取为自有 body 的独立 View
/// 结构体：ChatView 侧只余薄组装函数（依赖以值/
/// 绑定/闭包注入、ChatView 构建的子条经 AnyView
/// 擦除边界交付），父级类型表达式中三段各收为一
/// 个具名叶子，元数据实例化按结构体逐个分开求值、
/// 单串深度大幅下降。行为零改动：视图构成、修饰
/// 顺序、动画键、时序与原内联版逐字对应（搬移经
/// 脚本逐段替换＋diff 对账，见 §373.3）。

/// 发送区整栈（§257 起两承载共用）：条带行＋回底
/// 钮行＋朗读播放条＋输入舱（ChatInputBarView）＋
/// D3 编辑确认框（§352，自 0.50.88 起挂本子树）。
/// 依赖全数由 ChatView.bottomBar 组装函数注入。
struct ChatBottomBarView: View {
    var showsArrowRow: Bool
    var onScrollToBottom: () -> Void
    var importRetryBarView: AnyView?
    var importRetrySessionID: String?
    var historySyncBarView: AnyView
    var errorBannerView: AnyView?
    var errorMessageValue: String?
    var noticeBarView: AnyView?
    var noticeID: UUID?
    var showsBackToBottomButton: Bool
    var scrollToBottomButtonView: AnyView?
    var speechBarVisible: Bool
    var speechPlaybackBarView: AnyView?
    var approvalZoneView: AnyView?
    // 输入舱段依赖（透传下两件结构体）
    var dictation: DictationController
    var dictationFailureBarView: AnyView?
    var dictationNoticeBarView: AnyView?
    var editBannerArmed: Bool
    var onCancelEditSent: () -> Void
    var quoteBarView: AnyView?
    var feedQuoteBarView: AnyView?
    var sourceQuoteBarView: AnyView?
    var attachmentsCount: Int
    var attachmentsStripView: AnyView?
    var quoteSlotOccupied: Bool
    var composerRowView: AnyView
    var composerShape: AnyShape
    var onComposerTap: () -> Void
    @Binding var composerCapsuleHeight: CGFloat
    // D3 编辑确认（§352）：呈现绑定/文案/动作由
    // ChatView 注入，语义与原内联 Binding 逐字同
    var editConfirmPresented: Binding<Bool>
    var editConfirmMessage: String
    var onConfirmEditSend: () -> Void
    var onCancelEditSend: () -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        // 0.36.5（审计 bug 2 短修）：钮显隐走 Core 政
        // 策——当时是几何判定离底之外并入事实信号；
        // §135 改判几何单源（事实信号链退役，见
        // BottomFollowPolicy §135 注，迟滞带晚消失列
        // 真机待验）；显隐派生已提为全页单一出处
        // showsBackToBottomButton（本函数不再自算）；
        // 未读计数于 0.41.0 落地（AwayUnreadCounter），
        // 钮的宿主与落位于 §124 改归本区布局流（输
        // 入舱上方一行，见栈内钮行注）
        return VStack(spacing: OneDayMetrics.spacingS) {
            if let importRetryBarView {
                importRetryBarView
                    .transition(.opacity)
            }
            historySyncBarView
            if let errorBannerView {
                errorBannerView
                    // 0.25.0（动效专包）：错误/提示条进出
                    // 原为无过渡硬入硬出（高度跳变）——补
                    // opacity 过渡，高度与淡入同走下方
                    // swap 容器动画（单调无过冲，与回到底
                    // 部钮同口径）
                    .transition(.opacity)
            }
            if let noticeBarView {
                noticeBarView
                    .transition(.opacity)
            }
            // 回底钮行（§124 三代落位）：输入舱正上方
            // 一行、右对齐承载——钮底缘与输入舱顶缘之
            // 间只隔本栈 spacingS（既有 gap 口径），整
            // 段随发送区被系统安全区顶起，键盘升/降两
            // 态落位由构造恒成立、零几何推算；命中域
            // 是布局流内的真实帧，恒在宿主 bounds 内
            // （P-20 正案）。显隐由本行的存在承载：行
            // 高（44 命中域）＋间距的变化随下方容器
            // swap 动画与错误/提示条同口径滑动；显隐
            // 抖动的护栏在判定层（迟滞双阈值，0.36.5
            // 钉死；末条事实信号已于 §135 退役、显隐
            // 改几何单源），不靠把钮逐出布局流——三
            // 轮浮层落位病史见 DESIGN §124
            if showsArrowRow, let scrollToBottomButtonView {
                HStack {
                    Spacer(minLength: 0)
                    scrollToBottomButtonView
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.9)
                            )
                        )
                }
                .padding(.trailing, OneDayMetrics.spacingM)
            }
            // 朗读播放条（台账 183）：输入舱装配的
            // 一员（本栈内、舱正上方一行），非 overlay
            // 野挂——舱高账与落位随栈自洽。显隐/文案
            // 只读 SpeechPlayer 既有可观察面（Core 状
            // 态机派生 showsPlaybackBar/playbackBar-
            // Text），不新开状态通道；手动朗读与自动
            // 朗读同走状态机、同一条出口
            if speechBarVisible, let speechPlaybackBarView {
                speechPlaybackBarView
                    .transition(.opacity)
            }
            if let approvalZoneView {
                approvalZoneView
                    .padding(.horizontal, OneDayMetrics.pageGutter)
                    .transition(.opacity)
            }
            ChatInputBarView(
                dictation: dictation,
                dictationFailureBarView: dictationFailureBarView,
                dictationNoticeBarView: dictationNoticeBarView,
                editBannerArmed: editBannerArmed,
                onCancelEditSent: onCancelEditSent,
                quoteBarView: quoteBarView,
                feedQuoteBarView: feedQuoteBarView,
                sourceQuoteBarView: sourceQuoteBarView,
                attachmentsCount: attachmentsCount,
                attachmentsStripView: attachmentsStripView,
                quoteSlotOccupied: quoteSlotOccupied,
                composerRowView: composerRowView,
                composerShape: composerShape,
                onComposerTap: onComposerTap,
                composerCapsuleHeight: $composerCapsuleHeight
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        // 条 9（§14）动画口径沿革：本容器高度动画服
        // 务错误/提示条——0.4.2 起两键（errorMessage／
        // notice；§140 起提示条键改当前条代号 id，自清
        // 消失同走本动画）。回底钮的高度动画键两度退
        // 役又回归，
        // 如实记：0.41.0 钮浮层化时退役（当时的防摆
        // 手段是把钮逐出布局流）；§124 钮回到布局流，
        // 显隐键（showsBackToBottomButton）作第三键
        // 以同口径回归——防摆护栏改由判定层迟滞双阈
        // 值承担（0.36.5 钉死；末条事实信号已于 §135
        // 随信号链退役），三轮浮层落位的病史与取舍
        // 见 §124
        // 0.25.0（动效专包）：条本体淡入淡出、容器
        // 高度同步单调滑动，不再硬跳
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: importRetrySessionID
        )
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: errorMessageValue
        )
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: noticeID
        )
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: showsBackToBottomButton
        )
        // 台账 183：播放条显隐作第四键、同口径滑动
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: speechBarVisible
        )
        // D3（DESIGN §352；0.50.88 自 body 根链迁来本
        // 子树）：编辑非末轮的破坏性确认——N 轮实算
        // （RewindTurnSlicing.roundsAfter 呈现时刻现
        // 算）、文案明示不可恢复；取消回编辑态、发送
        // 舱一字不动
        .confirmationDialog(
            "编辑这条消息？",
            isPresented: editConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("发送并删除之后内容", role: .destructive) {
                onConfirmEditSend()
            }
            Button("取消", role: .cancel) {
                onCancelEditSend()
            }
        } message: {
            Text(editConfirmMessage)
        }
    }
}

/// 输入舱（§176 栈间距归零）：语音失败/提示条
/// （SmoothExpand 两段）＋输入舱卡（ChatComposer-
/// CardView）＋卡帧回报 background。依赖由
/// ChatBottomBarView 透传。
struct ChatInputBarView: View {
    var dictation: DictationController
    var dictationFailureBarView: AnyView?
    var dictationNoticeBarView: AnyView?
    // 卡段依赖（透传 ChatComposerCardView）
    var editBannerArmed: Bool
    var onCancelEditSent: () -> Void
    var quoteBarView: AnyView?
    var feedQuoteBarView: AnyView?
    var sourceQuoteBarView: AnyView?
    var attachmentsCount: Int
    var attachmentsStripView: AnyView?
    var quoteSlotOccupied: Bool
    var composerRowView: AnyView
    var composerShape: AnyShape
    var onComposerTap: () -> Void
    @Binding var composerCapsuleHeight: CGFloat

    var body: some View {
        // §176（2026-11-12，气泡间距收口）：栈间距归
        // 零——旧 spacingS 下两层 SmoothExpand 折叠高
        // 为 0 也照收两份间距（16pt，诊断九环第 8
        // 环），且任一条展开时，隐藏的另一层仍在替它
        // 收费（单条展开时条→卡实距 16）。改法：间距
        // 改由展开条自带底边距承载（见两处条注），收
        // 起时随帧高 0 被裁剪、不计费；展开时恒隔
        // spacingS，与旧口径同值
        VStack(spacing: 0) {
            // 0.36.6（§71）：语音失败行与到限提示行——
            // 三段式文案（发生了什么＋影响＋怎么办），
            // 权限被拒在此给「去设置」降级路（续编 S4）
            // §176：底边距长在条本体上——SmoothExpand
            // 的实测高含它、展开帧高含它；收起帧高 0
            // 时一并裁掉（见栈头注）
            SmoothExpand(isExpanded: dictation.failure != nil) {
                if let dictationFailureBarView {
                    dictationFailureBarView
                }
            }
            SmoothExpand(isExpanded: dictation.notice != nil) {
                if let dictationNoticeBarView {
                    dictationNoticeBarView
                }
            }
            // 输入舱卡（0.36.19 起引用块并入同卡，见
            // composerCard）：表面沿革——0.2.7 裸玻璃 →
            // 0.3.7 卡 19 撤玻璃改灰填充 → 0.3.8 第 28 条
            // 白浮纸（floatFill＋发丝边＋双环影）→ **0.4.1
            // 回系统玻璃**（用户 10:06/10:07 两点名：第 3
            // 修「输入栏与底部导航栏颜色不一致」＋第 7 修
            // 「改 Muse 本体形态：白色大圆角卡片」）：
            // .glassEffect(.regular) 与原生底栏同为 iOS 26
            // Liquid Glass 家族——同材质即同观感，不再自
            // 调灰阶对色。形态要素沿既有结构：圆角连续函
            // 数封顶 24（大圆角量级）、＋在卡内左下、发送
            // 圆形键在卡内右下、多行上文下钮（Composer-
            // BarLayout，0.3.4 定版）；自量高＋硬封顶（例
            // 外 E1）结构不动。白浮纸的发丝边与双环手搓
            // 影一并撤销（玻璃自带边缘折光与层级，§14 条
            // 2 的影口径随材质换代退役）
            ChatComposerCardView(
                editBannerArmed: editBannerArmed,
                onCancelEditSent: onCancelEditSent,
                quoteBarView: quoteBarView,
                feedQuoteBarView: feedQuoteBarView,
                sourceQuoteBarView: sourceQuoteBarView,
                attachmentsCount: attachmentsCount,
                attachmentsStripView: attachmentsStripView,
                quoteSlotOccupied: quoteSlotOccupied,
                composerRowView: composerRowView,
                composerShape: composerShape,
                onComposerTap: onComposerTap,
                composerCapsuleHeight: $composerCapsuleHeight
            )
                // A2（割裂感止血档）：卡本体帧回报——与
                // 整栈帧（桥侧 ComposerBarFrameKey）同
                // 法同系，经托管树 Preference 上行喂
                // ComposerGuideHost 定底衬高：衬顶随卡
                // 顶、整栈其余段（回底钮行/条带）不再
                // 进衬。量点只读帧、不接命中、不改布局
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ComposerCardFrameKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                }
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        // 0.36.27（§97 件二）：顶 padding 收一档
        // spacingS 8 → spacingXS 4（卡上外距，与列表
        // 底 contentMargins 同步，链总量 32 → 24）
        // §176：顶 padding 归零（本行删除）——气泡→
        // 输入舱卡顶的边距单点归列表底 contentMar-
        // gins 一处（见列表侧 §176 注），本处不再计量
        .padding(.bottom, OneDayMetrics.spacingS)
        // 提议链断环（0.2.5 根因注，§9）：本 VStack 的高度
        // 只认内容，不许把外层提议透传给胶囊
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 输入舱卡（0.36.19 入舱，§84）：玻璃卡的承载层——
/// 待发送引用块（有则显）、待发附件条（有则显）自
/// 上而下各带一条发丝分隔线、输入行（composerRow，
/// 标准行/录音条两态）在下，一张卡。
/// 0.4.1–0.36.18 引用条是输入舱外的一张独立浮卡，
/// 用户 2026-11-11 00:24 点题「一个在输入框里面，
/// 一个在外面」不对——对照 Muse 本体：引用嵌在输
/// 入舱内（引用块在上、分隔线、打字行在下）。
/// 高度核算：舱高＝引用块＋分隔线＋输入行整卡实测
/// （本层的 onGeometryChange 回写喂玻璃圆角连续半
/// 径）；输入行内部的文本量测与 6 行封顶只管文本
/// 域本身（ComposerLayout/ComposerBarLayout 口径
/// 不变），引用块高计入舱高、不挤占打字行数
/// 依赖由 ChatInputBarView 透传（源头 ChatView
/// 组装函数）：引用条/附件条/输入行本体仍由
/// ChatView 构建、经 AnyView 交付；卡内构成与
/// 修饰逐字沿原 composerCard。
struct ChatComposerCardView: View {
    var editBannerArmed: Bool
    var onCancelEditSent: () -> Void
    var quoteBarView: AnyView?
    var feedQuoteBarView: AnyView?
    var sourceQuoteBarView: AnyView?
    var attachmentsCount: Int
    var attachmentsStripView: AnyView?
    var quoteSlotOccupied: Bool
    var composerRowView: AnyView
    var composerShape: AnyShape
    var onComposerTap: () -> Void
    @Binding var composerCapsuleHeight: CGFloat

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // D3（DESIGN §352）：编辑横幅与引用块同
            // 位同式（卡根直接子级＋分隔线同进同
            // 出）——在场即编辑态在武装
            EditSentBannerSlot(
                isArmed: editBannerArmed,
                onCancel: onCancelEditSent
            )
            // §332（二次修复题 3）：引用块移出
            // SmoothExpand——与附件条同构造（卡
            // VStack 直接子级＋条件包含，引用块＋
            // 分隔线同进同出）。定因：引用块在
            // SmoothExpand 的 @State 高度量测反馈环
            // 内时，舱体落位读到滞后卡高、引用浮卡
            // 压输入框（附件条当年移出该环后同病消
            // 失）；高度变化改由卡根事务插值承接
            // （见下方 attachments.count 动画注，键
            // 扩至引用在场态）。quote/feed/source
            // 三变体共用本槽位（至多一个在场）
            if let quoteBarView {
                VStack(spacing: 0) {
                    quoteBarView
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .padding(
                            .horizontal, OneDayMetrics.spacingSM
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else if let feedQuoteBarView {
                // §208：动态引用与消息引用共用本槽
                // 位（至多一个在场），feed 变体渲染
                VStack(spacing: 0) {
                    feedQuoteBarView
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .padding(
                            .horizontal, OneDayMetrics.spacingSM
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else if let sourceQuoteBarView {
                // §219：点子／文件引用同槽（至多一
                // 个在场），按族分发条形态
                VStack(spacing: 0) {
                    sourceQuoteBarView
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .padding(
                            .horizontal, OneDayMetrics.spacingSM
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            // 待发附件条（0.36.19 入舱 §84.4；0.36.26
            // §95 移出量测层）：0.36.19 把满宽锚加在条
            // 内部两层、0.36.23 上移到卡直接子层，两
            // 轮真机居中分毫未动。调研裁决（produc-
            // tion-patterns-research-20261111 §2.3）：
            // 元凶是包着条的 SmoothExpand 量测层——
            // 它以实测内容理想尺寸为准定尺寸，条收到
            // 的宽度提议在到达条之前已被换成内容宽，
            // .frame(maxWidth:) 只能花提议到的宽
            // 度，两轮挪落点自然全数落空（同在该层下
            // 的引用块因自身近满宽把缺陷掩盖至今）。
            // 本轮按两家生产构造同构改（Stream
            // attachmentsTray／Exyte viewOnTop 同
            // 位）：条作卡根 VStack 的直接子级、条件
            // 包含显隐、链上三处 frame 补丁删尽；满
            // 宽由 ScrollView 对根栈提议的默认贪婪获
            // 得，左起由滚动内容自带横向 padding 获
            // 得。分隔线随条同进同出（挂同一直接子
            // 级的小 VStack 内）。引用块本轮不动
            // （仍在 SmoothExpand，最小范围）
            // 0.36.27 订正：上段「元凶是量测层」的单
            // 一归因已被 0.36.26 真机证伪（移出后仍居
            // 中）；0.36.27 续记的「包装层缺满宽 claim」
            // 说亦已被 0.36.28 真机证伪——第五轮定案
            // （0.36.29）：四轮共同死因是范畴错误，决
            // 定层是包装栈自身的 alignment 参数，修
            // 法见下方包装栈注与错题本 P-13；移出量测
            // 层本身保留（与生产构造同构、无回退理由）
            // 0.36.31 续记：第五轮修法真机再证伪，第
            // 六轮按呈报口径结构换代——条本体 Scroll-
            // View＋HStack 整类退役、改 Attachment-
            // FlowLayout 流式行（见 attachmentsStrip
            // 注与错题本 P-13 续案六）；包装栈与分隔
            // 线形态不动
            if let attachmentsStripView {
                // 0.36.29（P-13 第五轮定案）：条的横向位
                // 置由本包装栈自身的 alignment 参数决
                // 定——四轮全灭皆因改的是 .frame 的
                // alignment（只管「栈整体在他处怎么
                // 放」、管不到栈内子视图），栈自身
                // alignment 四轮一直默认 .center 从未
                // 被改。此处改 .leading 一词落到决定
                // 层；第 4 轮挂的 frame claim 经定案属
                // 无效修饰、一并删除（详见错题本 P-13）
                VStack(alignment: .leading, spacing: 0) {
                    attachmentsStripView
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .padding(
                            .horizontal, OneDayMetrics.spacingSM
                        )
                }
                // 条内容只淡入淡出防闪现；高度变化由
                // 卡根 .animation(attachments.count)
                // 的事务插值承接（见 composerCard 尾注）
                .transition(.opacity)
            }
            composerRowView
        }
        // 条显隐的高度动画（0.36.26 §95）：键原为
        // attachments.isEmpty（条高只在空↔非空之间
        // 变）；0.36.31 条改流式行多行化后，加/删筹
        // 码改行数同样改变条高，键扩为 attachments.
        // count——变化进动画事务后卡高（及安全区留白）
        // 同帧插值，不再靠 SmoothExpand 的实测回
        // 写；玻璃半径由卡层 onGeometryChange 的实
        // 测高连续函数逐帧跟随，无跳变源。动画令牌
        // 与 SmoothExpand 同源（MotionTokens.
        // swap、Reduce Motion 经 resolved 收口）
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: attachmentsCount
        )
        // §332（题 3）：引用块移出 SmoothExpand 后
        // 其显隐高变同理由卡根事务插值承接——键＝
        // 三变体在场态（至多一个在场，布尔即全量）
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: quoteSlotOccupied
        )
        // 第 1 修（P0 键盘不弹）的聚焦保底层：整卡背景
        // 命中域内点按（文本区外的卡面空隙，含引用块
        // 段的空隙）经焦点句柄聚焦文本视图。根因与定
        // 位见 DESIGN-V4 §26.7：焦点机器代码 0.3.8→
        // 0.4.0 逐字未动（diff 实证），回归随底栏可见化
        // 同批出现——文本视图自身触摸成为单点故障，本
        // 层把「点输入栏必弹键盘」改成双通道构造（文本
        // 视图直触＋卡面点按），不再依赖单一路径的环境
        // 状态。0.4.1 起本层挂在 composerRow 上，0.36.19
        // 随玻璃施加点上移到卡层、命中域扩到整卡
        .background {
            Color.clear
                .contentShape(composerShape)
                .onTapGesture {
                    onComposerTap()
                }
        }
        .glassEffect(.regular, in: composerShape)
        // 实测高在布局周期内回写（0.3.5，§20）：只喂玻
        // 璃圆角的连续半径（见 composerShape），高度本
        // 身不经任何动画——形态切换一帧落定。回写点
        // 0.4.1–0.36.18 在 composerRow 上（只量输入行），
        // 0.36.19 起上移卡层量整卡（引用块计入舱高）；
        // 0.2.6–0.3.4 的离散形状动画已整条撤销（理由见
        // standardComposerRow 沿革注）
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, newHeight in
            if abs(newHeight - composerCapsuleHeight) > 0.5 {
                composerCapsuleHeight = newHeight
            }
        }
    }
}

/// §374.9（步骤 6）自 ComposerGuideHost.swift 迁
/// 入：写入方（本文件 bottomBar 与 ChatView 的
/// inputBar）均为共用件、随迁保留；原读取方（引
/// 导线宿主控制器）已退役，preference 发布暂无
/// 消费者、惰性无副作用
/// 输入舱卡本体帧的 PreferenceKey（A2 舱带收边）：
/// 写入点在 ChatView 的 inputBar（composerCard 外
/// 挂背景 GeometryReader），与整栈帧同一窗口系、同
/// 一棵托管树上行；口径与 ComposerBarFrameKey 同
/// 式（单值、取后到非零帧）。internal 而非 private
/// ——写入点跨文件在 ChatView
struct ComposerCardFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(
        value: inout CGRect, nextValue: () -> CGRect
    ) {
        let next = nextValue()
        if next.height > 0 { value = next }
    }
}
