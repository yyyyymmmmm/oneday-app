import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 审批记录的支持件（原枢纽审核段 HubApprovalSection
/// 的存续部分）。§155 定版：枢纽只有记录、不能审批，
/// 审批只在聊天界面。§217（2026-11-13 枢纽收段）：
/// 审核段撤出分段栏——审批事件本就在工作台账里有
/// 同源条目（伴生采集器 write-gate 源：待批＝等待审
/// 批态、已决＝完成/取消态），记录呈现归活动段。
/// §244（2026-11-14，大厂九项⑦归位）：审批规则区
/// 迁出枢纽、落设置页「偏好与权限」组（Approval-
/// RulesSettingsView 承载，规则面全 App 只此一处不
/// 变）；台账自此只留审批记录（条目与详情即记录入
/// 口），不再兼收设置面。本文件留三件：
/// ①审批规则区（ApprovalRulesView）与设置页承载；
/// ②锚点点达支持（ApprovalAnchorSupport）——台账
///   详情的审批条目「查看原对话」复用原审核段的
///   §165 解析（本机线程表索引＋Core 解析），钮的
///   出没与点达口径与旧段逐字一致；
/// ③改动查看（HubDiffView/ApprovalReviewContent）
///   ——只读 diff 呈现，聊天就地卡与台账详情共用，
///   本来就不属于审核段本体、原样保留。

// MARK: - 审批规则（§244 归设置页权限区）

/// 审批规则区（0.36.21，规格 §4）：规则只存桥侧，
/// 这里是只读镜像＋撤销入口——没有撤销面不许交付
/// 是硬口径。§244 后本区由设置页「偏好与权限 →
/// 审批规则」（ApprovalRulesSettingsView）承载、
/// 撤销确认框由承载方挂，只在审批数据就绪
/// （.ready）时出现：通道未接通/未启用时规则无从
/// 谈起，不拿空区冒充（未就绪态由承载页如实呈现）。
/// 规则为空与未拉到分开说（诚实呈现），撤销失败
/// 留人话提示在区首
struct ApprovalRulesView: View {
    let store: AgentHubStore
    /// 撤销点按（确认框与执行在承载方，与旧段同一
    /// 确认文案与 revokeRule 路径）
    var onRevoke: (WriteGateRule) -> Void

    var body: some View {
        if case .ready = store.approvalState {
            Section("审批规则") {
                if let note = store.rulesNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                }
                if store.approvalRules.isEmpty {
                    Text(store.rulesLoaded
                        ? "暂无规则。在聊天里的待批卡上点「总是允许这一类」后，会在这里留下一条，可随时撤销。"
                        : "规则还没有拉到，下拉刷新后再看。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(store.approvalRules) { rule in
                    ruleRow(rule)
                }
            }
        }
    }

    private func ruleRow(_ rule: WriteGateRule) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(rule.scopeLabel)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                if let createdAt = rule.createdAt {
                    Text("建立于 \(ApprovalTimeText.relative(createdAt))")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
            if store.revokingRuleIDs.contains(rule.id) {
                ProgressView()
            } else {
                Button("撤销", role: .destructive) {
                    onRevoke(rule)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
    }
}

/// 审批规则设置页（§244 归位，大厂九项⑦）：规则是
/// 长期设置、归设置页「偏好与权限」组；台账只留审
/// 批记录。数据与枢纽/聊天卡同源（AppState 共享
/// AgentHubStore、同拉取同撤销路）；未就绪态在此
/// 如实呈现（加载中/通道未接通/未启用/失败），不
/// 拿空区冒充。撤销确认框与旧枢纽承载同一文案
struct ApprovalRulesSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var revokeTarget: WriteGateRule?

    private var store: AgentHubStore { appState.sharedHubStore() }

    var body: some View {
        List {
            Section {
                Text("在聊天里的待批卡上点「总是允许这一类」，会在这里留下一条规则：同类写入以后直接通过、不再逐条问。撤销一条，恢复逐条审批。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            stateSection
            ApprovalRulesView(store: store) { rule in
                revokeTarget = rule
            }
        }
        .navigationTitle("审批规则")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadApproval()
        }
        .refreshable {
            await store.loadApproval(force: true)
        }
        .confirmationDialog(
            "撤销这条规则？",
            isPresented: Binding(
                get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: revokeTarget
        ) { rule in
            Button("撤销规则", role: .destructive) {
                Task { await store.revokeRule(rule) }
                revokeTarget = nil
            }
            Button("取消", role: .cancel) {
                revokeTarget = nil
            }
        } message: { rule in
            Text("撤销后，「\(rule.scopeLabel)」的写入会重新逐条等你审批。")
        }
    }

    /// 未就绪态的诚实呈现（规则区本体只在 .ready
    /// 出现）：每种未就绪都给真状态，不留空白页
    @ViewBuilder
    private var stateSection: some View {
        switch store.approvalState {
        case .ready:
            EmptyView()
        case .loading:
            Section {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取规则…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        case .bridgeUnavailable:
            Section {
                Text("审批通道还没接通，规则暂时看不到。接通后这里会显示已留下的规则。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .gateDisabled:
            Section {
                Text("写入审批还没启用，现在没有规则可管。启用后，在聊天里点「总是允许这一类」就会在这里留下规则。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .failed(let message):
            Section {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}

// MARK: - 锚点点达（§165，自原审核段抽出共用）

/// 审批记录点达原对话的本机解析支持：一次扫线程表
/// 得映射（锚定键→线程/条目、服务端会话→线程），
/// 解析走 Core ApprovalAnchorNavigation——与原审
/// 核段逐字同一套判据（记录量级小、点按时现扫即
/// 可，不另立缓存状态）。调用方负责在解析非 .none
/// 时才出钮、点按后把 approvalAnchorRequest 落
/// AppState 并关枢纽（ChatView 消费切线程定位）
enum ApprovalAnchorSupport {
    struct Index {
        let materialized: ApprovalAnchorNavigation.MaterializedIndex
        let threadIDBySession: [String: UUID]
    }

    static func index(threads: [ChatThread]) -> Index {
        var threadIDByKey: [String: UUID] = [:]
        var entryIDByKey: [String: UUID] = [:]
        var bySession: [String: UUID] = [:]
        for thread in threads {
            if let sessionID = thread.serverSessionID,
               !sessionID.isEmpty {
                bySession[sessionID] = thread.id
            }
            for entry in thread.entries {
                if let key = entry.approvalKey {
                    threadIDByKey[key] = thread.id
                    entryIDByKey[key] = entry.id
                }
            }
        }
        return Index(
            materialized: ApprovalAnchorNavigation.MaterializedIndex(
                threadIDByKey: threadIDByKey,
                entryIDByKey: entryIDByKey
            ),
            threadIDBySession: bySession
        )
    }

    static func target(
        index: Index, subsystem: WriteGateSubsystem,
        recordID: String, anchorSessionID: String?
    ) -> ApprovalAnchorNavigation.Target {
        ApprovalAnchorNavigation.target(
            subsystem: subsystem, recordID: recordID,
            anchorSessionID: anchorSessionID,
            threadIDByServerSessionID: index.threadIDBySession,
            materialized: index.materialized
        )
    }

    /// 点达落点：解析出线程（带锚定键时连条目）→
    /// 返回要落 AppState.approvalAnchorRequest 的值；
    /// .none 返回 nil（调用方不出手）
    static func anchorRequest(
        index: Index, subsystem: WriteGateSubsystem,
        recordID: String, anchorSessionID: String?
    ) -> (threadID: UUID, approvalKey: String?)? {
        switch target(
            index: index, subsystem: subsystem,
            recordID: recordID, anchorSessionID: anchorSessionID
        ) {
        case .entry(let threadID, let key):
            return (threadID, key)
        case .threadOnly(let threadID):
            return (threadID, nil)
        case .none:
            return nil
        }
    }
}

/// diff 详情（规格 #20）：点开按需拉 detail——桥的
/// review.diff（skills 看 unified diff；memory 的 diff
/// 即 payload JSON 文本）。notes 与 patch 定位失败提示
/// 必须显性呈现，不许静默按成功处理（桥方案 §5 风险 2）
struct HubDiffView: View {
    let store: AgentHubStore
    let record: WriteGateRecord

    @Environment(\.dismiss) private var dismiss
    @State private var detail: WriteGateDetail?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    ApprovalReviewContent(detail: detail, record: record)
                }
            } else if let errorText {
                ContentUnavailableView(
                    "改动没读出来，可能是网络或服务暂时没响应",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorText)
                )
            } else {
                ProgressView()
            }
        }
        // 0.36.0（§5／审计 C9 同族）：撤手写关闭
        // （走系统下拉手势）；标题是审批对象名＝内
        // 容身份本身，保留（台账 E2 豁免候选）
        .navigationTitle(detail?.review.targetLabel ?? "查看改动")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            switch await store.loadDetail(record) {
            case .success(let loaded):
                detail = loaded
            case .failure(.recordGone):
                errorText = "这条待批已被处理或已失效。"
            case .failure:
                errorText = "通道未接通或读取出错，请稍后再试。"
            }
        }
    }
}

/// 差异内容体（0.36.21 从 HubDiffView 抽出）：枢纽
/// sheet 与聊天就地卡的 inline 展开共用同一份内容与
/// 口径（规格 §2）——notes 警示、patch 原文失效提示、
/// diff 正文，再加「原始信息」折叠区：服务端原始摘
/// 要与来源原值只许在这里出现（默认折叠、供排障，
/// P-16），卡面与列表一律走人话模板
struct ApprovalReviewContent: View {
    let detail: WriteGateDetail
    let record: WriteGateRecord
    /// 内嵌进卡片时为 true：卡面已有内边距，内容体不
    /// 再叠页面级边距（默认 false＝sheet 独立呈现）
    var embedded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            ForEach(detail.review.noteLabels, id: \.self) { label in
                Label(label, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
            }
            if detail.review.requestedOldString != nil {
                Label(
                    "这条修订要改的原文已经不存在，可能基于旧内容，批准前请仔细核对。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(Palette.warning)
            }
            Text(detail.review.displayDiff)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            DisclosureGroup("原始信息（排障用）") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("服务端摘要：\(record.summary)")
                    Text("来源原值：\(record.origin)")
                    Text("记录编号：\(record.id)")
                }
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
        }
        .padding(embedded ? 0 : OneDayMetrics.pageGutter)
    }
}
