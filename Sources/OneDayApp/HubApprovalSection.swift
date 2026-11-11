import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页审核段（规格 §3.2，用户定案⑥；0.16.0/P10
/// 起补已决历史段）。§155（HUB-1，用户 2026-11-11
/// 定版「枢纽只有记录、不能审批，审批只在聊天界
/// 面」）：本段改记录制——待批只呈现记录（详情走只
/// 读的改动查看），批准/驳回只在聊天就地卡；已决历
/// 史读桥 /decisions 账本（桥自上线起就有，本段只
/// 读呈现、不再造数据）。审批规则区保留撤销：规则
/// 是长期设置、不是单条裁决，且全 App 只此一处可撤
/// 销（0.36.21 硬口径不回退）。
/// gate 三态诚实呈现（未启用/通道未接通/已启用），
/// 裸空列表冒充「无待批」是红线：只有桥可达＋闸门开
/// ＋pending 为空才是真无待批（状态判定在
/// AgentHubStore.loadApproval 与 Core 的
/// ApprovalSectionState）。桥 /status 已上线（两闸门
/// true、counts 实时），本段直接消费。
struct HubApprovalSection: View {
    let store: AgentHubStore

    @Environment(AppState.self) private var appState
    /// 锚点点达的本地索引来源（§156）：线程表（找锚定
    /// 条目与会话绑定）——点按解析在 Core
    /// （ApprovalAnchorNavigation），本段只备数据
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// 通知落点聚焦的已决记录 id（§123 H2）：通知中心
    /// 点审批回执达本段时置位，本段消费后滚动定位＋
    /// 行底色点亮，消费即清 AppState 字段防复活
    @State private var focusDecisionID: String?

    @State private var diffTarget: WriteGateRecord?
    @State private var revokeTarget: WriteGateRule?

    var body: some View {
        Group {
            switch store.approvalState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .bridgeUnavailable:
                ContentUnavailableView {
                    Label("审批通道未接通", systemImage: "shield.slash")
                } description: {
                    Text("写入审批的通道还没接通，暂时看不到待批记录。")
                } actions: {
                    Button("重试") {
                        Task { await store.loadApproval(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
            case .gateDisabled:
                ContentUnavailableView {
                    Label("写入审批未启用", systemImage: "checkmark.shield")
                } description: {
                    Text("开启后，记忆与技能的写入会先在聊天里等你批准，这里留一份记录。")
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("没读出来", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await store.loadApproval(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
            case .ready(let records):
                if records.isEmpty && store.decisionHistory.isEmpty
                    && store.approvalRules.isEmpty {
                    ContentUnavailableView(
                        "暂无待批记录",
                        systemImage: "checkmark.circle",
                        description: Text("记忆与技能的写入会先在聊天里等你批准，这里会留一份记录")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            if !records.isEmpty {
                                Section {
                                    ForEach(records) { record in
                                        pendingRecordRow(record)
                                    }
                                } header: {
                                    Text("待批记录")
                                } footer: {
                                    Text("这里只留记录，批准或驳回请在聊天里处理。")
                                }
                            }
                            rulesSection
                            if !store.decisionHistory.isEmpty {
                                Section("已决历史") {
                                    ForEach(store.decisionHistory) { item in
                                        historyRow(item)
                                            .id(item.id)
                                            .listRowBackground(
                                                item.id == focusDecisionID
                                                    ? Palette.primaryTint
                                                    : Color.clear
                                            )
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await store.loadApproval(force: true)
                        }
                        // §123（H2）：聚焦滚动两路触发——
                        // 焦点置位时一次、历史数据落位后
                        // 再一次（段刚开时可能还在加载，
                        // 只有置位那一拍滚不到目标行）
                        .onChange(of: focusDecisionID) { _, id in
                            scrollToFocus(proxy, id: id)
                        }
                        .onChange(of: store.decisionHistory) { _, _ in
                            scrollToFocus(proxy, id: focusDecisionID)
                        }
                    }
                }
            }
        }
        .task {
            // §123（H2）：消费通知落点的聚焦字段（置位
            // —消费—清零）；记录不在已载历史里时聚焦自
            // 然落空——段本身就是记录的家，不假装定位
            if let id = appState.hubApprovalFocusID {
                focusDecisionID = id
                appState.hubApprovalFocusID = nil
            }
        }
        .sheet(item: $diffTarget) { record in
            NavigationStack {
                HubDiffView(store: store, record: record)
            }
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

    /// 待批记录行（§155 记录制）：与已决历史行同一视
    /// 觉语言——子系统徽章＋问句头条（Core
    /// ApprovalCardCopy 人话口径，与聊天就地卡同源）
    /// ＋一行说明＋时间；唯一的点按是只读的「查看改
    /// 动」（diff sheet 只呈现、不裁决）。待批点达原
    /// 对话的会话定位不在记录字段里（WriteGateRecord
    /// 无会话字段），归审批锚点包以时序关联补齐，本段
    /// 行级点按位即其落点，本包不越界自造定位
    private func pendingRecordRow(_ record: WriteGateRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(record.subsystem.badgeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, OneDayMetrics.stackGap)
                    .background(Palette.primaryTint, in: Capsule())
                Spacer()
                if let createdAt = record.createdAt {
                    Text(ApprovalTimeText.relative(createdAt))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Text(ApprovalCardCopy.question(for: record))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(ApprovalCardCopy.summaryLine(for: record))
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(2)
            HStack(spacing: OneDayMetrics.spacingM) {
                Button("查看改动") {
                    diffTarget = record
                }
                // §156（锚点包，规格 §4.4／HUB-1 §154.3
                // 留口）：记录带锚且本机有对应线程时给
                // 「查看原对话」——点达发起对话的锚定
                // 行（未物化时只达对话不定位）；无锚不
                // 出此钮，不许假定位
                if hasAnchorTarget(
                    subsystem: record.subsystem, id: record.id,
                    anchorSessionID: record.anchor?.sessionId
                ) {
                    Button("查看原对话") {
                        goToAnchor(
                            subsystem: record.subsystem,
                            id: record.id,
                            anchorSessionID: record.anchor?.sessionId
                        )
                    }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 锚点点达（§156）

    /// 本机锚索引：一次扫线程表得三份映射（锚定键→线
    /// 程/条目、服务端会话→线程）。记录量级为个位数、
    /// 点按时现扫即可，不另立缓存状态
    private func anchorIndex() -> (
        materialized: ApprovalAnchorNavigation.MaterializedIndex,
        threadIDBySession: [String: UUID]
    ) {
        let threads = (try? modelContext.fetch(
            FetchDescriptor<ChatThread>()
        )) ?? []
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
        return (
            ApprovalAnchorNavigation.MaterializedIndex(
                threadIDByKey: threadIDByKey,
                entryIDByKey: entryIDByKey
            ),
            bySession
        )
    }

    private func anchorTarget(
        subsystem: WriteGateSubsystem, id: String,
        anchorSessionID: String?
    ) -> ApprovalAnchorNavigation.Target {
        let index = anchorIndex()
        return ApprovalAnchorNavigation.target(
            subsystem: subsystem, recordID: id,
            anchorSessionID: anchorSessionID,
            threadIDByServerSessionID: index.threadIDBySession,
            materialized: index.materialized
        )
    }

    private func hasAnchorTarget(
        subsystem: WriteGateSubsystem, id: String,
        anchorSessionID: String?
    ) -> Bool {
        anchorTarget(
            subsystem: subsystem, id: id,
            anchorSessionID: anchorSessionID
        ) != .none
    }

    /// 点达执行：落点先落 AppState（与通知落点同字段
    /// approvalAnchorRequest），再关枢纽回聊天格——
    /// ChatView 消费请求切线程＋定位；解析为 .none 时
    /// 本函数不出手（钮已按同一解析隐藏，此为防御）
    private func goToAnchor(
        subsystem: WriteGateSubsystem, id: String,
        anchorSessionID: String?
    ) {
        switch anchorTarget(
            subsystem: subsystem, id: id,
            anchorSessionID: anchorSessionID
        ) {
        case .entry(let threadID, let key):
            appState.approvalAnchorRequest = (threadID, key)
        case .threadOnly(let threadID):
            appState.approvalAnchorRequest = (threadID, nil)
        case .none:
            return
        }
        dismiss()
    }

    /// 已决历史行（P10）：只读呈现——类别徽章＋结论
    /// chip＋摘要＋来源与时间；结论色只认桥账本原值
    /// （批准绿/驳回红，未知回落中性不臆断）
    private func historyRow(_ item: WriteGateDecisionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(item.subsystem.badgeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, OneDayMetrics.stackGap)
                    .background(Palette.primaryTint, in: Capsule())
                Text(item.decisionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(decisionColor(item))
                    .padding(.horizontal, 8)
                    .padding(.vertical, OneDayMetrics.stackGap)
                    .background(
                        decisionColor(item).opacity(0.12), in: Capsule()
                    )
                if item.isRuleApproved {
                    // 按规则放行必须标明（0.36.21）：与
                    // 人工批准分开呈现，账本 via_rule 是
                    // 据；样式二期 S2-03 收敛：不再叠第
                    // 三颗胶囊，降为结论后的普通灰字后缀
                    // （徽章至多两件：子系统＋结论）
                    Text("按规则放行")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
                if let decidedAt = item.decidedAt {
                    Text(ApprovalTimeText.relative(decidedAt))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Text(item.headline)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Text("来源：\(item.originText)")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            // §156：已决记录同样可点达原对话（呈现与
            // 聊天内已决行一致：结论＋时间在上方行内已
            // 备，本钮只补去向、无任何裁决入口）；无
            // 锚不出钮（任务第 2 件）
            if hasAnchorTarget(
                subsystem: item.subsystem, id: item.id,
                anchorSessionID: item.anchor?.sessionId
            ) {
                Button("查看原对话") {
                    goToAnchor(
                        subsystem: item.subsystem, id: item.id,
                        anchorSessionID: item.anchor?.sessionId
                    )
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    /// 聚焦滚动（§123 H2）：目标行已在历史里才滚，
    /// 不在（未载完/已被桥侧滚动淘汰）就静默落空
    private func scrollToFocus(
        _ proxy: ScrollViewProxy, id: String?
    ) {
        guard let id,
              store.decisionHistory.contains(where: { $0.id == id })
        else { return }
        withAnimation {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func decisionColor(_ item: WriteGateDecisionRecord) -> Color {
        // 与 Core 的 isApproved/isRejected 同一判定，
        // 不另立一套词表（桥实测只有 approved/rejected）
        if item.isApproved { return Palette.success }
        if item.isRejected { return Palette.danger }
        return Palette.inkMuted
    }

    /// 审批规则区（0.36.21，规格 §4）：规则只存桥侧，
    /// 这里是只读镜像＋撤销入口——没有撤销面不许交付
    /// 是本包的硬口径。规则为空与未拉到分开说（诚实
    /// 呈现），撤销失败留人话提示在区首
    private var rulesSection: some View {
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
                    revokeTarget = rule
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
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
