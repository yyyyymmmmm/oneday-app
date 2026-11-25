import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 会话页原生重建 R1＋R2（DESIGN §291/§293，施工
/// 图 chat-native-rebuild-blueprint-20261115 §五）：
/// ChatRootViewController＋UICollectionView（正
/// 向、不倒置）＋UICollectionViewDiffableDataSource
/// ＋compositional 单列布局。落定行全集以
/// UIHostingConfiguration 托管现有 SwiftUI 行内容
/// 进 cell（内容本体一字不动）；直播区自 R2 起逐
/// 项入快照（ChatView nativeLiveRow，§293）；输入
/// 舱自 R2 起收编为本容器子托管——落位原钉本视图
/// keyboardLayoutGuide（H8），§302 起改回 §194
/// 通知帧顶单常量形态（见下 H8 沿革）。
///
/// §325（B 档退役，2026-11-17；同根审计 chat-
/// page-root-audit-20261117 §5 定案）：自造三件
/// 整套退役——①双 cell 形态：R3 的原生散文 cell
/// （ChatNativeProseCell）整件删除，落定行统一走
/// 托管 cell 单渲染路径，内容 facet 只影响行内呈
/// 现、不再决定行是哪种 cell（§320.1 的形态翻转
/// 先删后插分流随之退役——无形态可翻）；②行高估
/// 算管线：产物层估算（carrierRowEstimate／占位
/// 均值聚合）退出列表关键路径，compositional 的
/// .estimated 只留固定常量供未物化区滚动几何，
/// 物化行高一律由 UIHostingConfiguration 自适应
/// ＋selfSizingInvalidation 由框架持有收敛；
/// ③手维护版本哈希：行版本（Int 折算）退役，改
/// ChatNativeRowRevision 结构化派生——行描述的
/// 渲染输入全量值比较（Equatable），条目行由条
/// 目模型全字段快照单点派生（见 revision 节）。
///
/// §329（布局环结构修，2026-11-18；定因 crash-
/// 05068-diagnosis-20261118）：.67/.68 真机同签
/// 名复崩证实 §325 ②「行高归框架自适应」不成立
/// ——环由 compositional post-pass 自我失效驱
/// 动、与 App 侧闸门无关。本节改：行高由量测
/// 栈同步合成（ChatNativeRowHeight）回喂、布
/// 局改 section-per-row＋.absolute 消费（框架
/// 不再估算→修正）；apply 入 §325.2 滚动闸
/// （滚动期整笔记账、停滚落定拍消费）。§325
/// ①③与 §325.2 守卫、selfSizingInvalidation
/// 档位、§321 均不动，详见 DESIGN §329。
///
/// 几何纪律（施工图 §四硬约束）：
/// - H1 间距单源：相邻消息纵向间距只由 section
///   的 interGroupSpacing 一处声明（spacingL 24）；
///   cell 内容不带任何泡外纵 padding，时间分隔仍
///   长在条目 cell 内（ChatView 行内容自带）。
/// - H2/H10 行高单权威、无帧表：本类没有任何帧
///   表、任何量实回填——行高由 ChatView 的合成
///   器（§329）同步算定、随行描述喂入，布局以
///   .absolute 逐 section 消费（section-per-
///   row）；contentSize 只由集合视图自己持有；
///   托管拟合高永不回写（拟合与布局脱钩是布局
///   环的构造拆除，定因见 §329）。
/// - H3 短内容底锚定：内容高＜有效视口时，按系
///   统实测 contentSize 派生一笔顶 inset（单点记
///   账、随实测重算），末行底→舱顶与长内容同值。
/// - H6 落点＝真实布局后的最大 offset：落定拍在
///   layoutIfNeeded 后按系统 contentSize 钉底；收
///   敛（自适应行高修正）后落点意图未消则同拍重
///   钉；用户接管（拖动）即消意图。
/// - H7 距底永远现测：全部判定在决策时刻现读
///   contentSize／contentOffset／adjusted 标尺计
///   算，不缓存事实位。
/// - 与 gen3 容器的关系：本面与 gen3 面共用同一
///   句柄形态（同形不同型，见 ChatNativeList-
///   Handle）；ChatView 跟随/锚链只认句柄、不为
///   本面再抄一份。喂入只剩顶 inset 与单点边距两
///   笔（§263 口径同源）；底几何自 R2 起全由本容
///   器内实测派生（见 H8）。
/// - H8 键盘跟随（R2 换代→§302 回 §194 形态）：
///   R2 曾定「只走 keyboardLayoutGuide」——舱底
///   钉本视图引导线顶、引导线逐帧驱动。2026-
///   11-16 用户 .59 真机录屏证伪（定因报告 key-
///   board-rise-diagnosis-20261116）：引导线在本
///   层级（SwiftUI 托管内嵌控制器）真机不追踪真
///   键盘、舱全程钉坞位被键盘盖住，与 §193→
///   §194 病史同族；其真机门 A2/A3 从未回填即
///   随 .59 转默认。§302 落位回 §194 形态：舱底
///   恒钉自有位置引导线 bottomGuide，其 top 常
///   量只由 syncBottomConstant 一个函数算——键
///   盘态＝通知广播的结束帧顶（窗口坐标）、静息
///   态＝坞实测顶、无坞回落窗口安全区底；状态翻
///   转与帧变化以通知动画参数原值推进布局（时
///   长 0 的逐帧事件直接布局）。台账 189（2026-
///   11-20 结构根治）：静息态自常量链分出——
///   「坞实测顶」实证是 UITabBar 帧顶、与可见
///   胶囊顶差 39pt（帧内悬浮内距），静息落位
///   改入布局流（bottomGuide.top 直约胶囊
///   topAnchor，见 dockCapsuleView/updateDock-
///   Mode）；常量链自此只辖键盘态与无胶囊回
///   落态，§194 键盘单常数链一字未动。keyboardLayout-
///   Guide 自此退出驱动位、只在事件拍作采样对
///   照记入自述（预期仍停静息值、即根因本人）。
///   列表底 inset 仍每拍由舱子托管实测帧一处派
///   生（量测→对账→在底同拍钉底，全在布局拍/
///   落定拍内），此半边 R2 口径不变。ChatView
///   侧键盘锚定挂账链在本面仍不消费（gen3/旧面
///   照旧）；但 kbSnapshot 供数自 §302 起同源
///   收口：同一通知解析点在驱动舱常量的同拍组
///   装 KeyboardFrameUpdate 经 onKeyboardFrame-
///   Change 喂 ChatView 的 kbFrameUpdate（与旧
///   面 ComposerGuideHost 同一口径、同一快照，
///   不许第二套）——isKeyboardUp／聚焦藏坞在
///   新面恢复触发（定因 K2 的修法）。

// MARK: - 行修订值（§325 结构化派生，代手维护版本哈希）

/// 行修订值：行「变没变」的唯一判据——不再是手
/// 工折算的 Int 哈希（carrierEntryVersion 一类：
/// facet 枚举漏一项、该行永不重配，§320 文件牌
/// 即此病），而是行渲染输入的有序清单，Equatable
/// 逐项比较。清单由构造点按渲染输入逐项填入，完
/// 整性靠 entry 单点枚举全字段保证（漏折防线在
/// 枚举、不在值本体）。
/// 【2026-11-20 卡顿修复包改摘要制】（全面对比报
/// 告 chat-lag-full-comparison-20261120 §8 处方）：
/// 文本/数据不再逐字入账——addText 存「长度＋
/// FNV-1a」摘要串、addData 存「长度＋采样哈希」
/// 定长字节。旧制每趟行构建把全语料（正文全文＋
/// 图片 Data 本体）搬进清单再全量比较，是喂入层
/// 每遍全量税的主体；摘要制后单项定长、比较与构
/// 建都与语料量脱钩。碰撞后果仅一行漏重配，与备
/// 忘键 fnv 同险同级（见合成器 revisionDigest 注）。
struct ChatNativeRowRevision: Equatable, Hashable {
    enum Part: Equatable, Hashable {
        case text(String)
        case data(Data)
        case flag(Bool)
        case count(Int)
        case real(Double)
    }

    var parts: [Part] = []

    init(parts: [Part] = []) {
        self.parts = parts
    }

    mutating func addText(_ value: String?) {
        parts.append(.flag(value != nil))
        parts.append(.text(Self.textDigest(value ?? "")))
    }

    mutating func addData(_ value: Data?) {
        parts.append(.flag(value != nil))
        if let value {
            parts.append(.data(Self.dataDigest(value)))
        }
    }

    /// 文本摘要：长度＋FNV-1a（与 LayoutProductKey
    /// 同算法同源）——定长短串，不留正文本体
    static func textDigest(_ value: String) -> String {
        "\(value.count):\(LayoutProductKey.fnv1a(value))"
    }

    /// 数据摘要：16 字节定长（长度 8B＋采样哈希
    /// 8B，小端）。采样＝头/中/尾各 512B 窗口的
    /// FNV-1a 混合（≤1536B 全覆盖）——大图本体不
    /// 全量扫、不入账；同长度同采样窗才碰撞
    static func dataDigest(_ value: Data) -> Data {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mixByte(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        func mixValue(_ word: UInt64) {
            var word = word
            for _ in 0..<8 {
                mixByte(UInt8(word & 0xff))
                word >>= 8
            }
        }
        mixValue(UInt64(value.count))
        let window = 512
        let count = value.count
        let mid = count / 2
        let ranges: [Range<Int>] = [
            0..<min(window, count),
            max(0, mid - window / 2)..<min(count, mid + window / 2),
            max(0, count - window)..<count,
        ]
        value.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for range in ranges {
                for index in range {
                    mixByte(buffer[index])
                }
            }
        }
        var out = Data()
        var length = UInt64(value.count).littleEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        var hashLE = hash.littleEndian
        withUnsafeBytes(of: &hashLE) { out.append(contentsOf: $0) }
        return out
    }

    mutating func addFlag(_ value: Bool) {
        parts.append(.flag(value))
    }

    mutating func addCount(_ value: Int) {
        parts.append(.count(value))
    }

    mutating func addReal(_ value: Double?) {
        parts.append(.flag(value != nil))
        parts.append(.real(value ?? 0))
    }

    /// 条目行修订值（单点派生）：按 ChatEntry 落盘
    /// 字段的声明序全量快照——渲染的一切 facet
    /// （正文/工具卡/思考/引用四族/图片与文件路径/
    /// 回响三键/发送状态）都由这些字段派生（计算
    /// 属性 allImageDatas/remoteImagePaths/toolCard
    /// 等无一例外），字段值不变则渲染输入不变、任
    /// 一字段变则修订必变，不存在「漏折一项」的清
    /// 单可漏。环境侧渲染输入（分隔文案/锚点点亮/
    /// 样式键）同列入账。
    /// 【选区在场永不入账】（141/142 根治，2026-
    /// 11-19 用户令对话页按 OpenBot 做法）：选区是
    /// 平台文本视图的内部状态、不是渲染输入——它
    /// 曾以 selectionActive 旗入账，结果选区一形成
    /// →修订翻转→该行重配→托管视图换代→UITextView
    /// 本体被拆、选区与编辑菜单当场被冲。OB 的同
    /// 构做法：selecting 态只切已建手势的
    /// enabled、不重建任何视图。自此选区的跨界影
    /// 响只走两条不重配的路：右滑引用在手势回调时
    /// 刻读账本停用、选区行重配在控制器分流处按单
    /// 键暂存（见 partitionSelectionStaged；§332
    /// 触摸序列门已随 §374.8 退役）。
    static func entry(
        _ entry: ChatEntry,
        dividerText: String?,
        highlighted: Bool,
        styleKey: String,
        showsUnreadDivider: Bool = false
    ) -> ChatNativeRowRevision {
        var revision = entryBase(
            entry,
            dividerText: dividerText,
            showsUnreadDivider: showsUnreadDivider
        )
        revision.addFlag(highlighted)
        revision.addText(styleKey)
        return revision
    }

    /// 条目字段基段（§325 立制、§362 迁址）：条目
    /// 本体字段的枚举实体已迁至 ChatEntryRevision-
    /// Snapshot（capture 字段读取单点＋basePrefix-
    /// Revision 摘要枚举单点，与行构建增量备忘共用
    /// 同一枚举——字段不许在第二处重列的漏折防线不
    /// 变）；本函数＝快照前缀段＋环境尾段（分隔文案
    /// ＋未读分界旗），输出与旧全量枚举逐值同（等价
    /// 钉测把守）。entry（行修订）与 entryMemoKey
    /// （高度备忘键的中性派生）共用本段，两路只在其
    /// 后接各自的环境尾段（点亮/样式键 vs 中性占位）
    static func entryBase(
        _ entry: ChatEntry,
        dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> ChatNativeRowRevision {
        var revision = ChatEntryRevisionSnapshot
            .capture(entry)
            .basePrefixRevision()
        revision.addText(dividerText)
        // 台账 148：NEW 分界线在席与否是渲染输入、
        // 同列入账（在席变化必触发重配与重测高）
        revision.addFlag(showsUnreadDivider)
        return revision
    }
}

// MARK: - 行描述（ChatView 喂入）

/// 动作面动作项（台账 187，方案 A）：自定义动作
/// 面下半的动作列表一项——kind 供测试与无障碍标
/// 识、title/systemImage 是呈现值、action 是
/// ChatView 侧的既有入口闭包。项集/序/图符由
/// ChatRowActionSheetData.actionItems 单源组装
/// （与 186 菜单项集逐项同：回复／在旁聊里接着
/// 问／复制／选择／分享／朗读），两面共用同一份
/// 描述呈现同一个自绘 sheet，不再各持一套承载
struct ChatRowActionItem: Identifiable {
    enum Kind: Equatable {
        case reply, fork, copy, select, share, speak
        /// 台账 154（DESIGN §336）：发件箱条目三项
        case resend, editUnsent, withdrawUnsent
        /// D3/D2（DESIGN §352）：已发消息编辑重发／
        /// 末轮重新生成——只对已落定条目由 ChatView
        /// 注入，发件箱项集恒不组装（互斥在席）
        case editSent, regenerate
    }

    let kind: Kind
    let title: String
    let systemImage: String
    /// 破坏性项（撤回）：动作面以危险色呈现，组装
    /// 侧逐项明示、不靠标题猜
    var isDestructive: Bool = false
    let action: () -> Void

    var id: Kind { kind }
}

/// 行菜单数据（台账 187 立制；台账 200 拆换后
/// 承载改系统上下文菜单）：由 ChatView 在呈现
/// 时刻以条目现成闭包组装（不在行构造时钉死——
/// 朗读项的播放态、自己的现反应都以呈现时刻为
/// 准）。两面同经 MessageMenuModifier 挂系统上
/// 下文菜单，项集语义见 actionItems
struct ChatRowActionSheetData {
    let plainText: String
    /// 反应排在否（台账 187 门控谓词 ChatEntry.
    /// canReact 的呈现时刻求值）：未钉桩/未落定行
    /// 整排不出，不给假动作
    let canReact: Bool
    /// 自己的现反应（反应排高亮态；nil＝未点）
    let ownEmoji: String?
    /// 点反应排一项（toggle 语义在 ChatView 侧收
    /// 口：点已点项＝撤回）
    let onPickReaction: (String) -> Void
    let onReply: () -> Void
    let onFork: () -> Void
    let onSelect: () -> Void
    let onShare: () -> Void
    /// 发件箱三项（台账 154，DESIGN §336）：未发送
    /// 条目（失败/待发/准备段中断）才由 ChatView 侧
    /// 注入——非 nil 即本条在发件箱内，组装改走发
    /// 件箱项集（见 actionItems）；落定条目恒 nil、
    /// 项集与旧口径逐项同
    var onResend: (() -> Void)? = nil
    var onEditUnsent: (() -> Void)? = nil
    var onWithdrawUnsent: (() -> Void)? = nil
    /// §451：已受理未执行条目的撤回（服务端 FIFO
    /// 排队中、尚未开轮）——ChatView 侧按账本序位
    /// 求值后注入；与发件箱撤回互斥（条目非此即
    /// 彼），项位/图符/危险色与发件箱撤回同
    var onWithdrawAccepted: (() -> Void)? = nil
    /// D3/D2（DESIGN §352）：已落定条目的编辑重发／
    /// 重新生成——门控谓词（ChatEntry.canEditSent/
    /// canRegenerateCandidate＋线程级条件）在
    /// ChatView 呈现时刻求值后注入，非 nil 才组装；
    /// 与发件箱三项互斥（条目非此即彼）
    var onEditSent: (() -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    /// 朗读项（H2-a）：呈现时刻求值——播放态随时
    /// 变，标题/在否不许在行构造时钉死；门控（只
    /// 给助手落定回复、未开通不出项）在 ChatView
    /// 的求值闭包内
    var makeSpeakItem: (@MainActor () -> ChatRowSpeakItem?)? = nil

    /// 动作列表组装（单源）：项集/序/图符与 186 菜
    /// 单逐项同——回复／在旁聊里接着问恒在席；文
    /// 本依赖项（复制/选择/分享）仅 plainText 非空
    /// 时组装（复制空文、选空文是假动作；台账 186
    /// 组装口径）；朗读项恒居末尾、求值 nil 整项
    /// 不出。复制走 Pasteboard 收敛口径（与 Copy-
    /// Button 同源一处）
    @MainActor
    func actionItems() -> [ChatRowActionItem] {
        // 台账 154（DESIGN §336）：发件箱条目项集——
        // 重新发送/编辑居首，回复/旁聊对一条从未发
        // 出的消息无意义、不组装（假动作）；复制/
        // 选择/分享对内容本体仍成立、照旧；撤回居
        // 末、危险色。落定条目（onResend 为 nil）走
        // 下方旧项集，逐项不变
        let isOutbox = onResend != nil
        var items: [ChatRowActionItem] = []
        if let onResend {
            items.append(
                ChatRowActionItem(
                    kind: .resend, title: "重新发送",
                    systemImage: MessageActionSymbols.resend,
                    action: onResend
                )
            )
        }
        if let onEditUnsent {
            items.append(
                ChatRowActionItem(
                    kind: .editUnsent, title: "编辑",
                    systemImage: MessageActionSymbols.editUnsent,
                    action: onEditUnsent
                )
            )
        }
        if !isOutbox {
            items += [
                ChatRowActionItem(
                    kind: .reply, title: "回复",
                    systemImage: MessageActionSymbols.reply,
                    action: onReply
                ),
                ChatRowActionItem(
                    kind: .fork, title: "在旁聊里接着问",
                    systemImage: MessageActionSymbols.fork,
                    action: onFork
                ),
            ]
        }
        // D3/D2（DESIGN §352）：编辑/重新生成同位组——
        // 紧随回复/旁聊、复制之前（编辑是本条的主动
        // 作、重新生成是本轮的主动作）；发件箱条目恒
        // 不组装（isOutbox 已在上方分流、此处再守一
        // 道，防注入侧误配时两套项集同席）
        if !isOutbox, let onEditSent {
            items.append(
                ChatRowActionItem(
                    kind: .editSent, title: "编辑",
                    systemImage: MessageActionSymbols.editSent,
                    action: onEditSent
                )
            )
        }
        if !isOutbox, let onRegenerate {
            items.append(
                ChatRowActionItem(
                    kind: .regenerate, title: "重新生成",
                    systemImage: MessageActionSymbols
                        .regenerate,
                    action: onRegenerate
                )
            )
        }
        if !plainText.isEmpty {
            let text = plainText
            items += [
                ChatRowActionItem(
                    kind: .copy, title: "复制",
                    systemImage: MessageActionSymbols.copy,
                    action: { Pasteboard.copy(text) }
                ),
                ChatRowActionItem(
                    kind: .select, title: "选择",
                    systemImage: MessageActionSymbols.select,
                    action: onSelect
                ),
                ChatRowActionItem(
                    kind: .share, title: "分享",
                    systemImage: MessageActionSymbols.share,
                    action: onShare
                ),
            ]
        }
        if let speak = makeSpeakItem?() {
            items.append(
                ChatRowActionItem(
                    kind: .speak, title: speak.title,
                    systemImage: speak.systemImage,
                    action: speak.action
                )
            )
        }
        if let onWithdrawUnsent {
            items.append(
                ChatRowActionItem(
                    kind: .withdrawUnsent, title: "撤回",
                    systemImage: MessageActionSymbols
                        .withdrawUnsent,
                    isDestructive: true,
                    action: onWithdrawUnsent
                )
            )
        }
        if let onWithdrawAccepted {
            items.append(
                ChatRowActionItem(
                    kind: .withdrawUnsent, title: "撤回",
                    systemImage: MessageActionSymbols
                        .withdrawUnsent,
                    isDestructive: true,
                    action: onWithdrawAccepted
                )
            )
        }
        return items
    }
}

/// 行菜单朗读项（H2-a，台账 159）：标题随播放态
/// 变（朗读/停止朗读）——台账 187 起两面同在动作
/// 面呈现时刻求值（ChatRowActionSheetData.make-
/// SpeakItem），共用本描述，项序恒在动作列表末尾
/// （与既有五项同面、不占气泡常驻位，施工图 3.1）
struct ChatRowSpeakItem {
    let title: String
    let systemImage: String
    let action: () -> Void
}

/// 原生面行：身份键（diffable 条目身份，与 gen3
/// 行键同名同源）＋条目 id（锚/顶可见用，非条目
/// 行为 nil）＋修订值（渲染输入全量值、变→
/// reconfigure 原位更新，§325）＋行高（§329 量
/// 测回喂固定高：由 ChatView 的高度合成器同步
/// 算定、布局以 .absolute 消费——框架不再估
/// 算→修正，见 DESIGN §329）＋视图构建闭包
/// （只在（重）配置 cell 时调用）。§325 起全体
/// 行只有托管 cell 一种形态——本描述不再携带
/// 形态判别
struct ChatNativeRow {
    let key: String
    let entryID: UUID?
    let revision: ChatNativeRowRevision
    /// §329 回喂高（pt）：合成器未给的构造点（测
    /// 试手搓行等）回落固定常量——单值、永不随
    /// 行集聚合（兜底口径见 §329）
    let height: CGFloat
    /// 台账 190②：本行高是否临界（量测未就绪、
    /// 以兜底/上次高顶替）——布局提供者对将入视
    /// 口的临界行就地量测换确定高；确定高行恒
    /// false。就地量测换高只改布局匣、不改本描
    /// 述（描述的戳含高值、量测台回填后经发布代
    /// 次以新描述重喂，两路同值）
    let heightIsProvisional: Bool
    let makeView: () -> AnyView
    /// 原生上下文菜单单源数据（非 nil 时由 UICollectionView
    /// 原生 UIContextMenuInteraction 接管长按浮起与菜单）
    let makeContextMenuData: (() -> ChatRowActionSheetData)?
    let contextMenuAlignsTrailing: Bool
    init(
        key: String, entryID: UUID?,
        revision: ChatNativeRowRevision = ChatNativeRowRevision(),
        height: CGFloat = ChatNativeRowHeightComposer
            .fallbackHeight,
        heightIsProvisional: Bool = false,
        makeContextMenuData: (() -> ChatRowActionSheetData)? = nil,
        contextMenuAlignsTrailing: Bool = false,
        makeView: @escaping () -> AnyView
    ) {
        self.key = key
        self.entryID = entryID
        self.revision = revision
        self.height = height
        self.heightIsProvisional = heightIsProvisional
        self.makeContextMenuData = makeContextMenuData
        self.contextMenuAlignsTrailing = contextMenuAlignsTrailing
        self.makeView = makeView
    }
}

// MARK: - 行描述备忘（2026-11-20 卡顿修复包）

/// 行描述备忘：nativeRows 每趟的产物缓存（全面
/// 对比报告 §2/§8 处方——喂入层增量化）。调用方
/// 给出行的全部构建输入折成的戳（stamp），戳不
/// 变则整行复用上趟描述：makeView 闭包、行菜单
/// （含 plainText 提取）、行描述组装全免；只有戳
/// 变的行才走 build 全构建。计数口供测试与探针
/// 读（构建数/复用数），生产路径只多字典读写。
/// 趟末由 prune 清账：本趟未出现的行键出缓存
@MainActor
final class ChatNativeRowDescriptorMemo {
    private var cache: [String: (stamp: String, row: ChatNativeRow)] = [:]
    private(set) var buildCount = 0
    private(set) var reuseCount = 0

    func row(
        key: String, stamp: String,
        build: () -> ChatNativeRow
    ) -> ChatNativeRow {
        if let hit = cache[key], hit.stamp == stamp {
            reuseCount += 1
            return hit.row
        }
        buildCount += 1
        let row = build()
        cache[key] = (stamp, row)
        return row
    }

    /// 趟末清账：只留本趟在席的行键（线程切换/行
    /// 删除后不留陈账，防旧描述被后来的同键行误用
    /// ——键含条目 id、同键复现时戳判定仍兜底）
    func prune(keeping keys: Set<String>) {
        cache = cache.filter { keys.contains($0.key) }
    }

    /// 测试读口：清计数不清缓存
    func resetCounts() {
        buildCount = 0
        reuseCount = 0
    }
}

// MARK: - 布局参数匣（compositional 布局提供者只认本匣、不认控制器本体）

private final class ChatNativeLayoutBox {
    var horizontalPadding: CGFloat = 20
    var topPadding: CGFloat = 16
    var bottomPadding: CGFloat = 8
    var rowSpacing: CGFloat = 24
    /// §325：未物化区滚动几何的固定占位高——只此
    /// 一个常量、不再由行估算聚合派生（产物层估
    /// 算管线退役）。§329 后只余布局提供者越界
    /// （section 序超出当前行集）的防御回落
    static let estimatedPlaceholder: CGFloat = 120
    /// §374.3：行高账条目——修订＋采用高＋临界
    /// 标记三值按键同账，代 §329 的平行四表
    /// （rowHeights／provisionalFlags／rowKeys／
    /// rowRevisions 按序对位）：高度以行键为身
    /// 份（施工图对位 #3：照 Signal LayoutInfo／
    /// 微信预排版的按身份缓存纪律），插行不挪
    /// 账、失效随修订、布局按序位取键再按键读
    /// 高；apply 落写、提供者只读，两处不许各
    /// 算一份
    struct HeightEntry {
        var revision: ChatNativeRowRevision
        var height: CGFloat
        var provisional: Bool
    }
    /// §329 的回喂高＋台账 190② 的临界标记（高
    /// 未量测确定：提供者对可见窗内的临界行经
    /// syncMeasure 就地量测换确定高并回写本账
    /// ——学 Telegram 无估算高，估算兜底只留给
    /// 从未接近视口的行；窗外临界行不付主线程
    /// 量测、等量测台后台回填），§374.3 起按键
    /// 存取
    var heightByKey: [String: HeightEntry] = [:]
    /// 行序（与快照条目序恒同）：序位真源只余
    /// 行键一列——非高度账本体（高度按键在
    /// heightByKey），布局提供者按序取键读账
    var rowOrder: [String] = []
    /// §374.3：布局构造旗（控制器按 ChatList-
    /// SingleSectionFeature 在喂入入口同步）：
    /// 真＝单 section 逐 item 组高构造、假＝
    /// §329 逐行 section 构造（回退形态）
    var singleSection = false
    /// 采用高按序镜像（测试读口/对账用；键缺
    /// 席回落占位常量——防御、正常路径不达）
    var orderedHeights: [CGFloat] {
        rowOrder.map {
            heightByKey[$0]?.height
                ?? Self.estimatedPlaceholder
        }
    }
    /// 序位读高（提供者口）：序→键→账
    func height(at index: Int) -> CGFloat {
        guard rowOrder.indices.contains(index)
        else { return Self.estimatedPlaceholder }
        return heightByKey[rowOrder[index]]?.height
            ?? Self.estimatedPlaceholder
    }
    /// 台账 190 留账·nanoMuse 列表三件①（DESIGN
    /// §335）：布局层确高备忘——确高一经喂入或就
    /// 地量得即归本匣所有（行键→（修订，确高））：
    /// 上游备忘（合成器 NSCache 备忘）被逐出/内存
    /// 警告清仓后，同修订行再以临界高喂入时，匣
    /// 以自存确高回填、临界标记同步清（失效永不
    /// 丢：布局失效/重喂都不许把已确高打回临界）；
    /// 显式失效只有两路——修订变（内容/facet 变
    /// 后旧高作废、认新喂入）与行离集（applyNow
    /// 按新行集剪账）。与量测台 lastKnown 的分工：
    /// 彼在量测层、跨修订沿用当临界顶替值；本匣
    /// 在布局层、同修订认确值——两层各管一段
    var exactHeightByKey: [String: (
        revision: ChatNativeRowRevision,
        height: CGFloat
    )] = [:]
    /// 就地量测口（控制器装配：行键→量测台
    /// measureNow）；nil＝无量测台在席（探针裸
    /// 装配），提供者不就地量测
    var syncMeasure: ((String) -> CGFloat?)?
    /// 可见窗（行序，控制器按可见项±缓冲刷
    /// 新）：syncMeasure 只许在本窗内触发
    var visibleWindow: Range<Int> = 0..<0
    /// 就地量测单窗预算（防整窗临界时主线程连
    /// 量失控；窗口刷新时由控制器重置）
    var syncMeasureBudget = 0
    static let syncMeasureBudgetPerWindow = 12
    /// §325.2 布局 pass 计数口（section 提供者被调
    /// 用次数）：收敛压测的 pass 数读数——稳态下强
    /// 制布局/重复 apply 不得再触发 section 重建；
    /// 生产路径只多一次计数、无行为影响
    private(set) var sectionProviderCallCount = 0
    func noteSectionProviderCall() {
        sectionProviderCallCount += 1
    }
}

// MARK: - 托管 cell

/// 托管 cell：UIHostingConfiguration 只渲染——
/// 内容以行键为 SwiftUI 身份（复用时状态不跨条
/// 目串行，施工图 §七风险 2）；拟合尺寸由集合视
/// 图布局自己消费，本类不读、不记（H10）
/// §332（二次修复题 2）：cell 本体不再挂任何
/// UIContextMenuInteraction（§265 禁令：交互挂
/// 文本视图祖先会压死原生选字/编辑菜单）——行
/// 菜单承载历经 delegate 内建通道（§332）→控制
/// 器长按识别器＋自绘动作面（台账 187），cell 始
/// 终只渲染。菜单点位分工的 hitTest 判读口在本
/// 类（静态、无状态）
/// （internal 而非 private：装配测试须以生产原
/// 物读配置普查——与控制器/合成器的 internal
/// 测试面同式）
final class ChatNativeHostingCell: UICollectionViewCell {
    static let reuseID = "ChatNativeHostingCell"

    /// 配置普查（测试读口，与布局匣计数口同式：
    /// 生产路径只多两次赋值、无行为影响）：本
    /// cell 的配置次数与最近配置行键——§332 触
    /// 摸序列暂存的断言以此为据（未闭合行计数不
    /// 动、闭合后恰涨一次）
    private(set) var configureCount = 0
    private(set) var configuredKey: String?

    /// 台账 190④：持久行托管（控制器持有、随
    /// cell 终身）：旧形态每次 configure 新建
    /// UIHostingConfiguration 并整体换配——托管
    /// 控制器与托管视图随之整套重建（WWDC23
    /// 《Demystify SwiftUI Performance》对列表
    /// 行托管换根的忌口在本仓的落点）。改收敛
    /// 为：托管由控制器在 cell 首次配置时装配
    /// 一次（子控制器收编、与舱托管同式），此
    /// 后 configure 只换 rootView——托管本体不
    /// 再换根，SwiftUI 侧按行键 .id 隔离逐行重
    /// 渲的口径不变
    weak var rowHost: UIHostingController<AnyView>?

    func configure(with row: ChatNativeRow) {
        configureCount += 1
        configuredKey = row.key
        // 卡顿探针（2026-11-20）：托管行构建耗时
        // 在闭包被求值时计——只记账、无行为影响
        // （ChatLagProbe）
        let root = ChatLagProbe.measureHostingBuild {
            row.makeView()
        }
            .id(row.key)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        if let host = rowHost {
            host.rootView = AnyView(root)
        } else {
            // 托管未装配（探针裸装配等无控制器在
            // 席的形态）：回落旧配置路，行为与旧
            // 形态逐字一致
            var config = UIHostingConfiguration {
                root
            }
            config = config.margins(.all, 0)
            contentConfiguration = config
        }
        backgroundConfiguration = .clear()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
        configuredKey = nil
        // 持久托管不拆：内容在下次 configure 换
        // rootView 时整体替换（行键 .id 隔离防
        // 状态跨行串行，口径不变）
    }

}

// MARK: - 根容器

/// 原生面句柄（§291）：与 gen3 句柄（ChatList-
/// CarrierHandle）同形态——四读数＋四命令转发，
/// 控制器为本面具体类型。两面句柄同形不同型：
/// 抽协议存在类型曾试、CI 两轮实证与本仓 Swift 6
/// 隔离形态冲突（协议标 @MainActor 则非隔离句柄
/// 调用成错误、不标则两容器 witness 隔离不一致），
/// 故 ChatView 链以四个分发器按当前面派发、链本
/// 体仍只一份（见 ChatView surface* 分发器）
final class ChatNativeListHandle {
    var latestDistance: CGFloat = 0
    var contentEndVisible = false
    var containerHeight: CGFloat = 0
    var bottomInset: CGFloat = 0

    weak var controller: ChatRootViewController?

    func scrollToBottom(animated: Bool) {
        controller?.scrollToBottom(animated: animated)
    }

    func scrollToEntry(_ id: UUID, animated: Bool) {
        controller?.scrollToEntry(id, animated: animated)
    }

    /// 搜索落点（台账 150）：收敛式定位到目标条目
    /// （多次重滚＋漂移容差，判定在 Core Search-
    /// FocusConvergence）
    func focusEntry(_ id: UUID) {
        controller?.focusEntry(id)
    }

    /// 选区在场行键（141/142 根治）：ChatView 选区
    /// 记账同步写入——控制器分流时该键的重配一律
    /// 暂存（选区在场期间该行托管视图不许换代，
    /// 与 OB selecting 态关行手势同构：平台文本视
    /// 图在场时行 machinery 让路）；清账时经
    /// noteSelectionProtectionEnded 唤醒 flush。
    /// 纯引用记账、无观察语义
    var selectionActiveRowKey: String?

    /// §366：抽屉运动窗终点（CACurrentMediaTime
    /// 系）：ChatView 在 router.drawerPresented 翻
    /// 转时按 DrawerSpringTiming.response＋落定余
    /// 量写入——落定拍在此窗内冻结施工、窗末合并
    /// 一拍（与选区记账同式：纯引用记账、无观察
    /// 语义）；0＝无窗在途
    var drawerMotionDeadline: CFTimeInterval = 0

    func noteSelectionProtectionEnded() {
        controller?.selectionProtectionEnded()
    }

    /// 台账 182：覆盖层（附件面板/选择器/相机）
    /// 呈现与收起完成点的离散重解析转手——控制器
    /// 未装配（gen3 面）时空转无副作用
    func reresolveAnchorsAfterPresentation() {
        controller?.reresolveAnchorsAfterPresentation()
    }

    func captureAnchor() -> ChatListAnchor? {
        controller?.captureAnchor()
    }

    func restore(_ anchor: ChatListAnchor) {
        controller?.restore(anchor)
    }
}

final class ChatRootViewController: UIViewController,
    UICollectionViewDelegate
{
    let collectionView: UICollectionView
    /// 与布局提供者闭包捕获的是同一个实例（init
    /// 里以本地实例回填本属性——提供者只认匣、不
    /// 认控制器本体，控制器初始化完成前不许自引）
    private let layoutBox: ChatNativeLayoutBox
    private var dataSource:
        UICollectionViewDiffableDataSource<Int, String>!

    var handle: ChatNativeListHandle?
    var callbacks: ChatNativeListCallbacks?

    /// 与 gen3 容器同口：两宿主的滚动边缘注册经共
    /// 享句柄绑本面本体（§260）
    var edgeScrollHandle: ChatListScrollViewHandle? {
        didSet { edgeScrollHandle?.register(collectionView) }
    }

    private var layoutParams = ChatNativeLayout(
        horizontalPadding: 20, topPadding: 16,
        bottomPadding: 8, rowSpacing: 24,
        arrowTrailing: 16, arrowSize: 44
    )
    private var rows: [ChatNativeRow] = []
    private var rowsByKey: [String: ChatNativeRow] = [:]
    private var revisionsByKey:
        [String: ChatNativeRowRevision] = [:]
    /// 非条目行的锚占位 id（与 gen3 同式：捕获命中
    /// 时顺延到下一条目行）
    private var frameIDByKey: [String: UUID] = [:]

    /// 喂入记账：顶 inset 喂入值／单点边距（§263
    /// 口径与 gen3 同源）。底侧自 R2 起无喂入——
    /// 舱在本容器内、留位全由其实测帧派生
    private var fedTopInset: CGFloat = 0
    private var bottomMargin: CGFloat = 0
    /// 实测留位（列表帧底−舱顶，两实测同在窗口系
    /// 相减）；nil＝尚未入窗量得（量得前底侧按 0
    /// 记账：首个布局拍即量得，先于任何可见帧）
    private var measuredBottomSpace: CGFloat?

    /// 输入舱子托管（R2 收编）：内容由 ChatView
    /// 以 AnyView 喂入（bottomBar 本体），底边钉
    /// 自有位置引导线 bottomGuide——其 top 常量
    /// 是舱落位的唯一数（§302 回 §194 形态：键
    /// 盘态＝通知帧顶、静息态＝坞实测顶，sync-
    /// BottomConstant 唯一计算点）。装配测试经
    /// internal 读口取其帧
    private(set) var composerHost:
        UIHostingController<AnyView>?
    /// §302：键盘帧更新回调（representable 桥接
    /// 回 ChatView 的 kbFrameUpdate 绑定）——与
    /// 舱常量同一通知解析点同拍组装（reportKey-
    /// boardFrame），帧顶已转窗口坐标、动画参数
    /// 原值；快照本体仍是 ChatView 的 kbSnapshot
    /// 一份，本容器不另持快照
    var onKeyboardFrameChange: ((KeyboardFrameUpdate) -> Void)?
    /// §302 位置引导线：top 由 bottomGuideTop-
    /// Constraint 的常量定位（布局空间换算，见
    /// syncBottomConstant）；舱底恒钉其 topAnchor、
    /// 约束永不切换激活态（§194「模式即病灶」）
    private let bottomGuide = UILayoutGuide()
    private var bottomGuideTopConstraint: NSLayoutConstraint!
    /// §302 坞锚当前参照（UITabBar 本体或类名兜
    /// 底命中；回落态为 nil 且 dockIsFallback＝
    /// true，参照＝窗口安全区底）——与 §194 同
    /// 式：只读其实帧、永不被约束直接引用
    private weak var dockBarView: UIView?
    private var dockIsFallback = false
    private weak var anchorWindow: UIWindow?
    /// 台账 189（结构根治）：可见胶囊参照——iOS
    /// 26 浮动坞的可见坞体是 UITabBar 子层级内
    /// 的胶囊/platter 子视图（bar 本体帧顶比胶
    /// 囊顶高 39pt，182/189 两轮实证）。静息落
    /// 位自本包起入布局流：bottomGuide.top 直接
    /// 约束到胶囊 topAnchor（布局引擎逐 pass 维
    /// 护、无人工换算、无原点配对），本字段只持
    /// 参照引用、由 resolveAnchors 在离散触发点
    /// 重解析（实例被换即重建约束）
    private weak var dockCapsuleView: UIView?
    /// 静息入流约束（guide.top＝胶囊.top）：仅静
    /// 息态＋胶囊在场时激活；键盘态/回落态由常
    /// 量约束接管（§194 单常数链不动）。激活态
    /// 切换只发生在离散事件点（锚重解析/键盘翻
    /// 转），永不在布局拍内切换
    private var dockFlowConstraint: NSLayoutConstraint?
    /// 胶囊参照失效（移窗/被换）时布局拍自愈重
    /// 解析的节流时刻（与回落态自愈同式）
    private var lastCapsuleResolveAt: CFTimeInterval = 0
    /// §302.1 续作：回落态布局拍重解析的上次尝试
    /// 时刻——回落壳内恒无坞时每拍全窗遍历找坞会
    /// 扰动落定收敛时序，布局拍自愈加 0.3s 节流
    /// （窗口变化与离散触发点不经此闸，见
    /// viewDidLayoutSubviews／resolveAnchors）
    private var lastFallbackResolveAt: CFTimeInterval = 0
    private var keyboardUp = false
    /// §302 键盘顶存账（窗口坐标）：willShow/
    /// willChangeFrame 通知的结束帧顶——键盘本
    /// 人广播的真值，常量换算的唯一键盘输入；
    /// 收起即清
    private var keyboardTopInWindow: CGFloat?
    /// 视图未装载时到达的舱内容（装载拍补装）
    private var pendingComposerView: AnyView?
    /// 落定拍调度账（与 gen3 §259 同式：滚动回调
    /// 只记账、施工与读数产出统一在落定拍）
    private var settleScheduled = false
    /// §374.3 测试口：单 section 模式覆盖（非 nil
    /// 时模式同步认本口不认全局开关——双控制器同
    /// 进程对账/探针用；生产恒 nil）
    var testSingleSectionOverride: Bool?
    /// §374.4 测试口：时间窗合并删除覆盖（非 nil
    /// 时落定拍删窗判定认本口不认全局开关——窗语
    /// 义钉测/量测探针用；生产恒 nil）
    var testCoalesceWindowDropOverride: Bool?
    /// §374.5 测试口：停滚结清单拍结清覆盖（非 nil
    /// 时停滚落写口单拍判定认本口不认全局开关——
    /// 拆拍语义钉测/量测探针用；生产恒 nil）
    var testSettleSingleBeatOverride: Bool?
    /// §374.6 测试口：抽屉动画期冻结删除覆盖（非 nil
    /// 时喂入冻结判据与落定拍冻结判定认本口不认全
    /// 局开关——冻结语义钉测/量测探针用；生产恒 nil）
    var testDrawerFreezeDropOverride: Bool?
    /// §374.7 测试口：滚动闸记账降级覆盖（非 nil
    /// 时停滚落写口降级判定认本口不认全局开关——
    /// 现行闸语义钉测/量测探针用；生产恒 nil）
    var testScrollLedgerOverride: Bool?
    /// §374.8 测试口：选区单键暂缓覆盖（非 nil
    /// 时分流暂缓判定认本口不认全局开关——暂缓
    /// 语义钉测用；生产恒 nil）
    var testSelectionKeyGuardOverride: Bool?
    /// §325.2：布局参数变更的失效记账（apply 只记
    /// 账、落定拍 pass 外合并施工，见 apply 注）
    private var pendingLayoutInvalidation = false
    /// §325.2：滚动期被冻结的落定拍记账（滚动结束
    /// 回调合并落写时消费）
    private var settleDeferredDuringScroll = false
    /// §366：落定拍布局失效施工计数（测试读口，与
    /// 布局匣 sectionProviderCallCount 同式：生产只
    /// 多一次计数、无行为影响）
    private(set) var settleLayoutFlushCount = 0
    /// §374.2：快照施工计数（测试读口：dataSource
    /// .apply 次数与其中 reconfigure 的条目数——
    /// 「高-only 回填不触发快照/重配」断言用；生
    /// 产只多计数、无行为影响）
    private(set) var snapshotApplyCount = 0
    private(set) var reconfiguredItemCount = 0
    /// §366：时间窗合并——上次布局失效施工时刻；
    /// 同窗内的行高类失效记账攒到窗末一拍合并施
    /// 工（定向失效实证不成立后的退路，§366.1）
    private var lastLayoutFlushAt: CFTimeInterval = 0
    /// §366：参数类失效的紧急记账（布局参数变＝
    /// 全几何变、不许等窗，落定拍见此账立即施工）
    private var pendingLayoutInvalidationUrgent = false
    /// §366：停滚结清拆拍阶段（0＝常态；1＝下一拍
    /// 只落数据；2＝紧接一拍落布局／量测／落位）。
    /// §374.5：单拍结清缺省成立——停滚落写口直
    /// 接武装 2，落定拍认领后一拍走全链结清；拆
    /// 拍只在回退开关置假时经武装 1 复活
    private var settleClearingStage = 0
    /// §366：抽屉运动窗冻结记账（窗内落定拍只记
    /// 账、窗末唤醒拍合并施工；唤醒拍以本旗标认
    /// 领、绕时间窗合并立即施工）
    private var settleDeferredDuringDrawer = false
    /// §366：时间窗合并窗长（调研退路口径 100–
    /// 200ms 取中值；流式发布闸约 80ms 一拍下每
    /// 窗约攒 2 拍失效）。§374.4：本窗缺省已删
    /// （删窗开关包裹保留为回退口，消费口见落定
    /// 拍布局失效施工处）
    private static let layoutCoalesceWindow:
        CFTimeInterval = 0.15
    /// §366：结清拆拍的布局拍顺延（数据拍与布局
    /// 拍错开一小拍：停指单拍不再叠满全账、时序
    /// 在钉测里可判读）
    private static let settleSplitBeatDelay:
        CFTimeInterval = 0.03
    /// §329：滚动期到达的整笔 apply 喂入（滚动闸
    /// 记账槽，与 §325.2 冻结同族——停滚后由落定
    /// 拍先行消费、再走原有落写链；后到覆盖先到，
    /// 与 representable 只认最新喂入同义）
    private struct PendingApply {
        var rows: [ChatNativeRow]
        var layout: ChatNativeLayout
        var topInset: CGFloat
        var bottomMargin: CGFloat
        var composerView: AnyView?
        var arrowView: AnyView?
        /// §374.2：本槽的路别——非 nil＝新路喂入
        /// （变更集已在槽内合成保全、落定拍走
        /// applyChangesNow）；nil＝旧路（applyNow
        /// 全量对账）
        var changeSet: EntryChangeSet? = nil
    }
    private var pendingApply: PendingApply?
    /// §374.8（步骤 5）：选区单键暂缓的待补账——
    /// 只存行键（至多选区在场行一键）、不存第二
    /// 份变更集；补发时按 rowsByKey 现行行值重算
    /// 该行 reconfigure（修订记账已按新行落写、
    /// 修订差不会再检出本键，键留本集作补发源），
    /// 选区清账回调唤醒后一拍 flush 落写。§332
    /// 触摸序列门的任意行暂存自此退役（DESIGN
    /// §374.8）
    private var selectionStagedReconfigureKeys:
        Set<String> = []
    /// 台账 200 拆换（2026-11-21 用户拍板）：行长
    /// 按识别器＋自绘动作面整套退役——长按菜单回归
    /// 系统上下文菜单（ChatView 的 MessageMenu-
    /// Modifier 挂气泡非文本层），本控制器不再持
    /// 有任何行长按 machinery

    /// 落点意图（H6）：冷开/命令贴底置真；落定拍
    /// 判达标＋几何跨拍稳定后消（§302.3）、或用
    /// 户拖动接管即消
    private var landingIntent = false
    /// 落点意图置真时刻（收敛重拍的时间窗预算起
    /// 点，见 performSettleBeat 的尾差处理）
    private var landingIntentSince: CFTimeInterval = 0
    /// §426（缺陷三）键盘贴底意图：键盘将升起的
    /// 事务开始前（几何未动时）捕获的「在底事实」
    /// ——升起前在底 ⇒ 整个键盘事务（升起/帧变/
    /// 收起前）每拍重钉；用户拖动接管或键盘收起
    /// 即消。与 landingIntent 分工：彼管内容落点
    /// （冷开/命令/落定），此管键盘几何事务——旧
    /// 链键盘路径无任何意图、只靠布局拍按当拍几
    /// 何采样 wasAtBottom，而量测留位在落定拍一
    /// 次跳到终值后距离读数恒≈键盘高、采样恒假，
    /// 永不重钉（真机 verdict 钉死：键盘起后记录
    /// 不到最新、须手拉）
    private var keyboardPinIntent = false
    /// §438 收起侧对称意图：收起事务开始前（几何
    /// 未动、键盘态几何下）捕获的在底事实——与升
    /// 起侧 keyboardPinIntent 同式（§426），收起事
    /// 务凭本意图在事务内按静息几何钉回；旧链收起
    /// 即清意图、无专属回钉，落偏后无机制找回（用
    /// 户视频合后 +149px 不归位实证）
    private var keyboardHidePinIntent = false
    /// §438 键盘事务窗记账：事务（升起/收起/帧变）
    /// 自通知处理起、至动画 completion（或被新事
    /// 务接管/用户拖动接管）止在途——窗内 inset 施
    /// 工与钉底由事务块内同事务应用独占（见
    /// animateLayout 的 §438 段），落定拍/布局拍只
    /// 记账不施工（与滚动/抽屉冻结同式纪律）；
    /// deadline 为 completion 丢失时的自愈上限
    /// （与抽屉窗 deadline 同式判定）
    private var keyboardTransactionInFlight = false
    private var keyboardTransactionID = 0
    private var keyboardTransactionDeadline: CFTimeInterval = 0
    /// §438 落定拍键盘窗冻结记账（窗末唤醒拍认领）
    private var settleDeferredDuringKeyboard = false
    /// §302.3 意图消费的几何稳定账：上一落定拍的
    /// contentSize——与本拍逐值同才算几何静止；消
    /// 费另须本拍钉前已在底（上一钉熬过整拍布局
    /// 冲刷、迟到回调未现形），意图置真/消解时清零
    private var landingSettleContentSize: CGFloat?
    private var userInteracting = false
    /// 台账 190 留账·nanoMuse 列表三件③（DESIGN
    /// §335）：浏览态——delegate 状态机口径（will-
    /// BeginDragging 置真、停滚清零：不减速的 did-
    /// EndDragging／didEndDecelerating），覆盖「手
    /// 指离屏→减速开始」的旗标空窗（该拍 isTrack-
    /// ing 已落、isDecelerating 未起，只读旗标的闸
    /// 门会漏进一笔施工）。滚动冻结闸门读本态∪旗
    /// 标（并集只扩不缩：触碰未拖的 isTracking 拍
    /// 仍按旧口径冻结）；与 userInteracting 的置/
    /// 清点位逐点同行、语义各管一段（彼管落点意
    /// 图、本态管冻结闸门），不许合并复用
    private var userBrowsing = false
    /// 搜索落点收敛（台账 150）：进行中的收敛机与
    /// 目标条目——落定拍逐拍喂屏上位置评估（判定
    /// 在 Core SearchFocusConvergence）；用户拖动
    /// 即弃、目标行消失即弃
    private var focusConvergence = SearchFocusConvergence()
    private var focusTargetID: UUID?
    /// 布局未就绪时到达的恢复命令（先记账、落定
    /// 拍执行——与 gen3 restore 的等拍口径同义）
    private var pendingAnchor: ChatListAnchor?
    private var lastReportedTopVisible: UUID??

    private var arrowHost: UIHostingController<AnyView>?
    private var arrowVisible = false
    /// 台账 190④：行持久托管池（按 cell 实例持
    /// 有；cell 随集合视图回收复用、池规模＝在席
    /// cell 数，控制器 deinit 时整池拆收）
    private var rowHosts:
        [ObjectIdentifier: UIHostingController<AnyView>] =
        [:]
    /// 台账 190②：就地量测口（ChatView 经 repre-
    /// sentable 喂入：行键→量测台 measureNow 的
    /// 确定高）；布局匣的 syncMeasure 经本口按序
    /// 取行键转发
    var exactHeightProvider: ((String) -> CGFloat?)?

    /// 行持久托管装配（台账 190④）：cell 首次配
    /// 置时建托管控制器收编为子控制器（与舱托管
    /// installComposerIfNeeded 同式：safeArea-
    /// Regions 清零防行内安全区污染、高由固有尺
    /// 寸——sizingOptions 取 intrinsicContent-
    /// Size，托管视图在 cell 内贴顶抱内容高，与
    /// 旧 UIHostingConfiguration 的抱高口径同
    /// 义）；托管视图入 cell 内容视图后随 cell
    /// 终身，configure 只换其 rootView
    private func ensureRowHost(
        for cell: ChatNativeHostingCell
    ) {
        guard cell.rowHost == nil else { return }
        let id = ObjectIdentifier(cell)
        let host: UIHostingController<AnyView>
        if let pooled = rowHosts[id] {
            host = pooled
        } else {
            host = UIHostingController(
                rootView: AnyView(EmptyView())
            )
            host.safeAreaRegions = []
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints =
                false
            addChild(host)
            rowHosts[id] = host
        }
        if host.view.superview !== cell.contentView {
            cell.contentView.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(
                    equalTo: cell.contentView.topAnchor
                ),
                host.view.leadingAnchor.constraint(
                    equalTo: cell.contentView.leadingAnchor
                ),
                host.view.trailingAnchor.constraint(
                    equalTo: cell.contentView.trailingAnchor
                ),
            ])
            host.didMove(toParent: self)
        }
        cell.rowHost = host
    }

    /// 行托管整池拆收（deinit）：子控制器逐个移
    /// 出收编，防收编关系悬挂
    private func teardownRowHosts() {
        for (_, host) in rowHosts {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        rowHosts = [:]
    }
    private var blankTapDelegate: ChatNativeBlankTapDelegate?

    // MARK: 生命周期

    override init(
        nibName nibNameOrNil: String?,
        bundle nibBundleOrNil: Bundle?
    ) {
        let box = ChatNativeLayoutBox()
        box.singleSection =
            ChatListSingleSectionFeature.isEnabled()
        layoutBox = box
        let layout = ChatRootViewController
            .makeLayout(box: box)
        collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: layout
        )
        super.init(
            nibName: nibNameOrNil, bundle: nibBundleOrNil
        )
        setUpCollectionView()
    }

    required init?(coder: NSCoder) {
        let box = ChatNativeLayoutBox()
        box.singleSection =
            ChatListSingleSectionFeature.isEnabled()
        layoutBox = box
        let layout = ChatRootViewController
            .makeLayout(box: box)
        collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: layout
        )
        super.init(coder: coder)
        setUpCollectionView()
    }

    /// 集合视图装配（init 期即完成：representable
    /// 的 update 可能先于 viewDidLoad 到达，cell 注
    /// 册与数据源不许等装载拍）
    private func setUpCollectionView() {
        collectionView.delegate = self
        // §374.8：§332 触摸观察识别器已随序列门
        // 退役——集合视图不再挂任何旁观识别器，
        // 选区保护只余分流处的单键暂缓
        // 自适应行高失效口径（iOS 16+ UICollection-
        // View 属性、非 layout 属性）：托管内容
        // （SwiftUI 拟合）的尺寸变化即自动重测，不
        // 手算不回填（H9/H10）。§325.2 守卫 3③ 定
        // 档：.enabled（内容尺寸变化才失效）——最激
        // 进档 .enabledIncludingConstraints（cell 内
        // 任何约束变化即失效）是 .66 崩溃成环三件
        // 套之一（诊断定因），托管内容的尺寸变化经
        // 托管视图本体上报、.enabled 已足；两档收敛
        // 对照由 R3 ⑮′ 压测实证（pass 数入 CI 日志）
        collectionView.selfSizingInvalidation =
            .enabled
        collectionView.register(
            ChatNativeHostingCell.self,
            forCellWithReuseIdentifier:
                ChatNativeHostingCell.reuseID
        )
        makeDataSource()
    }

    /// 布局构造分流（§374.3）：匣内构造旗决定
    /// 走 §329 逐行 section 构造还是单 section
    /// 构造——两构造共用同一高度账（按键）与同
    /// 一就地量测纪律，几何逐值等价（§374.3 对
    /// 账钉测把守）
    private static func makeLayout(
        box: ChatNativeLayoutBox
    ) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout {
            sectionIndex, _ in
            box.noteSectionProviderCall()
            if box.singleSection {
                return ChatRootViewController
                    .makeSingleSection(box: box)
            }
            return ChatRootViewController
                .makeRowSection(
                    box: box, sectionIndex: sectionIndex
                )
        }
    }

    /// 就地量测回写（台账 190②，两构造共用）：
    /// 可见窗内的临界行在提供者问高时同步量测
    /// ——单行毫秒级、入屏前付清，确高按键回写
    /// 匣内本账（本 pass 与后续 pass 同读新值）
    /// 并入布局层确高备忘（§335）；窗外/预算尽
    /// /无量测台时保留当趟喂入高（量测台回填后
    /// 经发布代次重喂，两路同值）
    private static func settleProvisionalHeight(
        box: ChatNativeLayoutBox, key: String,
        rowIndex: Int
    ) {
        guard box.visibleWindow.contains(rowIndex),
              box.syncMeasureBudget > 0,
              var entry = box.heightByKey[key],
              entry.provisional,
              let measured = box.syncMeasure?(key)
        else { return }
        entry.height = measured
        entry.provisional = false
        box.heightByKey[key] = entry
        box.syncMeasureBudget -= 1
        // §335：就地量得的确高同入布局层备忘——
        // 本行自此在布局层有确值，后续重喂不许
        // 打回临界
        box.exactHeightByKey[key] = (
            revision: entry.revision, height: measured
        )
    }

    /// compositional 单列 section（§329 改 section-
    /// per-row）：一行一 section、item/group 高＝
    /// .absolute(该行回喂高)——框架不估算、不修
    /// 正，post-pass 偏移修正按构造不存在。间距
    /// 仍单源（H1）：行距改由 section 底 inset 承
    /// 担（非末行＝rowSpacing、末行＝bottomPad-
    /// ding、首行顶＝topPadding），总几何与旧
    /// interGroupSpacing 口径逐值等价；左右 inset
    /// 恒 horizontalPadding。提供者越界（序≥行集
    /// 长）回落固定占位常量（防御、正常路径不达）
    /// §374.3：高度改按键读账（序→键→条目）；
    /// 本构造保留作单 section 旗关时的回退形态
    private static func makeRowSection(
        box: ChatNativeLayoutBox, sectionIndex: Int
    ) -> NSCollectionLayoutSection {
        let rowCount = box.rowOrder.count
        // 台账 190②：将入视口的临界行在提供者问
        // 高时就地量测（共用口 settleProvisional-
        // Height：窗/预算/量测台三闸同旧）
        if sectionIndex < rowCount {
            settleProvisionalHeight(
                box: box,
                key: box.rowOrder[sectionIndex],
                rowIndex: sectionIndex
            )
        }
        let height = sectionIndex < rowCount
            ? box.height(at: sectionIndex)
            : ChatNativeLayoutBox.estimatedPlaceholder
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(max(0, height))
        )
        let item = NSCollectionLayoutItem(
            layoutSize: itemSize
        )
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(max(0, height))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize, subitems: [item]
        )
        let section = NSCollectionLayoutSection(
            group: group
        )
        section.contentInsets = NSDirectionalEdgeInsets(
            top: sectionIndex == 0 ? box.topPadding : 0,
            leading: box.horizontalPadding,
            bottom: sectionIndex >= rowCount - 1
                ? box.bottomPadding : box.rowSpacing,
            trailing: box.horizontalPadding
        )
        return section
    }

    /// compositional 单 section 构造（§374.3，施
    /// 工图对位 #4：单 section 形态照 MessageKit
    /// ——单列、逐行确定高）：全体行同属 sec-
    /// tion 0，根组＝纵向组、逐行一 item（item
    /// 高＝.absolute(该行回喂高)），行距由
    /// 根组 interItemSpacing 承担、顶/底/左右
    /// inset 由 section contentInsets 承担，总
    /// 几何与逐行 section 构造逐值等价（顶 top-
    /// Padding＋Σ高＋rowSpacing×(n−1)＋底 bot-
    /// tomPadding；H1 间距单源不变）。根组高取
    /// 确值口径（步骤 0 探针 B 的 B1 档）：由同
    /// 一高度账求和得出——全链零估算，§329「按
    /// 构造拆除修正源」在根组一级同守（B2 粗估
    /// 档在 spike 同样收敛，但其根高修正仍托框
    /// 架 post-pass，与本仓口径相悖，故不取）。
    /// 高度按键读账：序位→行键→条目
    private static func makeSingleSection(
        box: ChatNativeLayoutBox
    ) -> NSCollectionLayoutSection {
        let rowCount = box.rowOrder.count
        // 台账 190②：窗内临界行在建组前逐行就地
        // 量定（共用口三闸与逐行构造同）——高度
        // 在本 pass 消费前已定，§329 构造纪律
        // 不变
        for index in 0..<rowCount
        where box.heightByKey[
            box.rowOrder[index]
        ]?.provisional == true {
            settleProvisionalHeight(
                box: box, key: box.rowOrder[index],
                rowIndex: index
            )
        }
        // 组树形状定版（§374.3 spike 三变体实
        // 数）：pass 成本由逐 item 帧求解主导、
        // 逐行一子组层纯增常数（@1200 行 pass
        // 8.55ms vs 单组多 item 3.36ms），故根组
        // 直挂逐行 item、不设子组层
        var subitems: [NSCollectionLayoutItem] = []
        subitems.reserveCapacity(max(1, rowCount))
        var contentHeight: CGFloat = 0
        if rowCount == 0 {
            // 空行集：零高占位 item（section 恒
            // 在、条目为零——组树只描述几何、无
            // 条目即不物化，占位高 0 不入总几何）
            let zeroSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(0)
            )
            subitems.append(
                NSCollectionLayoutItem(
                    layoutSize: zeroSize
                )
            )
        }
        for index in 0..<rowCount {
            let height = max(0, box.height(at: index))
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(height)
            )
            subitems.append(
                NSCollectionLayoutItem(
                    layoutSize: itemSize
                )
            )
            contentHeight += height
        }
        if rowCount > 1 {
            contentHeight += box.rowSpacing
                * CGFloat(rowCount - 1)
        }
        let rootSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(contentHeight)
        )
        let root = NSCollectionLayoutGroup.vertical(
            layoutSize: rootSize, subitems: subitems
        )
        if rowCount > 1 {
            root.interItemSpacing = .fixed(
                box.rowSpacing
            )
        }
        let section = NSCollectionLayoutSection(
            group: root
        )
        section.contentInsets = NSDirectionalEdgeInsets(
            top: box.topPadding,
            leading: box.horizontalPadding,
            bottom: box.bottomPadding,
            trailing: box.horizontalPadding
        )
        return section
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        // 句柄回指（representable 的 make/update 已
        // 立、本处为脱离 representable 装配时的兜底）
        handle?.controller = self
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        // 记账全手动（与 gen3 同口：inset 只认喂入
        // 记账＋实测派生，不许系统再叠安全区）
        collectionView.contentInsetAdjustmentBehavior =
            .never
        collectionView.keyboardDismissMode = .interactive
        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        // 边缘效果样式的 UIKit 直设（与 gen3 §260
        // 同义同值：样式挂滚动视图本体的 edge
        // effect、不自绘渐变——§173 红线）
        collectionView.topEdgeEffect.style = .soft
        collectionView.bottomEdgeEffect.style = .soft
        view.addSubview(collectionView)
        // §302：位置引导线入本视图（top 常量待
        // syncBottomConstant 按当前输入填，初始 0
        // ＝未解析前舱贴顶、无害瞬态，锚解析在入
        // 窗/显形拍即补）；舱装配（installComposer-
        // IfNeeded）把舱底钉其 topAnchor
        view.addLayoutGuide(bottomGuide)
        bottomGuideTopConstraint = bottomGuide.topAnchor
            .constraint(equalTo: view.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            bottomGuide.leadingAnchor.constraint(
                equalTo: view.leadingAnchor),
            bottomGuide.trailingAnchor.constraint(
                equalTo: view.trailingAnchor),
            bottomGuide.heightAnchor.constraint(
                equalToConstant: 0),
            bottomGuideTopConstraint,
        ])
        // §302 键盘信号（与 §194 同式）：willShow/
        // willHide 定状态翻转、willChangeFrame 供
        // 逐帧跟随，三者的结束帧都是位置常量的键
        // 盘输入；动画参数随通知取。selector 式观
        // 察者（不存 token，与 ComposerGuideHost-
        // Controller 同纪律：块式 token 在 Swift 6
        // 下 deinit/跨闭包发送有实证坑）
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        center.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        installComposerIfNeeded()
        installBlankTapDismiss()
        // 台账 190②：布局匣就地量测口装配（行键
        // →喂入口转发；行集以调用时刻的 rowsBy-
        // Key 为准，提供者在布局 pass 内同步调
        // 用、只读本匣与行集）
        layoutBox.syncMeasure = { [weak self] key in
            guard let self,
                  self.rowsByKey[key] != nil
            else { return nil }
            return self.exactHeightProvider?(key)
        }
        ChatDiagTrace.record(
            "原生重建 R1 新面装配（开关开）："
                + "UICollectionView＋diffable 就绪"
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        teardownRowHosts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // §302 锚解析触发点之一（入窗后窗口已定）：
        // 与 §194 的入窗/显形重解析同式——切格往返
        // 期间标签栏实例若被换过，在此换新参照
        resolveAnchors()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveAnchors()
    }

    // MARK: 键盘跟随（§302 回 §194 形态）

    @objc private func keyboardWillShow(
        _ note: Notification
    ) {
        setKeyboardUp(true, note: note)
    }

    @objc private func keyboardWillHide(
        _ note: Notification
    ) {
        setKeyboardUp(false, note: note)
    }

    /// §302 帧变化跟进（交互式下滑收键盘/候选条
    /// 高度变化）：键盘态内逐事件刷新存账帧顶并重
    /// 算常量——通知帧是键盘本人的广播，不经任何
    /// 引导线转译；时长 0 的逐帧事件直接布局、不
    /// 包动画（与 §194 willChangeFrame 同式）
    @objc private func keyboardWillChangeFrame(
        _ note: Notification
    ) {
        guard keyboardUp else { return }
        updateKeyboardTop(from: note)
        syncBottomConstant()
        animateLayout(
            with: note, immediateIfZero: true,
            pinIntent: keyboardPinIntent
        )
        reportKeyboardFrame(from: note)
    }

    /// §302 键盘帧顶存账：通知的结束帧是屏幕坐
    /// 标，经本窗换算成窗口坐标存下；常量换算在
    /// syncBottomConstant 里逐布局拍按本视图当前
    /// 布局空间重算，本函数只存窗口真值（与
    /// §194 updateKeyboardTop 同式）
    private func updateKeyboardTop(from note: Notification) {
        guard let value = note.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
        ] as? NSValue else { return }
        let screenFrame = value.cgRectValue
        if let window = view.window {
            keyboardTopInWindow = window.convert(
                screenFrame, from: nil
            ).minY
        } else {
            keyboardTopInWindow = screenFrame.minY
        }
    }

    /// §302 键盘态翻转：升起先把通知帧顶存账（常
    /// 量的唯一键盘输入），收起先重解析坞参照（聚
    /// 焦藏坞期间标签栏可能换实例）；常量重算后与
    /// 键盘动画同参推进布局（与 §194 setKeyboardUp
    /// 同式）。翻转拍采样引导线顶记入自述作对照
    /// ——引导线只采样、不驱动（预期其仍停静息
    /// 值、即定因 K1 本人）
    private func setKeyboardUp(
        _ up: Bool, note: Notification
    ) {
        // §426（缺陷三）：贴底意图在事务开始前捕
        // 获——本点几何未动（帧顶存账/常量重算都
        // 在其后），距离读数是升起前的真事实；等
        // 几何变完再判，新几何下恒不在底、永不重
        // 钉（旧链病灶）。收起即消（回落方向留位
        // 收缩不搁浅内容，布局拍在底链自理）
        if up, !keyboardUp {
            keyboardPinIntent = !userInteracting
                && collectionView.bounds.height > 0
                && currentDistance() <= Self.atBottomTolerance
            keyboardHidePinIntent = false
        } else if !up {
            // §438：收起侧对称捕获——清升起意图之
            // 前，先在键盘态几何（未动）下记当刻在
            // 底事实作收起事务的回钉意图；旧口径「收
            // 起即消、布局拍自理」使合后落偏无人收
            // 拾（定因见 kb-smooth-spec §438 二章）
            if keyboardUp {
                keyboardHidePinIntent = !userInteracting
                    && collectionView.bounds.height > 0
                    && currentDistance()
                        <= Self.atBottomTolerance
            }
            keyboardPinIntent = false
        }
        if up {
            updateKeyboardTop(from: note)
        } else {
            resolveAnchors()
        }
        guard up != keyboardUp else {
            // 同态重播（willShow 重发等）：按已存帧
            // 顶重同步常量即可，不重入记账
            if up {
                syncBottomConstant()
                view.layoutIfNeeded()
                reportKeyboardFrame(from: note)
            }
            return
        }
        keyboardUp = up
        if !up { keyboardTopInWindow = nil }
        // 台账 189：落位模式随键盘翻转同拍对账——
        // 升起切常量链（§194 帧顶常量、本包不动）、
        // 收起切回静息入流（胶囊参照已在上方
        // resolveAnchors 刷过）；updateDockMode 在
        // 常量模式内自带 syncBottomConstant
        updateDockMode()
        animateLayout(
            with: note, immediateIfZero: false,
            pinIntent: up ? keyboardPinIntent
                : keyboardHidePinIntent
        )
        reportKeyboardFrame(from: note)
        sampleGuideForTrace(event: up ? "kbShow" : "kbHide")
    }

    /// 与键盘动画同参推进一次布局（时长/曲线取自
    /// 通知）；immediateIfZero 时时长为 0 直接布
    /// 局——交互式逐帧跟随不许包进动画系统再迟
    /// 一拍（与 §194 animateLayout 同式）
    /// §438：本函数即键盘事务的唯一推进口——事务
    /// 窗开窗记账后，布局与列表几何（量测→inset 施
    /// 工→凭意图钉底）在同一动画块内落写（通行范
    /// 式：inset/offset 与键盘同一动画事务、UIKit
    /// 插值与舱同程，选型出处见 kb-smooth-spec
    /// §438 三章）；旧链几何归异步落定拍按模型终值
    /// 一步落写＝内容单帧瞬移、舱独行（用户视频实
    /// 证），§325.2 的逐帧到达假设对约束常量动画不
    /// 成立、就此收口
    private func animateLayout(
        with note: Notification, immediateIfZero: Bool,
        pinIntent: Bool = false
    ) {
        let userInfo = note.userInfo
        let duration = userInfo?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? Double ?? 0.25
        let curveRaw = userInfo?[
            UIResponder.keyboardAnimationCurveUserInfoKey
        ] as? UInt ?? 7
        keyboardTransactionID += 1
        let transactionID = keyboardTransactionID
        keyboardTransactionInFlight = true
        keyboardTransactionDeadline =
            CACurrentMediaTime() + duration + 0.5
        if immediateIfZero, duration <= 0 {
            view.layoutIfNeeded()
            applyKeyboardTransactionGeometry(
                pinIntent: pinIntent
            )
            endKeyboardTransaction(transactionID)
            return
        }
        UIView.animate(
            withDuration: duration, delay: 0,
            options: UIView.AnimationOptions(
                rawValue: curveRaw << 16
            )
        ) { [weak self] in
            guard let self else { return }
            view.layoutIfNeeded()
            applyKeyboardTransactionGeometry(
                pinIntent: pinIntent
            )
        } completion: { [weak self] _ in
            self?.endKeyboardTransaction(transactionID)
        }
    }

    /// §438 事务内几何应用（须在事务动画块内调
    /// 用）：布局已落终点帧后同块量测→inset 施工
    /// →凭事务意图钉底——三者在动画块内落写、呈
    /// 现层与舱同曲线推进，末行恒贴舱呈现顶（不抢
    /// 跑、不被盖）；落定拍其后收敛的目标与此同
    /// 值，不再产生可见位移
    private func applyKeyboardTransactionGeometry(
        pinIntent: Bool
    ) {
        measureBottomSpace()
        reconcileInsets()
        if pinIntent, !userInteracting {
            pinToBottom()
        }
    }

    /// §438 事务窗收窗：被接管的旧事务 completion
    /// 以 id 不符自弃；窗内被冻结的落定账在此唤醒
    /// 一拍合并落写
    private func endKeyboardTransaction(
        _ transactionID: Int
    ) {
        guard transactionID == keyboardTransactionID,
              keyboardTransactionInFlight
        else { return }
        keyboardTransactionInFlight = false
        if settleDeferredDuringKeyboard {
            settleDeferredDuringKeyboard = false
            scheduleSettle()
        }
    }

    /// §302 锚解析：在本视图所在窗口的层级里找坞
    /// 参照（UITabBar 本体或类名兜底），只登记引
    /// 用与命中模式——位置由 syncBottomConstant
    /// 逐拍换算进位置常量，参照本身不被任何约束
    /// 引用。触发点只在离散事件（入窗/显形/键盘
    /// 收起）与回落态布局拍自愈——后者经
    /// viewDidLayoutSubviews 的 0.3s 节流闸（§302.1
    /// 续作）、窗口变化仍立即触发；不在每拍布局
    /// 里无条件走层级（与 §194 resolveAnchors 同式）
    private func resolveAnchors() {
        guard let window = view.window else { return }
        let windowChanged = anchorWindow !== window
        anchorWindow = window
        let foundBar = Self.findDockAnchor(in: window)
        if let foundBar {
            if dockBarView !== foundBar || dockIsFallback
                || windowChanged {
                dockBarView = foundBar
                dockIsFallback = false
            }
        } else if !dockIsFallback || windowChanged {
            // 无坞环境回落（探针裸装配等非生产形
            // 态）：参照＝窗口安全区底——生产装配
            // 恒有坞，不走此路
            dockBarView = nil
            dockIsFallback = true
        }
        // 台账 189：胶囊参照随坞参照同拍重解析，
        // 落位模式（入流/常量）随之对账
        resolveDockCapsule()
        updateDockMode()
    }

    /// 台账 189：可见胶囊重解析——胶囊实例变了
    /// 才重建入流约束（旧约束先撤、参照先换）；
    /// 找不到胶囊（层级形态漂移）时参照置 nil、
    /// 落位回落常量链读 bar 帧顶（182 口径）＋
    /// 探针留痕（sampleAnchorQuad 的 capsuleTop
    /// 缺值即此态的证据）
    private func resolveDockCapsule() {
        let found = dockBarView.flatMap {
            Self.findDockCapsule(in: $0)
        }
        guard found !== dockCapsuleView else { return }
        dockFlowConstraint?.isActive = false
        dockFlowConstraint = nil
        dockCapsuleView = found
        if let found {
            dockFlowConstraint = bottomGuide.topAnchor
                .constraint(equalTo: found.topAnchor)
        }
    }

    /// 台账 189：落位模式对账（唯一切换点）——
    /// 静息态＋胶囊在场＝入流约束激活、常量约束
    /// 撤活；其余（键盘态/无胶囊/回落态）＝常量
    /// 约束激活并同步常量（§194 链）。切换只在
    /// 离散事件（锚重解析/键盘翻转）发生：先撤
    /// 后立、同拍不双活
    private func updateDockMode() {
        guard let bottomGuideTopConstraint else { return }
        let capsule = dockCapsuleView
        let wantFlow = !keyboardUp
            && capsule != nil
            && capsule?.window === view.window
        if wantFlow {
            if dockFlowConstraint?.isActive != true {
                bottomGuideTopConstraint.isActive = false
                dockFlowConstraint?.isActive = true
            }
        } else {
            if dockFlowConstraint?.isActive == true {
                dockFlowConstraint?.isActive = false
            }
            if !bottomGuideTopConstraint.isActive {
                bottomGuideTopConstraint.isActive = true
            }
            syncBottomConstant()
        }
    }

    /// 台账 189：UITabBar 子层级内定位可见胶囊
    /// ——全宽（≥bar 宽 85%）、胶囊高（36–90）、
    /// 位于 bar 帧下部（顶边在帧高 20% 以下）、
    /// 可见（非 hidden、alpha 有值）的子视图中
    /// 取顶边最靠下者（可见坞体悬浮内嵌在帧下
    /// 部，上部的全宽背景层帧高/位置不合本式自
    /// 然出局）。坐标一律经 convert 折进 bar 系
    /// 比较（与呈现帧同源）；找不到回 nil（形态
    /// 漂移的降级口在 resolveDockCapsule）
    /// （internal 而非 private：装配测试以合成层
    /// 级钉本启发式，与合成器/控制器的 internal
    /// 测试面同式）
    static func findDockCapsule(
        in bar: UIView
    ) -> UIView? {
        var best: UIView?
        var bestTop: CGFloat = -.greatestFiniteMagnitude
        func walk(_ view: UIView) {
            for sub in view.subviews {
                if !sub.isHidden, sub.alpha > 0.05 {
                    let frame = sub.convert(
                        sub.bounds, to: bar
                    )
                    let barWidth = bar.bounds.width
                    let barHeight = bar.bounds.height
                    if frame.width >= barWidth * 0.85,
                       frame.height >= 36,
                       frame.height <= 90,
                       frame.minY >= barHeight * 0.2,
                       frame.maxY <= barHeight + 1,
                       frame.minY > bestTop {
                        best = sub
                        bestTop = frame.minY
                    }
                }
                walk(sub)
            }
        }
        walk(bar)
        return best
    }

    /// 台账 182：呈现离散重解析入口——附件面板/
    /// 系统选择器/相机等覆盖层的呈现与收起完成点
    /// 由 ChatView 直调（经 ChatNativeListHandle）：
    /// 呈现期间 TabView 内部层级与变换态变化正是
    /// 静息锚失真的触发条件，收起后须在已恢复的
    /// 层级上立即重找坞参照＋重算常量，不经回落
    /// 态 0.3s 节流闸、不靠布局拍碰运气（与入窗/
    /// 显形/键盘收起的既有离散触发点同列）
    func reresolveAnchorsAfterPresentation() {
        resolveAnchors()
    }

    /// 台账 182 坏态三值同拍探针（只记账、永不驱
    /// 动）：静息态布局拍同拍采 ①bottomGuide 常
    /// 量 ②convert 口径坞顶 ③舱托管实际帧（窗口
    /// 系 minY/maxY）——健康态恒满足舱底＝坞顶；
    /// 偏差 >0.5 才记 ChatDiagTrace，同签名去重
    /// ＋1 秒节流（布局拍高频、坏态持续不许刷
    /// 屏）。真机复现坏态时以本记录定案：常量推
    /// 得的坞顶与 ②差→锚读法问题；①②相合而 ③
    /// 不合→舱装配/布局问题
    /// 台账 189 升四值：加采 ④可见胶囊顶（独立
    /// convert 读数、与入流约束不同源——约束失
    /// 效时本读数仍真）；判据改认舱底对胶囊顶
    /// （胶囊在场时），胶囊缺席回落旧三值判据对
    /// bar 帧顶。旧三值判据与锚同源、189 坏态下
    /// 三值自洽不留痕的盲区由 ④补上
    private var lastAnchorProbeSignature: String?
    private var lastAnchorProbeAt: CFTimeInterval = 0

    private func sampleAnchorTriadIfDiverged() {
        guard !keyboardUp,
              let window = view.window,
              let bar = dockBarView, bar.window === window,
              let host = composerHost,
              let bottomGuideTopConstraint
        else { return }
        let dockTop = bar.convert(
            bar.bounds, to: window
        ).minY
        let capsuleTop = dockCapsuleView.flatMap {
            capsule -> CGFloat? in
            guard capsule.window === window else {
                return nil
            }
            return capsule.convert(
                capsule.bounds, to: window
            ).minY
        }
        let hostFrame = host.view.convert(
            host.view.bounds, to: window
        )
        let referenceTop = capsuleTop ?? dockTop
        guard abs(hostFrame.maxY - referenceTop) > 0.5
        else { return }
        let signature = String(
            format: "%.0f|%.0f|%.0f|%.0f|%.0f",
            bottomGuideTopConstraint.constant, dockTop,
            capsuleTop ?? -1,
            hostFrame.minY, hostFrame.maxY
        )
        let now = CACurrentMediaTime()
        guard signature != lastAnchorProbeSignature,
              now - lastAnchorProbeAt >= 1
        else { return }
        lastAnchorProbeSignature = signature
        lastAnchorProbeAt = now
        if let capsuleTop {
            ChatDiagTrace.record(
                "原生面 §302 [anchorQuad] constant="
                    + String(
                        format: "%.1f",
                        bottomGuideTopConstraint.constant
                    )
                    + " dockTopConvert="
                    + String(format: "%.1f", dockTop)
                    + " capsuleTop="
                    + String(format: "%.1f", capsuleTop)
                    + " composerMinY="
                    + String(format: "%.1f", hostFrame.minY)
                    + " composerMaxY="
                    + String(format: "%.1f", hostFrame.maxY)
            )
        } else {
            ChatDiagTrace.record(
                "原生面 §302 [anchorTriad] constant="
                    + String(
                        format: "%.1f",
                        bottomGuideTopConstraint.constant
                    )
                    + " dockTopConvert="
                    + String(format: "%.1f", dockTop)
                    + " composerMinY="
                    + String(format: "%.1f", hostFrame.minY)
                    + " composerMaxY="
                    + String(format: "%.1f", hostFrame.maxY)
            )
        }
    }

    /// §302 位置常量唯一计算点：bottomGuide 的
    /// top 常量＝目标顶边－原点顶边（两项同坐标系
    /// 成对取值，不许混系相减）。
    /// 目标顶边按当前输入取实测真值：键盘升起态
    /// ＝通知广播的键盘帧顶（窗口坐标——键盘升
    /// 起时抽屉必闭、祖先链 transform 恒等，窗口
    /// 坐标与布局空间累加坐标同值；无帧存账时保
    /// 留上次常量、不许跌回坞值），原点项沿用布
    /// 局空间累加（§194 单常数链、本支不动）；
    /// 静息态＝坞参照的 convert() 窗口真值（台账
    /// 182 换代：layoutSpaceMinY 的原点累加在坞的
    /// 祖先链含 TabView 内部带变换容器时失真——
    /// §194 回报路注已自证偏 +83、锚本体当时冻结
    /// 未改；本包把回报路已验证的 convert 读法升
    /// 为锚本体唯一读法，累加近似在静息锚路退
    /// 役），原点项同走 convert 成对换算（抽屉为
    /// 水平平移、不入纵向读数，舱随前景同移的口
    /// 径不变）；回落态沿用旧式（无坞环境、探针
    /// 裸装配形态）。逐布局拍调用（只读缓存值、
    /// 无层级遍历），偏差 >0.5 才写
    private func syncBottomConstant() {
        guard let window = view.window,
              let bottomGuideTopConstraint else { return }
        let targetTop: CGFloat
        let originTop: CGFloat
        if keyboardUp {
            guard let kbTop = keyboardTopInWindow
            else { return }
            targetTop = kbTop
            originTop = Self.layoutSpaceMinY(of: view)
        } else if let bar = dockBarView,
                  bar.window === window {
            targetTop = bar.convert(
                bar.bounds, to: window
            ).minY
            originTop = view.convert(
                view.bounds, to: window
            ).minY
        } else if dockIsFallback {
            targetTop = window.bounds.height
                - window.safeAreaInsets.bottom
            originTop = Self.layoutSpaceMinY(of: view)
        } else {
            return
        }
        let constant = targetTop - originTop
        if abs(bottomGuideTopConstraint.constant - constant)
            > 0.5 {
            bottomGuideTopConstraint.constant = constant
        }
    }

    /// 视图在窗口布局空间的顶边（frame 原点沿父
    /// 链累加；transform 不进布局帧、天然不计，
    /// 与 §194 同名近似同式）
    private static func layoutSpaceMinY(
        of view: UIView
    ) -> CGFloat {
        var y = view.frame.minY
        var ancestor = view.superview
        while let current = ancestor,
              !(current is UIWindow) {
            y += current.frame.minY
            ancestor = current.superview
        }
        return y
    }

    /// 窗口层级内找坞锚目标（深度优先两级）：先
    /// UITabBar 本体；无本体时取类名含 TabBar 且
    /// 宽度 >300 的视图（系统内部实现跨版本改名/
    /// 换类的兜底，与 §194 findDockAnchor 同式）
    private static func findDockAnchor(
        in window: UIWindow
    ) -> UIView? {
        func walk(_ view: UIView) -> UIView? {
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews {
                if let hit = walk(sub) { return hit }
            }
            return nil
        }
        if let bar = walk(window) {
            return bar
        }
        func walkByName(_ view: UIView) -> UIView? {
            let name = String(describing: type(of: view))
            if name.contains("TabBar"),
               view.frame.width > 300 {
                return view
            }
            for sub in view.subviews {
                if let hit = walkByName(sub) { return hit }
            }
            return nil
        }
        return walkByName(window)
    }

    /// §302 键盘帧更新包的组装点——与 updateKey-
    /// boardTop 同一解析（window.convert 转窗口
    /// 坐标）、同一通知；停靠判定在窗口坐标系内
    /// 做（满宽＋底边贴窗口底＋帧顶在窗口内），
    /// 浮动/分离键盘按不在场报（top＝nil）；键盘
    /// 不在场（willHide 后）恒报 nil。动画参数取
    /// userInfo 原值。喂 ChatView 的 kbFrameUpdate
    /// ——与舱常量同源同拍（定因 K2 收口；与
    /// §194 reportKeyboardFrame 同式）
    private func reportKeyboardFrame(
        from note: Notification
    ) {
        let info = note.userInfo
        let duration = (info?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? NSNumber)?.doubleValue ?? 0
        let curve = (info?[
            UIResponder.keyboardAnimationCurveUserInfoKey
        ] as? NSNumber)?.intValue ?? 0
        var top: CGFloat? = nil
        if keyboardUp,
           let window = view.window,
           let value = info?[
               UIResponder.keyboardFrameEndUserInfoKey
           ] as? NSValue {
            let rect = window.convert(
                value.cgRectValue, from: nil
            )
            let docked = rect.width
                    >= window.bounds.width - 1
                && rect.maxY
                    >= window.bounds.height - 1
                && rect.minY
                    < window.bounds.height - 1
            top = docked ? rect.minY : nil
        }
        onKeyboardFrameChange?(
            KeyboardFrameUpdate(
                topInWindow: top,
                duration: duration,
                curveRawValue: curve
            )
        )
    }

    /// §325 引导线重验采样口（装配测试专用、只读）：
    /// 本视图 keyboardLayoutGuide 顶边的窗口坐标——
    /// 与通知帧顶同帧对账的测试读口（生产采样走
    /// sampleGuideForTrace 自述通道、本口不参与驱
    /// 动）
    /// §325.2 测试读口：布局 pass 计数（section 提
    /// 供者调用数）——长历史收敛压测断言 pass 数有
    /// 界/稳态零重建用，生产无消费
    var testSectionProviderCallCount: Int {
        layoutBox.sectionProviderCallCount
    }

    /// §366 测试读口：落定拍布局失效施工次数（时
    /// 间窗合并／拆拍／抽屉冻结的拍级断言用，生产
    /// 无消费）
    var testSettleLayoutFlushCount: Int {
        settleLayoutFlushCount
    }

    /// §329 测试读口：当前行集的回喂高（布局匣
    /// 高度账的按序镜像）——生产链压测对账「采
    /// 用高 vs 帧高」用，生产无消费
    var testAdoptedRowHeights: [CGFloat] {
        layoutBox.orderedHeights
    }

    /// §374.2 测试读口：快照条目序（新旧路终态
    /// 对账用，生产无消费）
    var testSnapshotKeyOrder: [String] {
        dataSource.snapshot().itemIdentifiers
    }

    /// §374.2 测试读口：修订账只读镜像（终态对
    /// 账用）
    var testRevisionsByKey:
        [String: ChatNativeRowRevision] {
        revisionsByKey
    }

    /// §374.2 测试读口：高度账按键镜像（布局匣
    /// 高度账本账的按键投影）
    var testRowHeightsByKey: [String: CGFloat] {
        layoutBox.heightByKey.mapValues { $0.height }
    }

    /// §374.2 测试读口：快照施工计数镜像
    var testSnapshotApplyCount: Int {
        snapshotApplyCount
    }
    var testReconfiguredItemCount: Int {
        reconfiguredItemCount
    }

    /// §325.2 测试口：selfSizingInvalidation 档位
    /// 对照压测用（生产默认 .enabled，见装配处注）
    var testSelfSizingInvalidation:
        UICollectionView.SelfSizingInvalidation {
        get { collectionView.selfSizingInvalidation }
        set { collectionView.selfSizingInvalidation = newValue }
    }

    var testKeyboardGuideTopInWindow: CGFloat? {
        guard let window = view.window else { return nil }
        return view.convert(
            CGPoint(
                x: 0,
                y: view.keyboardLayoutGuide.layoutFrame.minY
            ),
            to: window
        ).y
    }

    /// §302 引导线采样对照（只记自述、永不驱动）：
    /// 翻转拍记通知帧顶与本视图 keyboardLayout-
    /// Guide 顶的窗口值同帧对账——真机验收看数
    /// 字：舱底应＝通知帧顶；guide 若仍停静息值
    /// 即 K1 根因本人的持续留证
    private func sampleGuideForTrace(event: String) {
        guard let window = view.window else { return }
        let guideTopInWindow = view.convert(
            CGPoint(
                x: 0,
                y: view.keyboardLayoutGuide.layoutFrame.minY
            ),
            to: window
        ).y
        let kbText = keyboardTopInWindow.map {
            String(format: "%.1f", $0)
        } ?? "nil"
        ChatDiagTrace.record(
            "原生面 §302 [\(event)] kbTopWin=\(kbText) "
                + "guideTopWin="
                + String(format: "%.1f", guideTopInWindow)
        )
    }

    // MARK: 输入舱收编（R2／§302）

    /// 舱内容喂入（representable update 入口）：已
    /// 装配则原位换内容（rootView 替换、约束不
    /// 动）；未装配则记账待装载拍补装。nil＝本面
    /// 无舱（装配测试的裸列表形态），不装配
    func applyComposer(view newView: AnyView?) {
        pendingComposerView = newView
        guard isViewLoaded else { return }
        if newView == nil {
            if let host = composerHost {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
                composerHost = nil
            }
            return
        }
        installComposerIfNeeded()
        if let newView {
            composerHost?.rootView = newView
        }
    }

    /// 舱子托管装配：UIHostingController 收编为子
    /// 控制器（H2：safeAreaRegions 清零）；约束只
    /// 三条——左右贴本视图、底边恒钉自有位置引
    /// 导线 bottomGuide.topAnchor，高由内容固有
    /// 尺寸（舱栈自带定高口径）。键盘的一切运动
    /// （升起/候选条/交互消散）经通知帧顶常量逐
    /// 拍传到本约束（§302，见键盘跟随节），舱随
    /// 之同拍移动——本面不许有第二条键盘通道
    private func installComposerIfNeeded() {
        guard composerHost == nil,
              let content = pendingComposerView
        else { return }
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        // 台账 195：高由固有尺寸——与行托管（190
        // ④ ensureRowHost）同式补 sizingOptions。
        // 漏设时键盘稳态下内容生长（加引用/附件）
        // 无锚重解析事件捎带刷新、宿主帧不跟高、
        // 卡内容溢出宿主（实测：键盘态加引用卡长
        // 61 而舱高不变、输入行沉入键盘顶之下；
        // 静息态因回落重解析节流拍恒有布局活动而
        // 不显）。位置链（§194/§302）与静息入流
        // 约束（189）均不动、只补尺寸失效通道
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints =
            false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            host.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            host.view.bottomAnchor.constraint(
                equalTo: bottomGuide.topAnchor
            ),
        ])
        composerHost = host
        // 回底钮浮层恒在舱之上（装配序兜底）
        if let arrowHost {
            view.bringSubviewToFront(arrowHost.view)
        }
    }

    private func makeDataSource() {
        dataSource =
            UICollectionViewDiffableDataSource<Int, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, key in
                // §325：单渲染路径——全体行只有托管
                // cell 一种形态，内容 facet 只决定行
                // 内呈现（makeView 本体），不决定 cell
                // 类；reconfigure 恒同注册原地重配
                let cell = collectionView
                    .dequeueReusableCell(
                        withReuseIdentifier:
                            ChatNativeHostingCell.reuseID,
                        for: indexPath
                    ) as! ChatNativeHostingCell
                if let row = self?.rowsByKey[key] {
                    // 台账 190④：首次配置前装配持久
                    // 行托管（子控制器收编本控制器）
                    self?.ensureRowHost(for: cell)
                    cell.configure(with: row)
                }
                return cell
            }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // §302：本拍先做位置常量同步——窗口未解
        // 析（入窗前）或回落态（标签栏随呈现时序
        // 迟到）在此补解析、找到即退出回落；常量
        // 只读缓存的坞参照实帧/键盘存账帧顶（与
        // §194 布局拍纪律同式）。§302.1 续作：回
        // 落态重解析加节流——窗口变化立即走，否
        // 则距上次尝试 ≥0.3s 才走（回落壳内每拍
        // 全窗遍历扰动落定收敛，③⑯ 残差候选机制）；
        // 离散触发点（入窗/显形/键盘收起直调
        // resolveAnchors）不经此闸、行为不变
        if anchorWindow !== view.window {
            resolveAnchors()
        } else if dockIsFallback && !keyboardUp {
            let now = CACurrentMediaTime()
            if now - lastFallbackResolveAt >= 0.3 {
                lastFallbackResolveAt = now
                resolveAnchors()
            }
        } else if dockFlowConstraint?.isActive == true,
                  dockCapsuleView?.window !== view.window {
            // 台账 189：入流参照失效自愈（胶囊被
            // 换实例/移窗而离散触发未达）——节流
            // 重解析，与回落态自愈同式
            let now = CACurrentMediaTime()
            if now - lastCapsuleResolveAt >= 0.3 {
                lastCapsuleResolveAt = now
                resolveAnchors()
            }
        } else if !keyboardUp, dockBarView != nil,
                  dockCapsuleView == nil {
            // 台账 189：坞在场而胶囊未找到（首拍
            // 层级未定型/形态漂移）——同节流自愈
            // 重解析，胶囊一到即切入流；持续找不
            // 到即维持常量链回落（探针缺值留痕）
            let now = CACurrentMediaTime()
            if now - lastCapsuleResolveAt >= 0.3 {
                lastCapsuleResolveAt = now
                resolveAnchors()
            }
        }
        syncBottomConstant()
        // 台账 182：坏态三值同拍探针（常量同步后、
        // 本拍布局施工前采样——读的是上拍落定的舱
        // 帧与本拍常量/坞顶的同拍对照）
        sampleAnchorTriadIfDiverged()
        // 布局前先记在底事实（旧帧口径）：布局变化
        // （旋转/壳层帧变）后在底者钉底、不在底者不
        // 动——与 gen3 layoutContent 的位置保全同式
        let wasAtBottom = collectionView.bounds.height > 0
            && currentDistance() <= Self.atBottomTolerance
        collectionView.frame = view.bounds
        collectionView.layoutIfNeeded()
        refreshVisibleWindow()
        // §325.2 守卫 1：inset 施工（reconcileInsets
        // 与 measureBottomSpace）迁出布局拍——本拍
        // 只记账排落定拍，施工归落定拍在 pass 外合
        // 并执行（诊断守卫条目 1 点名本处）。键盘动
        // 画期本拍逐帧到达、落定拍在帧间逐拍合并落
        // 写，跟随链不断（§302 对账改走落定拍）
        scheduleSettle()
        // §438：键盘事务窗内钉底归事务块独占——布
        // 局拍以事务中途几何直设 offset 会打断事务
        // 插值（窗末落定拍收敛照旧）
        if (wasAtBottom || landingIntent || keyboardPinIntent)
            && !userInteracting
            && !keyboardTransactionInFlight {
            pinToBottom()
            // §302.3：布局拍只钉不消费意图——末钉
            // 之后集合视图内部布局拍仍可能迟到回调
            // offset（compositional 锚点保全，见落
            // 定拍注），消费判据须跨拍验几何稳定、
            // 统一归落定拍（performSettleBeat）
        }
        layoutArrow()
    }

    /// §366：抽屉运动窗在途（句柄记账的窗终点未
    /// 到）。信号源＝抽屉侧状态（ChatView 在
    /// router.drawerPresented 翻转时按弹簧
    /// response 写句柄），本面只读、不碰抽屉实现
    private var drawerMotionInFlight: Bool {
        guard let deadline = handle?.drawerMotionDeadline
        else { return false }
        return CACurrentMediaTime() < deadline
    }

    /// §366：抽屉运动窗剩余时长（唤醒拍自排用）
    private var drawerMotionRemaining: CFTimeInterval {
        max(
            0, (handle?.drawerMotionDeadline ?? 0)
                - CACurrentMediaTime()
        )
    }

    // MARK: 参数应用（representable update 入口）

    /// 快照施工单点（§374.2 起计数）：控制器内
    /// dataSource.apply 只许经本口——施工次数与
    /// 重配条目数入测试读口（高-only 不触发快
    /// 照/重配的断言据此），生产行为不变
    private func applySnapshot(
        _ snapshot:
            NSDiffableDataSourceSnapshot<Int, String>,
        reconfiguring reconfigureCount: Int = 0
    ) {
        snapshotApplyCount += 1
        reconfiguredItemCount += reconfigureCount
        dataSource.apply(
            snapshot, animatingDifferences: false
        )
    }

    /// 整表快照构建（旧路键集变分支与新路重建
    /// 路共用：序＝行序、重配键原位重构；结构随
    /// 布局构造分流——逐行构造＝一行一 section、
    /// 单 section 构造＝全体条目同入 section 0）
    private func rebuiltSnapshot(
        newKeys: [String],
        reconfigureKeys: [String]
    ) -> NSDiffableDataSourceSnapshot<Int, String> {
        var snapshot =
            NSDiffableDataSourceSnapshot<Int, String>()
        if layoutBox.singleSection {
            // 空行集不建 section（与逐行构造逐值
            // 一致：空集 contentSize 不含 section
            // inset；由空集长出走整笔重建路、增量
            // 条目编辑恒在非空集上发生）
            if !newKeys.isEmpty {
                snapshot.appendSections([0])
                snapshot.appendItems(
                    newKeys, toSection: 0
                )
            }
        } else {
            snapshot.appendSections(
                Array(newKeys.indices)
            )
            for (index, key) in newKeys.enumerated() {
                snapshot.appendItems(
                    [key], toSection: index
                )
            }
        }
        if !reconfigureKeys.isEmpty {
            snapshot.reconfigureItems(reconfigureKeys)
        }
        return snapshot
    }

    /// 喂入冻结判据（§329 滚动闸＋§335 浏览态
    /// 旗标＋§366 抽屉运动窗——apply 与 apply-
    /// Changes 共用）：nil＝未冻结可直落；drawer
    /// ＝仅抽屉窗冻结（无滚动回调可等、须自排
    /// 唤醒拍）；scroll＝滚动/浏览冻结（停滚回
    /// 调合并落写）
    private enum FeedFreeze {
        case scroll
        case drawer
    }

    private func currentFeedFreeze() -> FeedFreeze? {
        // §374.6：抽屉冻结缺省已删——删后抽屉运
        // 动窗不再入冻结判据（动画期喂入直落）；
        // 回退开关置假才恢复 §366 抽屉冻结（冻结
        // 本体以开关包裹保留）。滚动判据逐字不动
        // （步骤 4④ 领地）
        let drawerFrozen = drawerFreezeDropped()
            ? false
            : drawerMotionInFlight
        let scrollFrozen = userBrowsing
            || collectionView.isTracking
            || collectionView.isDecelerating
        if drawerFrozen && !scrollFrozen {
            return .drawer
        }
        if scrollFrozen || drawerFrozen {
            return .scroll
        }
        return nil
    }

    /// 冻结喂入入槽（apply 与 applyChanges 共
    /// 用）：后到覆盖先到（与 representable 只
    /// 认最新喂入同义）；新路在途换笔时变更集
    /// 先合成再入槽——两笔皆新路才合成，任一
    /// 笔旧路（changeSet 为 nil）即整槽回旧路
    /// （rows 全量在槽、旧路恒正确）。冻结记账
    /// 与抽屉唤醒拍同旧路 apply 原纪律
    private func storePendingFeed(
        _ pending: PendingApply, freeze: FeedFreeze
    ) {
        var pending = pending
        if let existing = pendingApply {
            if let existingSet = existing.changeSet,
               let newSet = pending.changeSet {
                pending.changeSet =
                    existingSet.composing(newSet)
            } else {
                pending.changeSet = nil
            }
        }
        pendingApply = pending
        switch freeze {
        case .drawer:
            settleDeferredDuringDrawer = true
            scheduleSettle(
                delay: drawerMotionRemaining + 0.02
            )
        case .scroll:
            settleDeferredDuringScroll = true
        }
    }

    /// 落定拍消费冻结槽的派发口：新路槽走
    /// applyChangesNow、旧路槽走 applyNow——槽
    /// 内 changeSet 有无即路别，在途换笔/开关
    /// 翻转不串路
    private func applyPendingFeed(
        _ pending: PendingApply
    ) {
        if let changeSet = pending.changeSet {
            applyChangesNow(
                rows: pending.rows,
                changeSet: changeSet,
                layout: pending.layout,
                topInset: pending.topInset,
                bottomMargin: pending.bottomMargin,
                composerView: pending.composerView,
                arrowView: pending.arrowView
            )
        } else {
            applyNow(
                rows: pending.rows,
                layout: pending.layout,
                topInset: pending.topInset,
                bottomMargin: pending.bottomMargin,
                composerView: pending.composerView,
                arrowView: pending.arrowView
            )
        }
    }

    /// 布局参数同步进匣（applyNow 与 apply-
    /// ChangesNow 共用）：间距/内边距任一变即
    /// 记账、失效施工归落定拍（§325.2 守卫集：
    /// invalidateLayout 不许在喂入同步链内执
    /// 行——2026-11-17 .66 真机崩溃链〈compo-
    /// sitional 在可见 cell 更新 pass 内自我
    /// invalidate 自递归至 UIKit 断言〉的防线
    /// 之一；§325 起 .estimated 占位是固定常
    /// 量、不入本对账）。返回是否变更
    private func syncLayoutParams(
        _ layout: ChatNativeLayout
    ) -> Bool {
        var paramsChanged = false
        if layoutBox.horizontalPadding
            != layout.horizontalPadding
            || layoutBox.topPadding != layout.topPadding
            || layoutBox.bottomPadding
                != layout.bottomPadding
            || layoutBox.rowSpacing != layout.rowSpacing {
            layoutBox.horizontalPadding =
                layout.horizontalPadding
            layoutBox.topPadding = layout.topPadding
            layoutBox.bottomPadding =
                layout.bottomPadding
            layoutBox.rowSpacing = layout.rowSpacing
            paramsChanged = true
        }
        layoutParams = layout
        if paramsChanged {
            pendingLayoutInvalidation = true
            // §366：参数变＝全几何变，紧急记账
            // 同置——落定拍见此账绕时间窗立即施工
            pendingLayoutInvalidationUrgent = true
        }
        return paramsChanged
    }

    /// §374.3：单 section 期望模式（测试覆盖口
    /// 优先、生产认全局开关）
    private func desiredSingleSection() -> Bool {
        testSingleSectionOverride
            ?? ChatListSingleSectionFeature.isEnabled()
    }

    /// §374.4：时间窗合并是否已删（测试覆盖口优
    /// 先、生产认 Core 开关；开关缺省＝已删）
    private func coalesceWindowDropped() -> Bool {
        testCoalesceWindowDropOverride
            ?? ChatListCoalesceWindowDropFeature
                .isEnabled()
    }

    /// §374.5：停滚结清是否单拍结清（测试覆盖口
    /// 优先、生产认 Core 开关；开关缺省＝单拍结
    /// 清，置假恢复 §366 拆拍）
    private func settleSingleBeat() -> Bool {
        testSettleSingleBeatOverride
            ?? ChatListSettleSingleBeatFeature
                .isEnabled()
    }

    /// §374.6：抽屉动画期冻结是否已删（测试覆盖口优
    /// 先、生产认 Core 开关；开关缺省＝已删）
    private func drawerFreezeDropped() -> Bool {
        testDrawerFreezeDropOverride
            ?? ChatListDrawerFreezeDropFeature
                .isEnabled()
    }

    /// §374.7：滚动闸是否已降级为过渡记账规则
    /// （测试覆盖口优先、生产认 Core 开关；开关
    /// 缺省＝已降级，置假恢复现行滚动闸）
    private func scrollLedgerDowngraded() -> Bool {
        testScrollLedgerOverride
            ?? ChatListScrollLedgerFeature
                .isEnabled()
    }

    /// §374.8：选区单键暂缓是否在场（测试覆盖口
    /// 优先、生产认 Core 开关；开关缺省＝在场，
    /// 置假＝暂缓停用、全部变更直达——应急档，
    /// 见 DESIGN §374.8 回退口径）
    private func selectionKeyGuardEnabled() -> Bool {
        testSelectionKeyGuardOverride
            ?? ChatListSelectionKeyGuardFeature
                .isEnabled()
    }

    /// §374.3：单 section 模式同步（applyNow／
    /// applyChangesNow 入口）：期望模式与匣内构
    /// 造旗不符即翻转——快照结构随构造同变，本
    /// 笔须整笔重建（调用方据返回值分流）；布局
    /// 失效只记账（紧急级与参数变同级）、施工仍
    /// 归落定拍唯一施工口（结构钉测把守：apply
    /// 同步链内不许执行 invalidateLayout）。返
    /// 回是否翻转
    @discardableResult
    private func refreshSingleSectionMode() -> Bool {
        let enabled = desiredSingleSection()
        guard enabled != layoutBox.singleSection
        else { return false }
        layoutBox.singleSection = enabled
        pendingLayoutInvalidation = true
        pendingLayoutInvalidationUrgent = true
        return true
    }

    /// 高度账整笔落写（§374.3，applyNow 与重建
    /// 路共用）：按键建账＋行序换现值；失效判据
    /// 只认高谱——临界标记变而高未变不单独触发
    /// 布局失效（台账 190②：标记只供提供者问高
    /// 时消费，落定拍布局 pass 自会读到）。返回
    /// 高谱是否变更
    private func writeHeightLedgerFull(
        rows newRows: [ChatNativeRow],
        mergedHeights: [CGFloat],
        mergedFlags: [Bool]
    ) -> Bool {
        var ledger: [String: ChatNativeLayoutBox
            .HeightEntry] = [:]
        ledger.reserveCapacity(newRows.count)
        for (index, row) in newRows.enumerated() {
            ledger[row.key] =
                ChatNativeLayoutBox.HeightEntry(
                    revision: row.revision,
                    height: mergedHeights[index],
                    provisional: mergedFlags[index]
                )
        }
        let heightsChanged =
            layoutBox.orderedHeights != mergedHeights
        layoutBox.heightByKey = ledger
        layoutBox.rowOrder = newRows.map(\.key)
        if heightsChanged {
            pendingLayoutInvalidation = true
        }
        return heightsChanged
    }

    /// 回喂高合并（§329/§335，applyNow 与
    /// applyChangesNow 共用）：临界喂入而匣内
    /// 有同键同修订确高→以确高回填（值与标记
    /// 同步清零）；确定高喂入即入匣确高备忘
    private func mergedHeight(
        for row: ChatNativeRow
    ) -> (height: CGFloat, provisional: Bool) {
        if row.heightIsProvisional,
           let exact = layoutBox
                .exactHeightByKey[row.key],
           exact.revision == row.revision {
            return (exact.height, false)
        }
        if !row.heightIsProvisional {
            layoutBox.exactHeightByKey[row.key] = (
                revision: row.revision,
                height: row.height
            )
        }
        return (row.height, row.heightIsProvisional)
    }

    /// 喂入收尾（applyNow 与 applyChangesNow
    /// 共用）：inset 只记账（施工归落定拍在布
    /// 局落定后同拍执行；底侧恒由舱实测帧派生
    /// ——R2 起键盘动画不再经参数喂入，通知帧
    /// 顶常量逐拍驱动舱帧、布局拍逐帧对账
    /// inset，§302）＋舱/回底钮落写＋落定拍排程
    private func finishFeed(
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?,
        contentChanged: Bool,
        paramsChanged: Bool,
        heightsChanged: Bool
    ) {
        let insetChanged = fedTopInset != topInset
            || bottomMargin != newMargin
        bottomMargin = newMargin
        if insetChanged {
            fedTopInset = topInset
            measureBottomSpace()
            handle?.bottomInset =
                effectiveBottomInset
        }
        applyComposer(view: composerView)
        if contentChanged || insetChanged
            || paramsChanged || heightsChanged {
            scheduleSettle()
        }
        applyArrow(view: arrowView)
    }

    func apply(
        rows newRows: [ChatNativeRow],
        layout: ChatNativeLayout,
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?
    ) {
        // §329 滚动闸：滚动期（tracking/deceler-
        // ating）到达的喂入整笔只记账、不施工——
        // 与 §325.2 落定拍冻结共用同一记账（settle-
        // DeferredDuringScroll），停滚后由 flush-
        // DeferredSettle→落定拍先消费本槽再落写。
        // §374.7（步骤 4④）：滚动闸缺省已降级为
        // 过渡记账规则——本记账纪律不变（喂入单
        // 点入账、变更集在槽内合成），变的是
        // flush 点：停滚回调点当场应用、不再经
        // 结清阶段武装托付落定拍（见 flushDefe-
        // rredSettle）；回退形态下本注原路成立
        // 削 apply 在滚动中开启布局 pass 的触发面；
        // 非滚动期行为逐字不变（走 applyNow）
        // §335：冻结判据扩为浏览态∪旗标——delegate
        // 状态机覆盖离屏→减速开始的旗标空窗（见
        // userBrowsing 注），空窗内到达的喂入同走
        // 只记账不施工
        // §366：冻结判据再扩抽屉运动窗——动画在途
        // 时喂入同走只记账（落定拍在窗内亦冻结、窗
        // 末唤醒拍合并消费）；抽屉单独成因时滚动旗
        // 不置（那是滚动结束回调的账），改记抽屉旗
        // 并自排唤醒拍（本路无回调可等）
        // §374.2：冻结判据与入槽收口共用口
        // （currentFeedFreeze/storePendingFeed，
        // applyChanges 同路）——判据与记账纪律
        // 逐字不变
        if let freeze = currentFeedFreeze() {
            storePendingFeed(
                PendingApply(
                    rows: newRows, layout: layout,
                    topInset: topInset,
                    bottomMargin: newMargin,
                    composerView: composerView,
                    arrowView: arrowView,
                    changeSet: nil
                ),
                freeze: freeze
            )
            return
        }
        applyNow(
            rows: newRows, layout: layout,
            topInset: topInset, bottomMargin: newMargin,
            composerView: composerView,
            arrowView: arrowView
        )
    }

    private func applyNow(
        rows newRows: [ChatNativeRow],
        layout: ChatNativeLayout,
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?
    ) {
        // 布局参数同步进匣（§374.2 起收口共用口
        // syncLayoutParams——§325.2 守卫集与 .66
        // 崩溃链防线见共用口注）
        let paramsChanged = syncLayoutParams(layout)
        // §374.3：单 section 模式同步——翻转笔强
        // 制整表重建（快照结构随构造同变）
        let modeFlipped = refreshSingleSectionMode()

        let newByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0)
            }
        )
        let oldKeys = rows.map(\.key)
        let newKeys = newRows.map(\.key)
        // §325：重配对账只认修订值全量比较——同键
        // 行的渲染输入任一值变即 reconfigure 原位
        // 更新；单形态下 reconfigure 恒同注册、不
        // 再有跨形态翻转分流（§320.1 退役）
        let keysChanged = oldKeys != newKeys
            || modeFlipped
        let revisionMismatchKeys = newKeys.filter {
            revisionsByKey[$0] != nil
                && revisionsByKey[$0]
                    != newByKey[$0]?.revision
        }
        // §374.8 选区单键分流：候选＝修订差∪暂
        // 存留账（留账键的修订差已被上趟记账吃
        // 掉、只认本集补发）；逐键只读选区在场行
        // 键——命中者本拍不重配、暂存待选区清账
        // 回调唤醒 flush，其余照旧落写。高度-only
        // 变化不入候选（候选只由修订差与留账构
        // 成）、本就不触发重配——回归断言在装配
        // 测试钉住
        var candidateKeys = revisionMismatchKeys
        for key in selectionStagedReconfigureKeys
        where newByKey[key] != nil
            && !candidateKeys.contains(key) {
            candidateKeys.append(key)
        }
        let (reconfigureKeys, selectionStaged) =
            partitionSelectionStaged(candidateKeys)
        selectionStagedReconfigureKeys =
            selectionStaged
        let wasEmpty = rows.isEmpty
        rows = newRows
        rowsByKey = newByKey
        // §329：回喂高落写布局匣——须先于快照 apply
        // （apply 触发的布局 pass 即读新高）；高变
        // 而键/修订未变时（如展开态翻转、异步 facet
        // 到达），布局失效走既有记账、落定拍唯一
        // 施工口合并落写（§325.2 条目 1 同路）
        // §335：回喂高落写先过布局层确高备忘合并
        // ——确高喂入即入账；临界喂入若匣内有同键
        // 同修订确高，以确高回填本趟（值与标记同
        // 步：标记清零、提供者不再为本行付就地量
        // 测）；行集变时按新行集剪账（离集即失效）
        var mergedHeights: [CGFloat] = []
        var mergedFlags: [Bool] = []
        mergedHeights.reserveCapacity(newRows.count)
        mergedFlags.reserveCapacity(newRows.count)
        for row in newRows {
            let merged = mergedHeight(for: row)
            mergedHeights.append(merged.height)
            mergedFlags.append(merged.provisional)
        }
        if keysChanged {
            let keep = Set(newKeys)
            layoutBox.exactHeightByKey = layoutBox
                .exactHeightByKey.filter {
                    keep.contains($0.key)
                }
        }
        // 台账 190②：临界标记与行集同趟落写（标
        // 记变而高未变时——如上次高被量测坐实同
        // 值——不单独触发布局失效：匣内标记只供
        // 提供者问高时消费，落定拍布局 pass 自会
        // 读到）——§374.3 起标记随高度账按键同
        // 写、失效判据仍只认高谱（共用口 write-
        // HeightLedgerFull）
        let heightsChanged = writeHeightLedgerFull(
            rows: newRows,
            mergedHeights: mergedHeights,
            mergedFlags: mergedFlags
        )
        if keysChanged {
            applySnapshot(
                rebuiltSnapshot(
                    newKeys: newKeys,
                    reconfigureKeys: reconfigureKeys
                ),
                reconfiguring: reconfigureKeys.count
            )
            if wasEmpty && !newRows.isEmpty {
                // 冷开首装：落点意图置真，落定拍在真
                // 实布局后钉底（H6）；切线程的落位由
                // ChatView 恢复链经句柄命令驱动
                landingIntent = true
                landingIntentSince = CACurrentMediaTime()
                landingSettleContentSize = nil
            }
        } else if !reconfigureKeys.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(reconfigureKeys)
            applySnapshot(
                snapshot,
                reconfiguring: reconfigureKeys.count
            )
        }
        revisionsByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0.revision)
            }
        )

        // 收尾（§374.2 起收口共用口 finishFeed：
        // inset 记账/舱落写/排程/回底钮——§302 口
        // 径见共用口注）
        finishFeed(
            topInset: topInset,
            bottomMargin: newMargin,
            composerView: composerView,
            arrowView: arrowView,
            contentChanged: keysChanged
                || !reconfigureKeys.isEmpty,
            paramsChanged: paramsChanged,
            heightsChanged: heightsChanged
        )
    }

    // MARK: 增量喂入（§374 步骤 2：控制器去对账）

    /// 变更集喂入入口（representable 在开关
    /// chat.list.incremental 开时调用）：冻结判
    /// 据与旧路 apply 共用（滚动/浏览/抽屉窗在
    /// 途整笔入槽、变更集在槽内合成保全），未
    /// 冻结直落 applyChangesNow。旧路 apply 保
    /// 留作回退（开关关即整路回旧）
    func applyChanges(
        rows newRows: [ChatNativeRow],
        changeSet: EntryChangeSet,
        layout: ChatNativeLayout,
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?
    ) {
        if let freeze = currentFeedFreeze() {
            storePendingFeed(
                PendingApply(
                    rows: newRows, layout: layout,
                    topInset: topInset,
                    bottomMargin: newMargin,
                    composerView: composerView,
                    arrowView: arrowView,
                    changeSet: changeSet
                ),
                freeze: freeze
            )
            return
        }
        applyChangesNow(
            rows: newRows, changeSet: changeSet,
            layout: layout, topInset: topInset,
            bottomMargin: newMargin,
            composerView: composerView,
            arrowView: arrowView
        )
    }

    /// 变更集落写本体：只消费变更集——快照增量
    /// 编辑（插→新 section＋条目、删→删 sec-
    /// tion、更→原位重构）、高度账按变更键局部
    /// 落写、三账增量维护。本函数内不许出现整
    /// 表对账形态（结构钉测 ChatSwapStep2Struc-
    /// tureTests 把守）；整笔重建只许走 apply-
    /// ChangesFullRebuild（序变/整批替换/空态
    /// 冷开三情形）
    private func applyChangesNow(
        rows newRows: [ChatNativeRow],
        changeSet: EntryChangeSet,
        layout: ChatNativeLayout,
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?
    ) {
        let paramsChanged = syncLayoutParams(layout)
        // §374.3：单 section 模式翻转笔——快照结
        // 构随构造同变、整笔走重建路（稳态快路在
        // 翻转笔不成立）
        if refreshSingleSectionMode() {
            applyChangesFullRebuild(
                rows: newRows,
                newKeys: newRows.map(\.key),
                updateCandidates: Array(
                    changeSet.updated
                ),
                paramsChanged: paramsChanged,
                topInset: topInset,
                bottomMargin: newMargin,
                composerView: composerView,
                arrowView: arrowView
            )
            return
        }
        // 稳态快路：变更集全空（无编辑、无高变、
        // 无序变）——快照/高度账/修订账一律不碰，
        // 只走参数同步与收尾（§374.0 门②性质二：
        // 无变更重喂列表侧工作量趋近于零；暂存重
        // 配的落写归落定拍 flush 本职、不在本路）
        if changeSet.isEmpty
            && changeSet.heightChanged.isEmpty
            && !changeSet.orderChanged {
            finishFeed(
                topInset: topInset,
                bottomMargin: newMargin,
                composerView: composerView,
                arrowView: arrowView,
                contentChanged: false,
                paramsChanged: paramsChanged,
                heightsChanged: false
            )
            return
        }
        let wasEmpty = rows.isEmpty
        let newKeys = newRows.map(\.key)
        var newIndexByKey: [String: Int] = [:]
        for (index, key) in newKeys.enumerated() {
            newIndexByKey[key] = index
        }
        // 变更行查找：一次扫描只取变更键的新行
        // 值（行对象是重构/落写的内容真源）
        let wantedKeys = changeSet.inserted
            .union(changeSet.updated)
            .union(changeSet.heightChanged)
        var changedRowByKey: [String: ChatNativeRow] =
            [:]
        if !wantedKeys.isEmpty {
            for row in newRows
            where wantedKeys.contains(row.key) {
                changedRowByKey[row.key] = row
            }
        }
        // 在场校正（数据源 indexPath 哈希查、单
        // 键计量）：变更集相对追踪器基态、控制器
        // 基态可能漂移（换面重建/开关翻转/在途丢
        // 笔），逐键以在场事实校正——插已在场者
        // 改走重构、删不在场者忽略、更不在场者
        // 补插，校正后本笔自洽
        var effectiveInserted: Set<String> = []
        var effectiveDeleted: Set<String> = []
        var updateCandidates: [String] = []
        for key in changeSet.inserted {
            if dataSource.indexPath(for: key) != nil {
                updateCandidates.append(key)
            } else {
                effectiveInserted.insert(key)
            }
        }
        for key in changeSet.deleted {
            if dataSource.indexPath(for: key) != nil {
                effectiveDeleted.insert(key)
            }
        }
        for key in changeSet.updated {
            if dataSource.indexPath(for: key) != nil {
                updateCandidates.append(key)
            } else {
                effectiveInserted.insert(key)
            }
        }
        // 重建路判据：序变（增量编辑无移动语义）
        // ／空态冷开（整表构建与旧路同价、含冷
        // 开落点意图）／插删量及现行行数（整批
        // 替换——增量逐键编辑反贵于整表构建）
        if changeSet.orderChanged || wasEmpty
            || effectiveInserted.count
                + effectiveDeleted.count
                >= rows.count {
            applyChangesFullRebuild(
                rows: newRows, newKeys: newKeys,
                updateCandidates: updateCandidates,
                paramsChanged: paramsChanged,
                topInset: topInset,
                bottomMargin: newMargin,
                composerView: composerView,
                arrowView: arrowView
            )
            return
        }
        // §374.8 选区单键分流（与旧路同口径）：
        // 候选＝更新在场键∪暂存留账（留账键须仍
        // 在新行集），选区在场行暂存、余者直达
        var candidateKeys = updateCandidates
        for key in selectionStagedReconfigureKeys
        where newIndexByKey[key] != nil
            && !candidateKeys.contains(key) {
            candidateKeys.append(key)
        }
        let (readyKeys, selectionStaged) =
            partitionSelectionStaged(candidateKeys)
        selectionStagedReconfigureKeys =
            selectionStaged
        let reconfigureKeys = readyKeys.filter {
            dataSource.indexPath(for: $0) != nil
        }
        // 高度账局部落写（§374.3 按键账，代
        // §374.2 的平行四表索引手术）：删→按键
        // 出账＋行序摘除；插→按键入账＋行序按新
        // 序索引落位（续行相对序不变＋已插键在
        // 位，新索引即终位）；更新/高-only→按键
        // 原位写。确高备忘随删出账、随合并入账
        // （mergedHeight 本职）；失效判据只认高
        // 值变（临界标记变而高未变不单独触发，
        // 与整笔落写同口径）
        var heightsChanged = false
        for key in effectiveDeleted {
            if let index = layoutBox.rowOrder
                .firstIndex(of: key) {
                layoutBox.rowOrder.remove(at: index)
                heightsChanged = true
            }
            layoutBox.heightByKey[key] = nil
            layoutBox.exactHeightByKey[key] = nil
        }
        let orderedInserted = newKeys.filter {
            effectiveInserted.contains($0)
        }
        for key in orderedInserted {
            guard let row = changedRowByKey[key],
                  let index = newIndexByKey[key]
            else { continue }
            let merged = mergedHeight(for: row)
            layoutBox.rowOrder.insert(
                key, at: index
            )
            layoutBox.heightByKey[key] =
                ChatNativeLayoutBox.HeightEntry(
                    revision: row.revision,
                    height: merged.height,
                    provisional: merged.provisional
                )
            heightsChanged = true
        }
        for key in changeSet.updated
            .union(changeSet.heightChanged) {
            guard let row = changedRowByKey[key],
                  let existing = layoutBox
                    .heightByKey[key]
            else { continue }
            let merged = mergedHeight(for: row)
            if existing.height != merged.height {
                heightsChanged = true
            }
            layoutBox.heightByKey[key] =
                ChatNativeLayoutBox.HeightEntry(
                    revision: row.revision,
                    height: merged.height,
                    provisional: merged.provisional
                )
        }
        if heightsChanged {
            pendingLayoutInvalidation = true
        }
        // §413：三账落写先行于快照编辑——与旧路
        // applyNow 同序（彼处 rows/rowsByKey 先
        // 于 applySnapshot）。快照 apply 内会同
        // 步物化可见区新 cell、供应器当场读 rows-
        // ByKey，三账在后即落定行有高无内容且不
        // 自愈（0.50.102 真机主症状、钉测在案）
        // 三账增量维护：按键行/按键修订只动变更
        // 键（删出账、插/更/高-only 入现行值——
        // 高-only 修订未变、修订账不写）
        for key in effectiveDeleted {
            rowsByKey[key] = nil
            revisionsByKey[key] = nil
        }
        for (key, row) in changedRowByKey {
            rowsByKey[key] = row
            if changeSet.updated.contains(key)
                || effectiveInserted.contains(key) {
                revisionsByKey[key] = row.revision
            }
        }
        rows = newRows
        // 快照增量编辑（两构造分流）：单 sec-
        // tion 构造＝条目级编辑（删条目→锚定插
        // 条目→重构）；逐行 section 构造＝sec-
        // tion 级编辑（删 section→插 section＋
        // 条目→重构）。锚义两构造同：新序中最近
        // 的在场前行之后、无前行取最近在场后行
        // 之前、皆无则尾附。section 身份账只在
        // 逐行构造本笔有结构变更时构建（纯更新
        // 笔零构建、成本只随变更量）
        var didEditSnapshot = false
        if layoutBox.singleSection,
           !effectiveDeleted.isEmpty
            || !orderedInserted.isEmpty {
            var snapshot = dataSource.snapshot()
            if !effectiveDeleted.isEmpty {
                snapshot.deleteItems(
                    Array(effectiveDeleted)
                )
                didEditSnapshot = true
            }
            if !orderedInserted.isEmpty {
                var presentNow = Set(
                    snapshot.itemIdentifiers
                )
                for key in orderedInserted {
                    guard let index = newIndexByKey[key]
                    else { continue }
                    var placed = false
                    var probe = index - 1
                    while probe >= 0 && !placed {
                        if presentNow.contains(
                            newKeys[probe]
                        ) {
                            snapshot.insertItems(
                                [key],
                                afterItem: newKeys[probe]
                            )
                            placed = true
                        }
                        probe -= 1
                    }
                    if !placed {
                        probe = index + 1
                        while probe < newKeys.count
                            && !placed {
                            if presentNow.contains(
                                newKeys[probe]
                            ) {
                                snapshot.insertItems(
                                    [key],
                                    beforeItem:
                                        newKeys[probe]
                                )
                                placed = true
                            }
                            probe += 1
                        }
                    }
                    if !placed {
                        snapshot.appendItems(
                            [key], toSection: 0
                        )
                    }
                    presentNow.insert(key)
                    didEditSnapshot = true
                }
            }
            if !reconfigureKeys.isEmpty {
                snapshot.reconfigureItems(
                    reconfigureKeys
                )
            }
            // 落写前终核（与逐行构造路同口径）：
            // 件数与新行集不符（基态漂移超出逐键
            // 校正面）即整表重建兜底——计数读口
            // O(1)、不比对全集
            if snapshot.numberOfItems
                != newRows.count {
                snapshot = rebuiltSnapshot(
                    newKeys: newKeys,
                    reconfigureKeys: reconfigureKeys
                )
            }
            applySnapshot(
                snapshot,
                reconfiguring: reconfigureKeys.count
            )
        } else if !effectiveDeleted.isEmpty
            || !orderedInserted.isEmpty {
            var snapshot = dataSource.snapshot()
            var sectionIDByKey: [String: Int] = [:]
            for section in snapshot.sectionIdentifiers {
                for key in snapshot
                    .itemIdentifiers(inSection: section) {
                    sectionIDByKey[key] = section
                }
            }
            if !effectiveDeleted.isEmpty {
                let deleteIDs = Array(Set(
                    effectiveDeleted.compactMap {
                        sectionIDByKey[$0]
                    }
                ))
                if !deleteIDs.isEmpty {
                    snapshot.deleteSections(deleteIDs)
                    didEditSnapshot = true
                }
            }
            if !orderedInserted.isEmpty {
                var nextID =
                    (snapshot.sectionIdentifiers.max()
                        ?? -1) + 1
                for key in orderedInserted {
                    guard let index = newIndexByKey[key]
                    else { continue }
                    let newID = nextID
                    nextID += 1
                    var placed = false
                    var probe = index - 1
                    while probe >= 0 && !placed {
                        if let anchor = sectionIDByKey[
                            newKeys[probe]
                        ] {
                            snapshot.insertSections(
                                [newID],
                                afterSection: anchor
                            )
                            placed = true
                        }
                        probe -= 1
                    }
                    if !placed {
                        probe = index + 1
                        while probe < newKeys.count
                            && !placed {
                            if let anchor =
                                sectionIDByKey[
                                    newKeys[probe]
                                ] {
                                snapshot.insertSections(
                                    [newID],
                                    beforeSection: anchor
                                )
                                placed = true
                            }
                            probe += 1
                        }
                    }
                    if !placed {
                        snapshot.appendSections([newID])
                    }
                    snapshot.appendItems(
                        [key], toSection: newID
                    )
                    sectionIDByKey[key] = newID
                    didEditSnapshot = true
                }
            }
            if !reconfigureKeys.isEmpty {
                snapshot.reconfigureItems(
                    reconfigureKeys
                )
            }
            // 落写前终核：件数与新行集不符（基态
            // 漂移超出逐键校正面）即整表重建兜底
            // ——计数读口 O(1)、不比对全集
            if snapshot.numberOfItems
                != newRows.count {
                snapshot = rebuiltSnapshot(
                    newKeys: newKeys,
                    reconfigureKeys: reconfigureKeys
                )
            }
            applySnapshot(
                snapshot,
                reconfiguring: reconfigureKeys.count
            )
        } else if !reconfigureKeys.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(reconfigureKeys)
            applySnapshot(
                snapshot,
                reconfiguring: reconfigureKeys.count
            )
        }
        finishFeed(
            topInset: topInset,
            bottomMargin: newMargin,
            composerView: composerView,
            arrowView: arrowView,
            contentChanged: didEditSnapshot
                || !reconfigureKeys.isEmpty,
            paramsChanged: paramsChanged,
            heightsChanged: heightsChanged
        )
    }

    /// 变更集重建路（§374.2）：序变／空态冷开
    /// ／整批替换三情形的整笔落写——高度合并与
    /// 快照构建与旧路 applyNow 同法（整表构建
    /// 在本路是正解、非对账），三账按新行集整
    /// 批换现值（整批替换时变更面即全集、与整
    /// 表构建同价）
    private func applyChangesFullRebuild(
        rows newRows: [ChatNativeRow],
        newKeys: [String],
        updateCandidates: [String],
        paramsChanged: Bool,
        topInset: CGFloat,
        bottomMargin newMargin: CGFloat,
        composerView: AnyView?,
        arrowView: AnyView?
    ) {
        let wasEmpty = rows.isEmpty
        // §374.8 分流同旧路：候选＝更新∪留账
        // （留账键须仍在新行集），选区在场行暂存
        var candidateKeys = updateCandidates
        for key in selectionStagedReconfigureKeys
        where newKeys.contains(key)
            && !candidateKeys.contains(key) {
            candidateKeys.append(key)
        }
        let (reconfigureKeys, selectionStaged) =
            partitionSelectionStaged(candidateKeys)
        selectionStagedReconfigureKeys =
            selectionStaged
        // 高度合并（旧路同法：确高备忘回填＋入
        // 账＋离集剪账）
        var mergedHeights: [CGFloat] = []
        var mergedFlags: [Bool] = []
        mergedHeights.reserveCapacity(newRows.count)
        mergedFlags.reserveCapacity(newRows.count)
        for row in newRows {
            let merged = mergedHeight(for: row)
            mergedHeights.append(merged.height)
            mergedFlags.append(merged.provisional)
        }
        let keep = Set(newKeys)
        layoutBox.exactHeightByKey = layoutBox
            .exactHeightByKey.filter {
                keep.contains($0.key)
            }
        let heightsChanged = writeHeightLedgerFull(
            rows: newRows,
            mergedHeights: mergedHeights,
            mergedFlags: mergedFlags
        )
        // §413：三账先行于快照落写（与旧路同序、
        // 与增量段同不变量）——重建路快照 apply
        // 内同步物化的 cell 同读 rowsByKey，短会
        // 话落定走本路实测同病（钉测在案）
        rowsByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0)
            }
        )
        revisionsByKey = Dictionary(
            uniqueKeysWithValues: newRows.map {
                ($0.key, $0.revision)
            }
        )
        rows = newRows
        applySnapshot(
            rebuiltSnapshot(
                newKeys: newKeys,
                reconfigureKeys: reconfigureKeys
            ),
            reconfiguring: reconfigureKeys.count
        )
        if wasEmpty && !newRows.isEmpty {
            // 冷开首装：落点意图置真，落定拍在真
            // 实布局后钉底（H6，与旧路同口径）
            landingIntent = true
            landingIntentSince = CACurrentMediaTime()
            landingSettleContentSize = nil
        }
        finishFeed(
            topInset: topInset,
            bottomMargin: newMargin,
            composerView: composerView,
            arrowView: arrowView,
            contentChanged: true,
            paramsChanged: paramsChanged,
            heightsChanged: heightsChanged
        )
    }

    /// §374.8 选区单键分流：候选键逐个只读选区
    /// 在场行键（句柄 selectionActiveRowKey）——
    /// 命中者暂存（留账待清账回调唤醒后由 flush
    /// 复读本分流自然放行）、余者本拍落写。分流
    /// 不读 cell、不认触摸生命周期、无任何定时
    /// 续排（§332 触摸序列门的任意行暂存＋0.3s
    /// 续排已随门退役，见 DESIGN §374.8）；暂缓
    /// 开关关时全员直达（应急档）
    private func partitionSelectionStaged(
        _ candidates: [String]
    ) -> (ready: [String], staged: Set<String>) {
        guard selectionKeyGuardEnabled() else {
            return (candidates, [])
        }
        var ready: [String] = []
        var staged: Set<String> = []
        let selectionKey = handle?.selectionActiveRowKey
        for key in candidates {
            if key == selectionKey {
                staged.insert(key)
            } else {
                ready.append(key)
            }
        }
        return (ready, staged)
    }

    /// 选区保护结束（句柄转达）：有暂存即排一拍
    /// flush——分流复读时选区键已清、暂存自然放行
    func selectionProtectionEnded() {
        if !selectionStagedReconfigureKeys.isEmpty {
            scheduleSettle()
        }
    }

    /// §374.8 暂存重配的落写口（落定拍在整笔喂
    /// 入消费后调用）：留账键逐个复读分流，选区
    /// 已清账者以现行快照 reconfigure 落写
    /// （cell 供应器读 rowsByKey 现行行＝补发按
    /// 当前行值重算该行）；仍在场者留账——不续
    /// 排任何定时拍，只等清账回调唤醒（选区可
    /// 停留任意久，不许陪跑定时器）
    private func flushSelectionStagedReconfigures() {
        guard !selectionStagedReconfigureKeys.isEmpty
        else { return }
        let present = selectionStagedReconfigureKeys
            .filter { rowsByKey[$0] != nil }
        let (ready, staged) =
            partitionSelectionStaged(Array(present))
        selectionStagedReconfigureKeys = staged
        let snapshotItems = Set(
            dataSource.snapshot().itemIdentifiers
        )
        let applicable = ready.filter {
            snapshotItems.contains($0)
        }
        if !applicable.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(applicable)
            applySnapshot(
                snapshot, reconfiguring: applicable.count
            )
        }
    }

    // MARK: 落定拍（§259 合并调度，与 gen3 同式）

    private func scheduleSettle(delay: TimeInterval = 0) {
        guard !settleScheduled else { return }
        settleScheduled = true
        let work = { [weak self] in
            guard let self else { return }
            settleScheduled = false
            performSettleBeat()
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay, execute: work
            )
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// 落定拍本体：布局落定→量实测→inset 施工→落
    /// 位（恢复优先于落点意图）→读数产出。布局期
    /// 与滚动回调内一律不进（只记账排拍）
    private func performSettleBeat() {
        guard collectionView.bounds.width > 0
        else { return }
        if userBrowsing
            || collectionView.isTracking
            || collectionView.isDecelerating {
            // §325.2 守卫 2③＋4：滚动期冻结——本拍
            // 只记账（report 轻量读数照常产出）、不
            // 施工：不写 inset、不钉底、不消费布局失
            // 效记账；滚动结束回调（didEndDrag 不减
            // 速／didEndDecelerating）一次性合并落写。
            // 手势中不改视口几何（诊断守卫口径）
            settleDeferredDuringScroll = true
            report()
            return
        }
        if !drawerFreezeDropped()
            && drawerMotionInFlight {
            // §366：抽屉动画期冻结（§325.2 条目 2③
            // 的同族扩展）——本拍只记账＋report、不
            // 施工，窗末自排唤醒拍合并落写：动画窗
            // 内不付布局／量测／落位账（调研问题一
            // 拟修法 3 的聊天侧落点）
            // §374.6：本冻结缺省已删（判定在条件首
            // 位）——删后本分支不达、落定拍照常走
            // 全链；回退开关置假才恢复本冻结
            settleDeferredDuringDrawer = true
            scheduleSettle(
                delay: drawerMotionRemaining + 0.02
            )
            report()
            return
        }
        if keyboardTransactionInFlight {
            if CACurrentMediaTime()
                <= keyboardTransactionDeadline {
                // §438：键盘事务窗冻结——窗内 inset
                // 施工/钉底由事务块同事务应用独占，
                // 本拍只记账＋report、不施工（与滚动/
                // 抽屉冻结同式）；窗末 completion 唤
                // 醒一拍合并落写。防异步拍以事务中途
                // 的瞬态几何（派生顶 inset 瞬态读数
                // 等）抢写、与事务动画打架（合后
                // +149px 竞速族的封口）
                settleDeferredDuringKeyboard = true
                report()
                return
            }
            // completion 丢失自愈（与抽屉 deadline
            // 同式）：过期即收窗、本拍按全链施工
            keyboardTransactionInFlight = false
            settleDeferredDuringKeyboard = false
        }
        // §366：抽屉窗末唤醒拍认领（本拍绕时间窗合
        // 并立即施工——冻结账已等满一窗、不许再攒）
        let drawerWakeBeat = settleDeferredDuringDrawer
        settleDeferredDuringDrawer = false
        if settleClearingStage == 1 {
            // §366 拆拍·数据拍：先武装布局拍再落数
            // 据——applyNow 内的 scheduleSettle 被已
            // 武装的调度旗守住、不会抢先成拍；本拍
            // 只落数据（整笔喂入＋暂存重配），布局
            // 冲刷／量测／落位全顺延布局拍，停指第
            // 一拍不再叠满全账（调研 C2）
            settleClearingStage = 2
            scheduleSettle(
                delay: Self.settleSplitBeatDelay
            )
            if let pending = pendingApply {
                pendingApply = nil
                // §374.2：槽内路别派发（新路槽走
                // applyChangesNow、旧路槽 applyNow）
                applyPendingFeed(pending)
            }
            flushSelectionStagedReconfigures()
            report()
            return
        }
        // §366 拆拍·布局拍（阶段 2）认领：本拍走余
        // 下全链且绕时间窗（结清账不许再攒窗）
        let clearingLayoutBeat =
            settleClearingStage == 2
        if clearingLayoutBeat {
            settleClearingStage = 0
        }
        if let pending = pendingApply {
            // §329：滚动闸记账的消费口——停滚后第
            // 一拍先落写整笔喂入（其引发的布局失效
            // 记账由紧随的既有合并口同拍消费），再
            // 走本拍余下链（量测/inset/落位）
            // §374.2：槽内路别派发（applyPendingFeed）
            pendingApply = nil
            applyPendingFeed(pending)
        }
        // §374.8：选区暂存重配的落写——须在整笔
        // 喂入消费之后（行集已是最新），布局失效
        // 施工之前（重配引发的布局需求由紧随的合
        // 并口同拍消费）
        flushSelectionStagedReconfigures()
        if pendingLayoutInvalidation {
            // §325.2：布局失效的唯一施工口——落定拍
            // 在布局 pass 外合并执行一次，随后
            // layoutIfNeeded 冲刷收敛。§366 时间窗合
            // 并：行高类失效在同窗内只记账、攒到窗末
            // 一拍施工（定向失效实证不成立的退路，
            // §366.1）；紧急账（参数变）／结清布局拍
            // ／抽屉唤醒拍绕窗立即施工。§374.4（步
            // 骤 4①）：时间窗合并缺省已删——删窗判
            // 定为真时下行窗闸条件恒真、见账即施工、
            // 攒拍分支不达，行高采纳归发布闸节拍；
            // 回退开关置假才恢复本窗闸（窗代码以开
            // 关包裹保留一个版本周期）
            let now = CACurrentMediaTime()
            let bypassWindow =
                pendingLayoutInvalidationUrgent
                || clearingLayoutBeat || drawerWakeBeat
            if coalesceWindowDropped()
                || bypassWindow
                || now - lastLayoutFlushAt
                    >= Self.layoutCoalesceWindow {
                pendingLayoutInvalidation = false
                pendingLayoutInvalidationUrgent = false
                lastLayoutFlushAt = now
                settleLayoutFlushCount += 1
                collectionView.collectionViewLayout
                    .invalidateLayout()
            } else {
                // 攒拍：记账保留、自排窗末一拍合并
                // 施工（其间再有记账同归本账）
                scheduleSettle(
                    delay: Self.layoutCoalesceWindow
                        - (now - lastLayoutFlushAt)
                )
            }
        }
        collectionView.layoutIfNeeded()
        measureBottomSpace()
        reconcileInsets()
        var didRestoreAnchor = false
        if let anchor = pendingAnchor {
            pendingAnchor = nil
            executeRestore(anchor)
            didRestoreAnchor = true
        } else if landingIntent && !userInteracting {
            let prePinDistance = currentDistance()
            pinToBottom()
            let csNow = collectionView.contentSize.height
            // §413：消费加一位闸——直播占位行在
            // 席（本轮未落定）时不许消费：占位行
            // 恒高使 contentSize 在生成期逐值稳
            // 定、与「落定后稳定」在判据上不可
            // 分，提前消费会吃掉落定增长拍的钉
            // 底承接（探针实测终距恰＝净增长）；
            // 占位离席后判据照旧，在席期间本拍
            // 钉底照常执行
            if prePinDistance <= Self.atBottomTolerance
                && currentDistance() <= Self.atBottomTolerance
                && landingSettleContentSize == csNow
                && !rows.contains(
                    where: { $0.key == "live-placeholder" }
                ) {
                // §302.3 消费判据＝上一钉熬过整拍：
                // 本拍开口（布局冲刷后、钉前）已在
                // 底＋钉后仍在底＋contentSize 与上一
                // 落定拍逐值同，才许消费意图。定因
                // （§302.3 量测）：落定链可达算术
                // max 且落点稳定（直设 3352 三读不
                // 动），残差是末钉之后集合视图内部
                // 布局拍迟到回调 offset（composi-
                // tional 锚点保全、R1 期 ≤2pt 残差
                // 同族；回调量随收敛几何走 3.3–4）——
                // 回调在本拍开口布局落地即现形于
                // prePinDistance、不许消费，须由后
                // 续拍重钉且整拍无回调才收口
                landingIntent = false
                landingSettleContentSize = nil
            } else if CACurrentMediaTime()
                - landingIntentSince < 2.0 {
                // 收敛尾差（H6）：意图存续期内延迟
                // 重拍（与 gen3 §259 落定拍的
                // asyncAfter 同式）——真实迟到修正
                // （如图片落图改行高）落地后重钉、收
                // 敛即停；预算按时间窗不按次数。2 秒
                // 窗外仍未收敛则停拍、残差由现测读数
                // 如实呈报不假装在底
                landingSettleContentSize = csNow
                scheduleSettle(delay: 0.05)
            } else {
                landingSettleContentSize = nil
            }
        }
        // §426（缺陷三）：键盘事务钉底——意图在事
        // 务开始前已捕获（setKeyboardUp），本拍几
        // 何（量测留位＋inset 施工）已落定，按派生
        // 标尺直钉终值；锚恢复拍不叠钉（恢复优先
        // 级不变）。事务中逐拍重钉＝末行恒贴舱顶、
        // 不被动画中的舱盖住/压扁（用户视频 f011
        // 的缝状卡即无钉时舱滑过尾行所致）
        if keyboardPinIntent, !userInteracting,
           !didRestoreAnchor {
            pinToBottom()
        }
        stepSearchFocus()
        layoutArrow()
        report()
    }

    /// 搜索落点的一拍（台账 150）：量目标行屏上位
    /// 置喂收敛机——停稳/预算尽即收官，仍漂移则再
    /// 滚一次；目标行已不在行集（切线程/数据变）
    /// 即弃（OB 同口径：失败保留现位置、聊天照常）
    private func stepSearchFocus() {
        guard focusConvergence.isActive,
              let targetID = focusTargetID
        else { return }
        guard let index = rows.firstIndex(
            where: { $0.entryID == targetID }
        ),
              let attrs = collectionView
                .layoutAttributesForItem(
                    at: indexPath(forRow: index)
                )
        else {
            focusConvergence.abort()
            focusTargetID = nil
            return
        }
        let shown = attrs.frame.minY
            - collectionView.contentOffset.y
        switch focusConvergence.evaluate(
            shownPosition: shown
        ) {
        case .scrollAgain:
            performFocusScroll()
        case .converged, .exhausted:
            focusTargetID = nil
        }
    }

    /// 搜索落点的一次滚动：目标行顶停到顶留位下
    /// 方 topGap 处（Core 常量），无动画直达（收敛
    /// 靠多拍校正、不靠动画掩盖漂移，OB 同式）
    private func performFocusScroll() {
        guard let targetID = focusTargetID,
              let index = rows.firstIndex(
                  where: { $0.entryID == targetID }
              )
        else { return }
        collectionView.layoutIfNeeded()
        guard let attrs = collectionView
            .layoutAttributesForItem(
                at: indexPath(forRow: index)
            )
        else { return }
        let target = min(
            max(
                attrs.frame.minY
                    - collectionView.contentInset.top
                    - SearchFocusConvergence.topGap,
                -collectionView.contentInset.top
            ),
            maxOffsetY()
        )
        collectionView.setContentOffset(
            CGPoint(x: 0, y: target), animated: false
        )
        scheduleSettle()
    }

    /// 实测对账（inset 唯一施工口，R2 收口）：每
    /// 拍把已应用 inset 拉回当拍实测恒等值——顶＝
    /// 喂入值＋短内容派生量、底＝舱实测留位＋单点
    /// 边距，施工值与量测一旦分叉即如实显形。R1
    /// 期另有「键盘动画参数驱动的施工」一路（con-
    /// structInsets），R2 起键盘运动经引导线逐帧
    /// 成本拍布局变化、对账逐帧跟进即同拍——动画
    /// 参数喂入与施工动画一并退役
    private func reconcileInsets() {
        let targetTop = fedTopInset + derivedTopInset()
        let targetBottom = effectiveBottomInset
        var inset = collectionView.contentInset
        var changed = false
        if abs(inset.top - targetTop) > 0.5 {
            inset.top = targetTop
            changed = true
        }
        if abs(inset.bottom - targetBottom) > 0.5 {
            inset.bottom = targetBottom
            changed = true
        }
        if changed {
            collectionView.contentInset = inset
            collectionView
                .verticalScrollIndicatorInsets = inset
            handle?.bottomInset = targetBottom
        }
    }

    /// 短内容派生顶 inset（H3）：内容高＜有效视口
    /// 高（帧高−顶 inset 喂入−底 inset）时差额整笔
    /// 作顶 inset——末行底在静止位恰落舱顶上 24
    /// （底 section 边距 spacingS＋单点边距
    /// spacingM）；只吃系统实测 contentSize，随内
    /// 容/落座每拍重算、一处记账。长内容恒 0
    private func derivedTopInset() -> CGFloat {
        let bounds = collectionView.bounds
        guard bounds.height > 0 else { return 0 }
        let effectiveViewport = bounds.height
            - fedTopInset - effectiveBottomInset
        return max(
            0, effectiveViewport
                - collectionView.contentSize.height
        )
    }

    // MARK: 几何读数（全部现测，H7）

    /// 实测留位量测（§263 同式、量测对象换代）：
    /// 帧底由本视图 convert 实帧、舱顶由舱子托管
    /// 的实帧 convert——两实测同在窗口系相减。R1
    /// 期舱在 ChatView 的 overlay 里、舱顶经绑定喂
    /// 入；R2 舱收编入本容器后量测不出容器、喂入
    /// 链退役（H8 的派生单源）
    private func measureBottomSpace() {
        guard let window = view.window,
              let host = composerHost
        else { return }
        let frameInWindow = view.convert(
            view.bounds, to: window
        )
        let hostInWindow = host.view.convert(
            host.view.bounds, to: window
        )
        measuredBottomSpace = max(
            0, frameInWindow.maxY - hostInWindow.minY
        )
    }

    private var effectiveBottomSpace: CGFloat {
        measuredBottomSpace ?? 0
    }

    private var effectiveBottomInset: CGFloat {
        effectiveBottomSpace + bottomMargin
    }
    /// 在底判定容差（修复包二 §3，键盘阈值收敛）：
    /// 距底读数 <= 本值即判「在底」。原为三处判定
    /// 点各自硬编码 0.5pt——比读数噪声底还窄（con-
    /// tentSize 量化＋回弹余量为数 pt 级），48pt 定
    /// 档依据：显著大于噪声底、约一个点达目标量级
    /// （44pt）＋一行短消息高、= 2 × 行距单律 24pt、
    /// 约一屏高 7% 不误判看历史。判定点（布局拍
    /// wasAtBottom／落定拍 landingIntent 消费判据／
    /// captureAnchor 钉底判据）只许引本常量；改值
    /// 须与 Q9 钉测（47pt 必抬／96pt 必不抬）同批
    /// 改。本常量只定「在底事实」的宽度，不涉意图
    /// 的置位与消费时机。
    static let atBottomTolerance: CGFloat = 48


    /// 距底读数：以 effectiveBottomInset（实测派
    /// 生）为标尺（与 gen3 §263 同式，不读 adjusted
    /// 自证）；决策时刻现算（H7）
    private func currentDistance() -> CGFloat {
        CGFloat(
            ChatScrollSupply.uiKitDistance(
                contentHeight: Double(
                    collectionView.contentSize.height
                ),
                offsetY: Double(
                    collectionView.contentOffset.y
                ),
                viewportHeight: Double(
                    collectionView.bounds.height
                ),
                bottomInset: Double(effectiveBottomInset)
            )
        )
    }

    private func maxOffsetY() -> CGFloat {
        max(
            -collectionView.contentInset.top,
            collectionView.contentSize.height
                + effectiveBottomInset
                - collectionView.bounds.height
        )
    }

    private func pinToBottom() {
        collectionView.contentOffset = CGPoint(
            x: 0, y: maxOffsetY()
        )
    }

    private func report() {
        guard let handle,
              collectionView.bounds.height > 0
        else { return }
        handle.latestDistance = currentDistance()
        handle.containerHeight =
            collectionView.bounds.height
        handle.bottomInset = effectiveBottomInset
        // 末端事实：末 item 布局帧完整落在有效视口
        // 内（帧出布局属性实测、不经 contentSize 反
        // 推末行位置）
        if !rows.isEmpty,
           let attrs = collectionView
               .layoutAttributesForItem(
                   at: indexPath(forRow: rows.count - 1)
               ) {
            let visibleTop = collectionView
                .contentOffset.y
                + collectionView.contentInset.top
            let effectiveBottom = collectionView
                .contentOffset.y
                + collectionView.bounds.height
                - effectiveBottomInset
            handle.contentEndVisible =
                attrs.frame.minY >= visibleTop - 1
                && attrs.frame.maxY
                    <= effectiveBottom + 1
        } else {
            handle.contentEndVisible = false
        }
        // 顶可见条目：帧序首个与有效视口顶相交的
        // 条目行（非条目行跳过、继续向下找条目行）。
        // §325.2 守卫 4：只查可见 cell（indexPaths-
        // ForVisibleItems、至多一屏行数），禁全 rows
        // 遍历——旧式全表扫描在长会话下每拍 O(n)，
        // 是 .66 滚动卡顿的放大器（诊断候选 2）
        let visibleTop = collectionView.contentOffset.y
            + collectionView.contentInset.top
        var topEntry: UUID?
        let visibleItems = collectionView
            .indexPathsForVisibleItems.map {
                rowIndex(for: $0)
            }.sorted()
        for index in visibleItems {
            guard index < rows.count,
                  let entryID = rows[index].entryID,
                  let attrs = collectionView
                    .layoutAttributesForItem(
                        at: indexPath(forRow: index)
                    ),
                  attrs.frame.maxY > visibleTop
            else { continue }
            topEntry = entryID
            break
        }
        if lastReportedTopVisible == nil
            || lastReportedTopVisible! != topEntry {
            lastReportedTopVisible = topEntry
            callbacks?.onTopVisibleEntry(topEntry)
        }
        callbacks?.onScrollGeometry()
    }

    // MARK: 滚动回调（只记账不施工，§259）

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        scheduleSettle()
        refreshVisibleWindow()
    }

    /// 行序↔indexPath 换算（§374.3 两构造分流单
    /// 点）：逐行 section 构造＝(item 0, section
    /// 行序)；单 section 构造＝(item 行序, sec-
    /// tion 0)。凡按行序取布局属性/可见项/触摸
    /// 落点皆经本口、不许各处自拼
    private func indexPath(
        forRow index: Int
    ) -> IndexPath {
        layoutBox.singleSection
            ? IndexPath(item: index, section: 0)
            : IndexPath(item: 0, section: index)
    }

    private func rowIndex(
        for indexPath: IndexPath
    ) -> Int {
        layoutBox.singleSection
            ? indexPath.item : indexPath.section
    }

    /// 台账 190②：可见窗刷新——可见行序±4 行
    /// 缓冲写入布局匣（就地量测只许窗内触发）；
    /// 窗真变时重置单窗量测预算。只读可见项
    /// （至多一屏行数＋缓冲，与 §325.2 守卫 4
    /// 同纪律、禁全 rows 遍历）
    private func refreshVisibleWindow() {
        let sections = collectionView
            .indexPathsForVisibleItems.map {
                rowIndex(for: $0)
            }
        guard let first = sections.min(),
              let last = sections.max() else { return }
        let window = max(0, first - 4)..<(last + 5)
        if layoutBox.visibleWindow != window {
            layoutBox.visibleWindow = window
            layoutBox.syncMeasureBudget =
                ChatNativeLayoutBox
                    .syncMeasureBudgetPerWindow
        }
    }

    func scrollViewWillBeginDragging(
        _ scrollView: UIScrollView
    ) {
        // 用户接管：落点意图即消（H6 的意图边界）
        userInteracting = true
        // §335：浏览态置真（与 userInteracting 同
        // 点位；减速开始前的空窗由本态覆盖）
        userBrowsing = true
        landingIntent = false
        // §426（缺陷三）：键盘贴底意图同点消——
        // 用户在键盘事务中接管位置，机器不许再钉
        keyboardPinIntent = false
        // §438：拖动接管同点收键盘事务窗与收起意
        // 图——偏移动画已被手势接管，窗内冻结账由
        // 滚动冻结链接手、停滚 flush 合并落写
        keyboardHidePinIntent = false
        if keyboardTransactionInFlight {
            keyboardTransactionInFlight = false
            settleDeferredDuringKeyboard = false
        }
        landingSettleContentSize = nil
        // 台账 150：搜索落点同弃——读者的位置优先
        // 于机器落点（OB 的 drags 计数同口径）
        focusConvergence.abort()
        focusTargetID = nil
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate {
            userInteracting = false
            // §335：无减速＝浏览结束、浏览态同清
            userBrowsing = false
            flushDeferredSettle()
        }
    }

    func scrollViewDidEndDecelerating(
        _ scrollView: UIScrollView
    ) {
        userInteracting = false
        // §335：减速落定＝浏览结束、浏览态同清
        userBrowsing = false
        flushDeferredSettle()
    }

    /// §325.2：滚动期冻结的施工在滚动结束一次性
    /// 合并落写（守卫 2③ 的落写口）
    /// §374.7（步骤 4④）：本口缺省走降级后的过
    /// 渡记账规则——flush 就在本回调点执行：记
    /// 账槽整笔喂入当场应用一次（不武装结清阶
    /// 段、不把应用托付给自排的落定拍）；应用
    /// 后的余链（布局失效施工／量测／inset／落
    /// 位）仍归落定拍（喂入收尾已排拍、无喂入
    /// 时本口补排一拍消费余账）。回退开关置假
    /// 才恢复下行现行闸原路（武装结清阶段＋自
    /// 排落定拍消费记账槽，闸本体以开关包裹保
    /// 留一个版本周期）
    private func flushDeferredSettle() {
        guard settleDeferredDuringScroll else { return }
        settleDeferredDuringScroll = false
        if scrollLedgerDowngraded() {
            if let pending = pendingApply {
                pendingApply = nil
                applyPendingFeed(pending)
            }
            scheduleSettle()
            return
        }
        // §366：停滚结清拆两拍——本回调武装阶段 1，
        // 落定拍先落数据、布局账顺延紧接的布局拍。
        // §374.5（步骤 4②）：单拍结清缺省成立——
        // 直接武装阶段 2，落定拍认领布局拍后一拍
        // 走全链（落数据＋触摸重配＋布局失效施工
        // ＋量测／落位）结清全部待结账目、不再拆
        // 拍顺延；回退开关置假才恢复武装阶段 1 的
        // 拆拍原路（拆拍本体以开关包裹保留）
        settleClearingStage = settleSingleBeat() ? 2 : 1
        scheduleSettle()
    }

    // MARK: 命令口（句柄转发目标，与 gen3 容器同名同义）

    func scrollToBottom(animated: Bool) {
        landingIntent = true
        landingIntentSince = CACurrentMediaTime()
        landingSettleContentSize = nil
        collectionView.layoutIfNeeded()
        let target = maxOffsetY()
        if animated {
            // 人发起的回底走 Core 回底弹簧参数（与
            // gen3 同参：ζ＝1.0、响应按距缩放），用
            // 户手势可接管
            let distance = currentDistance()
            UIView.animate(
                withDuration: TimeInterval(
                    BottomScrollSpring.response(
                        forDistance: distance
                    )
                ),
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState,
                          .allowUserInteraction]
            ) { [self] in
                collectionView.contentOffset = CGPoint(
                    x: 0, y: target
                )
            }
        } else {
            collectionView.contentOffset = CGPoint(
                x: 0, y: target
            )
        }
        scheduleSettle()
    }

    func scrollToEntry(_ id: UUID, animated: Bool) {
        guard let index = rows.firstIndex(
            where: { $0.entryID == id }
        ) else { return }
        collectionView.layoutIfNeeded()
        guard let attrs = collectionView
            .layoutAttributesForItem(
                at: indexPath(forRow: index)
            )
        else { return }
        let target = min(
            max(
                attrs.frame.minY
                    - collectionView.contentInset.top,
                -collectionView.contentInset.top
            ),
            maxOffsetY()
        )
        collectionView.setContentOffset(
            CGPoint(x: 0, y: target), animated: animated
        )
    }

    /// 搜索落点命令口（台账 150）：起收敛机并执行
    /// 第一次滚动；先撤落点意图——冷开钉底与搜索
    /// 落点是两种落位意图、后到者为准，不许落定拍
    /// 再把读者钉回底部。目标不在行集即无声落空
    /// （会话照常开在原落点）
    func focusEntry(_ id: UUID) {
        guard rows.contains(where: { $0.entryID == id })
        else { return }
        landingIntent = false
        landingSettleContentSize = nil
        focusTargetID = id
        focusConvergence.begin()
        performFocusScroll()
    }

    func captureAnchor() -> ChatListAnchor? {
        guard !rows.isEmpty else { return nil }
        if currentDistance() <= Self.atBottomTolerance {
            return .bottom
        }
        let visibleTop = collectionView.contentOffset.y
            + collectionView.contentInset.top
        for (index, row) in rows.enumerated() {
            guard let attrs = collectionView
                .layoutAttributesForItem(
                    at: indexPath(forRow: index)
                )
            else { continue }
            guard attrs.frame.maxY > visibleTop
            else { continue }
            if let entryID = row.entryID {
                return ChatListAnchor(
                    entryID: entryID,
                    intraEntryOffset: Double(
                        max(
                            0, visibleTop - attrs.frame.minY
                        )
                    ),
                    atBottom: false
                )
            }
            // 命中非条目行：顺延到其后第一个条目行
            // （与 gen3 同式）；其后无条目行则不存锚
            for next in index..<rows.count {
                if let entryID = rows[next].entryID {
                    return ChatListAnchor(
                        entryID: entryID,
                        intraEntryOffset: 0,
                        atBottom: false
                    )
                }
            }
            return nil
        }
        return nil
    }

    func restore(_ anchor: ChatListAnchor) {
        // 布局未就绪（零宽/无行）时先记账，落定拍
        // 在行集与布局落定后执行（与 ChatView 恢复
        // 链的等拍口径同义）
        guard collectionView.bounds.width > 0,
              !rows.isEmpty
        else {
            pendingAnchor = anchor
            scheduleSettle()
            return
        }
        executeRestore(anchor)
    }

    private func executeRestore(
        _ anchor: ChatListAnchor
    ) {
        collectionView.layoutIfNeeded()
        if anchor.atBottom {
            scrollToBottom(animated: false)
            return
        }
        if let offset = ChatListAnchor.restoredOffsetY(
            frames: pureFrames(),
            anchor: anchor,
            contentOriginY: Double(
                layoutParams.topPadding
            ),
            topInset: Double(
                collectionView.contentInset.top
            ),
            bottomInset: Double(effectiveBottomInset),
            contentHeight: Double(
                collectionView.contentSize.height
            ),
            viewportHeight: Double(
                collectionView.bounds.height
            )
        ) {
            collectionView.contentOffset = CGPoint(
                x: 0, y: CGFloat(offset)
            )
        }
        ChatDiagTrace.record(
            "原生重建 R1 锚恢复：条目 "
                + "\(anchor.entryID?.uuidString ?? "nil")"
                + " 条内偏移 "
                + "\(Int(anchor.intraEntryOffset))pt"
        )
    }

    /// 纯内容系帧表（首行顶边 y＝0，Core 锚模型口
    /// 径）：帧出布局属性（未物化 item 为布局估算
    /// 帧——锚恢复的近似源，恢复后距底由现测校验，
    /// H7）
    private func pureFrames() -> [ChatListAnchor.RowFrame] {
        rows.enumerated().map { index, row in
            let frame = collectionView
                .layoutAttributesForItem(
                    at: indexPath(forRow: index)
                )?.frame ?? .zero
            return ChatListAnchor.RowFrame(
                id: frameID(for: row),
                y: Double(
                    frame.minY - layoutParams.topPadding
                ),
                height: Double(frame.height)
            )
        }
    }

    private func frameID(
        for row: ChatNativeRow
    ) -> UUID {
        if let entryID = row.entryID { return entryID }
        if let existing = frameIDByKey[row.key] {
            return existing
        }
        let generated = UUID()
        frameIDByKey[row.key] = generated
        return generated
    }

    // MARK: 回底钮浮层（容器 overlay，与 gen3 同式）

    private func applyArrow(view newView: AnyView?) {
        if let newView {
            let host: UIHostingController<AnyView>
            if let existing = arrowHost {
                host = existing
                host.rootView = newView
            } else {
                host = UIHostingController(
                    rootView: newView
                )
                // H2：托管宿主 safeAreaRegions 清零
                host.safeAreaRegions = []
                host.view.backgroundColor = .clear
                arrowHost = host
                addChild(host)
                view.addSubview(host.view)
                host.didMove(toParent: self)
            }
            layoutArrow()
            if !arrowVisible {
                arrowVisible = true
                host.view.isHidden = false
                host.view.alpha = 0
                host.view.transform = CGAffineTransform(
                    scaleX: 0.9, y: 0.9
                )
                UIView.animate(withDuration: 0.2) {
                    host.view.alpha = 1
                    host.view.transform = .identity
                }
            }
        } else if let host = arrowHost, arrowVisible {
            arrowVisible = false
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    host.view.alpha = 0
                    host.view.transform =
                        CGAffineTransform(
                            scaleX: 0.9, y: 0.9
                        )
                },
                completion: { [weak self] _ in
                    if self?.arrowVisible == false {
                        host.view.isHidden = true
                    }
                }
            )
        }
    }

    /// 钮落位（与 gen3 §263 同源）：底缘＝帧底−实
    /// 测留位−gap；钮是 overlay 子视图，只改自身
    /// 帧、不触任何滚动记账
    private func layoutArrow() {
        guard let host = arrowHost else { return }
        measureBottomSpace()
        let size = layoutParams.arrowSize
        host.view.frame = CGRect(
            x: view.bounds.width
                - layoutParams.arrowTrailing - size,
            y: view.bounds.height
                - effectiveBottomSpace
                - layoutParams.arrowGapAboveComposer
                - size,
            width: size,
            height: size
        )
        view.bringSubviewToFront(host.view)
    }

    // MARK: 点空白收键盘（delegate 与 gen3 共用定版）

    private func installBlankTapDismiss() {
        let delegate = ChatNativeBlankTapDelegate {
            [weak self] in
            self?.callbacks?.onBlankTap()
        }
        let tap = UITapGestureRecognizer(
            target: delegate,
            action: #selector(
                ChatNativeBlankTapDelegate.handleTap
            )
        )
        tap.name = "OneDayBlankTapDismissNative"
        tap.cancelsTouchesInView = false
        tap.delegate = delegate
        collectionView.addGestureRecognizer(tap)
        blankTapDelegate = delegate
    }

    // MARK: - 原生上下文菜单 + 顶部玻璃反应条（方案 A：iMessage / Telegram 同构）

    private static var contextMenuDataAssocKey: UInt8 = 0
    private static var contextMenuTrailingAssocKey: UInt8 = 0
    private static var contextMenuIndexPathAssocKey: UInt8 = 0
    private static var reactionBarHostAssocKey: UInt8 = 0

    private var activeContextMenuData: ChatRowActionSheetData? {
        get { objc_getAssociatedObject(self, &Self.contextMenuDataAssocKey) as? ChatRowActionSheetData }
        set { objc_setAssociatedObject(self, &Self.contextMenuDataAssocKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var activeContextMenuAlignsTrailing: Bool {
        get { (objc_getAssociatedObject(self, &Self.contextMenuTrailingAssocKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.contextMenuTrailingAssocKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var activeContextMenuIndexPath: IndexPath? {
        get { objc_getAssociatedObject(self, &Self.contextMenuIndexPathAssocKey) as? IndexPath }
        set { objc_setAssociatedObject(self, &Self.contextMenuIndexPathAssocKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var activeReactionBarHost: UIHostingController<AnyView>? {
        get { objc_getAssociatedObject(self, &Self.reactionBarHostAssocKey) as? UIHostingController<AnyView> }
        set { objc_setAssociatedObject(self, &Self.reactionBarHostAssocKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first else { return nil }
        let idx = rowIndex(for: indexPath)
        guard rows.indices.contains(idx) else { return nil }
        let row = rows[idx]
        if handle?.selectionActiveRowKey == row.key { return nil }
        guard let data = row.makeContextMenuData?() else { return nil }
        let items = data.actionItems()
        guard !items.isEmpty || data.canReact else { return nil }
        activeContextMenuData = data
        activeContextMenuAlignsTrailing = row.contextMenuAlignsTrailing
        activeContextMenuIndexPath = indexPath
        return UIContextMenuConfiguration(
            identifier: row.key as NSString,
            previewProvider: nil
        ) { _ in
            let actions = items.map { item in
                UIAction(
                    title: item.title,
                    image: UIImage(systemName: item.systemImage),
                    attributes: item.isDestructive ? .destructive : []
                ) { _ in
                    item.action()
                }
            }
            return UIMenu(title: "", children: actions)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        targetedContextPreview(for: indexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        targetedContextPreview(for: indexPath)
    }

    private func targetedContextPreview(for indexPath: IndexPath) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? ChatNativeHostingCell else {
            return nil
        }
        let params = UIPreviewParameters()
        params.backgroundColor = .clear
        return UITargetedPreview(view: cell.contentView, parameters: params)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplayContextMenu configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        guard let data = activeContextMenuData, data.canReact,
              let indexPath = activeContextMenuIndexPath,
              let window = view.window else { return }
        removeActiveReactionBarHost()
        let barView = ReactionFloatingBarView(
            ownEmoji: data.ownEmoji,
            onPick: { [weak self] emoji in
                Haptics.selection()
                data.onPickReaction(emoji)
                self?.dismissActiveContextMenu()
            },
            onOpenMore: { [weak self] in
                self?.dismissActiveContextMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.presentAllReactionsSheet(ownEmoji: data.ownEmoji, onPick: data.onPickReaction)
                }
            }
        )
        let host = UIHostingController(rootView: AnyView(barView))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        let barW = ReactionFloatingBarView.barWidth
        let barH = ReactionFloatingBarView.barHeight
        let cellRect: CGRect
        if let attrs = collectionView.layoutAttributesForItem(at: indexPath) {
            cellRect = collectionView.convert(attrs.frame, to: window)
        } else {
            cellRect = CGRect(x: 20, y: window.bounds.midY - 40, width: window.bounds.width - 40, height: 80)
        }
        let safeTop = window.safeAreaInsets.top + 8
        let originX: CGFloat
        if activeContextMenuAlignsTrailing {
            originX = min(max(cellRect.maxX - barW, 8), window.bounds.width - barW - 8)
        } else {
            originX = min(max(cellRect.minX, 8), window.bounds.width - barW - 8)
        }
        let originY = max(safeTop, cellRect.minY - barH - 10)
        host.view.frame = CGRect(x: originX, y: originY, width: barW, height: barH)
        host.view.alpha = 0
        host.view.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        window.addSubview(host.view)
        activeReactionBarHost = host
        if let animator {
            animator.addAnimations {
                host.view.alpha = 1
                host.view.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.22) {
                host.view.alpha = 1
                host.view.transform = .identity
            }
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        let host = activeReactionBarHost
        activeContextMenuData = nil
        activeContextMenuIndexPath = nil
        guard let host else { return }
        if let animator {
            animator.addAnimations {
                host.view.alpha = 0
                host.view.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            }
            animator.addCompletion { [weak self] in
                host.view.removeFromSuperview()
                if self?.activeReactionBarHost === host {
                    self?.activeReactionBarHost = nil
                }
            }
        } else {
            removeActiveReactionBarHost()
        }
    }

    private func dismissActiveContextMenu() {
        removeActiveReactionBarHost()
        collectionView.contextMenuInteraction?.dismissMenu()
        for interaction in collectionView.interactions {
            if let menuInteraction = interaction as? UIContextMenuInteraction {
                menuInteraction.dismissMenu()
            }
        }
    }

    private func removeActiveReactionBarHost() {
        activeReactionBarHost?.view.removeFromSuperview()
        activeReactionBarHost = nil
    }

    private func presentAllReactionsSheet(ownEmoji: String?, onPick: @escaping (String) -> Void) {
        var pickerController: UIHostingController<ReactionEmojiPickerView>? = nil
        let picker = ReactionEmojiPickerView(ownEmoji: ownEmoji) { emoji in
            Haptics.selection()
            onPick(emoji)
            pickerController?.dismiss(animated: true)
        }
        let host = UIHostingController(rootView: picker)
        pickerController = host
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }
}

// MARK: - Representable

struct ChatNativeListView: UIViewControllerRepresentable {
    var rows: [ChatNativeRow]
    /// §374 步骤 2：本趟变更集（开关 chat.list
    /// .incremental 开时由 ChatView 交付——追踪
    /// 器 ingest 产物）；非 nil 时控制器走
    /// applyChanges 增量路，nil 走旧路 apply
    var changeSet: EntryChangeSet? = nil
    var layout: ChatNativeLayout
    var topInset: CGFloat
    var bottomMargin: CGFloat
    /// 输入舱内容（R2 收编）：由控制器子托管、底
    /// 边钉其位置引导线（§302 通知帧顶常量驱
    /// 动）；底几何的喂入自此只剩本内容本体，无
    /// 舱顶/动画参数喂入
    var composerView: AnyView
    /// §302：键盘帧更新收件槽（ChatView 的 kb-
    /// FrameUpdate 状态绑定）——控制器在键盘事
    /// 件拍直写（帧顶已转窗口坐标），与旧面
    /// ComposerGuideHost 的 keyboardFrame 绑定
    /// 同一口径、同一份快照
    var keyboardFrame: Binding<KeyboardFrameUpdate?>
    var arrowView: AnyView?
    var handle: ChatNativeListHandle
    var callbacks: ChatNativeListCallbacks
    var edgeScrollHandle: ChatListScrollViewHandle
    /// 台账 190②：就地量测口（行键→确定高）；
    /// 默认 nil（裸装配形态无量测台）
    var exactHeightProvider: ((String) -> CGFloat?)? = nil

    func makeUIViewController(
        context: Context
    ) -> ChatRootViewController {
        let controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = callbacks
        controller.edgeScrollHandle = edgeScrollHandle
        controller.exactHeightProvider = exactHeightProvider
        handle.controller = controller
        wireKeyboardFeed(to: controller)
        return controller
    }

    func updateUIViewController(
        _ controller: ChatRootViewController,
        context: Context
    ) {
        controller.handle = handle
        controller.callbacks = callbacks
        controller.edgeScrollHandle = edgeScrollHandle
        controller.exactHeightProvider = exactHeightProvider
        handle.controller = controller
        wireKeyboardFeed(to: controller)
        if let changeSet {
            controller.applyChanges(
                rows: rows,
                changeSet: changeSet,
                layout: layout,
                topInset: topInset,
                bottomMargin: bottomMargin,
                composerView: composerView,
                arrowView: arrowView
            )
        } else {
            controller.apply(
                rows: rows,
                layout: layout,
                topInset: topInset,
                bottomMargin: bottomMargin,
                composerView: composerView,
                arrowView: arrowView
            )
        }
    }

    /// §302：把控制器的键盘帧回调接回 ChatView
    /// 的绑定——回调源自通知处理（非布局拍），
    /// 事件拍直写同步：快照与舱常量同拍翻转是
    /// 本收口的本意（与 ComposerGuideHost 桥的
    /// keyboardFrame 接线同一纪律）；等值守卫防
    /// 同值重播触发无谓重渲
    private func wireKeyboardFeed(
        to controller: ChatRootViewController
    ) {
        let keyboardFrame = keyboardFrame
        controller.onKeyboardFrameChange = { update in
            if keyboardFrame.wrappedValue != update {
                keyboardFrame.wrappedValue = update
            }
        }
    }
}


// MARK: - 共用件（§374.9 自旧承载文件迁入）

/// §374.9（步骤 6）：gen3 承载文件 ChatListCarrier
/// .swift 退役时，其共用件迁入本文件（原生面的实
/// 现文件）——布局值/回调值/点空白 delegate 随迁
/// 改 Native 名；锚存取 ChatListAnchorStore 名无
/// 禁词、原样迁入（其 UserDefaults 键 chat.carrier
/// .anchors.v1 是落盘兼容键、逐字不动）

/// 承载布局参数（值源＝OneDayMetrics，ChatView 喂
/// 入，承载内不写第二套数）
struct ChatNativeLayout {
    var horizontalPadding: CGFloat
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    var rowSpacing: CGFloat
    /// 回底钮右距（与旧钮行 .padding(.trailing) 同值）
    var arrowTrailing: CGFloat
    /// 回底钮底缘距输入舱顶（蓝图/简报口径约 8pt）
    var arrowGapAboveComposer: CGFloat = 8
    /// 回底钮命中边（与旧钮 OneDayMetrics.minTap-
    /// Target 同值）
    var arrowSize: CGFloat
}

/// 承载回调（ChatView 注入；几何回调只报「变了」，
/// 读数经句柄引用匣取——与 BottomDistanceRecorder
/// 的 §199 纪律同式：写不失效任何视图）
struct ChatNativeListCallbacks {
    var onScrollGeometry: () -> Void
    var onTopVisibleEntry: (UUID?) -> Void
    var onBlankTap: () -> Void
}

/// 扩展锚的落盘口：旧 SideChatScrollAnchor 只有
/// （entryID, atBottom）两字段、装不下条内偏移——
/// 新承载的锚单独存本口（UserDefaults 编码字典，
/// 键＝线程 id），旧锚保留为回落（扩展锚缺位时按
/// 旧锚恢复）。切线程存取纪律与旧口一致（离线程
/// 时存、入线程时取）
enum ChatListAnchorStore {
    private static let defaultsKey = "chat.carrier.anchors.v1"

    private struct StoredAnchor: Codable {
        var entryID: String?
        var intraEntryOffset: Double
        var atBottom: Bool
    }

    static func anchor(for threadID: UUID) -> ChatListAnchor? {
        guard let dict = UserDefaults.standard.dictionary(
            forKey: defaultsKey
        ) as? [String: Data],
            let data = dict[threadID.uuidString],
            let stored = try? JSONDecoder().decode(
                StoredAnchor.self, from: data
            )
        else { return nil }
        return ChatListAnchor(
            entryID: stored.entryID.flatMap(UUID.init(uuidString:)),
            intraEntryOffset: stored.intraEntryOffset,
            atBottom: stored.atBottom
        )
    }

    static func setAnchor(
        _ anchor: ChatListAnchor, for threadID: UUID
    ) {
        let stored = StoredAnchor(
            entryID: anchor.entryID?.uuidString,
            intraEntryOffset: anchor.intraEntryOffset,
            atBottom: anchor.atBottom
        )
        guard let data = try? JSONEncoder().encode(stored)
        else { return }
        var dict = (UserDefaults.standard.dictionary(
            forKey: defaultsKey
        ) as? [String: Data]) ?? [:]
        dict[threadID.uuidString] = data
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }
}

/// 点空白收键盘的识别器 delegate：仲裁口径与
/// ScrollViewTapDismiss.swift 的定版逐字同义（触点
/// 落在任何 UITextView 子树内不接收、与既有识别器
/// 同时识别、不吞触摸）——旧承载的安装器靠 ascend
/// 找滚动视图，新承载的滚动视图就在自家容器内、
/// 直接装配，故只复用其 delegate 规则、不复用其
/// 寻面装配
final class ChatNativeBlankTapDelegate: NSObject,
    UIGestureRecognizerDelegate
{
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    @objc func handleTap() {
        onTap()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith
            otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
