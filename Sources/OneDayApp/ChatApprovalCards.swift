import OneDayCore
import OneDayDesign
import SwiftUI

/// 对话流就地审批（0.36.21，规格 approval-card-design
/// §1/§2/§6）：待批写入不再只躺在枢纽——用户正在看的
/// 对话流末尾就地出卡，问完、批完，不用先跑去枢纽页。
///
/// 数据前提（§3 已实查定案）：桥 /pending 载荷没有
/// 会话归属字段（WriteGateRecord 与桥 _norm_record 均
/// 无 thread/session 字段），故走退位形态——全部未决
/// 记录汇到当前对话流末尾＋枢纽保留总账兜底。
///
/// 呈现层纪律（与回告卡同源，0.7.0 红线 D4 先例）：
/// 卡片只在呈现层拼装、绝不写进会话消息；store 用
/// AppState 共享的 AgentHubStore（与枢纽同一份数据、
/// 同一裁决路径）；仅 ready 态渲染——未接通/未启用/
/// 失败态不在聊天里闹，用户在枢纽看得到真实状态。
struct ChatApprovalZone: View {
    let store: AgentHubStore
    /// 当前对话已落锚记录的排除集（§165，规格 §4.3 单源）：只排除
    /// 当前对话流里已经锚定展示的记录，防止他会话锚定把待批吞掉
    var anchoredRecordIDs: Set<String> = []
    /// 当前对话的服务端会话 ID：用于区分「当前对话内联卡片」
    /// 与「其他对话的紧凑审核提示条」
    var currentServerSessionID: String? = nil
    /// §329 行状态账本：透传给就地卡（详情四态上
    /// 提、合成器可见）；不传＝卡内 @State 原行为
    var ledger: ChatRowStateLedger? = nil
    /// 点击他会话「审核」提示条按钮时打开底部半屏审核卡
    var onOpenOtherThreadSheet: (() -> Void)? = nil

    private static func splitPending(
        records: [WriteGateRecord],
        anchoredIDs: Set<String>,
        currentServerSessionID: String?
    ) -> (current: [WriteGateRecord], other: [WriteGateRecord]) {
        var current: [WriteGateRecord] = []
        var other: [WriteGateRecord] = []
        for record in records {
            if !record.appliesToChat(sessionID: currentServerSessionID) {
                other.append(record)
            } else if !anchoredIDs.contains(record.id) {
                current.append(record)
            }
        }
        return (current, other)
    }

    /// 审批区当前是否有可见内容（供底栏按需挂载，避免空态白占间距）
    @MainActor
    static func hasVisibleContent(
        store: AgentHubStore,
        anchoredRecordIDs: Set<String>,
        currentServerSessionID: String? = nil
    ) -> Bool {
        guard case .ready(let records) = store.approvalState else {
            return false
        }
        if store.alwaysAllowToast != nil { return true }
        let split = splitPending(
            records: records,
            anchoredIDs: anchoredRecordIDs,
            currentServerSessionID: currentServerSessionID
        )
        if !split.current.isEmpty || !split.other.isEmpty {
            return true
        }
        return store.resolvedLines.contains {
            !anchoredRecordIDs.contains($0.id)
        }
    }

    var body: some View {
        if case .ready(let records) = store.approvalState {
            let split = Self.splitPending(
                records: records,
                anchoredIDs: anchoredRecordIDs,
                currentServerSessionID: currentServerSessionID
            )
            let queue = ApprovalZoneQueue.derive(
                recordIDs: split.current.map(\.id),
                anchoredIDs: []
            )
            let unanchoredResolved = store.resolvedLines.filter {
                !anchoredRecordIDs.contains($0.id)
            }
            VStack(spacing: OneDayMetrics.spacingS) {
                if let toast = store.alwaysAllowToast {
                    alwaysAllowToastRow(toast)
                }
                if let activeID = queue.activeRecordID,
                   let record = split.current.first(
                       where: { $0.id == activeID }
                   ) {
                    let progressText: String? = queue.queuedCount > 0
                        ? L10n.format(
                            "待批 1/%lld",
                            Int64(queue.queuedCount + 1)
                        )
                        : nil
                    ChatApprovalCard(
                        store: store,
                        record: record,
                        queueProgress: progressText,
                        ledger: ledger
                    )
                } else if !split.other.isEmpty {
                    otherThreadPromptBar(count: split.other.count)
                } else if !unanchoredResolved.isEmpty {
                    resolvedSummaryRow(unanchoredResolved)
                }
            }
        }
    }

    private func otherThreadPromptBar(count: Int) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Text(
                count == 1
                    ? "一项任务需要审核"
                    : "\(count) 项任务需要审核"
            )
            .font(.subheadline)
            .foregroundStyle(Palette.inkSecondary)
            .lineLimit(1)
            Spacer(minLength: OneDayMetrics.spacingS)
            Button("审核") {
                onOpenOtherThreadSheet?()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.primary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(height: 44)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
    }

    /// 「总是允许」一次点按后的轻量可撤销通知（5 秒自动消失）
    private func alwaysAllowToastRow(
        _ toast: AgentHubStore.AlwaysAllowToast
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
            Text(L10n.format("已允许并记住（%@）", toast.scopeLabel))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            Button("撤销") {
                Task { await store.undoAlwaysAllowToast() }
            }
            .buttonStyle(.plain)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.primary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
    }

    /// 全部批完后的静态普通回执行（非卡，不堆叠已决行）
    private func resolvedSummaryRow(
        _ lines: [ApprovalResolvedLine]
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            if lines.count == 1, let only = lines.first {
                Image(systemName: only.outcome.isPositive
                    ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(only.outcome.isPositive
                        ? Palette.success : Palette.danger)
                Text(only.summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Text("·")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
                Text(only.outcome.label)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.success)
                Text(L10n.format("已处理 %lld 项", Int64(lines.count)))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, OneDayMetrics.spacingXS)
    }
}

/// 单张就地审批卡：卡面本体走共用组件
/// ApprovalCardFace（样式二期 S2-01/02/03，与枢纽待
/// 批卡同一实现、同一几何与句式）；本宿主只持有卡
/// 体外框与详情的就地展开（SmoothExpand）。卡面零原
/// 始 JSON、零英文运维串（宪法 §8）；材质与枢纽卡
/// 同为实色面内容卡（Palette.surface），与玻璃消息
/// 面分工一致。
/// §165 起两个宿主共用：流末尾区（ChatApprovalZone）
/// 与锚定行（ChatView.approvalAnchorRow）——同一张
/// 卡、同一裁决路径，落位不同而已
struct ChatApprovalCard: View {
    let store: AgentHubStore
    let record: WriteGateRecord
    /// 多条排队时的进度文案（如「待批 1/3」），单条为 nil
    var queueProgress: String? = nil
    /// §329 行状态账本（聊天列表面传入）：详情四
    /// 态（展开/详情/错误/加载中）改存账本——详情
    /// 区高度对行高合成器可见（.absolute 回喂）；
    /// 无账本环境回落本地 @State、四态语义逐字不
    /// 变
    var ledger: ChatRowStateLedger? = nil

    @State private var localDetail: WriteGateDetail?
    @State private var localDetailError: String?
    @State private var localDetailExpanded = false
    @State private var localDetailLoading = false

    private var detail: WriteGateDetail? {
        if let ledger {
            return ledger.approvalDetail(
                for: record.id
            ).detail
        }
        return localDetail
    }

    private var detailError: String? {
        if let ledger {
            return ledger.approvalDetail(
                for: record.id
            ).error
        }
        return localDetailError
    }

    private var detailExpanded: Bool {
        if let ledger {
            return ledger.approvalDetail(
                for: record.id
            ).expanded
        }
        return localDetailExpanded
    }

    private var detailLoading: Bool {
        if let ledger {
            return ledger.approvalDetail(
                for: record.id
            ).loading
        }
        return localDetailLoading
    }

    private func setDetail(_ value: WriteGateDetail?) {
        if let ledger {
            ledger.updateApprovalDetail(record.id) {
                $0.detail = value
            }
        } else {
            localDetail = value
        }
    }

    private func setDetailError(_ value: String?) {
        if let ledger {
            ledger.updateApprovalDetail(record.id) {
                $0.error = value
            }
        } else {
            localDetailError = value
        }
    }

    private func setDetailExpanded(_ value: Bool) {
        if let ledger {
            ledger.updateApprovalDetail(record.id) {
                $0.expanded = value
            }
        } else {
            localDetailExpanded = value
        }
    }

    private func setDetailLoading(_ value: Bool) {
        if let ledger {
            ledger.updateApprovalDetail(record.id) {
                $0.loading = value
            }
        } else {
            localDetailLoading = value
        }
    }

    var body: some View {
        ApprovalCardFace(
            record: record,
            isDeciding: store.decidingIDs.contains(record.id),
            note: store.cardNotes[record.id],
            queueProgress: queueProgress,
            detailLinkTitle: detailExpanded ? "收起详情" : "查看详情",
            onDetail: toggleDetail,
            onAction: handleAction
        ) {
            SmoothExpand(isExpanded: detailExpanded) {
                detailArea
            }
        }
        .padding(OneDayMetrics.spacingM)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
    }

    /// 详情展开区：按需拉桥 detail，内容与枢纽 sheet
    /// 同一份（ApprovalReviewContent）；拉不到如实报
    /// 错、不拿空内容冒充。
    /// §165（任务第 3 件，用户既定修订）：「收起」控
    /// 件随展开内容落位——内容（或错误行）下方再给一
    /// 只收起钮，长内容不必滚回卡顶才收得起；折叠态
    /// 与加载态不出现本钮
    @ViewBuilder
    private var detailArea: some View {
        if detailLoading {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在读取改动…")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else if let detail {
            ScrollView {
                ApprovalReviewContent(
                    detail: detail, record: record, embedded: true
                )
            }
            .frame(maxHeight: 260)
            .padding(.top, OneDayMetrics.spacingS)
            collapseButtonRow
        } else if let detailError {
            Text(detailError)
                .font(.caption)
                .foregroundStyle(Palette.danger)
            collapseButtonRow
        }
    }

    /// 展开内容下方的收起钮（§165）：与卡面顶部详情链
    /// 同一动作（toggleDetail 的收起路），形态沿卡面
    /// 链句式（subheadline＋主题色），不新造视觉件
    private var collapseButtonRow: some View {
        HStack {
            Spacer()
            Button("收起") {
                toggleDetail()
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(Palette.primary)
        }
        .padding(.top, OneDayMetrics.spacingS)
    }

    /// 三档裁决出口：全部一次点按直接提交（总是允许
    /// 落定后出带「撤销」的轻量通知，不弹二次确认框）
    private func handleAction(_ action: ApprovalCardAction) {
        switch action {
        case .approve:
            Task { await store.decide(record, approve: true) }
        case .alwaysAllow:
            Task { await store.decideAlways(record) }
        case .reject:
            Task { await store.decide(record, approve: false) }
        }
    }

    private func toggleDetail() {
        if detailExpanded {
            setDetailExpanded(false)
            return
        }
        setDetailExpanded(true)
        guard detail == nil, !detailLoading else { return }
        setDetailLoading(true)
        setDetailError(nil)
        Task {
            switch await store.loadDetail(record) {
            case .success(let loaded):
                setDetail(loaded)
            case .failure(.recordGone):
                setDetailError("这条待批已被处理或已失效。")
            case .failure:
                setDetailError("改动没读出来，可能是网络或服务暂时没响应")
            }
            setDetailLoading(false)
        }
    }
}

/// 他会话待审核底部半屏弹窗（对标图三：点「审核」后弹出完整审核卡，不切走当前对话）
struct PendingApprovalSheetView: View {
    let store: AgentHubStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OneDayMetrics.spacingM) {
                    if case .ready(let records) = store.approvalState,
                       !records.isEmpty {
                        ForEach(records) { record in
                            ChatApprovalCard(
                                store: store,
                                record: record
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "暂无待审核任务",
                            systemImage: "checkmark.seal",
                            description: Text("所有请求均已处理完毕。")
                        )
                        .padding(.top, OneDayMetrics.spacingXL)
                    }
                }
                .padding(OneDayMetrics.pageGutter)
            }
            .background(Palette.settingsBG)
            .navigationTitle("待审核任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: store.hasPendingApprovals) { _, hasPending in
            if !hasPending {
                dismiss()
            }
        }
    }
}
