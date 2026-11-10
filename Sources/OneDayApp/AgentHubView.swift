import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页五段（规格 phase3-hub-spec §1 #9/#10）：图标
/// 纯符号、无文字；VoiceOver 读段名（Label 自带）。
enum HubSegment: String, CaseIterable, Identifiable {
    case activity
    case tasks
    case approval
    case browser
    case cron
    case monitors
    case identity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "活动"
        case .tasks: return "任务"
        case .approval: return "审核"
        case .browser: return "浏览器"
        case .cron: return "定时"
        case .monitors: return "监测"
        case .identity: return "身份"
        }
    }

    var systemImage: String {
        switch self {
        case .activity: return "list.bullet"
        case .tasks: return "checklist"
        case .approval: return "checkmark.shield"
        case .browser: return "display"
        case .cron: return "clock"
        case .monitors: return "eye"
        case .identity: return "touchid"
        }
    }
}

/// 智能体枢纽页（三期，规格 phase3-hub-spec）：页头
/// （圆钮行/头像/名/状态行）→ 模型常驻区 → 五段分段 →
/// 段内容。本视图自带 NavigationStack，呈现方不要再包一层。
/// 段切换只换内容区，页头与模型区常驻不动（规格 §0）。
/// 0.6.0 转正（蓝图 §4 一期）：枢纽页从「胶囊点开的
/// sheet」转正为活动格本体——mode=.activity 时留
/// 活动/任务/审核三段（任务段 0.10.0 增、监测段
/// 0.12.0 增）、撤页头
/// 圆钮行与模型常驻区（换模型
/// 入口在聊天页胶囊的模型段 Menu，硬规格不回退）；
/// mode=.sheet 保留五段全量形态，但聊天页胶囊已改道
/// 活动格、不再有 sheet 入口（不双份维护同一 UI）。
/// 0.17.0（真机五修⑤）：活动格撤销——mode=.activity
/// 改由聊天页胶囊/回告卡以 sheet 呈现（本视图自带导
/// 航栈、呈现方不外包，口径不变；下滑关 sheet 走系
/// 统拖拽指示器）；mode=.sheet 五段全量形态仍无入口、
/// 与 0.6.0 起的口径一致。
/// 0.36.22（枢纽页对齐包，用户点名学 Muse 智能体
/// 页）：呈现改整页 fullScreenCover（ChatView 侧，
/// DESIGN-V4 §89）——页头圆钮行（✕/分享）两模式统
/// 一常驻、左边缘右滑返回走系统边缘识别器桥、头像
/// 徽章改本地档案菜单（更换虚拟形象/编辑名称）；分
/// 段与段内容、数据面一律不动。
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
    /// 边缘右滑跟手位移（0.36.22）：只由边缘桥回调写，
    /// 松手回弹或 dismiss 后归零
    @State private var edgeOffset: CGFloat = 0
    /// 头像/名称编辑面（0.36.22 档案菜单两项）
    @State private var showAvatarEditor = false
    @State private var showNameEditor = false
    /// 分享名片（0.36.22）：名片图离屏渲染产物，随档
    /// 案修订/页头名/域名变化重算；未就绪时分享钮回
    /// 落纯文本名片
    @State private var shareItem: AgentShareItem?

    /// 本模式可见段：活动格＝活动/任务/审核/监测四段
    /// （任务段 0.10.0 P3 转正、监测段 0.12.0 P6 转正）
    private var availableSegments: [HubSegment] {
        mode == .activity
            ? [.activity, .tasks, .approval, .monitors]
            : HubSegment.allCases
    }

    /// 分享名片重算键：档案修订（改名/换头像）＋页头
    /// 名＋域名任一变，名片图就重渲染
    private var shareRenderKey: String {
        "\(appState.agentProfileStore.revision)"
            + "|\(store?.displayName ?? "")"
            + "|\(appState.serverShareHost ?? "")"
    }

    var body: some View {
        ZStack {
            // 整页 cover 的底色先行：边缘右滑跟手时内
            // 容横移、露出的空位是页底色而不是系统黑
            Palette.pageBG.ignoresSafeArea()
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
            .offset(x: edgeOffset)
        }
        .background {
            // 左边缘右滑返回（0.36.22）：cover 没有导
            // 航栈 pop 手势，系统边缘识别器桥补齐（判
            // 据 Core HubEdgeSwipe 单源；浏览器段禁用，
            // 网页自有横移手势优先）
            HubEdgeSwipeProbe(
                isEnabled: segment != .browser,
                onProgress: { edgeOffset = $0 },
                onRelease: { shouldDismiss in
                    if shouldDismiss {
                        edgeOffset = 0
                        dismiss()
                    } else if edgeOffset != 0 {
                        withAnimation(.snappy(duration: 0.25)) {
                            edgeOffset = 0
                        }
                    }
                }
            )
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showAvatarEditor) {
            AgentAvatarEditorView()
        }
        .sheet(isPresented: $showNameEditor) {
            AgentNameEditorView(
                initialOverride: appState.agentProfileStore
                    .profile.displayNameOverride
            )
        }
        .task(id: shareRenderKey) {
            shareItem = AgentShareItem.make(
                name: store?.displayName ?? appState.agentDisplayName,
                host: appState.serverShareHost,
                avatarImage: appState.agentAvatarImage
            )
        }
        .task {
            if store == nil {
                // 0.36.21：store 改走 AppState 共享单例
                // （就地审批卡与枢纽共用同一份 /pending
                // 数据与裁决路径，规格 §6）；审批终态回
                // 调仍在此注入（本视图是全 App 唯一呈现
                // 枢纽的入口）
                let shared = appState.sharedHubStore()
                shared.onApprovalChanged = onApprovalChanged
                store = shared
            }
            await store?.loadInitial()
            if mode == .activity {
                // 共享 store 后 loadApproval 默认可复用
                // 缓存（chat 刷新刚拉过会跳过），枢纽语
                // 义是「每次打开必刷新」——强制重拉保住
                await store?.loadApproval(force: true)
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
        case .tasks:
            break // 0.10.0：任务段自持 KanbanStore（段内 .task 驱动）
        case .approval:
            await store.loadApproval()
        case .browser:
            break // 0.9.0：浏览器面自带盒桥轮询（面内 .task 驱动）
        case .cron:
            await store.loadCronIfNeeded()
        case .monitors:
            break // 0.12.0：监测段自持 MonitorsStore（段内 .task 驱动）
        case .identity:
            await store.loadIdentityIfNeeded()
        }
    }

    // MARK: - 页头（规格 §2）

    /// 分享圆钮（0.36.22）：内容换代为智能体名片——
    /// 名称＋头像＋服务器域名（仅 host），红线不含任
    /// 何凭据（AgentShareCard）；名片图未渲染就绪时
    /// 回落纯文本名片，按钮永不假装。旧 shareText
    /// （含当前模型、无域名）自此退出分享面
    @ViewBuilder
    private func shareButton(_ store: AgentHubStore) -> some View {
        if let shareItem {
            ShareLink(item: shareItem.fileURL) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("分享智能体名片")
        } else {
            ShareLink(
                item: AgentShareCardText.make(
                    name: store.displayName,
                    host: appState.serverShareHost
                )
            ) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("分享智能体名片")
        }
    }

    private func header(_ store: AgentHubStore) -> some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            ZStack(alignment: .top) {
                avatarBlock
                // 圆钮行（✕ 关闭＋分享名片）：0.36.22 起
                // 两模式统一常驻——整页呈现下活动模式同
                // 样需要显式关闭与分享落点（学 Muse 智
                // 能体页）；0.6.0 的「活动模式撤圆钮行」
                // 口径由整页化覆盖
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

                    shareButton(store)
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

    /// 大头像＋编辑徽章（L2，用户定案④打包）：头像
    /// 0.6.0 换三狗搭档款定版图（蓝图 §3.10：吉祥物用
    /// 自有 IP，不借 OpenMuse 水豚；素材源
    /// ~/workspace/ip-design/STYLE-partner.webp 裁头入
    /// SangouPartner 资产）；徽章点按跳本页身份段（规格
    /// §2 推荐口径：本页内闭环），身份的实际编辑在身份
    /// 段内跳 ProfilesView（用户定案⑤）。
    /// 0.36.22（枢纽页对齐包，用户新定案覆盖上段徽章
    /// 口径）：头像改读本地档案（AppState 单一出口：
    /// 预置/符号盘/相册自定义图）；徽章两模式统一改
    /// 档案菜单——「更换虚拟形象」「编辑名称」改的是
    /// 本机档案（AgentProfileStore），不是服务器身份；
    /// 身份段仍在段列里、服务端身份编辑口径不变。
    private var avatarBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            appState.agentAvatarImage
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 0.5)
                }

            Menu {
                Button {
                    showAvatarEditor = true
                } label: {
                    Label("更换虚拟形象", systemImage: "person.crop.circle")
                }
                Button {
                    showNameEditor = true
                } label: {
                    Label("编辑名称", systemImage: "pencil")
                }
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
                    // 0.23.0（命中域审计）：视觉盘 36 不变、
                    // 命中域外扩 44（盘居中）
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("编辑头像与名称")
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
                        GroupDivider()
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
                    .buttonStyle(.odPressable)
                }
                GroupDivider()
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
                .buttonStyle(.odPressable)
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
        case .tasks:
            HubTaskSection()
        case .approval:
            HubApprovalSection(store: store)
        case .browser:
            HubBrowserSection()
        case .cron:
            HubCronSection(store: store)
        case .monitors:
            HubMonitorSection()
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
        .buttonStyle(.odPressable)
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

