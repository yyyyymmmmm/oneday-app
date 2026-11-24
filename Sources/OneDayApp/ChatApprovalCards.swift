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
    /// 已落锚记录的排除集（§165，规格 §4.3 单源）：这
    /// 些记录由其锚定行承载（含已决行形态），本区不
    /// 再重复出卡/出行；默认空集＝现行行为（预制合并
    /// 前的调用点零影响）
    var anchoredRecordIDs: Set<String> = []
    /// §329 行状态账本：透传给就地卡（详情四态上
    /// 提、合成器可见）；不传＝卡内 @State 原行为
    var ledger: ChatRowStateLedger? = nil

    var body: some View {
        if case .ready(let records) = store.approvalState {
            // D10 定版②（一次只活一张）：未锚待批
            // 只出桥序第一条活卡，其余收成计数行；
            // 派生走 Core ApprovalZoneQueue 单源，
            // 与行高合成/facet 摘要同口径。锚定行
            // 不入此口径（§165 自承载、主线裁定豁免）
            let queue = ApprovalZoneQueue.derive(
                recordIDs: records.map(\.id),
                anchoredIDs: anchoredRecordIDs
            )
            let unanchoredResolved = store.resolvedLines.filter {
                !anchoredRecordIDs.contains($0.id)
            }
            VStack(spacing: OneDayMetrics.spacingS) {
                if let toast = store.alwaysAllowToast {
                    alwaysAllowToastRow(toast)
                }
                if let activeID = queue.activeRecordID,
                   let record = records.first(
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
                } else if !unanchoredResolved.isEmpty {
                    resolvedSummaryRow(unanchoredResolved)
                }
            }
        }
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
