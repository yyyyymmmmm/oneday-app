import Foundation
import OneDayCore

/// 行状态账本（§329）：聊天行内「影响行高、却只活在
/// 视图 @State 里」的状态统一上提到 ChatView 持有——
/// 行高改 .absolute 回喂后，合成器必须看得见每一份
/// 影响高度的状态，否则合成高与呈现高必然分叉。本
/// 账本只收两类：①展开覆盖（ReasoningBlock／工具
/// 卡／工具组的展开态——相位默认仍由各视图按既有
/// 口径现算，账本只存用户点按覆盖值）；②审批详情
/// 四态（展开/加载中/详情本体/错误文案——详情数据
/// 本就来自 AgentHubStore 的 loadDetail，落账后合成
/// 器可按同一份详情算高）。
///
/// 纪律：键由 ChatRowStateKeys 单点派生（视图侧与合
/// 成侧同源、不许各拼一份）；无账本环境（其他表面
/// 复用同视图时不传）视图回落本地 @State、行为逐字
/// 不变；账本变更经 @Observable 触发 ChatView 重渲
/// →nativeRows 重合成→apply 落写新高，与 §329 的
/// 单一数据源口径同路。
@MainActor
@Observable
final class ChatRowStateLedger {
    /// 展开覆盖：键→用户点按定下的展开值；无键＝跟
    /// 视图相位默认（ReasoningBlock）或收起（工具卡）
    private(set) var expansionOverrides: [String: Bool] = [:]
    /// 审批详情四态：记录 id→状态
    private(set) var approvalDetails: [String: ApprovalDetailState] = [:]

    func expansionOverride(for key: String) -> Bool? {
        expansionOverrides[key]
    }

    func setExpansion(_ expanded: Bool, for key: String) {
        expansionOverrides[key] = expanded
    }

    /// NEW 未读分界线已演过入场动画的锚键（台账
    /// 148）：分界线入场只演一次——行随滚动重建时
    /// 查本账，已演过的直接静态呈现（与 OB 以 Set
    /// 记已演行同构）；纯呈现记账、不影响行高，不
    /// 入 §329 的两类收编范围
    private(set) var animatedUnreadDividers: Set<String> = []

    func hasAnimatedUnreadDivider(forKey key: String) -> Bool {
        animatedUnreadDividers.contains(key)
    }

    func markUnreadDividerAnimated(forKey key: String) {
        animatedUnreadDividers.insert(key)
    }

    /// 正文选区在场记账（141/142 根治）：哪个条目
    /// 的文本视图正持有选区——自此只存本账、永不
    /// 进 @State/行修订（理由见 ChatNativeRow-
    /// Revision.entry 的「选区在场永不入账」注）。
    /// 消费方全部在事件/手势时刻直读：右滑引用修
    /// 饰符在 pan 回调里查、ChatView 在选区回报时
    /// 把行键同步给原生面句柄作重配暂存凭据。视图
    /// body 不读本值（读了就会把选区变化变成重渲
    /// 染——正是要拆的回路）
    private(set) var textSelectionEntryID: UUID?
    /// 消选延迟清账的任务句柄（§152 旧制 350ms：
    /// 同一条内换块选字时旧块消选先于新块报选到
    /// 达，立即清账会把保护误清）
    var textSelectionClearTask: Task<Void, Never>?

    /// 选区回报入口：active＝该条目文本视图选区形
    /// 成；inactive＝消选（延迟 350ms 清账）。保护
    /// 真正结束（延迟清账落下）时回调 onProtect-
    /// ionEnded——ChatView 据此让原生面把暂存的该
    /// 行重配 flush 出去
    func noteTextSelection(
        entryID: UUID, active: Bool,
        onProtectionEnded: (() -> Void)? = nil
    ) {
        if active {
            textSelectionClearTask?.cancel()
            textSelectionClearTask = nil
            textSelectionEntryID = entryID
        } else if textSelectionEntryID == entryID {
            textSelectionClearTask?.cancel()
            textSelectionClearTask = Task { @MainActor in
                try? await Task.sleep(
                    for: .milliseconds(350)
                )
                guard !Task.isCancelled else { return }
                textSelectionEntryID = nil
                onProtectionEnded?()
            }
        }
    }

    func approvalDetail(for recordID: String) -> ApprovalDetailState {
        approvalDetails[recordID] ?? ApprovalDetailState()
    }

    func updateApprovalDetail(
        _ recordID: String,
        _ mutate: (inout ApprovalDetailState) -> Void
    ) {
        var state = approvalDetails[recordID] ?? ApprovalDetailState()
        mutate(&state)
        approvalDetails[recordID] = state
    }
}

/// 审批详情四态（§329）：与 ChatApprovalCard 旧
/// @State 四件（detailExpanded/detail/detailError/
/// detailLoading）一一对应、整组搬运，语义不变
struct ApprovalDetailState {
    var expanded = false
    var detail: WriteGateDetail?
    var error: String?
    var loading = false
}

/// 行状态键单点派生（§329）：视图构造点与高度合
/// 成点共用本表——键形态只此一处出处
enum ChatRowStateKeys {
    static func reasoningEntry(_ entryID: UUID) -> String {
        "reasoning-entry-\(entryID.uuidString)"
    }

    static let liveReasoning = "reasoning-live"

    static func toolEntry(_ entryID: UUID) -> String {
        "tool-entry-\(entryID.uuidString)"
    }

    /// 来源条（D4，§349）：定稿条目下方来源清单的
    /// 展开态键——与思考/工具卡同账本纪律（行高合
    /// 成器经 facet 快照看得见、展开即重测高）
    static func sourcesEntry(_ entryID: UUID) -> String {
        "sources-entry-\(entryID.uuidString)"
    }

    static func toolLive(_ cardID: String) -> String {
        "tool-live-\(cardID)"
    }

    /// 工具组：以行键为命名空间（落定组＝toolgroup-
    /// <首条目 id>、直播组＝live-toolgroup-<首卡 id>，
    /// 均由行构造点现成持有）
    static func toolGroupCard(
        groupKey: String, cardID: String
    ) -> String {
        "\(groupKey)/\(cardID)"
    }

    /// 直播工具组键：行键＝live-<LiveRenderItem.id>
    /// （item.id 恒为 toolgroup-<首卡 id>）
    static func liveToolGroup(_ itemID: String) -> String {
        "live-\(itemID)"
    }

    /// NEW 未读分界线锚键（台账 148）：分界线挂在
    /// 锚条目上方、入场动画记账以锚条目为键
    static func unreadDivider(_ entryID: UUID) -> String {
        "unread-divider-\(entryID.uuidString)"
    }
}
