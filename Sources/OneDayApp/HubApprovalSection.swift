import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页审核段（规格 §3.2，用户定案⑥；0.16.0/P10
/// 起补已决历史段）：待批一卡一条——人话摘要＋来源＋
/// diff 入口＋批准/驳回；已决历史读桥 /decisions 账本
/// （桥自上线起就有，本段只读呈现、不再造数据）。
/// gate 三态诚实呈现（未启用/通道未接通/已启用），
/// 裸空列表冒充「无待批」是红线：只有桥可达＋闸门开
/// ＋pending 为空才是真无待批（状态判定在
/// AgentHubStore.loadApproval 与 Core 的
/// ApprovalSectionState）。桥 /status 已上线（两闸门
/// true、counts 实时），本段直接消费。
struct HubApprovalSection: View {
    let store: AgentHubStore

    @Environment(AppState.self) private var appState
    /// 通知落点聚焦的已决记录 id（§123 H2）：通知中心
    /// 点审批回执达本段时置位，本段消费后滚动定位＋
    /// 行底色点亮，消费即清 AppState 字段防复活
    @State private var focusDecisionID: String?

    @State private var diffTarget: WriteGateRecord?
    @State private var rejectTarget: WriteGateRecord?
    @State private var alwaysTarget: WriteGateRecord?
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
                    Text("写入审批的通道还没接通，暂时看不到待批写入。")
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
                    Text("开启后，记忆与技能的写入会在这里等你批准。")
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("读取失败", systemImage: "exclamationmark.triangle")
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
                        "暂无待批写入",
                        systemImage: "checkmark.circle",
                        description: Text("记忆与技能的写入会先到这里等你批准")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            if !records.isEmpty {
                                Section("待审批") {
                                    ForEach(records) { record in
                                        card(record)
                                    }
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
            "驳回这条写入？",
            isPresented: Binding(
                get: { rejectTarget != nil },
                set: { if !$0 { rejectTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: rejectTarget
        ) { record in
            Button("驳回", role: .destructive) {
                Task { await store.decide(record, approve: false) }
                rejectTarget = nil
            }
            Button("取消", role: .cancel) {
                rejectTarget = nil
            }
        } message: { _ in
            Text("驳回后这条写入不会生效。")
        }
        .confirmationDialog(
            "总是允许这一类？",
            isPresented: Binding(
                get: { alwaysTarget != nil },
                set: { if !$0 { alwaysTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: alwaysTarget
        ) { record in
            Button("总是允许") {
                Task { await store.decideAlways(record) }
                alwaysTarget = nil
            }
            Button("取消", role: .cancel) {
                alwaysTarget = nil
            }
        } message: { record in
            Text("这条会立即批准；以后「\(ApprovalCardCopy.alwaysAllowScope(for: record))」的写入将直接通过，不再逐条询问。规则可以在下方「审批规则」里随时撤销。")
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

    /// 待批卡片（实色面内容卡，非玻璃——规格 §0 材质总则）
    private func card(_ record: WriteGateRecord) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
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

            Text(record.headline)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if let preview = record.previewLine, preview != record.headline {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }

            Text("来源：\(record.originLabel)")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)

            if let note = store.cardNotes[record.id] {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
            }

            if store.decidingIDs.contains(record.id) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在提交裁决…")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Button("查看改动") {
                        diffTarget = record
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if record.canDecide {
                        Button("驳回") {
                            rejectTarget = record
                        }
                        .buttonStyle(.bordered)
                        Button("批准") {
                            Task { await store.decide(record, approve: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("这类写入暂不支持在 App 内审批，请在 Hermes 中处理")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if record.canDecide {
                    // 第三档（0.36.21）：全宽一行，与聊
                    // 天就地卡同动作（store.decideAlways：
                    // 先建规则后批准，失败不假装记住）
                    Button("总是允许这一类") {
                        alwaysTarget = record
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(OneDayMetrics.spacingM)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
                    // 人工批准分开呈现，账本 via_rule 是据
                    Text("按规则放行")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, OneDayMetrics.stackGap)
                        .background(
                            Palette.primaryTint, in: Capsule()
                        )
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
                    ? "暂无规则。在待批卡上点「总是允许这一类」后，会在这里留下一条，可随时撤销。"
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
                    "改动读取失败",
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
                errorText = "通道未接通或读取出错，请稍后重试。"
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
