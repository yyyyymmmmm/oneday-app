import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 台账条目详情（下钻）：事件时间线全流水＋失败证
/// 据＋子计数；原始枚举只许出现在本页「技术信息」
/// 区（宪法口径：列表面零行话，排障原文有唯一的
/// 家）。进页拉详情面（列表快照先顶着渲染，history
/// 只在详情面有），记录已不在如实露。
/// §208（枢纽收段）：任务/审批条目在本页续行下钻
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
                        Label("打开会话", systemImage: "bubble.left")
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
            technicalSection
        }
        .listStyle(.plain)
        .navigationTitle("工作详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 监测合成条目在服务端没有详情面，不许拿
            // 合成 id 去拉（会误报「记录已不在」）
            if !LedgerMonitorSynthesis.isSynthetic(itemID: item.id) {
                await store.loadDetail(appState: appState, id: item.id)
            }
        }
        .sheet(item: $diffTarget) { record in
            NavigationStack {
                HubDiffView(store: hubStore, record: record)
            }
        }
    }

    // MARK: - §208 续行下钻（任务/审批）

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
                    Label("打开任务详情", systemImage: "checklist")
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

    /// 审批条目对应的已决记录（已载历史＋锚点宽账
    /// 本，与 AgentHubStore 自家组账同式）
    private var decidedRecord: WriteGateDecisionRecord? {
        guard let recordID = current.link?.targetId else {
            return nil
        }
        let all = hubStore.decisionHistory
            + (hubStore.anchorDecisions ?? [])
        return all.first { $0.id == recordID }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(ApprovalCardCopy.question(for: record))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(ApprovalCardCopy.summaryLine(for: record))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(decision.decisionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                decision.isApproved
                                    ? Palette.success
                                    : decision.isRejected
                                        ? Palette.danger
                                        : Palette.inkMuted
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
                .padding(.vertical, 4)
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
        appState.approvalAnchorRequest = (
            request.threadID, request.approvalKey
        )
        dismiss()
    }

    // MARK: - 段

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(current.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(
                    "\(LedgerText.statusWord(current.status)) · \(LedgerText.sourceWord(current.source))"
                )
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                if current.isReconciled {
                    Text("这条是对账时补记的：它开始时台账还没记上。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingMicro)
            .listRowSeparator(.hidden)
        }
    }

    private var overviewSection: some View {
        Section("概况") {
            row("类别", LedgerText.kindWord(current.kind))
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
            if let evidence = current.lastEvidenceAt {
                row(
                    "最后确认",
                    DisplayDate.dateTime(
                        Date(timeIntervalSince1970: evidence)
                    )
                )
            }
            if current.status.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let text = LedgerBoard.durationText(
                        for: current,
                        serverNow: store.displayServerNow(
                            at: context.date
                        )
                    ) {
                        row("已耗时", text)
                    }
                }
            } else if let text = LedgerBoard.durationText(
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
                    Text("暂无流转记录。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
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
                Text(
                    LedgerClock.timeWithSeconds(entry.at)
                )
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Palette.inkMuted)
                Text(transitionText(entry))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(LedgerText.actorWord(entry.by))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
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
            .foregroundStyle(Palette.inkMuted)
    }

    /// 技术信息：原始枚举与编号只进本区（排障用），
    /// 列表面不露
    private var technicalSection: some View {
        Section("技术信息") {
            row("状态原文", current.status.rawValue)
            row("类别原文", current.kind.rawValue)
            row("来源原文", current.source.rawValue)
            row("记账来源", LedgerText.originWord(current.origin))
            row("标题来源", LedgerText.titleSourceWord(current.titleSource))
            row("条目编号", current.id)
            if let session = current.sessionId {
                row("会话编号", session)
            }
            if let run = current.runId {
                row("运行编号", run)
            }
            if let by = current.correctedBy {
                row("纠正者", by)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}
