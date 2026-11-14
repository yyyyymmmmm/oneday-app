import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 审批记录的支持件（原枢纽审核段 HubApprovalSection
/// 的存续部分）。§155 定版：枢纽只有记录、不能审批，
/// 审批只在聊天界面。§208（2026-11-13 枢纽收段）：
/// 审核段撤出分段栏——审批事件本就在工作台账里有
/// 同源条目（伴生采集器 write-gate 源：待批＝等待审
/// 批态、已决＝完成/取消态），记录呈现归活动段；本
/// 文件只留三件段外仍要用的东西：
/// ①审批规则区（HubApprovalRulesView）——规则是长
///   期设置不是记录，且撤销面全 App 只此一处（聊天
///   卡文案明示「规则可以在枢纽『审批规则』里随时
///   撤销」，0.36.21 硬口径不回退），随收段迁进活
///   动段的台账列表顶部继续在枢纽里可达；
/// ②锚点点达支持（ApprovalAnchorSupport）——台账
///   详情的审批条目「查看原对话」复用原审核段的
///   §165 解析（本机线程表索引＋Core 解析），钮的
///   出没与点达口径与旧段逐字一致；
/// ③改动查看（HubDiffView/ApprovalReviewContent）
///   ——只读 diff 呈现，聊天就地卡与台账详情共用，
///   本来就不属于审核段本体、原样保留。

// MARK: - 审批规则（§208 迁入活动段）

/// 审批规则区（0.36.21，规格 §4）：规则只存桥侧，
/// 这里是只读镜像＋撤销入口——没有撤销面不许交付
/// 是硬口径。§208 后本区是活动段台账列表里的一节
/// （由 HubLedgerSection 承载、撤销确认框由承载方
/// 挂），只在审批数据就绪（.ready）时出现：通道未
/// 接通/未启用时规则无从谈起，不拿空区冒充。规则
/// 为空与未拉到分开说（诚实呈现），撤销失败留人
/// 话提示在区首
struct HubApprovalRulesView: View {
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
