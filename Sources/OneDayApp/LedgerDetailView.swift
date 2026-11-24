import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 台账条目详情（下钻）：事件时间线全流水＋失败证
/// 据＋子计数。进页拉详情面（列表快照先顶着渲染，
/// history 只在详情面有），记录已不在如实露。
/// §475（2026-11-24 用户裁）：本页按任务详情卡形态
/// 重做——页首人话标题＋状态 chip＋一句话摘要，概
/// 况只留人话字段；原始枚举（状态/类别/来源原文、
/// 记账/标题来源、条目编号）整段撤出用户面，旧
/// 「技术信息区是原文唯一的家」口径就此作废，排障
/// 原文归设置诊断领地（ChatDiagnosticsView 一带）。
/// §217（枢纽收段）：任务/审批条目在本页续行下钻
/// ——任务条目补「打开任务详情」（答题/证据/评论/
/// 控制动作的家），审批条目补记录原文＋只读「查
/// 看改动」＋「查看原对话」锚点（§165 同解析）；
/// 审批仍只在聊天界面裁决（§155），本页只有记录
/// 与去向、没有任何裁决入口。
struct LedgerDetailView: View {
    var store: LedgerStore
    /// 列表快照行（详情回执到达前先以它渲染）
    let item: LedgerItem
    /// 枢纽共享审批 store（审批条目补齐的数据源）
    let hubStore: AgentHubStore
    /// 任务数据面（任务详情下钻的动作执行者）
    let kanbanStore: KanbanStore
    var onOpenSession: (String) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// 审批记录的只读改动查看（与聊天卡同一 HubDiffView）
    @State private var diffTarget: WriteGateRecord?

    /// 详情回执（id 对得上才用）优先，缺失回落列表快照
    private var current: LedgerItem {
        if let detail = store.detail, detail.id == item.id {
            return detail
        }
        return item
    }

    private var sessionTarget: String? {
        if let link = current.link, link.kind == "session",
           !link.targetId.isEmpty {
            return link.targetId
        }
        return current.sessionId
    }

    var body: some View {
        List {
            headerSection
            overviewSection
            if current.toolCalls != nil || current.subTasks != nil {
                countsSection
            }
            if let reason = current.failReason {
                failSection(reason)
            }
            if let target = sessionTarget {
                Section {
                    Button {
                        onOpenSession(target)
                    } label: {
                        // §344（图标底色块）：下钻入口
                        // 行补统一 IconTile（旧版裸
                        // Label 字形无砖无底）
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            IconTile(symbol: "bubble.left")
                            Text("打开会话")
                        }
                    }
                }
            }
            if current.kind == .kanban {
                kanbanSection
            }
            if current.kind == .approval {
                approvalSection
            }
            historySection
        }
        .listStyle(.plain)
        .navigationTitle("工作详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 监测条目不走台账详情面：它的详情本体是
            // 监测详情（枢纽行下钻直达），本页只服务
            // 工作条目（按 id 契约识别，见
            // LedgerMonitorChange）
            if !LedgerMonitorChange.isMonitorChange(itemID: item.id) {
                await store.loadDetail(appState: appState, id: item.id)
            }
        }
        .sheet(item: $diffTarget) { record in
            NavigationStack {
                HubDiffView(store: hubStore, record: record)
            }
        }
    }

    // MARK: - §217 续行下钻（任务/审批）

    /// 任务条目的本体在任务详情里（说明/答题/结果/
    /// 证据/评论/附件/控制动作）——台账只记流水，
    /// 本节给一步直达，与原任务段的行点达同落点
    @ViewBuilder
    private var kanbanSection: some View {
        if let taskID = current.link?.targetId, !taskID.isEmpty {
            Section {
                NavigationLink {
                    KanbanTaskDetailView(
                        store: kanbanStore, taskID: taskID
                    )
                } label: {
                    // §344（图标底色块）：同「打开会话」
                    // 行，补统一 IconTile
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        IconTile(symbol: "checklist")
                        Text("打开任务详情")
                    }
                }
            }
        }
    }

    /// 审批条目对应的待批记录（台账 link 指回记录
    /// id；只认已载的待批集，与采集器的 appr: 条目
    /// 同 id 空间）
    private var pendingRecord: WriteGateRecord? {
        guard let recordID = current.link?.targetId,
              case .ready(let records) = hubStore.approvalState
        else { return nil }
        return records.first { $0.id == recordID }
    }

    /// 审批条目对应的已决记录（§259：读
    /// AgentHubStore.decidedRecords 单源合成面，
    /// View 不自拼两窗）
    private var decidedRecord: WriteGateDecisionRecord? {
        guard let recordID = current.link?.targetId else {
            return nil
        }
        return hubStore.decidedRecords.first { $0.id == recordID }
    }

    /// 审批记录节（§155 记录制）：待批给记录原文
    /// （问句/说明，与聊天卡同源人话）＋只读改动查
    /// 看；已决给结论与来源。两态都补「查看原对
    /// 话」（§165 锚点：有锚且本机有线程才出钮，
    /// 无锚不出、不假定位）。记录不在已载集里时整
    /// 节不出——台账本体信息在上方各节已齐，不拿
    /// 半截记录冒充
    @ViewBuilder
    private var approvalSection: some View {
        if let record = pendingRecord {
            Section("审批记录") {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                    Text(ApprovalCardCopy.question(for: record))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(ApprovalCardCopy.summaryLine(for: record))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
                Button("查看改动") {
                    diffTarget = record
                }
                if let request = anchorRequest(
                    subsystem: record.subsystem, recordID: record.id,
                    anchorSessionID: record.anchor?.sessionId
                ) {
                    Button("查看原对话") {
                        goToAnchor(request)
                    }
                }
            }
        } else if let decision = decidedRecord {
            Section("审批记录") {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(decision.decisionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                decision.isApproved
                                    ? Palette.successText
                                    : decision.isRejected
                                        ? Palette.danger
                                        : Palette.inkSecondary
                            )
                        if decision.isRuleApproved {
                            Text("按规则放行")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    Text(decision.headline)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    Text("来源：\(decision.originText)")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
                if let request = anchorRequest(
                    subsystem: decision.subsystem,
                    recordID: decision.id,
                    anchorSessionID: decision.anchor?.sessionId
                ) {
                    Button("查看原对话") {
                        goToAnchor(request)
                    }
                }
            }
        }
    }

    /// §165 锚点解析（与原审核段同一套：本机线程表
    /// 现扫＋Core 解析），无落点返回 nil
    private func anchorRequest(
        subsystem: WriteGateSubsystem, recordID: String,
        anchorSessionID: String?
    ) -> (threadID: UUID, approvalKey: String?)? {
        let threads = (try? modelContext.fetch(
            FetchDescriptor<ChatThread>()
        )) ?? []
        return ApprovalAnchorSupport.anchorRequest(
            index: ApprovalAnchorSupport.index(threads: threads),
            subsystem: subsystem, recordID: recordID,
            anchorSessionID: anchorSessionID
        )
    }

    /// 点达执行：落点落 AppState 后关枢纽回聊天格
    /// （ChatView 消费请求切线程定位，与原审核段同）
    private func goToAnchor(
        _ request: (threadID: UUID, approvalKey: String?)
    ) {
        appState.router.approvalAnchorRequest = (
            request.threadID, request.approvalKey
        )
        dismiss()
    }

    // MARK: - 段

    /// 页首卡（§475，对 Muse 任务详情卡形态）：人话
    /// 标题＋状态 chip＋一句话摘要，三件齐；不再用
    /// 「状态词 · 来源词」的字段拼接行冒充摘要
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                Text(current.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                statusChip
                if current.status.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let summary = LedgerBoard.detailSummary(
                            for: current,
                            serverNow: store.displayServerNow(
                                at: context.date
                            )
                        ) {
                            Text(summary)
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                } else if let summary = LedgerBoard.detailSummary(
                    for: current, serverNow: store.serverNow
                ) {
                    Text(summary)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkSecondary)
                }
                if current.isReconciled {
                    Text("这条是后来补记的：它开始的时候，台账还没记上。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingMicro)
            .listRowSeparator(.hidden)
        }
    }

    /// 状态 chip：状态词只走 LedgerText.statusWord
    /// 单源，原文枚举不出本页（§475）
    private var statusChip: some View {
        HStack(spacing: OneDayMetrics.spacingMicro) {
            Circle()
                .fill(statusTint)
                .frame(width: 7, height: 7)
            Text(LedgerText.statusWord(current.status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTint)
        }
        .padding(.horizontal, OneDayMetrics.spacingS)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Palette.fillSecondary)
        )
    }

    private var statusTint: Color {
        switch current.status {
        case .completed: return Palette.successText
        case .failed: return Palette.danger
        case .running, .queued, .blockedApproval: return Palette.primary
        case .cancelled, .stale, .other: return Palette.inkSecondary
        }
    }

    /// 概况（§475）：只留人话字段——来源、开始、结束
    /// 与用时；「最后确认」只在失联待核时有意义（它
    /// 就是失联的判据），其余状态不占行
    private var overviewSection: some View {
        Section("概况") {
            row("来源", LedgerText.sourceWord(current.source))
            row(
                "开始",
                DisplayDate.dateTime(
                    Date(timeIntervalSince1970: current.startedAt)
                )
            )
            if let ended = current.endedAt {
                row(
                    "结束",
                    DisplayDate.dateTime(
                        Date(timeIntervalSince1970: ended)
                    )
                )
            }
            if current.status == .stale,
               let evidence = current.lastEvidenceAt {
                row(
                    "最后确认",
                    DisplayDate.dateTime(
                        Date(timeIntervalSince1970: evidence)
                    )
                )
            }
            // 活跃态的已运行时长在页首摘要里逐秒走，
            // 本节不重复占行；终态在此给总用时
            if !current.status.isActive,
               let text = LedgerBoard.durationText(
                   for: current, serverNow: store.serverNow
               ) {
                row("用时", text)
            }
        }
    }

    private var countsSection: some View {
        Section("工作量") {
            if let calls = current.toolCalls {
                row("工具调用", "\(calls) 次")
            }
            if let subs = current.subTasks {
                row("子任务", "\(subs) 个")
            }
        }
    }

    private func failSection(
        _ reason: LedgerFailReason
    ) -> some View {
        Section("原因") {
            row("分类", reason.category)
            if let excerpt = reason.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section("事件时间线") {
            if store.detailGone {
                Text("这条记录已不在，时间线读不到。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            } else if store.detail?.id == item.id {
                if current.history.isEmpty {
                    ContentUnavailableView {
                        Label("暂无流转记录。", systemImage: "clock")
                    }
                } else {
                    ForEach(
                        Array(current.history.enumerated()),
                        id: \.offset
                    ) { _, entry in
                        historyRow(entry)
                    }
                }
            } else if store.detailLoading {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView().controlSize(.small)
                    Text("正在读取时间线…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else {
                Text("时间线暂时读不到。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func historyRow(_ entry: LedgerHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            HStack(spacing: OneDayMetrics.spacingS) {
                NumberText(
                    LedgerClock.timeWithSeconds(entry.at), font: .footnote
                )
                .foregroundStyle(Palette.inkSecondary)
                Text(transitionText(entry))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(LedgerText.actorWord(entry.by))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if entry.corrected {
                tag("已纠正")
            } else if entry.conflict {
                tag("证据有冲突 · 保持原判")
            }
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.vertical, 1)
    }

    private func transitionText(_ entry: LedgerHistoryEntry) -> String {
        let to = LedgerText.statusWord(
            LedgerStatus(rawValue: entry.to)
        )
        guard let from = entry.from else { return "开始 · \(to)" }
        return "\(LedgerText.statusWord(LedgerStatus(rawValue: from))) → \(to)"
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.inkSecondary)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}
