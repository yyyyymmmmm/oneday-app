import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页审核段（规格 §3.2，用户定案⑥：一期只上待批
/// 卡、无历史行）：一卡一条——人话摘要＋来源＋diff
/// 入口＋批准/驳回。gate 三态诚实呈现（未启用/通道未
/// 接通/已启用），裸空列表冒充「无待批」是红线：只有
/// 桥可达＋闸门开＋pending 为空才是真无待批（状态判定
/// 在 AgentHubStore.loadApproval 与 Core 的
/// ApprovalSectionState）。桥 /status 已上线（两闸门
/// true、counts 实时），本段直接消费。
struct HubApprovalSection: View {
    let store: AgentHubStore

    @State private var diffTarget: WriteGateRecord?
    @State private var rejectTarget: WriteGateRecord?

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
                if records.isEmpty {
                    ContentUnavailableView(
                        "暂无待批写入",
                        systemImage: "checkmark.circle",
                        description: Text("记忆与技能的写入会先到这里等你批准")
                    )
                } else {
                    List {
                        Section("审核记录") {
                            ForEach(records) { record in
                                card(record)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await store.loadApproval(force: true)
                    }
                }
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
    }

    /// 待批卡片（实色面内容卡，非玻璃——规格 §0 材质总则）
    private func card(_ record: WriteGateRecord) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(record.subsystem.badgeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.primaryTint, in: Capsule())
                Spacer()
                if let createdAt = record.createdAt {
                    Text(createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }

            Text(record.displaySummary)
                .font(.headline)
                .foregroundStyle(Palette.ink)

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
                        Text("这类写入暂不支持在 App 内审批")
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
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
                    }
                    .padding(OneDayMetrics.pageGutter)
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
        .navigationTitle(detail?.review.targetLabel ?? "查看改动")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { dismiss() }
            }
        }
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
