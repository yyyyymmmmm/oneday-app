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
/// 步骤卡改造（2026-11-28 皇上亲点）：整页收成
/// 一张卡——卡首（标题＋chip＋成果句）＋步骤清单
/// （history 变迁派生，LedgerBoard.steps）＋卡底
/// 元数据一行小字；旧概况节／工作量节／事件时间
/// 线节并入卡内，信息一件不少、重复全删。
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
            cardSection
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
            .fullscreenPopBridge()
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

    /// 详情主卡（Muse 式步骤卡，2026-11-28 皇上亲
    /// 点改造）：整页信息收进一张卡——卡首标题＋状
    /// 态 chip＋成果句（§475／270 的 detailSummary
    /// 口径不变），中段步骤清单（LedgerBoard.steps
    /// 由 history 变迁派生，真实数据、无步不编），
    /// 卡底把概况与工作量压成一行小字；旧「概况」节
    /// 与「事件时间线」节就此并入本卡，不再分节重复
    private var cardSection: some View {
        Section {
            Group {
                if current.status.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        cardContent(
                            serverNow: store.displayServerNow(
                                at: context.date
                            )
                        )
                    }
                } else {
                    cardContent(serverNow: store.serverNow)
                }
            }
            .listRowInsets(
                EdgeInsets(
                    top: OneDayMetrics.spacingS,
                    leading: OneDayMetrics.spacingSM,
                    bottom: OneDayMetrics.spacingS,
                    trailing: OneDayMetrics.spacingSM
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func cardContent(serverNow: Double) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingS
            ) {
                Text(current.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                statusChip
                if let summary = LedgerBoard.detailSummary(
                    for: current, serverNow: serverNow
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
            Divider()
            stepsBlock(serverNow: serverNow)
            if let reason = current.failReason {
                Divider()
                failBlock(reason)
            }
            Divider()
            metaLine(serverNow: serverNow)
        }
        .padding(OneDayMetrics.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusCard,
                style: .continuous
            )
            .fill(Palette.surface)
        )
    }

    /// 步骤区：详情未到／已删／空流水各如实露（与旧
    /// 时间线节同四态），不拿列表快照的空 history
    /// 冒充「没有步骤」
    @ViewBuilder
    private func stepsBlock(serverNow: Double) -> some View {
        if store.detailGone {
            Text("这条记录已不在，步骤读不到。")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
        } else if store.detail?.id == item.id {
            let steps = LedgerBoard.steps(
                for: current, serverNow: serverNow
            )
            if steps.isEmpty {
                Text("暂无流转记录。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { step in
                        stepRow(
                            step,
                            isLast: step.index == steps.count - 1
                        )
                    }
                }
            }
        } else if store.detailLoading {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView().controlSize(.small)
                Text("正在读取步骤…")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else {
            Text("步骤暂时读不到。")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    /// 步骤一行：状态图标＋竖线串联（末步无线）、步
    /// 名（当前步加重）、右侧步时；步长与记录者收副
    /// 行小字，变迁注记与对账留痕照旧时间线口径
    private func stepRow(
        _ step: LedgerStep, isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            VStack(spacing: 0) {
                stepIcon(step.phase)
                if !isLast {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Text(step.title)
                        .font(
                            .subheadline.weight(
                                step.phase == .current
                                    ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    NumberText(
                        LedgerClock.timeWithSeconds(step.at),
                        font: .caption
                    )
                    .foregroundStyle(Palette.inkSecondary)
                }
                if let subline = stepSubline(step) {
                    Text(subline)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkSecondary)
                }
                if step.corrected {
                    tag("已纠正")
                } else if step.conflict {
                    tag("证据有冲突 · 保持原判")
                }
                if let note = step.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.bottom, isLast ? 0 : OneDayMetrics.spacingSM)
        }
    }

    /// 步副行：步长（有才显）＋记录者人话，两件都缺
    /// 时整行不显
    private func stepSubline(_ step: LedgerStep) -> String? {
        var parts: [String] = []
        if let duration = step.duration {
            parts.append(
                "用时 \(LedgerElapsed.format(seconds: duration))"
            )
        }
        parts.append(step.actorWord)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 步相位图标：走完打勾、失败叉、取消减、失联
    /// 叹号（皆现行 Palette 语义色）；当前步＝主色
    /// 环＋实心点（进行中高亮，不用灰阶假装未到）
    @ViewBuilder
    private func stepIcon(_ phase: LedgerStepPhase) -> some View {
        switch phase {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Palette.successText)
                .frame(width: 20, height: 20)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .foregroundStyle(Palette.danger)
                .frame(width: 20, height: 20)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 20, height: 20)
        case .stale:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 20, height: 20)
        case .current:
            ZStack {
                Circle()
                    .strokeBorder(Palette.primary, lineWidth: 2)
                Circle()
                    .fill(Palette.primary)
                    .padding(5)
            }
            .frame(width: 18, height: 18)
            .frame(width: 20, height: 20)
        }
    }

    /// 失败块（卡内）：分类＋原始摘录，与旧「原因」
    /// 节同内容、收进卡里紧跟步骤
    private func failBlock(_ reason: LedgerFailReason) -> some View {
        VStack(
            alignment: .leading, spacing: OneDayMetrics.spacingXS
        ) {
            Text("失败原因 · \(reason.category)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.danger)
            if let excerpt = reason.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// 卡底元数据一行小字：来源／开始／结束／用时
    /// （终态）／最后确认（失联时）／工具调用／子任
    /// 务——旧概况节与工作量节的全部字段压到这一行，
    /// 缺哪件省哪件，不单开节、不重复页首摘要
    private func metaLine(serverNow: Double) -> some View {
        var parts: [String] = []
        parts.append("来源 \(LedgerText.sourceWord(current.source))")
        parts.append(
            "开始 \(DisplayDate.dateTime(Date(timeIntervalSince1970: current.startedAt)))"
        )
        if let ended = current.endedAt {
            parts.append(
                "结束 \(DisplayDate.dateTime(Date(timeIntervalSince1970: ended)))"
            )
        }
        if !current.status.isActive,
           let duration = LedgerBoard.durationText(
               for: current, serverNow: serverNow
           ) {
            parts.append(duration)
        }
        if current.status == .stale,
           let evidence = current.lastEvidenceAt {
            parts.append(
                "最后确认 \(DisplayDate.dateTime(Date(timeIntervalSince1970: evidence)))"
            )
        }
        if let calls = current.toolCalls {
            parts.append("工具调用 \(calls) 次")
        }
        if let subs = current.subTasks {
            parts.append("子任务 \(subs) 个")
        }
        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Palette.inkSecondary)
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

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.inkSecondary)
    }

}
