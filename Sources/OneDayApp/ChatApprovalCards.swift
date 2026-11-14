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

    var body: some View {
        if case .ready(let records) = store.approvalState {
            VStack(spacing: OneDayMetrics.spacingM) {
                ForEach(records) { record in
                    if !anchoredRecordIDs.contains(record.id) {
                        ChatApprovalCard(store: store, record: record)
                    }
                }
                ForEach(store.resolvedLines) { line in
                    if !anchoredRecordIDs.contains(line.id) {
                        resolvedRow(line)
                    }
                }
            }
        }
    }

    /// 裁决结果行：卡收起后的原地痕迹——结论图标＋标
    /// 题＋结果措辞；带走由下一轮新卡顶上（上限与去重
    /// 在 store 侧守）
    private func resolvedRow(_ line: ApprovalResolvedLine) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: line.outcome.isPositive
                ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(line.outcome.isPositive
                    ? Palette.success : Palette.danger)
            Text(line.summary)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            Text(line.outcome.label)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(
            Palette.surface,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.containerCorner)
        )
    }
}

/// 单张就地审批卡：卡面本体走共用组件
/// ApprovalCardFace（样式二期 S2-01/02/03，与枢纽待
/// 批卡同一实现、同一几何与句式）；本宿主只持有卡
/// 体外框、详情的就地展开（SmoothExpand）与两只确
/// 认弹窗。卡面零原始 JSON、零英文运维串（宪法
/// §8）；材质与枢纽卡同为实色面内容卡
/// （Palette.surface），与玻璃消息面分工一致。
/// §165 起两个宿主共用：流末尾区（ChatApprovalZone）
/// 与锚定行（ChatView.approvalAnchorRow）——同一张
/// 卡、同一裁决路径，落位不同而已
struct ChatApprovalCard: View {
    let store: AgentHubStore
    let record: WriteGateRecord

    @State private var detail: WriteGateDetail?
    @State private var detailError: String?
    @State private var detailExpanded = false
    @State private var detailLoading = false
    @State private var showRejectConfirm = false
    @State private var showAlwaysConfirm = false

    var body: some View {
        ApprovalCardFace(
            record: record,
            isDeciding: store.decidingIDs.contains(record.id),
            note: store.cardNotes[record.id],
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
        .confirmationDialog(
            "驳回这条写入？",
            isPresented: $showRejectConfirm,
            titleVisibility: .visible
        ) {
            Button("驳回", role: .destructive) {
                Task { await store.decide(record, approve: false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("驳回后这条写入不会生效。")
        }
        .confirmationDialog(
            "总是允许这一类？",
            isPresented: $showAlwaysConfirm,
            titleVisibility: .visible
        ) {
            Button("总是允许") {
                Task { await store.decideAlways(record) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这条会立即批准；以后「\(ApprovalCardCopy.alwaysAllowScope(for: record))」的写入将直接通过，不再逐条询问。规则可以在设置「偏好与权限」的「审批规则」里随时撤销。")
        }
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
            ApprovalReviewContent(
                detail: detail, record: record, embedded: true
            )
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

    /// 三档裁决出口（钮面在共用卡面组件内）：批准直
    /// 接提交；总是允许/驳回先过本宿主既有确认弹窗
    private func handleAction(_ action: ApprovalCardAction) {
        switch action {
        case .approve:
            Task { await store.decide(record, approve: true) }
        case .alwaysAllow:
            showAlwaysConfirm = true
        case .reject:
            showRejectConfirm = true
        }
    }

    private func toggleDetail() {
        if detailExpanded {
            detailExpanded = false
            return
        }
        detailExpanded = true
        guard detail == nil, !detailLoading else { return }
        detailLoading = true
        detailError = nil
        Task {
            switch await store.loadDetail(record) {
            case .success(let loaded):
                detail = loaded
            case .failure(.recordGone):
                detailError = "这条待批已被处理或已失效。"
            case .failure:
                detailError = "改动没读出来，可能是网络或服务暂时没响应"
            }
            detailLoading = false
        }
    }
}
