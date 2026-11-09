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
/// 段内容。呈现走系统 sheet（入口接线在 ChatView 胶囊，
/// 见交付回执接线点）；本视图自带 NavigationStack，
/// 呈现方不要再包一层。
/// 段切换只换内容区，页头与模型区常驻不动（规格 §0）。
struct AgentHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var store: AgentHubStore?
    @State private var segment: HubSegment = .activity

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
                        : WriteGateClient()
                )
            }
            await store?.loadInitial()
        }
    }

    private func content(_ store: AgentHubStore) -> some View {
        VStack(spacing: 0) {
            header(store)
            modelZone(store)
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
            await store.loadBrowserIfNeeded()
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

    /// 大头像＋编辑徽章（L2，用户定案④打包）：头像与
    /// 聊天页身份胶囊同源视觉（近白圆面＋sparkles 字形，
    /// 服务端无头像接口）；徽章点按跳本页身份段（规格
    /// §2 推荐口径：本页内闭环），身份的实际编辑在身份
    /// 段内跳 ProfilesView（用户定案⑤）
    private var avatarBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(Palette.chatSurface)
                Circle().stroke(Palette.hairline, lineWidth: 0.5)
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 110, height: 110)

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
            ForEach(HubSegment.allCases) { item in
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
            HubBrowserSection(store: store)
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
            // 关闭枢纽页后由 ChatView 消费
            appState.pendingChatSessionID = item.sessionID
            dismiss()
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                activityDisc(item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(Self.timeFormatter.string(from: item.occurredAt))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }

    /// 活动圆盘（L4，用户定案④打包）：石板灰蓝渐变
    /// 色面＋白色节点 glyph（内容层色面、非玻璃）；暗色
    /// 给同家族深值（规格 §0 暗色口径）
    private func activityDisc(_ item: HubActivityItem) -> some View {
        ZStack {
            Circle().fill(Self.discGradient)
            Image(systemName: discGlyph(item))
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
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

    private static let discGradient = LinearGradient(
        colors: [
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x5A / 255.0, green: 0x5F / 255.0, blue: 0x73 / 255.0, alpha: 1)
                    : UIColor(red: 0x8A / 255.0, green: 0x90 / 255.0, blue: 0xA6 / 255.0, alpha: 1)
            }),
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0x48 / 255.0, green: 0x4C / 255.0, blue: 0x5E / 255.0, alpha: 1)
                    : UIColor(red: 0x6E / 255.0, green: 0x74 / 255.0, blue: 0x88 / 255.0, alpha: 1)
            }),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
