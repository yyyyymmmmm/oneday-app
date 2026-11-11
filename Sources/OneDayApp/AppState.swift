import Foundation
import OneDayCore
import SwiftUI

/// 三步探活的步骤口径：连接页与设置页「重新测试连接」共用。
enum ProbeStep: Int, CaseIterable {
    case health
    case login
    case apiKey

    var label: String {
        switch self {
        case .health: return L10n.string("健康检查")
        case .login: return L10n.string("登录面板")
        case .apiKey: return L10n.string("验证 API 密钥")
        }
    }
}

/// AppState 弱引用转手盒（0.36.20）：供 @Sendable 回
/// 调（URLSession 队列/monitor 队列触发）安全持有
/// AppState——盒本身 @unchecked Sendable、只持 weak
/// 引用，回调经盒取值后以 `Task { @MainActor in }`
/// 显式跳回主隔离，不让 @Sendable 闭包直接捕获主隔
/// 离类实例
final class WeakAppStateBox: @unchecked Sendable {
    weak var value: AppState?

    init(_ value: AppState) {
        self.value = value
    }
}

/// 连接状态单点：持有当前服务器配置与客户端，负责
/// 启动恢复、三步探活、凭据存取、会话过期自动重登、断开连接。
/// 凭据只经 Keychain 进出，本类不落任何明文副本到磁盘。
@MainActor
@Observable
final class AppState {
    enum Phase {
        case needsConnection
        case connected
    }

    private(set) var phase: Phase = .needsConnection
    private(set) var config: ServerConfig?
    private(set) var username: String?
    /// 对话模型 id：探活第三步从 /v1/models 取第一个，缺失时回退实测值
    private(set) var modelID: String = "hermes-agent"
    // MARK: - §153 本会话模型（顶栏包 B1/B2/B4）

    /// 顶栏全量分组清单（§153 B1）：网关组（options
    /// 回执分组）＋具名服务商各组（注册表）同源拼装
    /// （Core ChatModelGroups.build 唯一拼装口），随
    /// 目录刷新一并重建；设置页增删服务商后同源刷新
    /// （refreshModelCatalog 是两面的共同入口）
    private(set) var chatModelGroups: [ChatModelGroup] = []

    /// 本会话选择账（§153 B2）：按会话键记各自的执行
    /// 选择（model＋providerField），UserDefaults 一份
    /// JSON 字典落盘（键＝会话键，见 sessionModelKey）。
    /// 私有 chatModel 全局单值层自此退场——旧键
    /// chatModelID 只在迁移播种时读一次（见
    /// refreshModelCatalog），不再写入
    private(set) var sessionModelChoices: [String: ChatModelChoice] = [:]

    /// 旧全局选择迁移标记（只迁一次：把 chatModelID
    /// 旧值播种给主线会话，免用户升级后被默认顶掉）
    private var legacyChatModelMigrated: Bool {
        get {
            UserDefaults.standard.bool(forKey: "chatModelMigrated149")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "chatModelMigrated149")
        }
    }

    /// 会话键：服务端会话 id 优先（跨设备/重装同认）；
    /// 尚无服务端 id 的本地线程用线程 id；主线未链接
    /// 时用固定键 main
    static func sessionModelKey(
        serverSessionID: String?, threadID: UUID?
    ) -> String {
        if let serverSessionID, !serverSessionID.isEmpty {
            return "s:\(serverSessionID)"
        }
        if let threadID { return "t:\(threadID.uuidString)" }
        return "main"
    }

    /// 本会话执行选择（B2/B4 同源口）：会话自选（仍在
    /// 清单内）＞服务端默认播种＞分组首项；分组未就绪
    /// 时回落历史口径（旧 chatModelID＞服务端默认＞
    /// 写死 fallback），保证离线/未刷新时顶栏仍有值
    func sessionModelChoice(
        serverSessionID: String?, threadID: UUID?
    ) -> ChatModelChoice {
        let key = Self.sessionModelKey(
            serverSessionID: serverSessionID, threadID: threadID
        )
        if let resolved = SessionModelResolution.resolve(
            stored: sessionModelChoices[key],
            groups: chatModelGroups,
            serverDefault: SessionModelResolution.serverDefaultChoice(
                in: chatModelGroups, defaultModel: defaultModel
            )
        ) {
            return resolved
        }
        let legacy = UserDefaults.standard.string(forKey: "chatModelID")
            ?? defaultModel ?? ChatModels.fallbackID
        return ChatModelChoice(
            model: ModelDisplayNames.canonicalID(for: legacy),
            providerField: ChatModels.contains(legacy) ? "custom" : nil
        )
    }

    // MARK: - §156 已隐藏服务商（本机呈现治理）

    /// 已隐藏服务商的组键集（本机持久化，UserDefaults
    /// 一键 JSON；Core ProviderGroupVisibility 编解码
    /// 唯一口径）。隐藏只撤呈现：服务端 config 不动、
    /// 执行管线（availableModels/sessionModelChoices）
    /// 不读本账
    private(set) var hiddenProviderGroupKeys: Set<String> = {
        ProviderGroupVisibility.decodeHidden(
            UserDefaults.standard.data(
                forKey: SectionCollapseStorageKeys.hiddenProviders
            )
        )
    }()

    /// 选择器呈现分组：全量分组过隐藏过滤（Core 唯一
    /// 过滤口，含默认组结构闸在此）
    var pickerModelGroups: [ChatModelGroup] {
        ProviderGroupVisibility.visibleGroups(
            chatModelGroups, hidden: hiddenProviderGroupKeys
        )
    }

    /// 隐藏一组（管理动作的唯一写入点）：只落本机账
    /// 并重算呈现，不发任何网络请求、不改服务端
    func hideProviderGroup(key: String) {
        hiddenProviderGroupKeys.insert(key)
        UserDefaults.standard.set(
            ProviderGroupVisibility.encodeHidden(
                hiddenProviderGroupKeys
            ),
            forKey: SectionCollapseStorageKeys.hiddenProviders
        )
    }

    /// 恢复一组（设置页「已隐藏的服务商」唯一写入点）
    func restoreProviderGroup(key: String) {
        hiddenProviderGroupKeys.remove(key)
        UserDefaults.standard.set(
            ProviderGroupVisibility.encodeHidden(
                hiddenProviderGroupKeys
            ),
            forKey: SectionCollapseStorageKeys.hiddenProviders
        )
    }

    /// 本会话模型 id（发送与触发器共用此口，不许两处
    /// 各算一份）
    func chatModel(
        serverSessionID: String?, threadID: UUID?
    ) -> String {
        sessionModelChoice(
            serverSessionID: serverSessionID, threadID: threadID
        ).model
    }

    /// 本会话选择落账（顶栏/枢纽选择器唯一写入点）：
    /// 别名先归一（B4），只记账不发网络请求、不改服
    /// 务端默认——作用域就是本会话
    func selectSessionModel(
        _ choice: ChatModelChoice,
        serverSessionID: String?, threadID: UUID?
    ) {
        let key = Self.sessionModelKey(
            serverSessionID: serverSessionID, threadID: threadID
        )
        let canonical = ChatModelChoice(
            model: ModelDisplayNames.canonicalID(for: choice.model),
            providerField: choice.providerField,
            isDefault: choice.isDefault
        )
        sessionModelChoices[key] = canonical
        persistSessionModelChoices()
    }

    private func persistSessionModelChoices() {
        let dict: [String: [String: String]] = sessionModelChoices
            .mapValues { choice in
                var fields = ["model": choice.model]
                if let provider = choice.providerField {
                    fields["provider"] = provider
                }
                return fields
            }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "chatModelBySession")
        }
    }

    private func loadSessionModelChoices() {
        guard let data = UserDefaults.standard.data(
            forKey: "chatModelBySession"
        ),
        let dict = try? JSONDecoder().decode(
            [String: [String: String]].self, from: data
        ) else { return }
        sessionModelChoices = dict.compactMapValues { fields in
            guard let model = fields["model"], !model.isEmpty
            else { return nil }
            return ChatModelChoice(
                model: model, providerField: fields["provider"]
            )
        }
    }

    /// 已下线模型落回提示（0.32.1，F05 止血）：旧全局
    /// 选择命中已停用模型时一次性如实告知（§153 后判
    /// 定输入改读旧键原值，语义不变）
    private(set) var modelFallbackNotice: String? =
        ChatModels.retiredFallbackNotice(
            stored: UserDefaults.standard.string(forKey: "chatModelID")
        )

    /// 消费落回提示：清提示（旧键自 §153 起只读不写，
    /// 消费后靠本标记防重报——提示本身由本属性承载、
    /// 清掉即不再生成）
    func consumeModelFallbackNotice() {
        modelFallbackNotice = nil
    }

    /// 抽屉数据刷新令牌（0.21.0）：已链接旁聊标题
    /// 回流的触发通道——服务端 llm 标题在首轮回复
    /// 后数秒才升级，抽屉须在一轮落地后主动重拉服
    /// 务端会话表才见新名。触发点全集：①抽屉打开/
    /// 壳层预挂载（0.18.0 既有 onAppear）；②App 回
    /// 前台（0.21.0 新增 scenePhase）；③已链接旁聊
    /// 一轮完整落地——即时一次＋6 秒延迟一次（本方
    /// 法）。DrawerView 观察本令牌变化重拉，本类只
    /// 记账不持有抽屉状态
    private(set) var drawerRefreshTick = 0

    func noteLinkedSideChatTurnFinished() {
        drawerRefreshTick += 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            drawerRefreshTick += 1
        }
    }
    /// 服务端默认模型（0.2.2 获取制）：自 /api/config 的 model 键
    /// 拉取，聊天页顶栏与抽屉身份块展示它；切换走 setDefaultModel
    private(set) var defaultModel: String?
    /// 可切换模型目录（0.2.4 根治）：候选只许来自上游——
    /// /api/model/options 正规端点优先，为空回落「用量 ∪
    /// 当前值」，且硬排除网关别名（见 ModelCatalog）。0.2.2
    /// 把网关 /v1/models 的别名并进候选是 bug，已撤销
    private(set) var availableModels: [String] = []
    /// 具名服务商模型总数（§119 未配模型判定用，随
    /// 目录刷新从 config 派生；nil＝还没读到配置）
    private(set) var providerModelTotal: Int?
    /// 网关别名集（/v1/models 返回的 id，如 hermes-agent）：
    /// 是客户端调网关时填的模型名、不是上游模型；只许在
    /// 连接信息里只读出现，永不进默认模型候选
    private(set) var gatewayAliases: Set<String> = []

    let client: HermesClientProtocol
    /// 演示模式（截图验收环）：为真时不读不写 Keychain、
    /// 不发网络请求（客户端已被替换为 DemoHermesClient）。
    let isDemo: Bool
    /// 会话派生标题解析器（0.6.1）：抽屉行/活动行共用
    /// 的首条消息缓存与预算拉取，全 App 只此一份
    let sessionTitles = SessionTitleResolver()

    /// 旁聊语义状态（0.7.0）：主线钦定/归档/标题覆盖/轻保活，
    /// 演示模式纯内存不落盘（见 SideChatStore）
    let sideChats: SideChatStore
    /// 未落定 run 账本（0.31.0）：生成中切后台/杀进程
    /// 后靠它恢复对账（ChatView 驱动消费）
    let runLedger: RunLedgerStore
    /// 设备会话控制器（0.34.0，本机连接器批一）：前
    /// 台＋已连接时向 device-bridge 注册会话、领智能
    /// 体的设备工具调用现读现回；生命周期由 RootView
    /// 按 scenePhase/连接态驱动（见 DeviceSession-
    /// Controller）。演示模式下控制器恒不激活
    let deviceSession: DeviceSessionController
    /// 同步控制器（0.36.14，同步制）：五数据集的副
    /// 本同步（授权→最小化副本→自有伴生服务）；与
    /// 设备会话共用同一分发器的引擎读本地数据，前
    /// 台检查由 RootView 与设备会话同拍驱动
    let deviceSync: DeviceSyncController

    /// 总览桥鉴权失败旗（0.7.0）：由 OverviewBridgeStore
    /// 在每轮刷新时回写——桥钥匙未粘（noKey）或被拒
    /// （401）为 true，桥取数成功清零，网络类失败不动
    /// 本旗（不把抖动说成钥匙问题）。设置页据此露
    /// 「桥未连接」提示，胶囊状态行不读本旗
    var overviewBridgeAuthFailed = false
    /// 本人裁决集（0.36.5，审批联动 C 部）：本人在
    /// App 内批准/驳回过的 write-gate 记录 id——其裁
    /// 决回执通知一到即自动消账（Core ApprovalReso-
    /// lution 判定、OverviewBridgeStore 执行）。落
    /// UserDefaults 是为跨重启仍认账（回执可能晚于
    /// 裁决一轮轮询才生成）；上限 200 条、超出弃最
    /// 旧（回执生成以分钟计，陈年 id 无联动价值）
    private(set) var selfDecidedApprovalIDs: Set<String> =
        Set(UserDefaults.standard.stringArray(
            forKey: "selfDecidedApprovalIDs"
        ) ?? [])

    /// 全局共享的枢纽 store（0.36.21，审批卡包）：聊
    /// 天内就地审批卡与枢纽审核段必须读同一份 /pending
    /// 数据、走同一个裁决动作（规格 §6），store 自此
    /// 由 AppState 持有单例、懒建；此前 AgentHubView
    /// 每次打开自建一份，聊天侧无从共享。审批终态回
    /// 调（刷新总览桥角标）仍由呈现枢纽的 ChatView 经
    /// AgentHubView 注入 store.onApprovalChanged
    private var hubStoreInstance: AgentHubStore?

    func sharedHubStore() -> AgentHubStore {
        if let hubStoreInstance { return hubStoreInstance }
        let store = AgentHubStore(
            appState: self,
            gateClient: isDemo ? DemoWriteGateClient() : WriteGateClient()
        )
        hubStoreInstance = store
        return store
    }

    /// 记一笔本人裁决（AgentHubStore.decide 成功落
    /// 账后调用；recordGone 等他人先裁的路径不记——
    /// 那类回执是「未读重要事件」、不归本人消账）
    func noteSelfDecision(recordID: String) {
        guard !recordID.isEmpty,
              !selfDecidedApprovalIDs.contains(recordID)
        else { return }
        selfDecidedApprovalIDs.insert(recordID)
        if selfDecidedApprovalIDs.count > 200 {
            selfDecidedApprovalIDs = Set(
                selfDecidedApprovalIDs.sorted().suffix(200)
            )
        }
        UserDefaults.standard.set(
            Array(selfDecidedApprovalIDs),
            forKey: "selfDecidedApprovalIDs"
        )
    }
    /// 云电脑接管态（0.10.0，P3 互斥的客户端半边）：
    /// BrowserFaceView 在接管开关变化时回写（施工图
    /// §4.3 产品层约定：Box 单桌面无锁原语，接管期间
    /// 暂停任务派发）。任务段据此禁用派发类动作并明示
    /// 原因；服务端真联动（派发层真暂停）待生产验收轮
    var boxTakeoverActive = false
    /// 智能体身份名（0.6.1，用户真机点名）：全局唯一解
    /// 析点——胶囊/抽屉/活动页三处显示名都读这里；值由
    /// soul 一级标题经 OneDayCore.AgentName.resolve 得
    /// 出，取不到为 nil、显示层回落 AgentName.fallback；
    /// 旧「档案名翻译当标题」（default→默认档案）口径
    /// 退役
    private(set) var identityName: String?
    private var identityNameResolved = false

    /// 解析身份名（幂等：只真正拉取一次；失败也记已解
    /// 析、回落显示，不逐次重试打服务端）。数据链：
    /// 档案列表 → 默认档案 → 其 soul → AgentName
    func resolveIdentityNameIfNeeded() async {
        guard !identityNameResolved, config != nil else { return }
        identityNameResolved = true
        guard let profiles = try? await performAdmin({ client, config in
            try await client.profiles(config: config)
        }),
              let profile = profiles.first(where: { $0.isDefault == true })
                ?? profiles.first,
              let document = try? await performAdmin({ client, config in
                  try await client.profileSoul(config: config, name: profile.name)
              })
        else { return }
        identityName = AgentName.resolve(soulContent: document.content)
    }

    /// 智能体本地档案（0.36.22，枢纽页对齐包）：用户
    /// 在本机改的显示名覆盖与头像，全 App 露脸面经下
    /// 方收敛口读，不再各自拼 identityName 回落链、更
    /// 不许写死字面名。档案只管呈现：identityName 仍
    /// 是 soul 解析的服务端真源，覆盖没设时自动跟随
    let agentProfileStore = AgentProfileStore()

    /// 伴生探测（本包，DESIGN §110）：登录后自动探
    /// 测伴生存在与版本（/api/companion/info），派生
    /// 态供设置页版本组消费；触发点在 RootView（连接
    /// 成立/回前台/冷启恢复，与设备会话同拍），派生
    /// 与缓存口径在 Core CompanionProbe 一件
    let companionProbe = CompanionProbeStore()

    /// 露脸面显示名单一出口：档案覆盖 → soul 解析名
    /// → Hermes 回落（OneDayCore.AgentDisplayName）
    var agentDisplayName: String {
        AgentDisplayName.resolve(
            override: agentProfileStore.profile.displayNameOverride,
            soulName: identityName
        )
    }

    /// 档案改名覆盖原值（枢纽店头的多源链还要再叠一
    /// 层本店 soul 解析，故单独出口）
    var profileNameOverride: String? {
        agentProfileStore.profile.displayNameOverride
    }

    /// 露脸面头像单一出口：档案解析图（预置/符号盘/
    /// 自定义图已在存储层收敛成一张）
    var agentAvatarImage: Image {
        agentProfileStore.avatarImage
    }

    /// 分享名片域名：只出 host（AgentServerHost 红线
    /// 口径）——读 Keychain 里的服务器地址串当场提取，
    /// 不缓存、不带出任何其他部分
    var serverShareHost: String? {
        AgentServerHost.extract(
            from: KeychainStore.read(account: CredentialKey.baseURL)
        )
    }

    /// 跨页深链（总览 → 智能体格/设置格二级页）：目标页消费后置 nil
    var pendingAgentRoute: AgentRoute?
    var pendingSettingsRoute: SettingsRoute?
    /// 设置 sheet 打开请求（0.20.0）：抽屉齿轮置位，
    /// ContentView 消费呈现根级设置 sheet 后置 false。
    /// 0.6.0 的 pendingAppsPage 通道随应用格退役一并
    /// 删除——应用格页面已各有新家（总览/电脑/服务器
    /// 文件进设置「管理」组、文件格升底栏），不再有
    /// 「切格落位」这回事
    var settingsSheetRequested = false
    /// 底栏切格请求（0.29.0）：设置内页面（如连接器目
    /// 录的本机服务详情）要把用户送到目标/点子底栏格
    /// 时置位，ContentView 消费后关设置 sheet 并切格
    /// 并清零——置位—消费—清零与 settingsSheet-
    /// Requested 同式；目标格枚举与底栏本体同源
    /// （ContentView.MainTab），不另立第二套格名
    var mainTabSwitchRequest: ContentView.MainTab?
    /// 文件页定位请求（§131，D8「在文件页中打开」）：
    /// 打开页动作置位目标路径并同行置 mainTabSwitch-
    /// Request=.files 切格，DeliverablesView 消费后
    /// 滚动定位＋高亮该行并清零——置位—消费—清零与
    /// pendingChatSessionID 同式
    var fileRevealPath: String?
    /// 文件库内容修订号（§131）：打开页改名成功后递
    /// 增，文件页以此为 .task(id:) 键重聚合——改名
    /// 结果不在文件页留旧名残影
    var fileLibraryRevision = 0
    /// 待续聊的服务端会话 id（0.4.0，审计 §3.4）：四处
    /// 入口（抽屉／服务端会话页／状态页／定时运行记录）
    /// 置位，ContentView 据此切聊天格、ChatView 消费后
    /// 导入历史并置 nil。不再走设置格的只读详情页
    var pendingChatSessionID: String?
    /// 待续聊会话的频道来源标记（0.36.29，频道规格
    /// §10.3）：频道页点行时与 pendingChatSessionID
    /// 同行置位（先标记、后置 id），ChatView 消费时
    /// 据此把抽屉当前对象置为 .channel 并落频道观
    /// 看出处；其他入口打开会话不置此标记，消费口
    /// 径据「无标记」清旧出处。消费后清零
    var pendingChatChannelID: String?
    /// 频道观看出处（0.36.29，§10.2）：当前线程是
    /// 从哪个频道的哪条会话打开的——ChatView 当前
    /// 线程同步据此维持 .channel 对象引用（导入线
    /// 程渲染期间不派生成 .side）；线程切离该会话
    /// 或从旁聊区/主线行重进同一条时由各置位点清
    /// 除。只存呈现出处、不参与分类（分类归属与选
    /// 择归属是两件事）
    var channelViewingOrigin: ChannelViewingOrigin?
    /// 总览快捷动作「新建定时任务」：定时页消费后自动拉起新建表单
    var cronCreateRequested = false
    /// 点子底栏角标（§123 M3）：新到的生成待阅卡数。
    /// 判定在 Core IdeasBadge（增量水位制），本类只持
    /// 数与水位落盘：ContentView 既有 30 秒轮询拍顺带
    /// 刷新（不新增轮询回路），进点子页即清零推进水位
    /// ——与动态角标同清零口径
    var ideasUnread = 0
    /// 点子已见水位（UserDefaults 落盘；nil＝还没立过
    /// 基线，首次刷新只立基线不报数，见 IdeasBadge）
    var ideasSeenWatermark: Double? {
        get {
            UserDefaults.standard.object(
                forKey: "ideas.seenWatermark"
            ) as? Double
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue, forKey: "ideas.seenWatermark"
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: "ideas.seenWatermark"
                )
            }
        }
    }

    /// 轮询拍刷新点子角标：无水位先立基线（存量不报
    /// 数）；有水位按增量判定。拉取失败不调用本方法，
    /// 角标保持旧值不清零（与动态角标同纪律）
    func refreshIdeasUnread(ideas: [BridgeIdea]) {
        guard let watermark = ideasSeenWatermark else {
            ideasSeenWatermark = IdeasBadge.advancedWatermark(
                ideas: ideas, current: nil
            )
            ideasUnread = 0
            return
        }
        ideasUnread = IdeasBadge.newCount(
            ideas: ideas, watermark: watermark
        )
    }

    /// 进点子页：水位推进到当前最新生成卡、角标清零
    func markIdeasSeen(ideas: [BridgeIdea]) {
        ideasSeenWatermark = IdeasBadge.advancedWatermark(
            ideas: ideas, current: ideasSeenWatermark
        )
        ideasUnread = 0
    }

    /// 通知落点请求（§123 H2）：通知中心点条目时置位
    /// （落点解析在 Core NotificationDestination），
    /// AgentHubView 开枢纽时消费段位、对应段消费各自
    /// 的聚焦字段，消费后清零——置位—消费—清零与
    /// hubOpenRequested 同式
    var hubDestinationRequest: NotificationDestination?
    /// 审批段聚焦的已决记录 id（approvalDecision 携带来）
    var hubApprovalFocusID: String?
    /// 监测段深链：直达的监测 id 与变化 id（变化 id 为
    /// nil 时只达监测详情）
    var monitorDeepLink: (monitorID: String, changeID: String?)?

    /// 通知条目落点分发：把落点拆成枢纽各段能消费的
    /// 字段；返回 false 表示无落点（调用方不导航）
    @discardableResult
    func requestHubDestination(
        _ destination: NotificationDestination
    ) -> Bool {
        switch destination {
        case .approvalDecision(let id):
            hubApprovalFocusID = id
        case .monitorChange(let monitorID, let changeID):
            monitorDeepLink = (monitorID, changeID)
        case .approvalHome, .monitorsHome, .none:
            break
        }
        guard destination.hasDestination else { return false }
        hubDestinationRequest = destination
        return true
    }
    /// 抽屉「枢纽」导航行的开枢纽请求（0.19.0）：抽屉置
    /// 位（先切聊天格再置位），ChatView 消费后开枢纽
    /// sheet 并清零——置位—消费—清零与 cronCreate-
    /// Requested 同式。枢纽 sheet 本体长在聊天页（胶囊
    /// 入口同处），不在抽屉另立第二份承载
    var hubOpenRequested = false
    /// 聊天抽屉开合的语义状态（0.2.2 立；0.4.5 改口径，
    /// §30）：壳层 ContentView 是执行者（覆盖式动画与跟手
    /// 状态在壳层），任何视图想开/关抽屉只写这里、壳层
    /// onChange 执行；DrawerView 据此在打开时补拉服
    /// 务端会话 source 映射（0.19.0 返工瘦身：只喂旁
    /// 聊行显的来源过滤判定，不再拉名单成行——名单
    /// 本体是本地线程）。（0.2.2–0.4.4 的旧注「Con-
    /// tentView 据此隐藏自绘底栏」随自绘底栏与覆盖式
    /// 抽屉一并作废）
    var drawerPresented = false
    /// 抽屉与 ChatView 之间的通道（0.4.5，抽屉提到
    /// 壳层后立；模式与 pendingChatSessionID 一致：置位
    /// 方写、消费方读后清零）
    /// 抽屉当前对象引用（0.36.7，频道规格 §10.2/§10.3）：
    /// 全抽屉唯一选择源——写入点只有导航动作（抽屉主
    /// 线行→.main、旁聊行→.side）与 ChatView 的当前线
    /// 程同步（落点/切换/新建/导入都经它派生）；抽屉
    /// 胶囊只许问 Core DrawerSelectionPolicy，不许再
    /// 私读页签或线程 id 自画。页签切走不清、回切恢
    /// 复。0.4.5 的 activeThreadID 随本引用落地退役
    /// （其消费面——胶囊判定与删当前线程判定——已全
    /// 部改读本引用经政策解析）
    var currentDrawerObject: DrawerCurrentObject?
    /// 抽屉点选/新建的线程 id（DrawerView 写，ChatView
    /// 消费后切 currentThreadID 并清零）
    var drawerThreadSelection: UUID?
    /// 抽屉刚删掉的线程 id（DrawerView 写，ChatView 若
    /// 正显示该线程则置空 currentThreadID 并清零）
    var drawerDeletedThreadID: UUID?

    /// 业务成功信号代次（0.36.20，§86.2）：HermesClient
    /// 任一业务请求收到 HTTP 响应即经回调递增，壳层观
    /// 察变化把在线判定清零回写（治 R4 双通道互不作证）
    private(set) var hermesBusinessSuccessTick = 0
    /// 网络路径恢复/切换代次（0.36.20，§86.4）：
    /// NetworkPathObserver 触发即递增——壳层据此立即
    /// 重探活、聊天页据此续对账；只是触发器，不携带
    /// 任何「离线」结论
    private(set) var networkPathEpoch = 0

    /// 业务成功信号落点（0.36.20）：只许主隔离上调
    func noteHermesBusinessSuccess() {
        hermesBusinessSuccessTick += 1
    }

    /// 路径触发信号落点（0.36.20）：只许主隔离上调
    func noteNetworkPathRecovered() {
        networkPathEpoch += 1
    }

    init(client: HermesClientProtocol = HermesClient(), demoMode: DemoMode = .off) {
        self.client = client
        isDemo = demoMode.isDemo
        sideChats = SideChatStore(persisted: !demoMode.isDemo)
        runLedger = RunLedgerStore(persisted: !demoMode.isDemo)
        deviceSession = DeviceSessionController()
        deviceSync = DeviceSyncController()
        deviceSync.dispatcher = deviceSession.dispatcher
        // 供给收敛（0.36.18）：五件记录型的「允许调
        // 用」不再有独立开关与镜像——会话每次重读权
        // 限时一律对齐真实权限（refreshPermissions
        // 内落），本处不再接线
        switch demoMode {
        case .connected:
            // 演示会话：地址与账号只是展示数据，密钥由假客户端消化
            config = ServerConfig(rawInput: "https://hermes.didichou.site")
            username = "admin"
            // 演示口径：模型名与总览「当前配置」同为 deepseek-chat，
            // 三处展示（顶栏副题/抽屉服务器行/设置）一致；假客户端
            // 不校验模型名，生产路径的 modelID 仍以 /v1/models 为准
            modelID = "deepseek-chat"
            defaultModel = "deepseek-chat"
            availableModels = ["deepseek-chat", "deepseek-flash", "deepseek-v4-pro"]
            gatewayAliases = ["hermes-agent"]
            phase = .connected
        case .connectPage:
            // 停在连接页：保持未连接，字段预填在 ConnectView 侧
            break
        case .off:
            restore()
        }
        // 0.36.20（§86.2/§86.4）：连接稳固两路信号接线
        // ——必须在全部存储属性初始化完成后（self 完整
        // 成立后才许把 self 装进弱盒）。回调都从非隔离
        // 域（URLSession 队列/monitor 队列）触发、只许
        // 经 Task 显式跳回主隔离写计数；@Sendable 闭包
        // 不直接捕获本类，经 @unchecked Sendable 弱盒
        // 转手（盒内只持 weak 引用）
        if !demoMode.isDemo {
            // §153：回读本会话模型账——init 内调 self
            // 方法须在全部存储属性初始化之后（二轮 CI
            // 实证：前置调用报 self 未完全初始化）
            loadSessionModelChoices()
        }
        let signalBox = WeakAppStateBox(self)
        if let hermesClient = client as? HermesClient {
            hermesClient.onTransportSuccess = {
                Task { @MainActor in
                    signalBox.value?.noteHermesBusinessSuccess()
                }
            }
        }
        NetworkPathObserver.shared.start {
            Task { @MainActor in
                signalBox.value?.noteNetworkPathRecovered()
            }
        }
    }

    // MARK: - 启动恢复

    /// 已连接的判定（0.6.0 直登口径）：地址＋API 密钥
    /// （Bearer）齐全即成立；面板账号/密码是 0.5.x 四件
    /// 套存量凭据，有则一并恢复（管理面自动重登要用），
    /// 缺失不挡直登成立——直登连接的管理面 401 时没有
    /// 静默重登兜底、按会话过期报错（performAdmin 口径）。
    private func restore() {
        guard let base = KeychainStore.read(account: CredentialKey.baseURL),
              let config = ServerConfig(rawInput: base),
              KeychainStore.read(account: CredentialKey.apiKey) != nil else {
            phase = .needsConnection
            return
        }
        self.config = config
        username = KeychainStore.read(account: CredentialKey.username)
        phase = .connected
    }

    var apiKey: String? {
        // 演示假值：只会被递给 DemoHermesClient，不出设备
        if isDemo { return "demo-api-key" }
        return KeychainStore.read(account: CredentialKey.apiKey)
    }

    private var password: String? {
        if isDemo { return "demo-password" }
        return KeychainStore.read(account: CredentialKey.password)
    }

    // MARK: - 三步探活并连接

    /// 依次执行三步探活，onStep 在每步开始时回调（连接页画进度）。
    /// 全部通过才落 Keychain 并置 connected；任一步失败抛
    /// HermesError，凭据不落盘（不存坏凭据）。
    func connect(
        config: ServerConfig,
        username: String,
        password: String,
        apiKey: String,
        onStep: @escaping (ProbeStep) -> Void = { _ in }
    ) async throws {
        onStep(.health)
        let health = try await client.health(config: config)
        guard ServiceHealth.from(health: health) == .up else {
            throw HermesError.healthCheckFailed(status: 200)
        }
        onStep(.login)
        try await client.login(config: config, username: username, password: password)
        onStep(.apiKey)
        let ids = try await client.models(config: config, apiKey: apiKey)
        if let first = ids.first {
            modelID = first
        }
        // 演示模式不落 Keychain：假凭据写进去会污染真实连接
        if !isDemo {
            KeychainStore.save(config.baseString, account: CredentialKey.baseURL)
            KeychainStore.save(username, account: CredentialKey.username)
            KeychainStore.save(password, account: CredentialKey.password)
            KeychainStore.save(apiKey, account: CredentialKey.apiKey)
        }
        self.config = config
        self.username = username
        phase = .connected
    }

    /// 直登（0.6.0，用户拍板学 OpenMuse 欢迎页）：欢迎页
    /// 只输服务器地址＋密钥（Hermes Bearer），两步校验
    /// （健康检查→验证密钥）全过才落 Keychain 并置
    /// connected。面板账号/密码不参与直登：落盘时清掉
    /// 旧四件套里的账号/密码，防换址后拿旧服务器的面板
    /// 凭据去新服务器静默重登。设置页改址/换钥走同一
    /// 方法（ServerDetailView）。
    func connectDirect(
        config: ServerConfig,
        apiKey: String,
        onStep: @escaping (ProbeStep) -> Void = { _ in }
    ) async throws {
        onStep(.health)
        let health = try await client.health(config: config)
        guard ServiceHealth.from(health: health) == .up else {
            throw HermesError.healthCheckFailed(status: 200)
        }
        onStep(.apiKey)
        let ids = try await client.models(config: config, apiKey: apiKey)
        if let first = ids.first {
            modelID = first
        }
        if !isDemo {
            KeychainStore.save(config.baseString, account: CredentialKey.baseURL)
            KeychainStore.save(apiKey, account: CredentialKey.apiKey)
            KeychainStore.delete(account: CredentialKey.username)
            KeychainStore.delete(account: CredentialKey.password)
        }
        self.config = config
        username = nil
        phase = .connected
    }

    /// 设置页「重新测试连接」：存量四件套走三步探活；
    /// 直登连接（无面板密码）走两步（健康＋密钥），不改状态。
    func retestConnection(onStep: @escaping (ProbeStep) -> Void = { _ in }) async throws {
        guard let config, let apiKey else {
            throw HermesError.sessionExpired
        }
        if let username, let password {
            try await connect(
                config: config, username: username, password: password,
                apiKey: apiKey, onStep: onStep
            )
        } else {
            onStep(.health)
            let health = try await client.health(config: config)
            guard ServiceHealth.from(health: health) == .up else {
                throw HermesError.healthCheckFailed(status: 200)
            }
            onStep(.apiKey)
            _ = try await client.models(config: config, apiKey: apiKey)
        }
    }

    // MARK: - 会话接口（自动重登）

    /// 管理面统一通道：拿当前配置执行操作，遇 401 先用已存
    /// 密码静默重登再重试一次；重登失败或再 401 →
    /// sessionExpired（页面提示重新登录）。全部 /api/* 调用走它。
    func performAdmin<T>(
        _ operation: (HermesClientProtocol, ServerConfig) async throws -> T
    ) async throws -> T {
        guard let config else {
            throw HermesError.sessionExpired
        }
        do {
            return try await operation(client, config)
        } catch HermesError.unexpectedStatus(_, let status) where status == 401 {
            guard let username, let password else {
                throw HermesError.sessionExpired
            }
            try await client.login(config: config, username: username, password: password)
            do {
                return try await operation(client, config)
            } catch HermesError.unexpectedStatus(_, let retryStatus) where retryStatus == 401 {
                throw HermesError.sessionExpired
            }
        }
    }

    // MARK: - 模型目录（0.2.2 获取制）

    /// 刷新默认模型与可切换目录（0.2.4）：当前值来自
    /// /api/config；候选只来自上游（ModelCatalog 口径）：
    /// /api/model/options 优先，为空回落近 30 天用量 ∪
    /// 当前值；网关 /v1/models 的返回只作别名集用于排除，
    /// 本身永不进候选（0.2.2 的并集口径是 bug 源头）
    func refreshModelCatalog() async {
        guard phase == .connected else { return }
        var registryEntries: [ProviderRegistry.Entry] = []
        if let raw = try? await performAdmin({ client, config in
            try await client.rawConfig(config: config)
        }), let current = raw["model"]?.stringValue {
            defaultModel = current
            // §119 未配模型判定输入：具名服务商的模型
            // 总数（读到配置才有值；未知时判定不报）
            registryEntries = ProviderRegistry
                .entries(from: raw["providers"])
            providerModelTotal = registryEntries
                .reduce(0) { $0 + $1.models.count }
        }
        var aliases = Set<String>()
        if let apiKey,
           let ids = try? await performAdmin({ client, config in
               try await client.models(config: config, apiKey: apiKey)
           }) {
            aliases = Set(ids)
        }
        gatewayAliases = aliases
        var options: [String] = []
        var optionsRoot: JSONValue?
        if let root = try? await performAdmin({ client, config in
            try await client.modelOptionsRaw(config: config)
        }) {
            optionsRoot = root
            options = ModelCatalog.extractModelIDs(from: root)
        }
        var usage: [String] = []
        if let analytics = try? await performAdmin({ client, config in
            try await client.modelAnalytics(config: config, days: 30)
        }) {
            usage = analytics.models.map(\.model)
        }
        let merged = ModelCatalog.candidates(
            options: options, usage: usage,
            current: defaultModel, gatewayAliases: aliases
        )
        if !merged.isEmpty {
            availableModels = merged
        }
        // §153 B1：顶栏全量分组同源重建（网关组回执
        // 分组＋注册表具名组）；拼装失败/全空不覆盖
        // 已有分组（离线保旧清单，与 availableModels
        // 同纪律）
        let groups = ChatModelGroups.build(
            optionsRoot: optionsRoot,
            providers: registryEntries,
            gatewayCandidates: merged,
            defaultModel: defaultModel,
            gatewayAliases: aliases
        )
        if !groups.isEmpty {
            // §156：隐藏名单过滤只作用于呈现清单——
            // chatModelGroups 本体保留全量（枢纽模型
            // 区/恢复名单/默认解析都要拿全量对账），
            // 选择器消费端过 Core visibleGroups；含默
            // 认的组结构上不许被滤掉（Core 闸）
            chatModelGroups = groups
        }
        // §153 旧全局选择一次性迁移：chatModelID 旧值
        // 播种给主线会话键（升级不丢用户既有选择）；
        // 此后旧键只读不写
        if !isDemo, !legacyChatModelMigrated {
            legacyChatModelMigrated = true
            if let legacy = UserDefaults.standard
                .string(forKey: "chatModelID"),
               ChatModels.contains(legacy),
               sessionModelChoices[Self.sessionModelKey(
                   serverSessionID: nil, threadID: nil
               )] == nil {
                sessionModelChoices[Self.sessionModelKey(
                    serverSessionID: nil, threadID: nil
                )] = ChatModelChoice(
                    model: legacy, providerField: "custom"
                )
                persistSessionModelChoices()
            }
        }
    }

    /// 切换服务端默认模型：读全量 config → 只改 model 键 →
    /// 整包写回（PUT /api/config 既有写接口，演示/单测验证，
    /// 不对生产执行）
    func setDefaultModel(_ model: String) async throws {
        // 写入校验（0.2.4）：不在上游候选集内的值一律拦截，
        // 不许把网关别名等非法值写进生产配置
        guard ModelCatalog.isWritable(model, candidates: availableModels) else {
            throw HermesError.modelNotUpstream(model)
        }
        var raw = try await performAdmin { client, config in
            try await client.rawConfig(config: config)
        }
        raw["model"] = .string(model)
        try await performAdmin { client, config in
            try await client.updateConfig(config: config, newConfig: raw)
        }
        defaultModel = model
        if !availableModels.contains(model) {
            availableModels.insert(model, at: 0)
        }
    }

    /// 设置页在本页内写回 config 后同步内存态（避免两处口径漂移）。
    /// 网关别名不回填候选（它不是可选的上游模型）。
    func noteDefaultModel(_ model: String) {
        defaultModel = model
        if !availableModels.contains(model), !gatewayAliases.contains(model) {
            availableModels.insert(model, at: 0)
        }
    }

    /// 拉配置摘要（总览旧路径，走统一通道）
    func configSummary() async throws -> ServerConfigSummary {
        try await performAdmin { client, config in
            try await client.configSummary(config: config)
        }
    }

    // MARK: - 断开

    /// 断开连接：清 Keychain 与该服务器 cookie，回连接页。
    /// 本地聊天记录保留（是用户数据，删除口子在聊天页历史里）。
    func disconnect() {
        if isDemo {
            // 演示模式只复位状态：不动 Keychain、不清 cookie
            config = nil
            username = nil
            phase = .needsConnection
            return
        }
        if let config {
            client.clearCookies(config: config)
        }
        KeychainStore.clearAll()
        config = nil
        username = nil
        phase = .needsConnection
    }
}
