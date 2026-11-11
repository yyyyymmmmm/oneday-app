import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 通知面板（0.6.0 一期总览桥；0.36.7 人话三行结构；
/// §166 按用户亲递原型 oneday-notifications.html 重
/// 塑）：铃铛点开为底部大面板——头部（标题「通知」＋
/// 全部已读＋关闭钮）＋副标题（未读数实算）＋筛选条
/// （全部/未读两档带计数，轨道画法与连接器页分段同
/// 源 SegmentedControlSpec）＋按日分组列表；点行即
/// 标已读并推入详情页（大符号/结果标签/人话正文/
/// 变更清单/固定提示/落点按钮/技术记录折叠页底）。
///
/// 原型三原则落法：①事件优先——行面只给人话摘要、
/// 机器原文（rawDetail）下沉到详情页底「技术记录」
/// 折叠（0.36.7 的行内「原始记录」展开随之收编退
/// 役）；②**已读不褪色**——已读条目保持正常对比度，
/// 未读只靠三信号区分：标题 semibold、元信息蓝点、
/// 图标砖强调底；旧版「已读标题降 inkSecondary」就
/// 此作废；③技术信息下沉——同①。
///
/// 不许回退的既有语义：
/// - 伴生 1.0.27「已决不提醒」：已决回执在桥侧已读
///   出生，本页不重算、不复活未读；角标口径原样由
///   桥快照出，本页零改动；
/// - 已读通道走 store 既有 markRead/markAllRead（桥
///   确认后才改本地态、失败保持未读如实提示）；
/// - 落点走 §123 NotificationDestination＋AppState
///   .requestHubDestination 既有分发（枢纽由 ChatView
///   在 sheet 关闭后接力打开）；锚点包的原对话落点
///   （approvalAnchor/approvalThread）已于 §166 合
///   裁接线——本页 destination(for:) 先查本机锚、
///   落点按钮文案以 hasAnchorRoute 申报（见 Notifi-
///   cationDetail.destinationLabel），不另建第二套
///   跳转；
/// - 人话翻译层 NotificationSummary 与按日分组
///   NotificationGrouping 复用不重写；单一时间倒序
///   不重排（标已读后条目不跳位）。
struct NotificationsView: View {
    let store: OverviewBridgeStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    /// 锚点解析的本地索引来源（§165/§166 合裁）：审
    /// 批回执先查本机锚定条目/会话绑定，命中走原对
    /// 话落点、未命中回 §123 枢纽落点
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Namespace private var filterNamespace


    /// 筛选档（全部/未读）：纯本页呈现态，不落盘
    @State private var filter: NotificationDetail.Filter = .all
    /// 相对时间的新鲜度时钟：开页期间每 60 秒重算
    /// 一次，不许停留半小时还显旧「刚刚」（S7，沿旧版）
    @State private var now = Date()
    /// 「全部已读」部分失败的提示开关（S10 三段式
    /// 文案在 alert 内一次说清，沿旧版）
    @State private var markAllFailed = false

    private var unreadCount: Int {
        store.notifications.filter { !$0.read }.count
    }

    private var visibleItems: [OverviewNotification] {
        NotificationDetail.filtered(store.notifications, filter: filter)
    }

    private var groups: [NotificationDayGroup] {
        NotificationGrouping.groups(
            notifications: visibleItems, now: now
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Palette.pageBG)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await store.loadNotifications(appState: appState)
            }
            .onReceive(
                Timer.publish(every: 60, on: .main, in: .common)
                    .autoconnect()
            ) { tick in
                now = tick
            }
            .alert("没有全部标上已读", isPresented: $markAllFailed) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("有几条通知没能标为已读，它们仍保持未读状态。下拉刷新后再试一次。")
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - 头部（标题＋全部已读＋关闭＋副标题＋筛选条）

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
                Text("通知")
                    .font(.screenName)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if store.notificationsLoaded,
                   !store.notificationsFailed,
                   unreadCount > 0 {
                    Button("全部已读") {
                        Task {
                            let ok = await store.markAllRead(
                                appState: appState
                            )
                            if !ok { markAllFailed = true }
                        }
                    }
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.primary)
                    .frame(minHeight: OneDayMetrics.minTapTarget)
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Palette.selectionFill, in: Circle()
                        )
                        .frame(
                            width: OneDayMetrics.minTapTarget,
                            height: OneDayMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("关闭")
            }
            Text(subtitleText)
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, OneDayMetrics.spacingXS)
            if store.notificationsLoaded, !store.notificationsFailed,
               !store.notifications.isEmpty {
                filterBar
                    .padding(.top, OneDayMetrics.spacingSM)
            }
        }
        .padding(.horizontal, ListRowSpec.horizontalPadding)
        .padding(.top, OneDayMetrics.spacingSM)
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 副标题按面态分形（与原型同口径）：加载中/失败/
    /// 真空各有其词，列表态走 Core 实算（N 条未读/已
    /// 全部读过）
    private var subtitleText: String {
        if !store.notificationsLoaded {
            return String(localized: "正在获取最新通知…")
        }
        if store.notificationsFailed {
            return String(localized: "通知暂时无法获取")
        }
        if store.notifications.isEmpty {
            return String(localized: "需要你处理的事项会出现在这里")
        }
        return NotificationDetail.subtitle(unreadCount: unreadCount)
    }

    /// 筛选条：轨道＝surface＋发丝边全胶囊、选中药丸
    /// ＝selectionFill 垫＋字 semibold（与连接器页分
    /// 段同源同值，SegmentedControlSpec）；档题后带
    /// 计数小字（全部＝总数、未读＝未读数，均实算）
    private var filterBar: some View {
        HStack(spacing: 0) {
            filterButton(.all, title: String(localized: "全部"),
                         count: store.notifications.count)
            filterButton(.unread, title: String(localized: "未读"),
                         count: unreadCount)
        }
        .padding(SegmentedControlSpec.inset)
        .background(Palette.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Palette.separator, lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func filterButton(
        _ value: NotificationDetail.Filter,
        title: String, count: Int
    ) -> some View {
        let selected = filter == value
        return Button {
            withAnimation(
                MotionTokens.resolved(
                    MotionTokens.selectionSpring,
                    reduceMotion: reduceMotion
                )
            ) { filter = value }
        } label: {
            HStack(spacing: OneDayMetrics.spacingXS) {
                Text(title)
                Text("\(count)")
                    .foregroundStyle(Palette.inkMuted)
            }
            .font(.bodyText.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(
                maxWidth: .infinity,
                minHeight: SegmentedControlSpec.pillHeight
            )
            .background {
                if selected {
                    Capsule()
                        .fill(Palette.selectionFill)
                        .matchedGeometryEffect(
                            id: "notificationFilterPill",
                            in: filterNamespace
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel("\(title) \(count)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 内容面（四态：骨架/失败/空/列表）

    @ViewBuilder
    private var content: some View {
        if !store.notificationsLoaded {
            skeleton
        } else if store.notificationsFailed {
            ContentUnavailableView {
                Label("暂时联系不上", systemImage: "bell.slash")
            } description: {
                Text("通知暂时读不到。请检查服务器连接，或稍后重试。")
            } actions: {
                Button("重新加载") {
                    Task { await store.loadNotifications(appState: appState) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.notifications.isEmpty {
            ContentUnavailableView(
                "暂无通知",
                systemImage: "bell",
                description: Text("审批结果、监测变化和任务结果会出现在这里")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleItems.isEmpty {
            // 未读筛选为空（全部不空）：独立一形（原型
            // 同款），给回看全部的出口
            ContentUnavailableView {
                Label("没有未读通知", systemImage: "bell")
            } description: {
                Text("重要的变化，你都已经看过了。")
            } actions: {
                Button("查看全部通知") { filter = .all }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            notificationList
        }
    }

    /// 加载骨架（原型同款行数与行形）：图标砖＋三行
    /// 线，全走 selectionFill 静默面、无假文案；真数
    /// 据到达即整面替换（状态由 store.notifications-
    /// Loaded 驱动，不编造进度）
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(
                    alignment: .top,
                    spacing: ListRowSpec.columnSpacing
                ) {
                    RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusTile,
                        style: .continuous
                    )
                    .fill(Palette.selectionFill)
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                        Capsule().fill(Palette.selectionFill)
                            .frame(height: 12)
                        Capsule().fill(Palette.selectionFill)
                            .frame(height: 12)
                            .padding(.trailing, OneDayMetrics.spacingXL)
                        Capsule().fill(Palette.selectionFill)
                            .frame(width: 90, height: 9)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, ListRowSpec.horizontalPadding)
        .padding(.top, OneDayMetrics.spacingM)
        .accessibilityLabel("正在加载")
    }

    private var notificationList: some View {
        List {
            ForEach(Array(groups.enumerated()), id: \.element.id) {
                index, group in
                Section {
                    ForEach(group.items) { item in
                        notificationRow(item)
                    }
                } header: {
                    groupHeader(group, isFirst: index == 0)
                }
            }
            if store.notifications.count >= 50 {
                // 桥上限 50 条：达上限如实标注，不装全量
                Section {
                    Text("只显示最近 50 条")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.loadNotifications(appState: appState)
        }
    }

    /// 组头（沿 §3.4）：DisplayDate.dateOnly 文案、
    /// Footnote inkMuted、无底色无横线；首组上距 8、
    /// 其余 24，下距 8。「全部已读」已按原型上移面
    /// 板头部（原型落点），组头不再承载
    private func groupHeader(
        _ group: NotificationDayGroup, isFirst: Bool
    ) -> some View {
        Text(group.title)
            .font(.footnote)
            .foregroundStyle(Palette.inkMuted)
            .padding(.horizontal, ListRowSpec.horizontalPadding)
            .padding(.top, isFirst ? OneDayMetrics.spacingS : OneDayMetrics.spacingL)
            .padding(.bottom, OneDayMetrics.spacingS)
    }

    // MARK: - 列表行

    /// 行形态（原型 §行）：36pt 图标砖（Core 按 kind
    /// 取符号与着色）＋标题＋人话摘要两行截断＋元信
    /// 息行（未读蓝点＋相对时间＋类别词）。点行＝标
    /// 已读（未读时）＋推入详情（恒可达——已读不褪
    /// 色、详情是变更与技术记录的家）；落点跳转不在
    /// 行上发生、归详情页落点按钮（原型分工）

    private func notificationRow(
        _ item: OverviewNotification
    ) -> some View {
        let presentation = NotificationSummary.presentation(
            kind: item.kind, title: item.title, body: item.body
        )
        return NavigationLink {
            NotificationDetailView(
                store: store,
                item: item,
                destination: destination(for: item)
            )
        } label: {
            HStack(
                alignment: .top,
                spacing: ListRowSpec.columnSpacing
            ) {
                iconTile(item)
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingXS

                ) {
                    Text(item.title)
                        .font(item.read
                            ? .rowTitleL
                            : .rowTitleL.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if !presentation.summary.isEmpty {
                        Text(presentation.summary)
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                    metaLine(item)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .listRowInsets(EdgeInsets(
            top: OneDayMetrics.spacingSM,
            leading: ListRowSpec.horizontalPadding,
            bottom: OneDayMetrics.spacingSM,
            trailing: ListRowSpec.horizontalPadding
        ))
        // 分隔整行贯通（宪法 §3）：引导归零、发丝线
        // 自左缘起（沿旧版落法）
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .swipeActions(edge: .trailing) {
            if !item.read {
                Button("标已读") {
                    Task {
                        await store.markRead(
                            appState: appState, id: item.id
                        )
                    }
                }
                .tint(Palette.primary)
            }
        }
        .accessibilityLabel(
            item.read ? item.title : "未读，\(item.title)"
        )
    }

    /// 图标砖：36pt、radiusTile 连续圆角；着色按类——
    /// 裁决已批准＝绿砖/已驳回＝红砖（结果色先于类别
    /// 色）、监测＝天蓝砖、任务＝紫砖、其余＝橙砖；未
    /// 读一律升强调砖（primaryTint＋primary 字形）；
    /// 字形 18pt
    private func iconTile(
        _ item: OverviewNotification
    ) -> some View {
        let kind = NotificationDetail.iconKind(for: item)
        let symbol: String
        let fill: Color
        let glyph: Color
        switch kind {
        case .decision:
            symbol = "doc.text"
            if !item.read {
                fill = Palette.primaryTint
                glyph = Palette.primary
            } else {
                switch NotificationDetail.outcome(for: item) {
                case .rejected:
                    fill = Palette.errorSurface
                    glyph = Palette.danger
                default:
                    fill = Palette.tintGreen
                    glyph = Palette.success
                }
            }
        case .monitor:
            symbol = "waveform.path.ecg"
            fill = item.read ? Palette.tintSky : Palette.primaryTint
            glyph = item.read ? Palette.primary : Palette.primary
        case .task:
            symbol = "checklist"
            fill = item.read ? Palette.tintLavender : Palette.primaryTint
            glyph = item.read ? Palette.primary : Palette.primary
        case .other:
            symbol = "bell"
            fill = item.read ? Palette.tintOrange : Palette.primaryTint
            glyph = item.read ? Palette.warning : Palette.primary
        }
        return Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(glyph)
            .frame(width: 36, height: 36)
            .background(fill, in: RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusTile,
                style: .continuous
            ))
            .accessibilityHidden(true)
    }

    /// 元信息行：未读蓝点（5pt，只此一处未读点——旧
    /// 版左列点已随行形态收编）＋相对时间＋「· 类别」
    private func metaLine(
        _ item: OverviewNotification
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            if !item.read {
                Circle()
                    .fill(Palette.primary)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            Text(metaText(item))
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
                .monospacedDigit()
        }
    }

    /// 元信息文案：相对时间＋类别词（类别走 Core 单
    /// 源——旧版只给监测加「· 监测」、裁决不加的口径
    /// 随原型收编为全类带类别）。createdAt 解析不了
    /// 原样呈现（不编造时间，沿旧版）
    private func metaText(_ item: OverviewNotification) -> String {
        let time: String
        if let date = NotificationGrouping.parseCreatedAt(item.createdAt) {
            time = DisplayDate.relative(date, now: now)
        } else {
            time = item.createdAt
        }
        return time + " · " + NotificationDetail.categoryName(for: item)
    }

    // MARK: - 落点（详情页消费，跳转机制单一来源）

    /// 条目落点（§123＋§166 合裁）：审批回执先查本
    /// 机锚（§165 ApprovalNotificationRouting——已
    /// 物化条目/锚会话线程），未命中回落 §123
    /// resolve——出入点只此一处
    private func destination(
        for item: OverviewNotification
    ) -> NotificationDestination {
        guard item.isDecisionReceipt,
              let refId = item.refId, !refId.isEmpty
        else {
            return NotificationDestination.resolve(item)
        }
        let hubStore = appState.sharedHubStore()
        let decided = hubStore.decisionHistory
            + (hubStore.anchorDecisions ?? [])
        guard let record = decided.first(where: { $0.id == refId })
        else {
            return NotificationDestination.resolve(item)
        }
        let threads = (try? modelContext.fetch(
            FetchDescriptor<ChatThread>()
        )) ?? []
        var threadIDByKey: [String: UUID] = [:]
        var entryIDByKey: [String: UUID] = [:]
        var bySession: [String: UUID] = [:]
        for thread in threads {
            if let sessionID = thread.serverSessionID,
               !sessionID.isEmpty {
                bySession[sessionID] = thread.id
            }
            for entry in thread.entries {
                if let key = entry.approvalKey {
                    threadIDByKey[key] = thread.id
                    entryIDByKey[key] = entry.id
                }
            }
        }
        let target = ApprovalAnchorNavigation.target(
            subsystem: record.subsystem, recordID: refId,
            anchorSessionID: record.anchor?.sessionId,
            threadIDByServerSessionID: bySession,
            materialized: ApprovalAnchorNavigation.MaterializedIndex(
                threadIDByKey: threadIDByKey,
                entryIDByKey: entryIDByKey
            )
        )
        return ApprovalNotificationRouting.destination(
            notification: item, anchorTarget: target
        )
    }

}

/// 通知详情页（§166，原型 detail 面）：面板内导航栈
/// 推入。大符号砖＋标题（detailTitle）＋时间·类别＋
/// 结果标签＋人话正文＋「涉及的变更」清单＋审批固
/// 定提示＋落点按钮＋「技术记录」折叠置页底。
///
/// 进页即标已读由列表侧 .task 承接（行点按时数据
/// 已在手）；本页只读呈现，不持有第二份状态——条
/// 目以 id 回 store 取最新一份（标已读后 read 翻真、
/// 呈现随之收敛），取不到（刷新被清）回落进页快照。
private struct NotificationDetailView: View {
    let store: OverviewBridgeStore
    let item: OverviewNotification
    let destination: NotificationDestination

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var technicalExpanded = false

    /// 最新一份条目（store 优先、快照兜底）
    private var current: OverviewNotification {
        store.notifications.first(where: { $0.id == item.id }) ?? item
    }

    /// 锚点命中申报（§166 合裁）：落点为锚点两档
    /// （approvalAnchor/approvalThread）时按钮走
    /// 「返回关联会话」文案（Core destinationLabel
    /// 既备），其余落点恒 false
    private var hasAnchorRoute: Bool {
        switch destination {
        case .approvalAnchor, .approvalThread: return true
        default: return false
        }
    }

    var body: some View {
        let current = current
        let presentation = NotificationSummary.presentation(
            kind: current.kind, title: current.title, body: current.body
        )
        let lines = NotificationDetail.changeLines(for: current)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                detailSymbol(current)
                    .padding(.bottom, OneDayMetrics.spacingSM)
                Text(current.title)
                    .font(.detailTitle)
                    .foregroundStyle(Palette.ink)
                Text(timeLine(current))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, OneDayMetrics.spacingXS)
                if let outcome = NotificationDetail.outcome(for: current) {
                    outcomeChip(outcome)
                        .padding(.top, OneDayMetrics.spacingSM)
                }
                if !presentation.summary.isEmpty {
                    Text(presentation.summary)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineSpacing(6)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                if !lines.isEmpty {
                    sectionLabel(
                        NotificationDetail.changeSectionTitle(for: current)
                    )
                    changeBox(lines)
                }
                if let note = NotificationDetail.approvalNote(for: current) {
                    approvalNote(note)
                }
                if let label = NotificationDetail.destinationLabel(
                    destination: destination,
                    hasAnchorRoute: hasAnchorRoute
                ) {
                    destinationButton(label)
                        .padding(.top, OneDayMetrics.spacingSM)
                }
                if let raw = presentation.rawDetail {
                    technicalRecord(raw)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ListRowSpec.horizontalPadding)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("通知详情")
                    .font(.headline)
            }
        }
        .task {
            // 点行即标已读：进页触发（行点按与本页推
            // 入同拍）；已记者 store 侧自然跳过
            if !item.read {
                await store.markRead(appState: appState, id: item.id)
            }
        }
    }

    /// 大符号砖：48pt、radiusPreview；着色与列表砖同
    /// 源同档（按 kind 与结果），字形 22pt
    private func detailSymbol(
        _ item: OverviewNotification
    ) -> some View {
        let kind = NotificationDetail.iconKind(for: item)
        let symbol: String
        let fill: Color
        let glyph: Color
        switch kind {
        case .decision:
            symbol = "doc.text"
            switch NotificationDetail.outcome(for: item) {
            case .rejected:
                fill = Palette.errorSurface
                glyph = Palette.danger
            default:
                fill = Palette.tintGreen
                glyph = Palette.success
            }
        case .monitor:
            symbol = "waveform.path.ecg"
            fill = Palette.tintSky
            glyph = Palette.primary
        case .task:
            symbol = "checklist"
            fill = Palette.tintLavender
            glyph = Palette.primary
        case .other:
            symbol = "bell"
            fill = Palette.tintOrange
            glyph = Palette.warning
        }
        return Image(systemName: symbol)
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(glyph)
            .frame(width: 48, height: 48)
            .background(fill, in: RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusPreview,
                style: .continuous
            ))
            .accessibilityHidden(true)
    }

    /// 时间行：相对时间＋「· 类别」（与列表元信息同
    /// 源同口径；解析不了原样呈现）
    private func timeLine(_ item: OverviewNotification) -> String {
        let time: String
        if let date = NotificationGrouping.parseCreatedAt(item.createdAt) {
            time = DisplayDate.relative(date, now: Date())
        } else {
            time = item.createdAt
        }
        return time + " · " + NotificationDetail.categoryName(for: item)
    }

    /// 结果标签 chip：强调弱面＋强调字＋对勾（已批
    /// 准/已恢复/已完成）或叉（已被驳回）
    private func outcomeChip(
        _ outcome: NotificationDetail.Outcome
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            Image(systemName: outcome == .rejected ? "xmark" : "checkmark")
                .font(.system(size: 11, weight: .semibold))
            Text(outcome.label())
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(Palette.primary)
        .padding(.horizontal, OneDayMetrics.spacingS)
        .padding(.vertical, OneDayMetrics.spacingXS)
        .background(Palette.primaryTint, in: Capsule())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkMuted)
            .padding(.top, OneDayMetrics.spacingL)
            .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 变更清单：fieldFill 底＋radiusCard；行＝doc 符
    /// 号＋名/标识两行＋描述右列（描述为空不显，是
    /// 多技能归属不确凿时的如实留空）
    private func changeBox(
        _ lines: [NotificationDetail.ChangeLine]
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) {
                index, line in
                if index > 0 {
                    Divider()
                }
                HStack(
                    alignment: .top,
                    spacing: OneDayMetrics.spacingSM
                ) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.rowSubtitle.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        if let identifier = line.identifier {
                            Text(identifier)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                    if !line.changeDescription.isEmpty {
                        Text(line.changeDescription)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(OneDayMetrics.spacingSM)
            }
        }
        .background(Palette.fieldFill, in: RoundedRectangle(
            cornerRadius: OneDayMetrics.radiusCard,
            style: .continuous
        ))
    }

    /// 审批固定提示：info 符号＋小字两行（文案走
    /// Core 单源，逐字口径见 NotificationDetail）
    private func approvalNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, 1)
            Text(note)
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
                .lineSpacing(4)
        }
        .padding(.top, OneDayMetrics.spacingM)
    }

    /// 落点按钮：fieldFill 行钮（落点符号＋文案＋右
    /// 箭头）；点按＝关面板走既有分发（openDestin-
    /// ation 在父视图，同一入口）。符号按落点类取：
    /// 审批＝文档、原对话＝链接、监测＝波形
    private func destinationButton(_ label: String) -> some View {
        Button {
            // 经父视图入口关面板并分发（父视图持有
            // dismiss 与 AppState，本页只回调）
            NotificationDestinationFlow.open(
                destination, appState: appState, dismiss: dismiss
            )
        } label: {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: destinationSymbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Palette.inkSecondary)
                Text(label)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(OneDayMetrics.spacingSM)
            .frame(minHeight: OneDayMetrics.minTapTarget)
            .background(Palette.fieldFill, in: RoundedRectangle(
                cornerRadius: OneDayMetrics.radiusCard,
                style: .continuous
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private var destinationSymbol: String {
        switch NotificationDetail.iconKind(for: item) {
        case .decision: return "doc.text"
        case .monitor: return "waveform.path.ecg"
        case .task: return "link"
        case .other: return "arrow.up.right"
        }
    }

    /// 技术记录折叠（页底）：上发丝线分区；展开显
    /// rawDetail 等宽小字（机器原文只在此处出现——
    /// 行内「原始记录」展开已收编至此）
    private func technicalRecord(_ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.top, OneDayMetrics.spacingL)
            Button {
                withAnimation(
                    MotionTokens.resolved(
                        MotionTokens.swap, reduceMotion: reduceMotion
                    )
                ) { technicalExpanded.toggle() }
            } label: {
                HStack {
                    Text("技术记录")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                    Spacer()
                    Image(systemName: technicalExpanded
                        ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                }
                .frame(minHeight: OneDayMetrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            if technicalExpanded {
                Text(raw)
                    .font(.footnote)
                    .monospaced()
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OneDayMetrics.spacingSM)
                    .background(Palette.fieldFill, in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.radiusCard,
                        style: .continuous
                    ))
            }
        }
    }
}

/// 落点分发单一入口（§123 沿用）：通知详情的落点按
/// 钮与父视图共用——字段先落 AppState、再关面板，
/// 枢纽由 ChatView 在 sheet onDismiss 接力打开。详
/// 情页独立成型后以自由函数承接同一逻辑，不许另起
/// 第二套跳转
private enum NotificationDestinationFlow {
    @MainActor
    static func open(
        _ destination: NotificationDestination,
        appState: AppState,
        dismiss: DismissAction
    ) {
        guard appState.requestHubDestination(destination)
        else { return }
        dismiss()
    }
}
