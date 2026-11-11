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
    /// 根页边缘拖退出已触发旗（0.36.27 §97 件五）：
    /// 整段拖动只许 dismiss 一次，松手复位防重入
    @State private var edgeDismissTriggered = false
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

    /// 根页左缘右滑退出手势（0.36.27 §97 件五）：起
    /// 始点须落在左缘 28pt 内（.global 坐标判），只
    /// 消费横向分量、途中过 60 即 dismiss（整段只触
    /// 发一次、旗防重入，松手复位）；浏览器段排除
    /// （与退役探针的 segment 门一致，网页自有横移
    /// 手势优先）。纵向拖动横向分量≈0、永不过线，
    /// 枢纽内纵滚不受扰
    private var hubEdgeDismissGesture: some Gesture {
        DragGesture(
            minimumDistance: HubEdgeSwipe.minimumDistance,
            coordinateSpace: .global
        )
        .onChanged { value in
            guard segment != .browser, !edgeDismissTriggered
            else { return }
            if HubEdgeSwipe.shouldTrigger(
                startGlobalX: value.startLocation.x,
                translationX: value.translation.width
            ) {
                edgeDismissTriggered = true
                dismiss()
            }
        }
        .onEnded { _ in
            edgeDismissTriggered = false
        }
    }

    var body: some View {
        ZStack {
            // 整页 cover 的底色先行：cover 升起/退下与
            // 内容切换的空位是页底色而不是系统黑
            // （0.36.27 前此注的「边缘右滑跟手横移」已
            // 随整桥退役作废——新边缘拖不带页面跟手）
            Palette.pageBG.ignoresSafeArea()
            // 0.36.27（§97 件五）：栈绑回无参——0.36.26
            // 的 path 绑定深度门控已被真机证伪（path
            // 不追踪目标式推入、恒空），整桥退役后栈内
            // 页右滑返回全归系统 pop，不再需要栈深
            NavigationStack {
                Group {
                    if let store {
                        content(store)
                    } else {
                        ProgressView()
                    }
                }
                .background(Palette.pageBG)
                // 根页左缘右滑退出（0.36.27 §97 件五）：
                // 挂点＝栈根内容本体——推入页覆盖其上、
                // 触摸不达此处，「仅根页生效」由挂点天
                // 然成立；构造与聊天右滑引用同族（同宿
                // 主已真机证明），判读走 Core HubEdge-
                // Swipe 阈值小件
                .simultaneousGesture(hubEdgeDismissGesture)
            }
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
            // §123（H2）：通知落点消费——按落点切到对
            // 应段（聚焦字段由各段自己消费），消费后清
            // 零，不许陈年请求在下次手动开枢纽时复活
            if let destination = appState.hubDestinationRequest {
                switch destination {
                case .approvalDecision, .approvalHome:
                    segment = .approval
                case .monitorChange, .monitorsHome:
                    segment = .monitors
                case .none:
                    break
                }
                appState.hubDestinationRequest = nil
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
            break // 台账段自持 LedgerStore（段内 .task 驱动）
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

            HStack(spacing: OneDayMetrics.rowInnerGap) {
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

    /// 模型行无障碍标签拼装（A11Y-V5）：选中行多
    /// 念一截「已选」，与可见勾形同义
    private static func modelRowA11yLabel(
        _ choice: ChatModelChoice, isSelected: Bool
    ) -> String {
        let name = ModelDisplayNames.displayName(for: choice.model)
            ?? choice.model
        var parts = [name]
        if let label = choice.sourceLabel {
            parts.append(L10n.string(label))
        }
        if isSelected { parts.append(L10n.string("已选")) }
        return parts.joined(separator: "，")
    }

    /// 枢纽模型区呈现集（§149）：全量分组清单拍平
    /// （组序即行序），与顶栏同源同物；分组未就绪时
    /// 为空（区内只剩默认行，不拿写死清单冒充）
    private var hubModelChoices: [ChatModelChoice] {
        appState.chatModelGroups.flatMap(\.choices)
    }

    /// 枢纽的会话键（§149）：枢纽自聊天页打开、语境
    /// 是主线——用主线键读写，与顶栏在主线时同账
    private var hubCurrentChoice: ChatModelChoice {
        appState.sessionModelChoice(
            serverSessionID: appState.sideChats.mainServerSessionID,
            threadID: nil
        )
    }

    /// 模型行无障碍特征（A11Y-V5）：选中行带
    /// isSelected，未选行为空集
    private static func modelRowA11yTraits(
        _ isSelected: Bool
    ) -> AccessibilityTraits {
        isSelected ? .isSelected : AccessibilityTraits()
    }

    // MARK: - 模型常驻区（规格 §2：不做第六段）

    private func modelZone(_ store: AgentHubStore) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            SectionLabel("会话模型")
                .padding(.horizontal, OneDayMetrics.pageGutter)
            VStack(spacing: 0) {
                ForEach(
                    Array(hubModelChoices.enumerated()),
                    id: \.element.id
                ) { index, choice in
                    if index > 0 {
                        GroupDivider()
                    }
                    Button {
                        appState.selectSessionModel(
                            choice,
                            serverSessionID: appState
                                .sideChats.mainServerSessionID,
                            threadID: nil
                        )
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                                Text(ModelDisplayNames.displayName(
                                    for: choice.model
                                ) ?? choice.model)
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                if let label = choice.sourceLabel {
                                    Text(L10n.string(label))
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                            Spacer()
                            if hubCurrentChoice == choice {
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
                    // 0.43.0（A11Y-V5）：当前模型只有勾
                    // 形——补「已选」播报（名＋来源＋已选）
                    // ＋特征，与房内先例同式。拼装走助
                    // 手函数：内联三元＋连加曾把本区表
                    // 达式压过类型检查时限（CI 实证）
                    .accessibilityLabel(
                        Self.modelRowA11yLabel(
                            choice, isSelected: hubCurrentChoice == choice
                        )
                    )
                    .accessibilityAddTraits(
                        Self.modelRowA11yTraits(
                            hubCurrentChoice == choice
                        )
                    )
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
            // 工作台账（§95）：段自持 LedgerStore，行
            // 下钻打开会话走既有 pendingChatSessionID
            // 通道，与旧活动行同路（sheet 模式关页、
            // 活动模式只置位）
            HubLedgerSection(onOpenSession: { sessionID in
                appState.pendingChatSessionID = sessionID
                if mode == .sheet {
                    dismiss()
                }
            })
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
}

