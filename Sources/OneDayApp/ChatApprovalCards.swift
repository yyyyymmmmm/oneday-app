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

    var body: some View {
        if case .ready(let records) = store.approvalState {
            VStack(spacing: OneDayMetrics.spacingM) {
                ForEach(records) { record in
                    ChatApprovalCard(store: store, record: record)
                }
                ForEach(store.resolvedLines) { line in
                    resolvedRow(line)
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

/// 单张就地审批卡：人话标题问句（Core 模板）＋结构化
/// 头条与来源行＋一句后果＋「查看详情」就地展开（复
/// 用枢纽差异内容体 ApprovalReviewContent）＋三档全
/// 宽裁决（批准一次/总是允许这一类/驳回）。卡面零原
/// 始 JSON、零英文运维串（宪法 §8）；材质与枢纽卡同
/// 为实色面内容卡（Palette.surface），与玻璃消息面分
/// 工一致
private struct ChatApprovalCard: View {
    let store: AgentHubStore
    let record: WriteGateRecord

    @State private var detail: WriteGateDetail?
    @State private var detailError: String?
    @State private var detailExpanded = false
    @State private var detailLoading = false
    @State private var showRejectConfirm = false
    @State private var showAlwaysConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(record.subsystem.badgeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, OneDayMetrics.stackGap)
                    .background(Palette.primaryTint, in: Capsule())
                Text("待审批")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.warning)
                Spacer()
                if let createdAt = record.createdAt {
                    Text(ApprovalTimeText.relative(createdAt))
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            Text(ApprovalCardCopy.question(for: record))
                .font(.headline)
                .foregroundStyle(Palette.ink)

            // 说明行：结构化头条（子系统·动作·对象的人
            // 话拼装）＋内容预览；原始英文摘要不上卡面
            Text(record.headline)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            if let preview = record.previewLine, preview != record.headline {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            Text("来源：\(record.originLabel)")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            Text(ApprovalCardCopy.consequence(for: record))
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)

            if record.canDecide {
                Text("总是允许范围：\(ApprovalCardCopy.alwaysAllowScope(for: record))（可在枢纽撤销）")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }

            if let note = store.cardNotes[record.id] {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
            }

            if detailExpanded {
                detailArea
            }

            actions
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
            Text("这条会立即批准；以后「\(ApprovalCardCopy.alwaysAllowScope(for: record))」的写入将直接通过，不再逐条询问。规则可以在枢纽「审批规则」里随时撤销。")
        }
    }

    /// 详情展开区：按需拉桥 detail，内容与枢纽 sheet
    /// 同一份（ApprovalReviewContent）；拉不到如实报
    /// 错、不拿空内容冒充
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
        } else if let detailError {
            Text(detailError)
                .font(.caption)
                .foregroundStyle(Palette.danger)
        }
    }

    /// 动作区：查看详情（左）＋裁决三档全宽堆叠——批
    /// 准一次（主）／总是允许这一类／驳回（末位、确
    /// 认后执行）。不支持在 App 内审批的类型只留说明
    /// 与去向（规格 §5 枚举定案），不摆假按钮
    @ViewBuilder
    private var actions: some View {
        if store.decidingIDs.contains(record.id) {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在提交裁决…")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        } else if record.canDecide {
            VStack(spacing: OneDayMetrics.spacingS) {
                Button(detailExpanded ? "收起详情" : "查看详情") {
                    toggleDetail()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("批准") {
                    Task { await store.decide(record, approve: true) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button("总是允许这一类") {
                    showAlwaysConfirm = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                Button("驳回", role: .destructive) {
                    showRejectConfirm = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                Button(detailExpanded ? "收起详情" : "查看详情") {
                    toggleDetail()
                }
                .buttonStyle(.bordered)
                Text("这类写入暂不支持在 App 内审批，请在 Hermes 中处理")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
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
                detailError = "改动读取失败，通道未接通或读取出错。"
            }
            detailLoading = false
        }
    }
}
