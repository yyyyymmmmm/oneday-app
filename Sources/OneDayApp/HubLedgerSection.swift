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
/// §217（2026-11-13 枢纽收段）：本段兼收三撤段的
/// 内容与入口——①任务：台账本有看板同源条目，下
/// 钻在台账详情里补「打开任务详情」（答题/证据/
/// 控制动作都在任务详情里），新建任务入口迁来页
/// 首菜单；②审核：只并记录（审批仍只在聊天界面，
/// §155 不变）——审批条目在台账详情里补记录原文、
/// 只读「查看改动」与「查看原对话」锚点，审批规
/// 则区迁来列表首节（撤销面全 App 只此一处）；
/// ③监测：变化事件由 LedgerStore 合成同形条目并
/// 入同流，点达监测详情（变化在详情内对号呈现、
/// 控制动作也在详情里），新建监测同入页首菜单。
/// 通知落点（审批聚焦/监测深链）也改由本段消费。
struct HubLedgerSection: View {
    /// 枢纽共享审批 store（规则区与台账详情的审批
    /// 补齐用，与聊天就地卡同源同数据）
    let hubStore: AgentHubStore
    /// 运行类条目下钻打开会话（宿主负责置位通道＋
    /// 必要的关页，与旧活动行同路）
    var onOpenSession: (String) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = LedgerStore()
    /// 任务数据面（新建任务与任务详情下钻用；原任
    /// 务段自持，收段后归本段持有，Goals/动态等其
    /// 他面的 KanbanStore 实例互不相干）
    @State private var kanbanStore = KanbanStore()
    /// 监测数据面（监测详情下钻与新建监测用；合成
    /// 条目在 LedgerStore 里另走桥读面，两边同源）
    @State private var monitorsStore = MonitorsStore()
    @State private var showCreateTask = false
    @State private var showCreateMonitor = false
    /// 审批规则撤销待确认（确认框文案与旧审核段同）
    @State private var revokeTarget: WriteGateRule?
    /// 通知落点聚焦的条目 id（审批＝appr:<记录 id>、
    /// 监测＝monitor-change:<变化 id>）：置位后滚
    /// 动定位＋行底色点亮，与原审核段聚焦同形态
    @State private var focusItemID: String?

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
            await kanbanStore.load(appState: appState)
            await monitorsStore.load(appState: appState)
            consumeFocusFields()
            await store.runVisibleLoop(appState: appState)
        }
        .sheet(isPresented: $showCreateTask) {
            KanbanCreateTaskView(store: kanbanStore)
        }
        .sheet(isPresented: $showCreateMonitor) {
            MonitorCreateView(store: monitorsStore)
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
                Task { await hubStore.revokeRule(rule) }
                revokeTarget = nil
            }
            Button("取消", role: .cancel) {
                revokeTarget = nil
            }
        } message: { rule in
            Text("撤销后，「\(rule.scopeLabel)」的写入会重新逐条等你审批。")
        }
    }

    /// 通知落点聚焦消费（§123 置位—消费—清零同式）：
    /// 审批聚焦字段换算成台账条目 id 后清零；监测深
    /// 链带变化 id 时换算成合成条目 id——monitor-
    /// DeepLink 本体不清零（监测详情页还要靠它对号
    /// 推变化详情，与原监测段口径同），只在目标监
    /// 测已不存在时按旧段口径清掉防陈年链复活
    private func consumeFocusFields() {
        if let id = appState.hubApprovalFocusID {
            focusItemID = "appr:\(id)"
            appState.hubApprovalFocusID = nil
        }
        if let deepLink = appState.monitorDeepLink {
            if monitorsStore.monitor(id: deepLink.monitorID) == nil,
               monitorsStore.loadState == .ready {
                appState.monitorDeepLink = nil
            } else if let changeID = deepLink.changeID {
                focusItemID = LedgerMonitorSynthesis.itemID(
                    changeID: changeID
                )
            }
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
            if store.allItems.isEmpty {
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
            // §217：新建入口收口——原任务段/监测段各
            // 自的新建钮随段退役，迁来页首一处菜单
            // （两件新建表单本体与门控口径原样，见
            // KanbanCreateTaskView/MonitorCreateView）
            Menu {
                Button {
                    showCreateTask = true
                } label: {
                    Label("新建任务", systemImage: "checklist")
                }
                Button {
                    showCreateMonitor = true
                } label: {
                    Label("新建监测", systemImage: "eye")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.primary)
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("新建")
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
        ScrollViewReader { proxy in
            List {
                // §217：审批规则区迁入列表首节（撤销
                // 面全 App 只此一处，见 HubApproval-
                // RulesView 头注）；规则数据不在台账
                // 账里、走共享 hubStore
                HubApprovalRulesView(store: hubStore) { rule in
                    revokeTarget = rule
                }
                ForEach(store.dayGroups) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            NavigationLink {
                                destination(for: item)
                            } label: {
                                ledgerRow(item)
                            }
                            .id(item.id)
                            .listRowBackground(
                                item.id == focusItemID
                                    ? Palette.primaryTint
                                    : Color.clear
                            )
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
                await hubStore.loadApproval(force: true)
            }
            // 通知落点聚焦滚动（§123/§217）：焦点置位
            // 时一次、条目落位（首拉/轮询合并）后再试
            // ——目标不在流里（已滚出窗口）时静默落空，
            // 不假装定位（与原审核段聚焦同口径）
            .onChange(of: focusItemID) { _, id in
                scrollToFocus(proxy, id: id)
            }
            .onChange(of: store.allItems) { _, _ in
                scrollToFocus(proxy, id: focusItemID)
            }
        }
    }

    /// 行下钻分发（§217）：监测合成条目的「详情」就
    /// 是监测详情本体（变化对号、控制动作都在那
    /// 里），不走台账详情读面（服务端没有合成条目
    /// 的详情可读）；其余条目一律台账详情（任务/
    /// 审批的补齐在详情内续行）
    @ViewBuilder
    private func destination(for item: LedgerItem) -> some View {
        if item.link?.kind == "monitor",
           let monitorID = item.link?.targetId {
            MonitorDetailView(
                store: monitorsStore, monitorID: monitorID
            )
        } else {
            LedgerDetailView(
                store: store, item: item,
                hubStore: hubStore, kanbanStore: kanbanStore,
                onOpenSession: onOpenSession
            )
        }
    }

    private func scrollToFocus(
        _ proxy: ScrollViewProxy, id: String?
    ) {
        guard let id,
              store.allItems.contains(where: { $0.id == id })
        else { return }
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.systemDefault, reduceMotion: reduceMotion
            )
        ) {
            proxy.scrollTo(id, anchor: .center)
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
        // §217：监测变化是事件不是工作——合成条目的
        // 占位状态是 .completed，但图标不许打勾冒充
        // 「做完了」，直给监测眼标（与段图标同形）
        if item.kind == .monitor {
            Image(systemName: "eye")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.ink)
        } else {
            boxContentByStatus(item)
        }
    }

    @ViewBuilder
    private func boxContentByStatus(_ item: LedgerItem) -> some View {
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
        case .monitor: return "eye"
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
        case .monitor: return Palette.tintLavender
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
