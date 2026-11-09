import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页五段（规格 phase3-hub-spec §1 #9/#10）：图标
/// 纯符号、无文字；VoiceOver 读段名（Label 自带）。
enum HubSegment: String, CaseIterable, Identifiable {
    case activity
    case approval
    case browser
    case cron
    case identity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "活动"
        case .approval: return "审核"
        case .browser: return "浏览器"
        case .cron: return "定时"
        case .identity: return "身份"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "list.bullet"
        case .approval: return "checkmark.shield"
        case .browser: return "display"
        case .cron: return "clock"
        case .identity: return "touchid"
        }
    }
}

/// 智能体枢纽页（三期，规格 phase3-hub-spec）：页头
/// （圆钮行/头像/名/状态行）→ 模型常驻区 → 五段分段 →
/// 段内容。本视图自带 NavigationStack，呈现方不要再包一层。
/// 段切换只换内容区，页头与模型区常驻不动（规格 §0）。
/// 0.6.0 转正（蓝图 §4 一期）：枢纽页从「胶囊点开的
/// sheet」转正为活动格本体——mode=.activity 时只留
/// 活动/审核两段、撤页头圆钮行与模型常驻区（换模型
/// 入口在聊天页胶囊的模型段 Menu，硬规格不回退）；
/// mode=.sheet 保留五段全量形态，但聊天页胶囊已改道
/// 活动格、不再有 sheet 入口（不双份维护同一 UI）。
struct AgentHubView: View {
    enum Mode {
        case sheet
        case activity
    }

    var mode: Mode = .sheet
    /// 审批终态回调（活动格据此刷新总览桥角标）
    var onApprovalChanged: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var store: AgentHubStore?
    @State private var segment: HubSegment = .activity

    /// 本模式可见段：活动格一期只两段先行
    private var availableSegments: [HubSegment] {
        mode == .activity ? [.activity, .approval] : HubSegment.allCases
    }

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    content(store)
                } else {
                    ProgressView()
                }
            }
            .background(Palette.pageBG)
        }
        .presentationDragIndicator(.visible)
        .task {
            if store == nil {
                store = AgentHubStore(
                    appState: appState,
                    gateClient: appState.isDemo
                        ? DemoWriteGateClient()
                        : WriteGateClient(),
                    onApprovalChanged: onApprovalChanged
                )
            }
            await store?.loadInitial()
            if mode == .activity {
                await store?.loadApproval()
            }
        }
    }

    private func content(_ store: AgentHubStore) -> some View {
        VStack(spacing: 0) {
            header(store)
            if mode == .sheet {
                modelZone(store)
            }
            segmentPicker
            Divider()
            segmentContent(store)
        }
        .onChange(of: segment) { _, newSegment in
            Task { await loadSegment(newSegment, store: store) }
        }
    }

    private func loadSegment(_ segment: HubSegment, store: AgentHubStore) async {
        switch segment {
        case .activity:
            break // 初始加载已覆盖
        case .approval:
            await store.loadApproval()
        case .browser:
            break // 0.9.0：浏览器面自带盒桥轮询（面内 .task 驱动）
        case .cron:
            await store.loadCronIfNeeded()
        case .identity:
            await store.loadIdentityIfNeeded()
        }
    }

    // MARK: - 页头（规格 §2）

    private func header(_ store: AgentHubStore) -> some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            ZStack(alignment: .top) {
                avatarBlock
                if mode == .sheet {
                HStack {
                    // 页头圆钮（L1，用户定案③：照样板形态、
                    // 用系统玻璃原生件拼装）
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("关闭")

                    Spacer()

                    ShareLink(item: store.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("分享智能体摘要")
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                }
            }

            Text(store.displayName)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(1)

            HStack(spacing: 6) {
                Circle()
                    .fill(store.isOnline ? Palette.success : Palette.inkMuted)
                    .frame(width: 8, height: 8)
                Text(store.statusText)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 大头像＋编辑徽章（L2，用户定案④打包）：头像
    /// 0.6.0 换三狗搭档款定版图（蓝图 §3.10：吉祥物用
    /// 自有 IP，不借 OpenMuse 水豚；素材源
    /// ~/workspace/ip-design/STYLE-partner.webp 裁头入
    /// SangouPartner 资产）；徽章点按跳本页身份段（规格
    /// §2 推荐口径：本页内闭环），身份的实际编辑在身份
    /// 段内跳 ProfilesView（用户定案⑤）。活动格模式无
    /// 身份段，徽章不挂（点了没落点不如不挂）。
    private var avatarBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("SangouPartner")
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 0.5)
                }

            if mode == .sheet {
            Button {
                segment = .identity
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Palette.surface, in: Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }
                    .shadow(
                        color: Palette.shadowBase.opacity(0.12),
                        radius: 4, y: 1
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑身份")
            }
        }
    }

    // MARK: - 模型常驻区（规格 §2：不做第六段）

    private func modelZone(_ store: AgentHubStore) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            SectionLabel("会话模型")
                .padding(.horizontal, OneDayMetrics.pageGutter)
            VStack(spacing: 0) {
                ForEach(
                    Array(ChatModels.items.enumerated()),
                    id: \.element.id
                ) { index, item in
                    if index > 0 {
                        GroupDivider(inset: OneDayMetrics.spacingM)
                    }
                    Button {
                        appState.selectChatModel(item.id)
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                Text(item.note)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer()
                            if appState.chatModel == item.id {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.primary)
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                NavigationLink {
                    ModelSettingsView()
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Text("服务端默认模型")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(serverDefaultText)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
                .buttonStyle(.plain)
            }
            .odGroup()
            .padding(.horizontal, OneDayMetrics.pageGutter)
        }
        .padding(.bottom, OneDayMetrics.spacingSM)
    }

    /// 服务端默认模型参考值：未就绪时显「读取中」，不拿
    /// 会话模型冒充服务端默认（数据设计 §1.3）
    private var serverDefaultText: String {
        guard let model = appState.defaultModel else { return "读取中" }
        return ModelDisplayNames.displayName(for: model) ?? model
    }

    // MARK: - 五段分段控件（用户定案①：原生 segmented 先行）

    private var segmentPicker: some View {
        Picker("枢纽页分段", selection: $segment) {
            ForEach(availableSegments) { item in
                Label(item.title, systemImage: item.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    // MARK: - 段内容

    @ViewBuilder
    private func segmentContent(_ store: AgentHubStore) -> some View {
        switch segment {
        case .activity:
            activityContent(store)
        case .approval:
            HubApprovalSection(store: store)
        case .browser:
            HubBrowserSection()
        case .cron:
            HubCronSection(store: store)
        case .identity:
            HubIdentitySection(store: store)
        }
    }

    // MARK: - 活动段（规格 §3.1 降级拼装）

    @ViewBuilder
    private func activityContent(_ store: AgentHubStore) -> some View {
        if store.sessionsFailed {
            ContentUnavailableView {
                Label("会话读取失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text("活动流暂时拼不出来，请重试。")
            } actions: {
                Button("重试") {
                    Task { await store.reloadActivity() }
                }
                .buttonStyle(.bordered)
            }
        } else if let groups = store.activityGroups {
            if groups.isEmpty {
                ContentUnavailableView(
                    "暂无活动",
                    systemImage: "list.bullet",
                    description: Text("还没有会话记录")
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.label) {
                            ForEach(group.items) { item in
                                activityRow(item)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await store.reloadActivity()
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func activityRow(_ item: HubActivityItem) -> some View {
        Button {
            // 点行跳对应会话聊天页续聊（规格 §3.1 推荐
            // 口径）：走既有 pendingChatSessionID 通道，
            // 关闭枢纽页后由 ChatView 消费。活动格模式
            // 本就是一级页、没有可关的 sheet，只置位通
            // 道（ContentView 据此切聊天格）
            appState.pendingChatSessionID = item.sessionID
            if mode == .sheet {
                dismiss()
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                activityIconBox(item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(item.meta)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    /// 活动图标盒（0.6.1，用户真机点名＋OpenMuse 令牌
    /// 语言）：52pt 石板灰蓝渐变大圆退役——每行雷同的
    /// 大色块与 OpenMuse 活动卡的克制语言不符；改
    /// 36pt 小圆角盒：按来源给 pastel 令牌底（Open-
    /// Muse iconBox 的色面法、尺寸遵守「图标按来源
    /// 小而克制」口径）、glyph 回墨色细线，与文件页/
    /// 欢迎页的同族盒同语言
    private func activityIconBox(_ item: HubActivityItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(activityTint(item))
            Image(systemName: discGlyph(item))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Palette.ink)
        }
        .frame(width: 36, height: 36)
    }

    /// 来源 → pastel 令牌（与 OpenMuse iconBox 的四色
    /// pastel 同族：定时 lav 薰衣草、控制台 sky 天蓝、
    /// 其他应用 green 绿、命令行 orange 橙、缺省 sky）
    private func activityTint(_ item: HubActivityItem) -> Color {
        switch item.sourceLabel {
        case "定时任务": return Palette.tintLavender
        case "控制台": return Palette.tintSky
        case "其他应用": return Palette.tintGreen
        case "命令行": return Palette.tintOrange
        default: return Palette.tintSky
        }
    }

    private func discGlyph(_ item: HubActivityItem) -> String {
        switch item.sourceLabel {
        case "定时任务": return "clock"
        case "控制台": return "display"
        case "其他应用": return "iphone"
        case "命令行": return "terminal"
        default: return "bubble.left"
        }
    }

    // （0.6.1 删残：timeFormatter 随活动行改 meta 副题失去消费者）
}

