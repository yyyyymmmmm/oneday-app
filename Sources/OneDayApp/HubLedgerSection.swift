import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页「活动」段＝工作台账（规格 work-ledger-
/// design-20261110.md §5.6：会话拼装活动流退役、段
/// 名保留）：按天分组的工作时间线——标题是「干了
/// 什么」、进行中条目带真转指示与秒级已耗时、页首
/// 「正在进行 N 件」、失败与取消留在原位不隐藏、失
/// 联条目停转明示。段消费 AppState 共享 LedgerStore
/// （§259，段内 .task 驱动加载与轮询）。
/// §217（2026-11-13 枢纽收段）：本段兼收三撤段的
/// 内容与入口——①任务：台账本有看板同源条目，下
/// 钻在台账详情里补「打开任务详情」（答题/证据/
/// 控制动作都在任务详情里），新建任务入口迁来页
/// 首菜单；②审核：只并记录（审批仍只在聊天界面，
/// §155 不变）——审批条目在台账详情里补记录原文、
/// 只读「查看改动」与「查看原对话」锚点；审批规
/// 则曾随收段暂住列表首节，§244 已归位设置页权限
/// 区（大厂九项⑦），本段只留记录、不再兼收设置面；
/// ③监测：变化事件由 LedgerStore 合成同形条目并
/// 入同流，点达监测详情（变化在详情内对号呈现、
/// 控制动作也在详情里），新建监测同入页首菜单。
/// 通知落点（审批聚焦/监测深链）也改由本段消费。
/// §434（2026-11-24）：本段正名为中枢「工作」格
/// （注册表 HubSegmentID.work）；原定时段并入本
/// 段作列表首个折叠节「预定任务」（HubCronSec-
/// tion 整段退役）；行距与图标盒按参照行解剖放
/// 开（pitch ≈70pt、图标盒 40）。
/// §477（2026-11-24 全抄）：删页首「正在进行」段
/// （计数行＋蓝色 ⊕ 新建菜单整行退役，进行中条目
/// 并入今天段以状态副题呈现）；段制收口为预定任
/// 务＋按天两类、段头统一 HubSectionHeader 令牌件
/// 且均可折叠；台账按会话聚合一行；行改圆盘 44＋
/// 标题 20 semibold＋副题人话摘要，右列只留一行
/// HH:MM（「最后确认」撤出列表归详情面）。
struct HubLedgerSection: View {
    /// 枢纽共享审批 store（规则区与台账详情的审批
    /// 补齐用，与聊天就地卡同源同数据）
    let hubStore: AgentHubStore
    /// 运行类条目下钻打开会话（宿主负责置位通道＋
    /// 必要的关页，与旧活动行同路）
    var onOpenSession: (String) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// §259 三店合一：台账/任务/监测三店由 AppState
    /// 持有单例，本段只消费——条目只从共享 Ledger-
    /// Store 一口出；任务/监测数据面与全 App 各面同
    /// 一份（本段新建/动作在他面即时同见），不再私
    /// 建互不相通的副本（段内 .task 加载序列不变）
    private var store: LedgerStore {
        appState.sharedLedgerStore()
    }
    private var kanbanStore: KanbanStore {
        appState.sharedKanbanStore()
    }
    private var monitorsStore: MonitorsStore {
        appState.sharedMonitorsStore()
    }
    /// 预定任务折叠节展开态（§434）：默认收起——对
    /// 参照大头态列表格「N 项预定任务」折叠行形态
    @State private var cronExpanded = false
    /// 按天段折叠态（§477）：段头统一可折叠，默认全
    /// 展开、收起的组名记在此集（组名＝LedgerDay-
    /// Group.title，与分组单源同键）
    @State private var collapsedDayTitles: Set<String> = []
    /// 定时数据（§434 并格）：与原定时段同源——共
    /// 享 CronStore 单源（台账 198 收敛口径不变）
    private var cronStore: CronStore {
        appState.sharedCronStore()
    }
    private var cronTotalCount: Int {
        cronStore.hubGroups.reduce(0) { $0 + $1.items.count }
    }
    /// 通知落点聚焦的条目 id（审批＝appr:<记录 id>、
    /// 监测＝monitor-change:<变化 id>）：置位后滚
    /// 动定位＋行底色点亮，与原审核段聚焦同形态
    @State private var focusItemID: String?
    /// 派生快照缓存（第 3 项，照抄 FeedListSnapshot）
    @State private var snapshotCache = LedgerSnapshotCache()

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
                    Text(message ?? "台账功能还没开通。开通后，这里会自动开始记录每件工作的进度。")
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
            await kanbanStore.loadIfNeeded(appState: appState)
            await monitorsStore.loadIfNeeded(appState: appState)
            // §434：预定任务折叠节同轮备数（原定时段
            // .task 的两拉迁入，与 HubCronSection 原
            // 口径一致）
            await cronStore.loadIfNeeded()
            await cronStore.loadLastRunsIfNeeded()
            consumeFocusFields()
            await store.runVisibleLoop(appState: appState)
        }
    }

    /// 通知落点聚焦消费（§123 置位—消费—清零同式）：
    /// 审批聚焦字段换算成台账条目 id 后清零；监测深
    /// 链带变化 id 时按 id 契约（LedgerMonitorChange）
    /// 换算成台账条目 id——monitorDeepLink 本体不清
    /// 零（监测详情页还要靠它对号推变化详情，与原监
    /// 测段口径同），只在目标监测已不存在时按旧段口
    /// 径清掉防陈年链复活
    private func consumeFocusFields() {
        if let id = appState.router.hubApprovalFocusID {
            focusItemID = "appr:\(id)"
            appState.router.hubApprovalFocusID = nil
        }
        if let deepLink = appState.router.monitorDeepLink {
            if monitorsStore.monitor(id: deepLink.monitorID) == nil,
               monitorsStore.loadState == .ready {
                appState.router.monitorDeepLink = nil
            } else if let changeID = deepLink.changeID {
                focusItemID = LedgerMonitorChange.itemID(
                    changeID: changeID
                )
            }
        }
    }

    // MARK: - 就绪态

    @ViewBuilder
    private var readyContent: some View {
        VStack(spacing: 0) {
            // §477：「正在进行」段头行（计数文案＋蓝色
            // ⊕ 新建菜单）整行退役——进行中条目并入
            // 今天段以状态副题呈现（见 ledgerRow），新
            // 建入口回任务/监测本面。迟滞注脚是鲜度信
            // 号、不随段头丢：降为独立弱提示行保留
            if !store.connectionLost,
               store.freshness == .lagging,
               let note = store.freshness.note(
                   ledgerUpdatedAt: store.ledgerUpdatedAt
               ) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OneDayMetrics.hubGutter)
                    .padding(.vertical, OneDayMetrics.spacingXS)
            }
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

    private var ledgerSnapshot: LedgerListSnapshot {
        snapshotCache.snapshot(
            items: store.allItems,
            now: Date(timeIntervalSince1970: store.serverNow)
        )
    }

    private var ledgerList: some View {
        let snapshot = ledgerSnapshot
        return ScrollViewReader { proxy in
            List {
                // §434／第 3 项：预定任务折叠节——原生
                // Section ＋ DisclosureGroup 带平滑动画
                if cronStore.hasLoaded, !cronStore.hubGroups.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $cronExpanded) {
                            ForEach(cronStore.hubGroups, id: \.kind) { group in
                                ForEach(group.items) { item in
                                    NavigationLink {
                                        CronJobsView()
                                    } label: {
                                        CronOverviewRow(item: item)
                                    }
                                    .listRowInsets(rowInsets)
                                }
                            }
                        } label: {
                            sectionTitle("预定任务 · \(cronTotalCount) 项")
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                        .listRowBackground(Color.clear)
                    }
                }
                // §244／§477／第 3 项：按天分段——原生
                // Section ＋ DisclosureGroup，消费快照
                // 中已聚合好的会话行，不再每帧重算
                ForEach(snapshot.daySections) { section in
                    Section {
                        DisclosureGroup(
                            isExpanded: dayExpandedBinding(for: section.title)
                        ) {
                            ForEach(section.sessionGroups) { sessionGroup in
                                NavigationLink {
                                    destination(
                                        for: sessionGroup.representative
                                    )
                                } label: {
                                    ledgerRow(sessionGroup)
                                }
                                .id(sessionGroup.representative.id)
                                .listRowInsets(rowInsets)
                                .listRowBackground(
                                    sessionGroup.members.contains {
                                        $0.id == focusItemID
                                    }
                                        ? Palette.primaryTint
                                        : Color.clear
                                )
                            }
                        } label: {
                            sectionTitle(section.title)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                        .listRowBackground(Color.clear)
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

    /// 行下钻分发（§217）：监测条目（服务端直供
    /// kind=monitor）的「详情」就是监测详情本体（变
    /// 化对号、控制动作都在那里），不走台账详情读
    /// 面；其余条目一律台账详情（任务/审批的补齐在
    /// 详情内续行）
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
        guard let id else { return }
        // 第 3 项：直接从快照索引 O(1) 查代表行 id
        guard let targetID = ledgerSnapshot.representativeIDByMemberID[id]
        else { return }
        withAnimation(
            MotionTokens.resolved(
                MotionTokens.systemDefault, reduceMotion: reduceMotion
            )
        ) {
            proxy.scrollTo(targetID, anchor: .center)
        }
    }

    // MARK: - 段头（第 3 项：原生 Section + DisclosureGroup）

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(
                size: OneDayMetrics.hubTitleSize,
                weight: .semibold
            ))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.vertical, OneDayMetrics.spacingXS)
    }

    private func dayExpandedBinding(for title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedDayTitles.contains(title) },
            set: { expanded in
                if expanded {
                    collapsedDayTitles.remove(title)
                } else {
                    collapsedDayTitles.insert(title)
                }
            }
        )
    }

    /// 列表行边距（§477：中枢局部 16，段头与数据行
    /// 同一条左缘线）
    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: 0, leading: OneDayMetrics.hubGutter,
            bottom: 0, trailing: OneDayMetrics.hubGutter
        )
    }

    // MARK: - 行

    /// 会话聚合行（§477）：左圆盘／中题＋副题／右单
    /// 行时刻——标题走代表条目（最近一次运行），副
    /// 题是人话摘要（运行次数＋状态词＋已耗时/工具
    /// 调用数，全是真字段、不编造步文）；右列只留
    /// 一行 HH:MM（终态＝结束时刻、活跃态＝开始时
    /// 刻），「最后确认」标龄注撤出列表（归工作详情
    /// 面，§475 同源）。旧 §344 三段式的右段复合列
    /// （已耗时＋注＋补记徽标）整段退役；rowParts 单
    /// 源不动，详情面照旧消费
    private func ledgerRow(_ group: LedgerSessionGroup) -> some View {
        let item = group.representative
        return HStack(spacing: OneDayMetrics.spacingSM) {
            iconBox(item)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(item.titleHuman ?? item.title)
                    .font(.system(
                        size: OneDayMetrics.hubTitleSize,
                        weight: .semibold
                    ))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                subtitle(group)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(rowTime(item))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
        }
        // 行距对位：参照工作行 pitch ≈70pt——行内上
        // 下各补 spacingS（§434 口径续）
        .padding(.vertical, OneDayMetrics.spacingS)
        .contentShape(Rectangle())
        .opacity(item.status == .cancelled ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    /// 副题（中段）：活跃态每秒重算（TimelineView 只
    /// 包副题一行，列表本体不跟着整表重绘）；其余状
    /// 态静态一帧。文案组法见 subtitleText
    @ViewBuilder
    private func subtitle(_ group: LedgerSessionGroup) -> some View {
        let item = group.representative
        if item.status.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(
                    subtitleText(
                        group,
                        serverNow: store.displayServerNow(
                            at: context.date
                        )
                    )
                )
                // §500：副题 16 → 15（rowSubtitle）
                .font(.rowSubtitle)
                .monospacedDigit()
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            }
        } else {
            Text(subtitleText(group, serverNow: store.serverNow))
                // §500：副题 16 → 15（rowSubtitle）
                .font(.rowSubtitle)
                .foregroundStyle(
                    item.status == .stale
                        ? Palette.danger : Palette.inkSecondary
                )
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// 副题人话摘要（§477）：[共 N 次运行 ·] 状态词
    /// [· 已运行/已等 时长] [· 工具调用 N 次]——状
    /// 态词与已耗时出 rowParts 单源（§344），聚合次
    /// 数与工具调用数是台账真字段；证据迟滞的「最
    /// 后确认」注（rowParts.trailingNote）不在列表
    /// 消费、只留详情面
    private func subtitleText(
        _ group: LedgerSessionGroup, serverNow: Double
    ) -> String {
        let item = group.representative
        let parts = LedgerBoard.rowParts(
            for: item, serverNow: serverNow
        )
        var segments: [String] = []
        if group.count > 1 {
            segments.append(
                L10n.format("共 %lld 次运行", group.count)
            )
        }
        var status = parts.subtitle
        if item.status.isActive, let elapsed = parts.trailing {
            status += " · " + (
                item.status == .running
                    ? L10n.format("已运行 %@", elapsed)
                    : L10n.format("已等 %@", elapsed)
            )
        }
        segments.append(status)
        if let toolCalls = item.toolCalls, toolCalls > 0 {
            segments.append(
                L10n.format("工具调用 %lld 次", toolCalls)
            )
        }
        return segments.joined(separator: " · ")
    }

    /// 右列单行时刻（§477）：终态取结束时刻、活跃态
    /// 取开始时刻，HH:MM 走 LedgerClock 单源口径
    private func rowTime(_ item: LedgerItem) -> String {
        let epoch = item.status.isActive
            ? item.startedAt
            : (item.endedAt ?? item.startedAt)
        return LedgerClock.time(epoch)
    }

    /// 图标盘（§434 起 40pt 方盒；§477 改圆盘 44——
    /// 参照工作行左盘形态）：底色按类别给 pastel 令
    /// 牌；状态层——进行中＝系统转圈（真转、状态变
    /// 了同帧停：呈现只由条目状态驱动，没有第二条
    /// 驱动源）、排队＝小点、待审批＝盾牌、完成＝细
    /// 勾、失败＝叹号（红只点缀 glyph）、失联＝断
    /// 链。Reduce Motion 时转圈由系统自动降级，状态
    /// 另有副题文字通道不靠图标单传。字形色守 ink
    /// 系：参照是深彩底＋白字形，OneDay 类别底是浅
    /// pastel 令牌、白字形对比不达标——形态照抄、
    /// 字形色随自家令牌走，差异在此登记
    private func iconBox(_ item: LedgerItem) -> some View {
        ZStack {
            Circle()
                .fill(tint(item.kind))
            boxContent(item)
            if item.status == .queued {
                Circle()
                    .fill(Palette.inkMuted)
                    .frame(width: 6, height: 6)
                    .offset(x: 15, y: 15)
            }
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private func boxContent(_ item: LedgerItem) -> some View {
        // §217：监测变化是事件不是工作——监测条目
        // 的状态恒为 .completed 占位，但图标不许打
        // 勾冒充「做完了」，直给监测眼标（与段图标
        // 同形）
        if item.kind == .monitor {
            Image(systemName: "eye")
                .font(.system(size: FrameworkIcon.fileGlyphSize))
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
                .font(.system(size: FrameworkIcon.fileGlyphSize))
                .foregroundStyle(Palette.ink)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: FrameworkIcon.composerGlyphSize))
                .foregroundStyle(Palette.ink)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: FrameworkIcon.fileGlyphSize, weight: .semibold))
                .foregroundStyle(Palette.danger)
        case .stale:
            Image(systemName: "wifi.slash")
                .font(.system(size: FrameworkIcon.composerGlyphSize))
                .foregroundStyle(Palette.inkSecondary)
        default:
            Image(systemName: glyph(item.kind))
                .font(.system(size: FrameworkIcon.fileGlyphSize))
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
                .font(.system(size: FrameworkIcon.smallGlyphSize, weight: .semibold))
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
        .padding(.horizontal, OneDayMetrics.hubGutter)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(Palette.fieldFill)
    }
}
