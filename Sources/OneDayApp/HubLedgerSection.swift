import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页「活动」段＝工作台账（规格 work-ledger-
/// design-20261110.md §5.6：会话拼装活动流退役、段
/// 名保留）：按天分组的工作时间线——标题是「干了
/// 什么」、进行中条目带真转指示与秒级已耗时、页首
/// 「正在进行 N 件」、失败与取消留在原位不隐藏、失
/// 联条目停转明示。段自持 LedgerStore（段内 .task
/// 驱动，与任务/监测段同形态）。
struct HubLedgerSection: View {
    /// 运行类条目下钻打开会话（宿主负责置位通道＋
    /// 必要的关页，与旧活动行同路）
    var onOpenSession: (String) -> Void

    @Environment(AppState.self) private var appState
    @State private var store = LedgerStore()

    var body: some View {
        Group {
            switch store.loadState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable(let message):
                ContentUnavailableView {
                    Label("台账还没上线", systemImage: "list.bullet")
                } description: {
                    Text(message ?? "台账服务还没上线。上线后，这里会自动开始记录每件工作的进度。")
                } actions: {
                    Button("重新检查") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.bordered)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("台账没读出来，可能是网络或服务暂时没响应", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.bordered)
                }
            case .ready:
                readyContent
            }
        }
        .task {
            await store.load(appState: appState)
            await store.runVisibleLoop(appState: appState)
        }
    }

    // MARK: - 就绪态

    @ViewBuilder
    private var readyContent: some View {
        VStack(spacing: 0) {
            headerLine
            if store.summary?.degraded == true {
                banner(
                    icon: "exclamationmark.triangle",
                    text: "台账目前处于降级状态",
                    detail: "记录可能不完整，其余部分照常更新。"
                )
            }
            if store.connectionLost {
                banner(
                    icon: "wifi.slash",
                    text: "台账暂时连不上",
                    detail: "显示的是最后一次拿到的记录，恢复后会自动更新。"
                )
            } else if store.freshness == .stalled {
                banner(
                    icon: "exclamationmark.triangle",
                    text: store.freshness.note(
                        ledgerUpdatedAt: store.ledgerUpdatedAt
                    ) ?? "台账已停更",
                    detail: "负责对账的程序可能停了，新进度暂时不会出现。"
                )
            }
            if store.items.isEmpty {
                ContentUnavailableView(
                    "暂无记录",
                    systemImage: "list.bullet",
                    description: Text(
                        "台账从服务上线后开始记账，之前的工作不会补录。有新工作时会出现在这里。"
                    )
                )
            } else {
                ledgerList
            }
        }
    }

    /// 页首总览行：计数与下方列表同一 payload（规格
    /// §4.2）；迟滞档（30 秒–5 分钟）在行尾挂弱标注，
    /// 停更/断连走横幅不在这里重复
    private var headerLine: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Text(headerText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            if !store.connectionLost,
               store.freshness == .lagging,
               let note = store.freshness.note(
                   ledgerUpdatedAt: store.ledgerUpdatedAt
               ) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            Spacer()
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    private var headerText: String {
        let counts = store.headerCounts
        return LedgerBoard.headerText(
            inProgress: counts.inProgress,
            blockedApproval: counts.blockedApproval
        )
    }

    private var ledgerList: some View {
        List {
            ForEach(store.dayGroups) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        NavigationLink {
                            LedgerDetailView(
                                store: store, item: item,
                                onOpenSession: onOpenSession
                            )
                        } label: {
                            ledgerRow(item)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        // 陈旧呈现（§2.5）：停更或断连时旧数据弱化，
        // 不许同字重同位置冒充现值
        .opacity(
            store.connectionLost || store.freshness == .stalled
                ? 0.55 : 1
        )
        .refreshable {
            await store.load(appState: appState)
        }
    }

    // MARK: - 行

    private func ledgerRow(_ item: LedgerItem) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            iconBox(item)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                subtitle(item)
            }
            Spacer()
            if item.isReconciled {
                Text("补记")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, OneDayMetrics.iconTextGap)
                    .padding(.vertical, OneDayMetrics.spacingMicro)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Palette.hairline, lineWidth: 1)
                    }
            }
        }
        .contentShape(Rectangle())
        .opacity(item.status == .cancelled ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    /// 副题：活跃态每秒重算已耗时（TimelineView 只包
    /// 副题一行，列表本体不跟着整表重绘）；其余状态
    /// 静态一帧
    @ViewBuilder
    private func subtitle(_ item: LedgerItem) -> some View {
        if item.status.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(
                    LedgerBoard.subtitle(
                        for: item,
                        serverNow: store.displayServerNow(
                            at: context.date
                        )
                    )
                )
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            }
        } else {
            Text(
                LedgerBoard.subtitle(
                    for: item, serverNow: store.serverNow
                )
            )
            .font(.subheadline)
            .foregroundStyle(
                item.status == .stale
                    ? Palette.danger : Palette.inkSecondary
            )
            .lineLimit(1)
        }
    }

    /// 图标盒（36pt，与旧活动行同骨架）：底色按类别
    /// 给 pastel 令牌；状态层——进行中＝系统转圈（真
    /// 转、状态变了同帧停：呈现只由条目状态驱动，没
    /// 有第二条驱动源）、排队＝小点、待审批＝盾牌、
    /// 完成＝细勾、失败＝叹号（红只点缀 glyph）、失
    /// 联＝断链。Reduce Motion 时转圈由系统自动降级，
    /// 状态另有副题文字通道不靠图标单传
    private func iconBox(_ item: LedgerItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb, style: .continuous)
                .fill(tint(item.kind))
            boxContent(item)
            if item.status == .queued {
                Circle()
                    .fill(Palette.inkMuted)
                    .frame(width: 6, height: 6)
                    .offset(x: 11, y: 11)
            }
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private func boxContent(_ item: LedgerItem) -> some View {
        switch item.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .blockedApproval:
            Image(systemName: "checkmark.shield")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.ink)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.ink)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.danger)
        case .stale:
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Palette.inkSecondary)
        default:
            Image(systemName: glyph(item.kind))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.ink)
        }
    }

    private func glyph(_ kind: LedgerKind) -> String {
        switch kind {
        case .run: return "bubble.left"
        case .kanban: return "checklist"
        case .job: return "clock"
        case .approval: return "checkmark.shield"
        case .device: return "iphone"
        case .other: return "doc.text"
        }
    }

    private func tint(_ kind: LedgerKind) -> Color {
        switch kind {
        case .run: return Palette.tintSky
        case .kanban: return Palette.tintGreen
        case .job: return Palette.tintLavender
        case .approval: return Palette.tintOrange
        case .device: return Palette.tintSky
        case .other: return Palette.tintSky
        }
    }

    // MARK: - 横幅（与任务段同形态）

    private func banner(
        icon: String, text: String, detail: String?
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.fieldFill)
    }
}
