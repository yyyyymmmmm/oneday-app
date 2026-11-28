import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// 枢纽页分段沿革：§217 七段收四段（活动/定时/
/// 浏览器/身份，任务/审核/监测并入活动段）；
/// §434（2026-11-24，用户亲裁）分格改注册表驱动
/// ——写死枚举 HubSegment 整段退役，格集由 Core
/// HubSegmentRegistry 按真回读输入裁决（工作/
/// 审核/电脑/身份/邮箱五格登记，有真能力才长
/// 格），段 id/标题/图标单源在 HubSegmentID。
/// 定时并入工作格作「预定任务」折叠节（HubLed-
/// gerSection 内），审核格转正（HubAuditSec-
/// tion），浏览器格正名为电脑格（本体仍是
/// BrowserFaceView，云电脑通道）。

/// 中枢「选择模型」入口的注入包（§434）：宿主
/// （ChatView）把本会话模型账（分组/当前选择/
/// 落账回调）整包注入——选择器本体 ChatModel-
/// PickerView 同组件同数据源复用（§153），枢纽
/// 不另造一套；未注入时入口不出（测试装配台等
/// 无会话上下文的宿主不假装有模型可换）。
/// §名下状态行（2026-11-27）：增 onTap 回调——
/// 身份段模型按钮点按时触发（宿主传开面动作）
struct HubModelEntry {
    let groups: [ChatModelGroup]
    let current: ChatModelChoice
    /// 当前模型触发标签（宿主按 ModelDisplay-
    /// Names 同源派生，行尾展示）
    let currentLabel: String
    let onSelect: (ChatModelChoice) -> Void
    /// 点按入口回调（§名下状态行）：身份段模型
    /// 按钮点按时触发，宿主传 `{ showModelPicker = true }`
    let onTap: () -> Void
}

/// 智能体枢纽页（三期，规格 phase3-hub-spec）：页头
/// （圆钮行/头像/名/状态行）→ 分段 → 段内容（模型常
/// 驻区已随结构归位包撤除，见文末新注）。本视图自带
/// NavigationStack，呈现方不要再包一层。
/// 段切换只换内容区，页头常驻不动（规格 §0）。
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
/// §155（HUB-1 枢纽全量接通，用户 2026-11-11 拍板
/// 「死面接入真实的」）：ChatView 呈现改 .sheet 全量
/// 形态转正——七段全开＋模型常驻区，默认落活动段；
/// .activity 四段形态自此无入口（Mode 定义与段集留
/// 一版防回滚，下线归后续收口）。
/// §217（2026-11-13 枢纽收段＋呈现对齐，用户拍板）：
/// 分段七收四（活动/定时/浏览器/身份，任务/审核/
/// 监测并入活动，见 HubSegment 头注）；呈现由
/// fullScreenCover 改系统 sheet 大 detent 卡片式
/// （ChatView 侧 .sheet＋hubSheetPresentation()，
/// 对齐 Muse 枢纽的圆角卡浮起形态：初态留边圆
/// 角、后景压暗、落定近全屏；关闭反向回缩淡出走
/// 系统弹簧）。本视图的内容与导航栈不变，枢纽内
/// 自带 sheet（分享/模型/档案编辑）为嵌套呈现、
/// 与外层 sheet 互不相干。
/// §222（2026-11-14 枢纽页全页对 Muse 重建，用
/// 户总评「和人家的 UI 设计差远了」）：分段控件改自
/// 绘胶囊条对齐基准量测（系统 segmented 反相且尺寸
/// 钉死，见 segmentPicker 注）、撤条下 Divider、页
/// 头纵向节奏放开（头像→名字 16／名字→状态 8）；四
/// 段口径、模型常驻区、呈现形态（sheet 大 detent）
/// 一律不动，头像组件归头像呈现包、身份段正文提炼
/// 归专包。全档＝hub-page-muse-parity-report-
/// 20261114。
/// 结构归位包（2026-11-20，纲要 D4-1/D4-2，用户亲
/// 批「按纲要逐页归位」）：①页头状态行改「活动优
/// 先、状态兜底」——台账有进行中条目时显其人话标题
/// （多件显「正在进行 N 件 · 标题」，派生与进展胶
/// 囊同源 ProgressCapsule.derive、枢纽看全局不剔
/// 除任何会话），无进行中回落现行连接状态词；活动
/// 态图标换系统转圈、兜底保留圆点（落法＝hub-
/// muse-benchmark §3.2）。②段外「会话模型行」整
/// 区撤除：枢纽回归只读档案面，模型切换正主＝聊天
/// 页胶囊模型段 Menu 与模型设置页（本行自始即与
/// 胶囊同面同账的第二入口，撤之不丢功能）。
/// 台账 199（2026-11-21，全 App 收敛）：§155 留置
/// 的 Mode.activity 孤儿形态整段下线——Mode 枚举、
/// mode 属性与段集分支全删，本面只剩全量形态一种；
/// 上文 0.6.0/0.17.0/§155 各段关于 Mode 的记述自此
/// 均为历史。
/// §434（2026-11-24，页头改版包，用户五次亲点＋
/// 授权自拍）：呈现由 sheet 改导航 push（宿主
/// ChatView 须在 NavigationStack 内，zoom 转场挂
/// 宿主侧；本视图自带内层 NavigationStack 承载格
/// 内下钻的口径不变）；页头改居中 hero（覆盖
/// §344 横排）；分格改注册表驱动五格（覆盖 §217
/// 四段写死）；身份头下增「选择模型」入口（覆盖
/// 结构归位包「段外模型行撤除」——本轮用户亲点
/// 恢复为入口形态，点开仍是 §153 同一选择面、本
/// 会话作用域不变）；左缘右滑自研手势退役归系
/// 统 pop。正本＝header-zoom-spec-20261124.md。
struct AgentHubView: View {
    /// 审批终态回调（活动格据此刷新总览桥角标）
    var onApprovalChanged: (() -> Void)? = nil
    /// 选择模型入口注入（§434）：宿主给齐才出入口
    var modelEntry: HubModelEntry? = nil
    /// 卡片呈现关闭接缝（§502）：宿主（HubCard-
    /// Host）给齐时，✕ 与下钻关页走宿主飞出动画；
    /// 未给时回退系统 dismiss（其余四面 push 入口
    /// 与标准呈现照旧）
    var onCardClose: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 共享 store 同步直取（§449 第 4 条）：本体是
    /// AppState 的同步单例（0.36.21 起）——body 求
    /// 值即在手、内容首帧直出。旧 @State 可空＋.task
    /// 内赋值（且排在网络调用之后）令整页先转圈，
    /// 连同 body 的 nil 闸整段退役
    private var hubStore: AgentHubStore {
        appState.sharedHubStore()
    }
    @State private var segment: HubSegmentID = .work
    /// 分格注册表输入（§434）：初值＝连通＋本地通
    /// 道状态（Box 钥匙在位可同步判），其余回读旗
    /// 在开页任务回读后刷新——格集随真回读生长，
    /// 不在视图层写死
    @State private var segmentInputs: HubSegmentInputs =
        AgentHubView.initialSegmentInputs()
    /// 模型选择面（§434 入口点开，与聊天页同组件）
    @State private var showModelPicker = false
    /// 隐藏服务商待确认（§449 自顶栏选择面迁入，
    /// §158 口径不变）：点隐藏的组正是服务端当前
    /// 默认所在组时先弹后果确认，确认后才落账
    @State private var pendingHideGroup: ChatModelGroup?
    /// 头像/名称编辑面（0.36.22 档案菜单两项）
    @State private var showAvatarEditor = false
    @State private var showNameEditor = false

    /// 注册表初值输入：连通先行（枢纽开页即连通
    /// 语境，store 未就绪时内容区本就只显加载态）；
    /// Box 在位走钥匙串同步判（box.mcp.key，与
    /// BoxMCPClient 同键同源）；邮件能力等待本页
    /// /v1/capabilities 回读后才可用
    static func initialSegmentInputs() -> HubSegmentInputs {
        HubSegmentInputs(
            connected: true,
            grantsReadbackOK: false,
            approvalsReadbackOK: false,
            boxConfigured:
                KeychainStore.read(account: "box.mcp.key") != nil,
            mailDataSourceAvailable: false
        )
    }
    /// 分享名片懒生成载荷：点分享按钮时才离屏渲染名片图
    /// 并弹出系统分享面板，不在进页时预渲染
    @State private var shareSheetPayload: HubShareSheetPayload?

    /// 可见段（§434 注册表驱动）：格集＝注册表按
    /// 当前输入的裁决（工作/审核/电脑/身份/邮箱
    /// 按真能力生长），不再写死全集。初值输入下
    /// 恒含锚格（工作/身份），回读刷新后审核/电
    /// 脑格按活证长入
    var availableSegments: [HubSegmentID] {
        HubSegmentRegistry.resolve(segmentInputs)
    }

    /// 有效段集（§449 第 4 条）：注册表输入叠加共
    /// 享 store 的现行回读态——同会话内聊天页或上
    /// 一次开枢纽已把审批/授权拉成 .ready 时，本
    /// 次开页第一帧即全格，不等本页 .task 回读；
    /// 纯输入版 availableSegments 仍是注册表裁决
    /// 的单源（单测可直读、无环境依赖，口径不变）
    private func effectiveSegments(
        considering store: AgentHubStore
    ) -> [HubSegmentID] {
        var inputs = segmentInputs
        if case .ready = store.grantsState {
            inputs.grantsReadbackOK = true
        }
        if case .ready = store.approvalState {
            inputs.approvalsReadbackOK = true
        }
        return HubSegmentRegistry.resolve(inputs)
    }

    /// 通知落点的段位改道（§217 立、§434 沿用）：
    /// 原指向任务/审核/监测三撤段的落点全部改落
    /// 工作段——内容已并入工作台账（审批聚焦与
    /// 监测深链字段仍由 AppState 携带、工作段内
    /// 对号消费），落点语义一条不丢。纯函数收口
    /// 于此供单测钉死（HubSegmentsConsolidation-
    /// Tests）
    static func segment(
        for destination: NotificationDestination
    ) -> HubSegmentID {
        switch destination {
        case .approvalDecision, .approvalHome,
             .monitorChange, .monitorsHome:
            return .work
        case .approvalAnchor, .approvalThread, .none:
            // §165：锚点落点不在枢纽、本函数不被这类
            // 落点调用；防御性回落工作段
            return .work
        }
    }



    /// （根页左缘右滑退出手势 HubEdgeSwipe 已随
    /// §434 退役：中枢呈现由 sheet 改导航 push 后，
    /// 返回归系统交互式 pop 手势——平台原生优先，
    /// 自研边缘手势不与系统手势并存。Core 的
    /// HubEdgeSwipe 阈值件保留备查。）

    var body: some View {
        ZStack {
            // 整页底色先行：sheet 升起/退下与内容切换
            // 的空位是页底色而不是系统黑
            // （0.36.27 前此注的「边缘右滑跟手横移」已
            // 随整桥退役作废——新边缘拖不带页面跟手）
            Palette.pageBG.ignoresSafeArea()
            // 0.36.27（§97 件五）：栈绑回无参——0.36.26
            // 的 path 绑定深度门控已被真机证伪（path
            // 不追踪目标式推入、恒空），整桥退役后栈内
            // 页右滑返回全归系统 pop，不再需要栈深
            // 2026-11-24（手势审计问题二）：栈根挂全
            // 屏 pop 桥——卡内下钻页右滑走全屏 pop；
            // 卡级关卡手势的让行由宿主 HubCardHost
            // 按层级现采深度裁决（H1），path 绑定仍
            // 不复活
            NavigationStack {
                Group {
                    content(hubStore)
                }
                .background(Palette.pageBG)
            }
            .fullscreenPopBridge()
        }
        .sheet(isPresented: $showAvatarEditor) {
            AgentAvatarEditorView()
        }
        .sheet(isPresented: $showNameEditor) {
            AgentNameEditorView(
                initialName: appState.identityName ?? ""
            )
        }
        .sheet(item: $shareSheetPayload) { payload in
            HubShareActivitySheet(items: payload.items)
        }
        .task {
            hubStore.onApprovalChanged = onApprovalChanged
            // 机制还原（2.22.1/268）：进中枢先拉一次
            // 本体实时状况——顶栏胶囊与聊天页同源
            await appState.refreshAgentStatus()
            refreshSegmentInputs()
            // 阶段 1：首屏必需数据并发先行
            async let initial: Void = hubStore.loadInitial()
            async let ledger: Void = appState.sharedLedgerStore()
                .load(appState: appState)
            async let approval: Void = hubStore.loadApproval(force: true)
            async let mailCapability: Void = loadMailCapability()
            _ = await (initial, ledger, approval, mailCapability)
            refreshSegmentInputs()
            // §123（H2）：通知落点消费
            if let destination = appState.router.hubDestinationRequest {
                switch destination {
                case .approvalAnchor, .approvalThread:
                    break
                case .none:
                    break
                default:
                    segment = Self.segment(for: destination)
                }
                appState.router.hubDestinationRequest = nil
            }
            // 阶段 2：非必需后台请求延后到入场弹簧（≈0.38s）结束后再并发拉取
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            async let identity: Void = appState.refreshIdentitySurfaces()
            async let grants: Void = hubStore.loadGrants()
            _ = await (identity, grants)
            refreshSegmentInputs()
        }
    }

    /// 隐藏请求分流（§158 自 ChatView 顶栏选择面迁
    /// 入、口径逐字不变）：组键取不到不处理；组里
    /// 带默认标记＝服务端当前默认正走这组——先弹
    /// 后果确认（pendingHideGroup 的确认框在本面
    /// sheet 上声明）；其余直接落账隐藏。隐藏全程
    /// 只动本机呈现账（AppState），服务端与执行链
    /// 零触碰
    private func requestHideProviderGroup(_ group: ChatModelGroup) {
        guard ProviderGroupVisibility.groupKey(for: group) != nil
        else { return }
        if ProviderGroupVisibility.containsDefault(group) {
            pendingHideGroup = group
        } else {
            commitHideProviderGroup(group)
        }
    }

    private func commitHideProviderGroup(_ group: ChatModelGroup) {
        guard let key = ProviderGroupVisibility.groupKey(for: group)
        else { return }
        appState.hideProviderGroup(key: key)
    }

    /// 回读后刷新注册表输入（§434）：旗标只认真回
    /// 读结果——grants 或审批任一 ready，审核格长
    /// 入；当前段若被新格集落下（仅回读翻转时理
    /// 论可能），回落首格不留空段
    private func refreshSegmentInputs() {
        var inputs = segmentInputs
        if case .ready = hubStore.grantsState {
            inputs.grantsReadbackOK = true
        }
        if case .ready = hubStore.approvalState {
            inputs.approvalsReadbackOK = true
        }
        segmentInputs = inputs
        if !availableSegments.contains(segment) {
            segment = availableSegments.first ?? .work
        }
    }

    /// Email segment is enabled only by the live gateway feature flag.
    private func loadMailCapability() async {
        guard !appState.isDemo,
              let config = appState.config,
              let apiKey = await appState.effectiveBearerToken(),
              let capabilities = try? await appState.client.capabilities(
                config: config, apiKey: apiKey
              ) else { return }
        var inputs = segmentInputs
        inputs.mailDataSourceAvailable =
            capabilities.featureFlag("mail_gateway") == true
        segmentInputs = inputs
        if !availableSegments.contains(segment) {
            segment = availableSegments.first ?? .work
        }
    }

    private func content(_ store: AgentHubStore) -> some View {
        VStack(spacing: 0) {
            header(store)
            if let modelEntry {
                modelEntryRow(modelEntry)
            }
            segmentPicker(store)
            segmentContent(store)
        }
        .onChange(of: segment) { _, newSegment in
            Task { await loadSegment(newSegment, store: store) }
        }
        .sheet(isPresented: $showModelPicker) {
            if let modelEntry {
                // 同组件同数据源（§153/§434）：分组与
                // 当前选择由宿主注入的本会话模型账。
                // §449（第 2 条连带）：隐藏服务商自顶
                // 栏选择面迁入本面——分流/确认/落账整
                // 套随迁（旧「枢纽不改服务商收纳」口
                // 径由用户删顶栏令覆盖），顶栏侧同名
                // 逻辑已整删、全 App 只剩这一处
                ChatModelPickerView(
                    groups: modelEntry.groups,
                    current: modelEntry.current,
                    onSelect: { choice in
                        modelEntry.onSelect(choice)
                        showModelPicker = false
                    },
                    onHideGroup: { group in
                        requestHideProviderGroup(group)
                    }
                )
                .confirmationDialog(
                    "隐藏默认服务商？",
                    isPresented: Binding(
                        get: { pendingHideGroup != nil },
                        set: { if !$0 { pendingHideGroup = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("隐藏服务商", role: .destructive) {
                        if let group = pendingHideGroup {
                            commitHideProviderGroup(group)
                        }
                        pendingHideGroup = nil
                    }
                    Button("取消", role: .cancel) {
                        pendingHideGroup = nil
                    }
                } message: {
                    Text("隐藏这家，服务端的新对话默认也会随之改走默认服务商。当前已经打开的对话不受影响。")
                }
            }
        }
    }

    private func loadSegment(_ segment: HubSegmentID, store: AgentHubStore) async {
        switch segment {
        case .work:
            break // 工作段自持 LedgerStore（段内 .task 驱动）；审批数据由开枢纽时的强制重拉保鲜（见 body .task）
        case .audit:
            await store.loadGrants() // 审核段内 .task 亦拉，双路同守卫不重复发
        case .computer:
            break // 电脑面自带盒桥轮询（面内 .task 驱动）
        case .identity:
            await store.loadIdentityIfNeeded()
        case .mail:
            break // 邮件段由自身 .task 读取服务端列表
        }
    }

    /// 选择模型紧凑胶囊（居中轻胶囊，避免与下方分段条形成两条大胶囊叠罗汉）
    private func modelEntryRow(_ entry: HubModelEntry) -> some View {
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: OneDayMetrics.spacingXS) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.primary)
                Text(entry.currentLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(height: 34)
            .background(Palette.fillTertiary, in: Capsule())
            .frame(minHeight: OneDayMetrics.minTapTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.odPressable)
        .padding(.top, OneDayMetrics.spacingXS)
        .accessibilityLabel("选择模型，当前 \(entry.currentLabel)")
    }

    // MARK: - 页头（规格 §2）

    /// 分享圆钮（0.36.22）：内容换代为智能体名片——
    /// 名称＋头像＋服务器域名（仅 host），红线不含任
    /// 何凭据（AgentShareCard）；名片图未渲染就绪时
    /// 回落纯文本名片，按钮永不假装。旧 shareText
    /// （含当前模型、无域名）自此退出分享面
    private func shareButton(_ store: AgentHubStore) -> some View {
        Button {
            // 分享图懒生成：点分享时才离屏渲染名片图，渲染失败回落纯文本
            if let rendered = AgentShareItem.make(
                name: store.displayName,
                host: appState.serverShareHost,
                avatarImage: appState.agentAvatarImage
            ) {
                shareSheetPayload = HubShareSheetPayload(
                    items: [rendered.fileURL]
                )
            } else {
                shareSheetPayload = HubShareSheetPayload(
                    items: [AgentShareCardText.make(
                        name: store.displayName,
                        host: appState.serverShareHost
                    )]
                )
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        // 第 83 条（命中域收口）：玻璃盘 36 不变（样
        // 式按标签帧成盘）、命中域在钮外层外扩 44；
        // 负内边距抵消外扩、页头行布局不动
        .frame(
            width: OneDayMetrics.minTapTarget,
            height: OneDayMetrics.minTapTarget
        )
        .contentShape(Rectangle())
        .padding(-(OneDayMetrics.minTapTarget - 36) / 2)
        .accessibilityLabel("分享智能体名片")
    }

    private func header(_ store: AgentHubStore) -> some View {
        // §434（2026-11-24，用户亲点对位 Muse 身
        // 份页大头态）：页头恢复居中 hero——§344 的
        // 横排紧凑行（44 头像＋名/状态同行、总高
        // ≈118）由本节覆盖：头像 avatarHubHero 档
        // 居中（参照工具采样定值）、名居中（字阶
        // .title 28 bold 不动，HIG Title1 用户定版
        // 口径）、状态行居中；纵向节奏承 §222 hero
        // 口径（头像→名 16、名→状态 8）。§344 的
        // 收紧理由（占高过大）让位于用户本轮明确
        // 的整页对位要求，覆盖关系在此登记
        // §449（第 3/6 条）：钮行改与 hero 同带叠放
        // （ZStack 顶对齐）——§344 的独立成行退役：
        // 钮 44 命中帧顶与头像顶同线，钮心在头像心
        // 上方实得 ≈20.5pt（参照量测 ≈22，见 DESIGN
        // §449.3）
        ZStack(alignment: .top) {

            // 身份 hero（§434）：头像居中＋名居中＋
            // 状态行居中（状态语义与派生不动，仍是
            // statusLine 本体：活动优先、连接兜底）
            VStack(spacing: 0) {
                avatarBlock

                Text(store.displayName)
                    // §477：大名 .title(28) → hubHero-
                    // NameSize 令牌档；§500 订正：令牌
                    // 值 32→25（§477 注记的参照量测
                    // ≈32 系误记，实测 ≈25 bold，见
                    // hub-type-measurement-20261124.md）
                    .font(.system(
                        size: OneDayMetrics.hubHeroNameSize,
                        weight: .bold
                    ))
                    .lineLimit(1)
                    .padding(.top, OneDayMetrics.spacingM)

                statusLine(store)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, OneDayMetrics.spacingS)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OneDayMetrics.hubGutter)

            // 圆钮行（✕ 关闭＋分享名片）：0.36.22 起
            // 两模式统一常驻——整页呈现下活动模式同
            // 样需要显式关闭与分享落点（学 Muse 智
            // 能体页）；0.6.0 的「活动模式撤圆钮行」
            // 口径由整页化覆盖。§449 改同带叠放
            // （§344 独立成行退役，见 header 头注）
            HStack {
                // 页头圆钮（L1，用户定案③：照样板形态、
                // 用系统玻璃原生件拼装）
                Button {
                    closeHub()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                // 第 83 条（命中域收口）：玻璃盘 36 不
                // 变（样式按标签帧成盘）、命中域在钮外
                // 层外扩 44；负内边距抵消外扩、页头行
                // 布局不动
                .frame(
                    width: OneDayMetrics.minTapTarget,
                    height: OneDayMetrics.minTapTarget
                )
                .contentShape(Rectangle())
                .padding(-(OneDayMetrics.minTapTarget - 36) / 2)
                .accessibilityLabel("关闭")

                Spacer()

                shareButton(store)
            }
            .padding(.horizontal, OneDayMetrics.hubGutter)
        }
        .padding(.top, OneDayMetrics.spacingS)
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 状态行（结构归位包，D4-1）：第一语义＝
    /// 当前活动，连接状态降为兜底（无活动时回落
    /// 现行状态词，§449 起不带点）。§344 起自页头
    /// 抽出独立件、搬入身份行名下
    /// §449.9 增补：本轮工具活动短语（AppState.live-
    /// ActivityPhrase，与聊天页头胶囊第二行同源同
    /// 口径）优先于台账活动行——同一活动两面一词
    /// §477（2026-11-24）：第二级「台账标题顶替」
    /// 整级退役——无工具短语时旧派生拿台账进行中
    /// 条目的标题（会话名＋日期）顶上状态行，与参
    /// 照状态语义不符（审计头号差 2 定因）；自此
    /// 活动语义只许 liveActivityPhrase 单源（与
    /// §474 胶囊线同源收口），无短语即回落状态词，
    /// 不许再起第二套状态源
    private func statusLine(_ store: AgentHubStore) -> some View {
        // §477 呈现对齐：字档主黑（墨色口径保留）；
        // §500 订正：§477 注记的参照量测 ≈19–20 系
        // 误记——实测 ≈17 regular，字档回 .body 17
        // regular（hub-type-measurement-20261124.md）
        HStack(spacing: OneDayMetrics.rowInnerGap) {
            if let livePhrase = appState.capsuleActivityPhrase {
                ProgressView()
                    .controlSize(.mini)
                Text(livePhrase)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            } else if !store.statusText.isEmpty {
                // §449（03:19 去重）：状态点删除——
                // 本簇 presence 只以文案呈现（参照中
                // 枢状态行同为纯文案、无点）；词的派
                // 生与语义不动
                // §474：statusText 空串（运行中无待审
                // 批）＝本行不呈现，不留空行占位
                Text(store.statusText)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
        }
    }

    /// 头像＋编辑角标（L2，用户定案④打包）：头像
    /// 0.6.0 换三狗搭档款定版图（蓝图 §3.10：吉祥物用
    /// 自有 IP，不借 OpenMuse 水豚；素材源
    /// ~/workspace/ip-design/STYLE-partner.webp 裁头入
    /// SangouPartner 资产）；服务端人设的编辑在身份段
    /// 内的人设编辑面（§155 前旧注「跳 ProfilesView」
    /// 是空跳、已销账）。
    /// 0.36.22（枢纽页对齐包，用户新定案覆盖上段徽章
    /// 口径）：头像改读本地档案（AppState 单一出口：
    /// 预置/符号盘/相册自定义图）；徽章两模式统一改
    /// 档案菜单——「更换虚拟形象」「编辑名称」改的是
    /// 本机档案（AgentProfileStore），不是服务器身份；
    /// 身份段仍在段列里、服务端身份编辑口径不变。
    /// §434（hero 化）：头像升 avatarHubHero 档
    /// （§477 复量改 95）；菜单仍整头像承载——点头像
    /// 任意处出菜单（§344 立的口径不变），铅笔角标
    /// 随头像放大为 26pt 圆（字形等比），Palette.
    /// surface 底＋hairline 描边＋浮件档阴影不变
    private var avatarBlock: some View {
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
            ZStack(alignment: .bottomTrailing) {
                appState.agentAvatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: OneDayMetrics.avatarHubHero,
                        height: OneDayMetrics.avatarHubHero
                    )
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    }

                ZStack {
                    Circle().fill(Palette.surface)
                    Circle().stroke(Palette.hairline, lineWidth: 0.5)
                    Image(systemName: "pencil")
                        .font(.system(
                            size: FrameworkIcon.badgeGlyphSize + 4,
                            weight: .bold
                        ))
                        .foregroundStyle(Palette.ink)
                }
                .frame(width: 26, height: 26)
                // §247.3 档 F 浮件档（阴影两档之一）
                .shadow(
                    color: Palette.shadowBase.opacity(
                        ElevationTokens.floatingOpacity
                    ),
                    radius: ElevationTokens.floatingRadius,
                    y: ElevationTokens.floatingY
                )
            }
            .contentShape(Circle())
        }
        .accessibilityLabel("编辑头像与名称")
    }

    // MARK: - 四段分段控件（§222 胶囊条形态对齐）

    /// 分段条形态（§222，用户 2026-11-14 总评「枢纽页
    /// 和人家的 UI 设计差远了」后的全页对齐）：对 Muse
    /// 智能体页量测——整条胶囊高 ≈48、白面＋发丝描边，
    /// 选中段是浅灰填充胶囊（高 ≈36），图标 ≈22。系统
    /// segmented 与基准恰好反相（灰轨 32 高＋白选胶囊）
    /// 且高度/图标钉死不可调，形态对齐只能自绘；旧
    /// 「原生 segmented 先行」定案（0.36.22）由本节覆
    /// 盖。选中填充取 selectionFill——与 OpenMuse 底栏
    /// 激活项同一填充角色（Palette 本源）。段集/顺序/
    /// 图标走注册表输出（§434：HubSegmentRegistry
    /// 裁决的 HubSegmentID 列，形态本体不变）；
    /// 无障碍与旧 Picker 等价：按钮＋段名标签＋选中
    /// trait（UI 布局探针按标签回落查按钮、兼容）。
    /// 条下 Divider 撤除——基准是留白节奏不是线（宪
    /// 法③的分隔几何收口不在此面回潮）
    private func segmentPicker(
        _ store: AgentHubStore
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingXS) {
            ForEach(effectiveSegments(considering: store)) { item in
                let selected = segment == item
                Button {
                    segment = item
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 15, weight: selected ? .semibold : .regular))
                        Text(item.title)
                            .font(.caption.weight(selected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: OneDayMetrics.hubSegCapsuleHeight)
                    .background(
                        selected ? Palette.selectionFill : Color.clear,
                        in: Capsule()
                    )
                    .frame(height: OneDayMetrics.minTapTarget)
                    .contentShape(Rectangle())
                    .padding(
                        .vertical,
                        -(OneDayMetrics.minTapTarget
                            - OneDayMetrics.hubSegCapsuleHeight) / 2
                    )
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingXS)
        .frame(height: OneDayMetrics.hubSegBarHeight)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, OneDayMetrics.hubGutter)
        .padding(.top, OneDayMetrics.spacingSM)
        .padding(.bottom, OneDayMetrics.spacingSM)
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: segment
        )
    }

    /// 关页单点（§502）：卡片宿主在场走飞出动画关
    /// 闭、不在场走系统 dismiss——全页两处关页点
    /// （✕／台账下钻）共用，不许各点自判
    private func closeHub() {
        if let onCardClose {
            onCardClose()
        } else {
            dismiss()
        }
    }

    // MARK: - 段内容

    @ViewBuilder
    private func segmentContent(_ store: AgentHubStore) -> some View {
        switch segment {
        case .work:
            // 工作台账（§95）：段自持 LedgerStore，行
            // 下钻打开会话走既有 pendingChatSessionID
            // 通道，与旧活动行同路（下钻即关页）。
            // §217 起本段兼收任务/审批下钻补齐与监测
            // 合成条目；§434 起定时并入本段作「预定
            // 任务」折叠节（段内自理，见 HubLedger-
            // Section），原定时段整段退役
            HubLedgerSection(hubStore: store, onOpenSession: { sessionID in
                appState.router.pendingChatSessionID = sessionID
                closeHub()
            })
        case .audit:
            // 审核段（§434 转正）：授权账本＋审批记
            // 录，数据在 AgentHubStore（grants 回读
            // ＋决定账），本体 HubAuditSection
            HubAuditSection(hubStore: store)
        case .computer:
            // 电脑段：与应用格「浏览器」页共用同一
            // 面 BrowserFaceView（云电脑真画面＋接
            // 管，Simular Box 直连通道）
            HubBrowserSection()
        case .identity:
            HubIdentitySection(store: store, modelEntry: modelEntry)
        case .mail:
            HubMailSection()
        }
    }
}


/// 分享名片系统分享单载荷（点分享时懒生成，不在进页预渲染）
private struct HubShareSheetPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct HubShareActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController, context: Context
    ) {}
}

/// （§502 沿革：hubFullPageChrome 随 push 呈现退役——卡片呈现走 fullScreenCover、覆盖层自带全屏 chrome，藏栏修饰不再需要。）
