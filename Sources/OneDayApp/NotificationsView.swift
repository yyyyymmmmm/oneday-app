import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 通知 sheet（0.6.0 一期，总览桥；0.36.7 按规格
/// notifications-page-benchmark §3 重排）：
/// - 条目三行人话结构：标题＝桥的结论句、摘要＝
///   Core 模板翻译（NotificationSummary，解析不出
///   禁止直出原文、降级通用句＋原文收进点按展开
///   的次级详情）、元信息＝DisplayDate 相对档＋
///   监测类别词。
/// - 按日分组、单一时间倒序（废 0.6.0「未读在前」
///   重排：回执账的时间序是唯一可预期心智，标已
///   读后条目不跳位）；未读只留一个信号（强调色
///   点＋标题全色），已读无点（留空列保文字列对
///   齐）＋标题降色。
/// - 点按：未读＝标已读（桥确认后才改本地态）；
///   已读且有原文＝展开/收起次级详情。左滑只给
///   「标已读」——桥只有 /read 一个写端点，「标未
///   读」无服务端落点且角标以桥为准（规格 §3.5），
///   不造本地假态（出入登记 DESIGN-V4 §72）。
/// - §123（H2，闭环包）：条目按类型点达对象——落点
///   解析在 Core NotificationDestination（审批回枢
///   纽审批段/聚焦已决记录、监测达监测详情/具体变
///   化、存量监测只达监测段）；有落点的行带去向箭
///   头，点按＝标已读＋关本页＋开枢纽达对象（枢纽
///   开启走 ChatView sheet 的 onDismiss 接力，避免
///   两个呈现打架）；机器原文（rawDetail）改走行内
///   独立的「原始记录」折叠钮——默认折起、与导航点
///   按互不干扰，不再靠点整行展开。
/// - 桥不可达时明示「暂时联系不上」，不拿空列表
///   冒充没有通知；真空态文案只在加载成功且确为
///   空时出现。断桥无缓存态不适用：现行 store 失
///   败即清空、无缓存保留（§3.6 施工核对结论）。
struct NotificationsView: View {
    let store: OverviewBridgeStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    /// 锚点解析的本地索引来源（§165）：审批回执先查本
    /// 机锚定条目/会话绑定，命中走原对话落点、未命中
    /// 回 §123 枢纽落点（解析在 Core，本页只备数据）
    @Environment(\.modelContext) private var modelContext

    /// 已读条目展开的次级详情（原始记录）集合
    @State private var expandedIDs: Set<String> = []
    /// 相对时间的新鲜度时钟：开页期间每 60 秒重算
    /// 一次，不许停留半小时还显旧「刚刚」（S7）
    @State private var now = Date()
    /// 「全部已读」部分失败的提示开关（S10 三段式
    /// 文案在 alert 内一次说清）
    @State private var markAllFailed = false

    private var groups: [NotificationDayGroup] {
        NotificationGrouping.groups(
            notifications: store.notifications, now: now
        )
    }

    private var unreadCount: Int {
        store.notifications.filter { !$0.read }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.notificationsLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.notificationsFailed {
                    ContentUnavailableView {
                        Label("暂时联系不上", systemImage: "bell.slash")
                    } description: {
                        Text("通知暂时读不到，请稍后再试。")
                    } actions: {
                        Button("重试") {
                            Task { await store.loadNotifications(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if store.notifications.isEmpty {
                    ContentUnavailableView(
                        "暂无通知",
                        systemImage: "bell",
                        description: Text("审批结果和监测变化会出现在这里")
                    )
                } else {
                    notificationList
                }
            }
            .background(Palette.pageBG)
            // 0.36.0（宪法 §5／审计 C9 同族）：撤居中
            // 标题与手写关闭——列表内容领头、关闭走
            // 系统下拉手势
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
        .refreshable {
            await store.loadNotifications(appState: appState)
        }
    }

    /// 组头（规格 §3.4）：DisplayDate.dateOnly 文案、
    /// Footnote 13 inkMuted、无底色无横线；首组上
    /// 距 8、其余 24，下距 8。未读 ≥2 时首组组头右
    /// 侧出「全部已读」（§3.5）
    private func groupHeader(
        _ group: NotificationDayGroup, isFirst: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.title)
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
            Spacer()
            if isFirst, unreadCount >= 2 {
                Button("全部已读") {
                    Task {
                        let ok = await store.markAllRead(
                            appState: appState
                        )
                        if !ok { markAllFailed = true }
                    }
                }
                .font(.footnote)
                .foregroundStyle(Palette.primary)
            }
        }
        .padding(.horizontal, ListRowSpec.horizontalPadding)
        .padding(.top, isFirst ? OneDayMetrics.spacingS : OneDayMetrics.spacingL)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 落点导航（§123 H2）：落点字段先落 AppState，
    /// 再关通知页——枢纽由 ChatView 在 sheet 关闭后接
    /// 力打开（见 ChatView 通知 sheet 的 onDismiss）。
    /// §165：锚点落点同样经 requestHubDestination 落
    /// 字段（approvalAnchorRequest），ChatView 在
    /// onDismiss 里优先消费它切线程定位、不开枢纽
    private func openDestination(
        _ destination: NotificationDestination
    ) {
        guard appState.requestHubDestination(destination)
        else { return }
        dismiss()
    }

    /// 条目落点（§165 扩展 §123）：审批回执先查本机锚
    /// ——回执的 refId 是记录 id，但通知载荷不带子系
    /// 统与 anchor，子系统经共享 store 的已决集反查
    /// （回执对应的记录必在已决账本里）、anchor 同源
    /// 取；任一环查不到 → Core 解析回落 §123 现行落
    /// 点，绝不凭标题/时间猜锚
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

    private func notificationRow(
        _ item: OverviewNotification
    ) -> some View {
        let presentation = NotificationSummary.presentation(
            kind: item.kind, title: item.title, body: item.body
        )
        let destination = destination(for: item)
        let expanded = expandedIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if !item.read {
                    Task {
                        await store.markRead(
                            appState: appState, id: item.id
                        )
                    }
                }
                if destination.hasDestination {
                    openDestination(destination)
                } else if item.read,
                          presentation.rawDetail != nil {
                    if expanded {
                        expandedIDs.remove(item.id)
                    } else {
                        expandedIDs.insert(item.id)
                    }
                }
            } label: {
                HStack(
                    alignment: .top,
                    spacing: OneDayMetrics.spacingSM
                ) {
                    // 状态点列：仅未读渲染（已读保留列
                    // 宽、文字列对齐不跳动）；顶偏移 8
                    // 与标题首行视觉居中对齐
                    ZStack {
                        if !item.read {
                            Circle()
                                .fill(Palette.primary)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(width: 8, height: 8)
                    .padding(.top, OneDayMetrics.spacingS)
                    .accessibilityHidden(true)
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(
                                item.read
                                    ? Palette.inkSecondary
                                    : Palette.ink
                            )
                            .lineLimit(2)
                        if !presentation.summary.isEmpty {
                            Text(presentation.summary)
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(2)
                        }
                        Text(metaText(item))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkMuted)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if destination.hasDestination {
                        // §123（H2）：有落点的行明示可达
                        // （宪法 §9：可点必有指示）
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Palette.inkMuted)
                            .padding(.top, OneDayMetrics.spacingS)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            if let raw = presentation.rawDetail {
                // 机器原文折叠（§123 H2）：独立小钮开合，
                // 默认折起；行面只留人话摘要，原文只在
                // 展开区出现（S10 的「原始记录」标性＋
                // 等宽小字口径不变）
                Button {
                    if expanded {
                        expandedIDs.remove(item.id)
                    } else {
                        expandedIDs.insert(item.id)
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text("原始记录")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkMuted)
                        Image(
                            systemName: expanded
                                ? "chevron.up" : "chevron.down"
                        )
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Palette.inkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
                .padding(.top, OneDayMetrics.spacingS)
                .padding(
                    .leading,
                    8 + OneDayMetrics.spacingSM
                )
                if expanded {
                    Text(raw)
                        .font(.footnote)
                        .monospaced()
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, OneDayMetrics.spacingXS)
                        .padding(
                            .leading,
                            8 + OneDayMetrics.spacingSM
                        )
                }
            }
        }
        .listRowInsets(EdgeInsets(
            top: OneDayMetrics.spacingSM,
            leading: ListRowSpec.horizontalPadding,
            bottom: OneDayMetrics.spacingSM,
            trailing: ListRowSpec.horizontalPadding
        ))
        // 分隔整行贯通（宪法 §3）：引导归零、发丝线
        // 自左缘起（0.36.0 既定落法）
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

    /// 元信息行（规格 §3.1）：相对时间；监测类后
    /// 缀类别词「· 监测」（裁决类标题已明、不加）。
    /// createdAt 解析不了原样呈现（不编造时间）
    private func metaText(_ item: OverviewNotification) -> String {
        let time: String
        if let date = NotificationGrouping.parseCreatedAt(item.createdAt) {
            time = DisplayDate.relative(date, now: now)
        } else {
            time = item.createdAt
        }
        return item.isMonitorChange ? time + " · 监测" : time
    }
}
