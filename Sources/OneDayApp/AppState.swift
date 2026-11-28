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

/// （§210：FeedDiscussSeed 已随种子机制退役——待发
/// 引用改挂 AppState.pendingQuotes.feedQuotesByThread 按线
/// 程寻址，见该字段注与定因报告）

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
    /// 连接状态快照（总表 156，DESIGN §394）：阶段＋尝
    /// 试次数＋人话原因的单源持有点——OverviewBridge-
    /// Store 探活链唯一喂入、自检面等呈现层只读；判定
    /// 口径在 Core ConnectionStatus
    var connectionStatus = ConnectionStatus()
    /// 当前工具活动短语（§449.9）：聊天运行驱动在工
    /// 具开始/结束事件处单点写入（Core ToolCardClas-
    /// sifier.activityPhrase 派生），聊天页头身份胶囊
    /// 第二行与中枢状态行同读此值——两面同源同口径；
    /// 无工具在飞恒 nil，两面各自回落既有状态口径
    var liveActivityPhrase: String?
    /// AI 自反应能力结论（DESIGN §432）：外观页
    /// 「AI 反应」开关行的显隐单读此值——判定单源
    /// 在 Core CapabilityNegotiation，本处只持有最
    /// 近一次回读结论（按服务器落盘，换服务器不
    /// 串）；未探得恒 unknown＝行不出（僵尸禁令）
    private(set) var selfReactionsAvailability:
        CapabilityAvailability = .unknown

    private static func storedSelfReactionsAvailability(
        for base: String?
    ) -> CapabilityAvailability {
        AppPreferences.selfReactionsAvailability(for: base)
    }

    private static func storeSelfReactionsAvailability(
        _ verdict: CapabilityAvailability, for base: String
    ) {
        AppPreferences.setSelfReactionsAvailability(verdict, for: base)
    }

    /// AI 自反应能力回读（§432）：外观页出现时
    /// 调——已判 available 不重探（省一记 GET），
    /// 其余态（未探/曾判无）每次重探：服务端后升
    /// 级（部署包 1.8.0 应用）时用户重进外观即自
    /// 愈见行。失败静默保旧结论（呈现降级不报
    /// 错，§394 口径）；演示模式假客户端抛错同理
    /// 恒保 unknown、行不出
    func refreshSelfReactionsAvailability() async {
        guard selfReactionsAvailability != .available,
              let config, let apiKey,
              let caps = try? await client.capabilities(
                config: config, apiKey: apiKey
              )
        else { return }
        let verdict =
            CapabilityNegotiation.selfReactionsAvailability(caps)
        selfReactionsAvailability = verdict
        Self.storeSelfReactionsAvailability(
            verdict, for: config.baseString
        )
    }
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
        get { AppPreferences.legacyChatModelMigrated }
        set { AppPreferences.legacyChatModelMigrated = newValue }
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
        let stored = sessionModelChoices[key]
        let effectiveStored: ChatModelChoice?
        if let serverSessionID,
           !serverSessionID.isEmpty,
           serverSessionID == sessionLedger.mainServerSessionID,
           let serverModel = sessionLedger.visibleSessions
                .first(where: { $0.id == serverSessionID })?.model {
            effectiveStored = SessionModelAccount.effectiveStored(
                stored: stored, serverReportedModel: serverModel
            )
        } else {
            effectiveStored = stored
        }
        if let resolved = SessionModelResolution.resolve(
            stored: effectiveStored,
            groups: chatModelGroups,
            serverDefault: SessionModelResolution.serverDefaultChoice(
                in: chatModelGroups, defaultModel: defaultModel
            )
        ) {
            return resolved
        }
        let legacy = AppPreferences.legacyChatModelID
            ?? defaultModel ?? ChatModels.fallbackID
        return ChatModelChoice(
            model: ModelDisplayNames.canonicalID(for: legacy),
            providerField: ChatModels.contains(legacy) ? "custom" : nil
        )
    }

    // MARK: - §158 已隐藏服务商（本机呈现治理）

    /// 已隐藏服务商的组键集（本机持久化，经 AppPreferences 统一收口）。
    private(set) var hiddenProviderGroupKeys: Set<String> =
        AppPreferences.loadHiddenProviderGroupKeys()

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
        AppPreferences.saveHiddenProviderGroupKeys(hiddenProviderGroupKeys)
    }

    /// 恢复一组（设置页「已隐藏的服务商」唯一写入点）
    func restoreProviderGroup(key: String) {
        hiddenProviderGroupKeys.remove(key)
        AppPreferences.saveHiddenProviderGroupKeys(hiddenProviderGroupKeys)
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

    /// 会话账迁键（§227 模型账合一）：主线链接改绑
    /// （服务端改派/收养回执）落定新 id 时，旧键下的
    /// 存量选择迁到新键下——不迁则用户的既有选择被
    /// 留在旧键发霉、新键回落默认，呈现为「换了会话
    /// 模型就变了」。语义：目标键已有存量时不覆盖
    /// （那是新会话自己的账）；源账保留不删（旧 id
    /// 若仍是活会话，它的账不许被主线迁账误伤）。
    /// 返回是否实际迁入
    @discardableResult
    func migrateSessionModelChoice(
        fromServerSessionID: String?, toServerSessionID: String?
    ) -> Bool {
        guard let from = fromServerSessionID, !from.isEmpty,
              let to = toServerSessionID, !to.isEmpty,
              from != to else { return false }
        let fromKey = Self.sessionModelKey(
            serverSessionID: from, threadID: nil
        )
        let toKey = Self.sessionModelKey(
            serverSessionID: to, threadID: nil
        )
        guard let choice = sessionModelChoices[fromKey],
              sessionModelChoices[toKey] == nil else { return false }
        sessionModelChoices[toKey] = choice
        persistSessionModelChoices()
        return true
    }

    private func persistSessionModelChoices() {
        AppPreferences.saveSessionModelChoices(sessionModelChoices)
    }

    private func loadSessionModelChoices() {
        sessionModelChoices = AppPreferences.loadSessionModelChoices()
    }

    /// 已下线模型落回提示（0.32.1，F05 止血）：旧全局
    /// 选择命中已停用模型时一次性如实告知（§153 后判
    /// 定输入改读旧键原值，语义不变）
    private(set) var modelFallbackNotice: String? =
        ChatModels.retiredFallbackNotice(
            stored: AppPreferences.legacyChatModelID
        )

    /// 消费落回提示：清提示（旧键自 §153 起只读不写，
    /// 消费后靠本标记防重报——提示本身由本属性承载、
    /// 清掉即不再生成）
    func consumeModelFallbackNotice() {
        modelFallbackNotice = nil
    }

    /// 乐观删除协调器（§232）：本地先删/后台删/失
    /// 败恢复的唯一执行件，全 App 只此一份（队列落
    /// 盘在协调器内）
    let sessionDeletions = SessionDeletionCoordinator()

    /// 乐观删除最终失败的恢复提醒（§232）：协调器
    /// 在恢复落定后置位，ChatView 提示条消费后清；
    /// 文案人话、不露接口原文（消费口径与模型落回
    /// 提示同式）
    var sessionDeletionFailureNotice: String?

    func consumeSessionDeletionFailureNotice() {
        sessionDeletionFailureNotice = nil
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
        // §370：新会话/服务端新标题的事实在本拍成立
        // ——名单新鲜度同步作废（抽屉未挂载时令牌无
        // 人消费，靠失效保下次打开必真拉）
        sessionLedger.invalidateListFreshness()
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
    /// 会话账本（第 67 条包一，2026-11-15）：「我有
    /// 哪些会话」的单店——全 App 唯一拉取者与合并
    /// 名单持有者，管理页自持名单与抽屉自拉第一页
    /// 同批退役。第 90 条收尾起兼持主线钦定/归档列/
    /// 三张关联表与分页装配核，原 ServerSession-
    /// Catalog 转发壳整件删除（B-07）
    let sessionLedger: SessionLedger

    /// 旁聊呈现保活状态（0.7.0）：标题覆盖/落点记忆/
    /// 草稿/滚动锚，演示模式纯内存不落盘（见
    /// SideChatStore）；主线钦定/归档/关联三账已迁
    /// 账本（第 90 条收尾）
    let sideChats: SideChatStore
    /// 未落定 run 账本（0.31.0）：生成中切后台/杀进程
    /// 后靠它恢复对账（ChatView 驱动消费）
    let runLedger: RunLedgerStore
    /// 发件箱自动重试记账（台账 154，DESIGN §336）
    let outboxRetry: OutboxRetryStore
    /// 推送登记（总表 138，DESIGN §397）：远程推送的
    /// App 侧准备面——登记状态机＋令牌快照＋就绪报告；
    /// RootView 三处与伴生探测同拍 synchronize
    let pushRegistration = PushRegistrationStore()
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

    /// 本人裁决集（0.36.5，审批联动 C 部）：本人在
    /// App 内批准/驳回过的 write-gate 记录 id——其裁
    /// 决回执通知一到即自动消账（Core ApprovalReso-
    /// lution 判定、OverviewBridgeStore 执行）。落
    /// UserDefaults 是为跨重启仍认账（回执可能晚于
    /// 裁决一轮轮询才生成）；上限 200 条、超出弃最
    /// 旧（回执生成以分钟计，陈年 id 无联动价值）
    private(set) var selfDecidedApprovalIDs: Set<String> =
        AppPreferences.loadSelfDecidedApprovalIDs()
    /// 本地单一真源协调器（#38）：收口凭据/账本/发件箱/偏好边界
    let localStore: LocalStoreCoordinator

    /// 全局共享的枢纽 store（0.36.21，审批卡包）：聊
    /// 天内就地审批卡与枢纽审核段必须读同一份 /pending
    /// 数据、走同一个裁决动作（规格 §6），store 自此
    /// 由 AppState 持有单例、懒建；此前 AgentHubView
    /// 每次打开自建一份，聊天侧无从共享。审批终态回
    /// 调（刷新总览桥角标）仍由呈现枢纽的 ChatView 经
    /// AgentHubView 注入 store.onApprovalChanged
    private var hubStoreInstance: AgentHubStore?

    /// 选择框瞬态覆盖层（总表 203／§441）：AppState
    /// 持有单例——聊天面（呈现/点选）与历史回补器
    /// （播种）共达；真源在服务端消息行，本层只持
    /// 呈现态，突变随条目/线程变更的重建趟消费
    let optionsOverlay = OptionsCardOverlay()

    /// 凭据请求卡覆盖层（0.51.2）：与 options-
    /// Overlay 同式持有——聊天面（呈现）与历史回
    /// 补器（播种）共达；真源在服务端消息行的
    /// vault_request 块，本层按行持呈现副本
    let vaultRequestOverlay = VaultRequestOverlay()

    /// 中枢卡片底层处理进度（§502 灰底根治）：写端
    /// HubCardHost、读端壳层 HubUnderlayTreatment 的
    /// 共享持有者（与 optionsOverlay 同式单例持有、
    /// 全 App 一份）；ChatView 呈现路径驱动——开页
    /// 置满格、关页落账同事务归零
    let hubCardProgress = HubCardProgress()

    func sharedHubStore() -> AgentHubStore {
        if let hubStoreInstance { return hubStoreInstance }
        let store = AgentHubStore(
            appState: self,
            gateClient: isDemo ? DemoWriteGateClient() : WriteGateClient()
        )
        hubStoreInstance = store
        return store
    }

    /// 全局共享的定时任务店（台账 198 收敛·普查
    /// R4/D2）：同一份服务端定时数据此前三路取数
    /// （枢纽段/管理页/状态页各拉一份），自此由本单
    /// 例一口出（与 sharedHubStore 同形态），三面只
    /// 消费、写动作后经店 refresh 同步
    private var cronStoreInstance: CronStore?

    func sharedCronStore() -> CronStore {
        if let cronStoreInstance { return cronStoreInstance }
        let store = CronStore(appState: self)
        cronStoreInstance = store
        return store
    }

    /// 全局共享的台账/任务/监测三店（§259 枢纽台账
    /// 三店合一）：三店此前在各面各自 @State 私建——
    /// KanbanStore 全 App 五份、MonitorsStore 三份、
    /// LedgerStore 两份，互不相通（同物多账的实例级
    /// 变体，普查 app-wide-assembly-audit 枢纽节）。
    /// 自此由 AppState 持有单例、懒建（与 sharedHub-
    /// Store 同形态），各面只消费同一份；三店 load
    /// 均有在飞守卫，多面同呼安全。枢纽台账段的条
    /// 目只从 sharedLedgerStore 一口出。
    private var ledgerStoreInstance: LedgerStore?
    private var kanbanStoreInstance: KanbanStore?
    private var monitorsStoreInstance: MonitorsStore?

    func sharedLedgerStore() -> LedgerStore {
        if let ledgerStoreInstance { return ledgerStoreInstance }
        let store = LedgerStore()
        ledgerStoreInstance = store
        return store
    }

    func sharedKanbanStore() -> KanbanStore {
        if let kanbanStoreInstance { return kanbanStoreInstance }
        let store = KanbanStore()
        kanbanStoreInstance = store
        return store
    }

    func sharedMonitorsStore() -> MonitorsStore {
        if let monitorsStoreInstance {
            return monitorsStoreInstance
        }
        let store = MonitorsStore()
        monitorsStoreInstance = store
        return store
    }

    /// 全局共享的点子/目标两店（台账 199，随 §259
    /// 先例补齐合一）：两店此前在点子格／目标格／
    /// 动态格／目标详情四面各自 @State 私建（普查
    /// D3：同桥数据源、两份内存缓存），自此由
    /// AppState 持有单例、懒建（与 §259 三店同形
    /// 态），各面只消费同一份；两店 load 均有在飞
    /// 守卫，多面同呼安全
    private var ideasStoreInstance: IdeasStore?
    private var goalsStoreInstance: GoalsStore?

    func sharedIdeasStore() -> IdeasStore {
        if let ideasStoreInstance { return ideasStoreInstance }
        let store = IdeasStore()
        ideasStoreInstance = store
        return store
    }

    func sharedGoalsStore() -> GoalsStore {
        if let goalsStoreInstance { return goalsStoreInstance }
        let store = GoalsStore()
        goalsStoreInstance = store
        return store
    }

    /// 文件库名单店（§369 缓存 C4）：资源库／影音名
    /// 单走 AppState 共享单例＋落盘快照（LibraryList-
    /// Store），与 §259 三店同形态；名单不再随文件格
    /// 视图生死、冷启先显快照后台对账
    private var libraryListStoreInstance: LibraryListStore?

    func sharedLibraryListStore() -> LibraryListStore {
        if let libraryListStoreInstance {
            return libraryListStoreInstance
        }
        let store = LibraryListStore()
        libraryListStoreInstance = store
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
        AppPreferences.saveSelfDecidedApprovalIDs(selfDecidedApprovalIDs)
    }
    /// 云电脑接管态（0.10.0，P3 互斥的客户端半边）：
    /// BrowserFaceView 在接管开关变化时回写（施工图
    /// §4.3 产品层约定：Box 单桌面无锁原语，接管期间
    /// 暂停任务派发）。任务段据此禁用派发类动作并明示
    /// 原因；服务端真联动（派发层真暂停）待生产验收轮
    var boxTakeoverActive = false
    /// 智能体身份名（0.6.1 立、§253 改缓存镜像）：全
    /// 局唯一呈现出口——胶囊/抽屉/活动页三处显示名都
    /// 读这里。真值在服务端 SOUL、本机只存带时间戳
    /// 的缓存副本（AgentProfileStore.nameCache），本
    /// 属性是缓存的只读镜像；刷新链以 Dashboard 回
    /// 读整份替换缓存，App 改名走写穿（renameAgent）。
    /// 旧「档案名翻译当标题」（default→默认档案）与
    /// 本机改名覆盖两套口径均已退役
    var identityName: String? { agentProfileStore.cachedName }
    private var identityNameResolved = false

    /// 身份名拉取（A2 直连，§253：档案列表 → 默认档
    /// 案 → 其 soul，全程 Hermes Dashboard 管理口、
    /// 不经桥）→ 解析名＋文档时刻（缓存的时间戳凭
    /// 据）；任一步失败回 nil，调用方保现状不回落
    /// 假名
    private func fetchResolvedIdentityName() async
        -> (name: String, updatedAt: Date?)? {
        guard let profiles = try? await performAdmin({ client, config in
            try await client.profiles(config: config)
        }),
              let profile = profiles.first(where: { $0.isDefault == true })
                ?? profiles.first,
              let document = try? await performAdmin({ client, config in
                  try await client.profileSoul(config: config, name: profile.name)
              })
        else { return nil }
        // AgentName.resolve 非可选：无名标题时其自身回
        // 落 Hermes（与旧呈现口径逐字一致）
        return (AgentName.resolve(soulContent: document.content),
                document.updatedAt)
    }

    /// 服务器名回读后的统一收尾（§253）：先处置迁移
    /// 待推——§253 迁移时本机旧改名胜出且与回读名不
    /// 同时，先直连写穿服务端（§383 包一），成功后重读一次以
    /// 服务端回读为准落缓存；写穿失败保留缓存里的待
    /// 推值呈现、本次回读不覆盖（下个触发点再试）。
    /// 无待推时整份替换名字缓存
    private func adoptFetchedIdentityName(
        _ fetched: (name: String, updatedAt: Date?)
    ) async {
        if agentProfileStore.namePushPending,
           let pending = agentProfileStore.cachedName {
            if pending == fetched.name {
                agentProfileStore.markNamePushed()
            } else if config != nil {
                let pushed = (try? await writeAgentNameDirect(
                    pending
                )) != nil
                if pushed {
                    agentProfileStore.markNamePushed()
                    if let again = await fetchResolvedIdentityName() {
                        agentProfileStore.applyName(
                            again.name, serverUpdatedAt: again.updatedAt
                        )
                    } else {
                        agentProfileStore.applyName(
                            pending, serverUpdatedAt: nil
                        )
                    }
                    return
                }
                return
            }
        }
        agentProfileStore.applyName(
            fetched.name, serverUpdatedAt: fetched.updatedAt
        )
    }

    /// 解析身份名（幂等：只真正拉取一次；失败也记已解
    /// 析、回落显示，不逐次重试打服务端）
    func resolveIdentityNameIfNeeded() async {
        guard !identityNameResolved, config != nil else { return }
        identityNameResolved = true
        guard let fetched = await fetchResolvedIdentityName()
        else { return }
        await adoptFetchedIdentityName(fetched)
    }

    /// 上次刷新尝试时刻（身份反映修复）：回前台/连接
    /// 成立/冷启与头像仓同步同拍刷新，30 秒内不重打
    private var lastIdentityRefreshAt: Date?

    /// 身份名生命周期刷新（身份反映修复）：旧口径解
    /// 析一次闩死、进程内永不重拉——AI 在服务器改了
    /// 名，App 要等冷重启才跟上（2026-11-13 改名事
    /// 故的第二断点）。刷新失败保旧值不翻假名；演示
    /// 模式不连真服务端、跳过
/// §416 新鲜度普查豁免：单值尝试节流（尝试计时、保旧值），非名单新鲜度判定，与门口径分离（判定表见 DESIGN §416）
    func refreshIdentityName() async {
        guard config != nil, !isDemo else { return }
        if let last = lastIdentityRefreshAt,
           Date().timeIntervalSince(last) < 30 { return }
        lastIdentityRefreshAt = Date()
        guard let fetched = await fetchResolvedIdentityName()
        else { return }
        identityNameResolved = true
        await adoptFetchedIdentityName(fetched)
    }

    /// soul 编辑保存后的身份名重解析（§155 HUB-1）：
    /// 内容已由保存方重新取回并比对确认，直接以确认
    /// 内容重算显示名并整份替换名字缓存，不再走一次
    /// 性解析的网络链。§253：这次编辑本身就是一次服
    /// 务端写入（服务器收到时刻＝当下），迁移待推就
    /// 此作废——末写胜按时间裁决，这次写最晚
    func reresolveIdentityName(soulContent: String) {
        identityNameResolved = true
        agentProfileStore.markNamePushed()
        agentProfileStore.applyName(
            AgentName.resolve(soulContent: soulContent),
            serverUpdatedAt: Date()
        )
    }

    /// 智能体身份缓存（§253）：名字/头像的服务端单真
    /// 值在本机只剩带时间戳的缓存副本，全 App 露脸面
    /// 经下方收敛口读缓存，不再各自拼回落链、更不许
    /// 写死字面名
    let agentProfileStore = AgentProfileStore()

    /// 伴生探测（本包，DESIGN §110）：登录后自动探
    /// 测伴生存在与版本（/api/companion/info），派生
    /// 态供设置页版本组消费；触发点在 RootView（连接
    /// 成立/回前台/冷启恢复，与设备会话同拍），派生
    /// 与缓存口径在 Core CompanionProbe 一件
    let companionProbe = CompanionProbeStore()

    /// 上次头像仓同步尝试时刻（呈现跟随节流）：开枢
    /// 纽/开抽屉也成了触发点后防高频打仓，30 秒内不
    /// 重打（与身份名刷新同口径）
    private var lastAvatarSyncAt: Date?

    /// 头像仓同步（P1 身份包、§253 改镜像口径）：触
    /// 发点与伴生探测同拍（OneDayApp 的连接成立/回前
    /// 台/冷启恢复），另加开枢纽/开抽屉（经 refresh-
    /// IdentitySurfaces）——2026-11-13 事故里 App 全
    /// 程在前台聊天、三触发点一个都没响，AI 换完头像
    /// 8 分钟没人重拉。把头像仓当前指针整份替换进缓
    /// 存；演示模式不连真仓；失败静默保现状，口径在
    /// AgentAvatarSync。force＝写穿链回读（刚写完必
    /// 须立刻以仓指针为准刷新缓存，绕过节流）
    func syncAgentAvatarFromBridge(force: Bool = false) async {
        guard let config, !isDemo else { return }
        if !force, let last = lastAvatarSyncAt,
           Date().timeIntervalSince(last) < 30 { return }
        lastAvatarSyncAt = Date()
        await AgentAvatarSync.run(
            config: config, store: agentProfileStore
        )
    }

    /// 露脸面呈现跟随总口：用户正要看身份的面打开时
    /// （枢纽/抽屉）重拉名字与头像——服务器刚被改过
    /// 就当场跟上，不等下一次回前台/冷启。两路各自
    /// 带 30 秒节流，高频开合不打爆服务端
    func refreshIdentitySurfaces() async {
        await refreshIdentityName()
        await syncAgentAvatarFromBridge()
    }

    /// 露脸面显示名单一出口：名字缓存 → Hermes 回落
    /// （OneDayCore.AgentDisplayName，§253 收敛后只剩
    /// 这一级链）
    var agentDisplayName: String {
        AgentDisplayName.resolve(
            cachedName: agentProfileStore.cachedName
        )
    }

    /// 改名直连写（§383 包一）：校验（Core，与
    /// 桥规则同口径）→ 默认档案 soul 读改写（与
    /// 名读同源：profiles 取默认档）→ 留痕自报。
    /// 桥 _set_name 的备份/name-state 账随迁退
    /// 出 App 写路（桥侧对他路写入有 mtime 兜底，
    /// §383.2 记账）；写后回读验名由调用方的回
    /// 读尾链承接。错误口径与 §253 写穿一致：校
    /// 验失败给具体人话、401 映射未授权、余皆通
    /// 用失败文案不露原文
    private func writeAgentNameDirect(
        _ rawName: String
    ) async throws {
        guard let config else {
            throw IdentityBridgeError.noKey
        }
        let name: String
        do {
            name = try AgentName.validatedNewName(rawName)
        } catch let error as AgentNameWriteError {
            throw IdentityBridgeError.failed(
                Self.agentNameWriteMessage(error)
            )
        }
        let outcome: (previousName: String, replacedTitle: Bool)
        do {
            let profiles = try await performAdmin { client, config in
                try await client.profiles(config: config)
            }
            guard let profile = profiles.first(where: {
                $0.isDefault == true
            }) ?? profiles.first else {
                throw IdentityBridgeError.failed(
                    L10n.string("身份名保存失败，请稍后再试。")
                )
            }
            outcome = try await performAdmin { client, config in
                let document = try await client.profileSoul(
                    config: config, name: profile.name
                )
                let previous = AgentName.resolve(
                    soulContent: document.content
                )
                let replaced = AgentName.hasIdentityTitle(
                    in: document.content
                )
                guard let updated = AgentName.applyingNewName(
                    name, to: document.content
                ) else {
                    throw IdentityBridgeError.failed(
                        L10n.string("身份名保存失败，请稍后再试。")
                    )
                }
                try await client.updateProfileSoul(
                    config: config, name: profile.name,
                    content: updated
                )
                return (previousName: previous,
                        replacedTitle: replaced)
            }
        } catch let error as IdentityBridgeError {
            throw error
        } catch HermesError.sessionExpired {
            throw IdentityBridgeError.unauthorized
        } catch {
            throw IdentityBridgeError.failed(
                L10n.string("身份名保存失败，请稍后再试。")
            )
        }
        await reportAgentNameTrace(
            config: config, name: name,
            previousName: outcome.previousName,
            replacedTitle: outcome.replacedTitle
        )
    }

    /// 改名留痕自报（§383 包一，best-effort）：
    /// 五要素与桥 _set_name 自记同形（action=
    /// identity.set_name、actor=user、target 为
    /// soul 名位、result 摘要同桥文案式样），
    /// detail 标 via=app-direct 以别于桥内改名；
    /// 自报失败不回滚改名——落本地诊断留痕（对
    /// 齐「留痕不许静默消失」口径的 App 侧等价物）
    private func reportAgentNameTrace(
        config: ServerConfig, name: String,
        previousName: String, replacedTitle: Bool
    ) async {
        let mode = replacedTitle ? "replace" : "insert"
        let summary = "智能体改名为「\(name)」"
            + "（\(mode) 标题行，"
            + "原 soul 名「\(previousName)」）"
        do {
            try await OneDayBridgeClient().recordTrace(
                config: config, action: "identity.set_name",
                actor: "user", targetKind: "identity",
                targetID: "soul-name", targetLabel: name,
                targetRef: "oneday://identity/name",
                status: "ok", result: summary, error: nil,
                detail: ["via": "app-direct"]
            )
        } catch {
            ChatDiagTrace.record(
                "改名留痕自报失败 [identity.set_name] \(error)"
            )
        }
    }

    /// 改名校验人话（与桥 _validate_new_name 的
    /// 拒绝文案同义，编辑器经 identityWriteErrorText 呈现）
    private static func agentNameWriteMessage(
        _ error: AgentNameWriteError
    ) -> String {
        switch error {
        case .empty:
            return L10n.string("名字不能为空。")
        case .tooLong:
            return L10n.string("名字超过 20 字了。")
        case .punctuation:
            return L10n.string("名字不能含句读标点。")
        case .structural:
            return L10n.string("这个名字是文档结构词，换一个。")
        case .illegalCharacter:
            return L10n.string("名字含非法字符。")
        }
    }

    // MARK: - 身份写穿（§253：App 改名/换头像直达服务端单真值）
    //
    // 写口共用口径：成功后以服务端回读/仓指针整份
    // 替换缓存——App 不留第二真值。失败原样抛回编辑
    // 器呈现（IdentityBridgeError 文案已过 §232 安全
    // 门）。演示模式无真服务端：只动缓存演示、不发网
    // 络（与演示数据同性子）。改名面 §383 包一修订：
    // 改名走 Dashboard 直连写（校验与标题行手术在
    // Core、与桥规则同口径；留痕经桥 POST /traces
    // 自报补账）；换头像仍走服务端既有窄口写穿。

    /// App 改名（§253 立口、§383 包一迁 Dashboard 直连写）
    func renameAgent(to newName: String) async throws {
        if isDemo {
            agentProfileStore.applyName(newName, serverUpdatedAt: nil)
            return
        }
        try await writeAgentNameDirect(newName)
        if let fetched = await fetchResolvedIdentityName() {
            agentProfileStore.applyName(
                fetched.name, serverUpdatedAt: fetched.updatedAt
            )
        } else {
            agentProfileStore.applyName(newName, serverUpdatedAt: nil)
        }
    }

    /// App 换预置头像写穿（成功后强制同步刷新缓存）
    func selectAvatarPreset(id: String) async throws {
        if isDemo {
            agentProfileStore.applyAvatarFromSync(
                cache: IdentityAvatarCache(
                    selection: .preset(
                        id: AgentAvatarPreset.resolve(id: id).id
                    ),
                    itemID: nil, serverUpdatedAt: nil, cachedAt: Date()
                ),
                imageData: nil
            )
            return
        }
        guard let config else { throw IdentityBridgeError.noKey }
        try await IdentityBridgeClient().addAvatarPreset(
            config: config, presetID: id
        )
        await syncAgentAvatarFromBridge(force: true)
    }

    /// App 换图片头像写穿：制备 JPEG → 上仓 → 强制
    /// 同步（同步按新条目整份替换缓存并落盘缓存图）
    func setCustomAvatar(imageData: Data) async throws {
        guard let jpeg = AgentProfileStore.preparedAvatarJPEG(
            from: imageData
        ) else {
            throw IdentityBridgeError.failed(
                L10n.string("这张图片读不了，换一张试试。")
            )
        }
        if isDemo {
            agentProfileStore.applyAvatarFromSync(
                cache: IdentityAvatarCache(
                    selection: .image(itemID: ""),
                    itemID: nil, serverUpdatedAt: nil, cachedAt: Date()
                ),
                imageData: jpeg
            )
            return
        }
        guard let config else { throw IdentityBridgeError.noKey }
        try await IdentityBridgeClient().addAvatarImage(
            config: config, imageData: jpeg
        )
        await syncAgentAvatarFromBridge(force: true)
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

    /// 全 App 唯一导航真值（§305，横扫 A-03）：跨页
    /// 路由信箱群（0.4.0–§219 六代、约 20 字段）已整
    /// 组迁入 AppRouter，本类不再自持任何导航请求字
    /// 段——消费方一律经 appState.router 读写（字段
    /// 名与置位—消费—清零协议逐项不变、只换持有者）
    let router = AppRouter()
    /// 线程待发引用（§305）：草稿数据非导航，自顶层
    /// 迁出独立持有（见 PendingThreadQuotes），不随
    /// 路由走；写入/消费口径逐项不变
    let pendingQuotes = PendingThreadQuotes()
    /// 文件库内容修订号（§131）：打开页改名成功后递
    /// 增，文件页以此为 .task(id:) 键重聚合——改名
    /// 结果不在文件页留旧名残影
    var fileLibraryRevision = 0

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
        let persisted = !demoMode.isDemo
        let sideChatsStore = SideChatStore(persisted: persisted)
        let ledgerStore = SessionLedger(persisted: persisted)
        let runLedgerStore = RunLedgerStore(persisted: persisted)
        let outboxRetryStore = OutboxRetryStore(persisted: persisted)
        sideChats = sideChatsStore
        sessionLedger = ledgerStore
        runLedger = runLedgerStore
        outboxRetry = outboxRetryStore
        localStore = LocalStoreCoordinator(
            sessionLedger: ledgerStore,
            sideChats: sideChatsStore,
            runLedger: runLedgerStore,
            outboxRetry: outboxRetryStore,
            isPersisted: persisted
        )
        deviceSession = DeviceSessionController()
        deviceSync = DeviceSyncController()
        deviceSync.dispatcher = deviceSession.dispatcher
        // 第 67 条包二：删除协调器壳接线账本引擎——
        // 删除自此走账本单管线
        sessionDeletions.ledger = sessionLedger
        // §244 P-5／§261 ④：授权卡续办前的补同步接线
        // 收编为具名协议口——把同步控制器挂上即完，
        // 不再有无名闭包接线点
        deviceSession.permissionFlow.syncProvider = deviceSync
        // 供给收敛（0.36.18）：五件记录型的「允许调
        // 用」不再有独立开关与镜像——会话每次重读权
        // 限时一律对齐真实权限（refreshPermissions
        // 内落），本处不再接线
        switch demoMode {
        case .connected:
            // 演示会话：地址只是展示数据，密钥由假客户端消化
            config = ServerConfig(rawInput: "https://your-hermes.example.com")
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
            // §432：AI 自反应能力结论按当前服务器回
            // 读落盘值播种（未连接/无记录恒 unknown）
            selfReactionsAvailability =
                Self.storedSelfReactionsAvailability(
                    for: config?.baseString
                )
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
    /// 当前设备已签发的短时票据对（Keychain 持久化，内存镜像）
    private(set) var shortLivedTokenPair: ShortLivedTokenPair?
    /// 并发换票单飞句柄，避免多请求同时触发 refresh 撞窗
    private var tokenRefreshTask: Task<ShortLivedTokenPair?, Never>?

    var shortLivedTokenActive: Bool {
        shortLivedTokenPair != nil
    }

    private func restore() {
        guard let base = KeychainStore.read(account: CredentialKey.baseURL),
              var config = ServerConfig(rawInput: base),
              KeychainStore.read(account: CredentialKey.apiKey) != nil else {
            phase = .needsConnection
            return
        }
        config.username = KeychainStore.read(account: CredentialKey.username)
        self.config = config
        self.shortLivedTokenPair = KeychainStore.readShortLivedTokenPair()
        phase = .connected
    }

    var apiKey: String? {
        // 演示假值：只会被递给 DemoHermesClient，不出设备
        if isDemo { return "demo-api-key" }
        return KeychainStore.read(account: CredentialKey.apiKey)
    }

    /// #1 短时票据自动换票入口：优先返回有效的 odt1.* 短时票据；
    /// 距过期不足 2 小时自动单飞刷新；旧服务端未部署或无票据时无感回退长期钥。
    func effectiveBearerToken(preferShortLived: Bool = true) async -> String? {
        if isDemo { return "demo-api-key" }
        guard preferShortLived, let config else {
            return apiKey
        }
        if let current = shortLivedTokenPair ?? KeychainStore.readShortLivedTokenPair() {
            if shortLivedTokenPair == nil {
                shortLivedTokenPair = current
            }
            if !ShortLivedTokenLifecycle.needsRefresh(expiresAt: current.accessExpiresAt) {
                return current.accessToken
            }
            if let refreshed = await refreshShortLivedTokenSingleFlight(config: config, pair: current) {
                return refreshed.accessToken
            }
        }
        return apiKey
    }

    private func refreshShortLivedTokenSingleFlight(
        config: ServerConfig,
        pair: ShortLivedTokenPair
    ) async -> ShortLivedTokenPair? {
        if let existing = tokenRefreshTask {
            return await existing.value
        }
        let task = Task<ShortLivedTokenPair?, Never> { @MainActor in
            do {
                let next = try await self.client.refreshShortLivedToken(
                    config: config,
                    refreshToken: pair.refreshToken
                )
                self.shortLivedTokenPair = next
                KeychainStore.saveShortLivedTokenPair(next)
                return next
            } catch let error as HermesError {
                if case .serverError(_, let status, let code) = error,
                   status == 401,
                   (code == "session_revoked" || code == "refresh_token_reused" || code == "refresh_token_expired") {
                    self.clearShortLivedToken()
                } else if case .apiKeyRejected = error {
                    self.clearShortLivedToken()
                }
                return nil
            } catch {
                return nil
            }
        }
        tokenRefreshTask = task
        let result = await task.value
        tokenRefreshTask = nil
        return result
    }

    /// 主动以当前长期登录钥换取一对短时票据并持久化到 Keychain
    @discardableResult
    func enableShortLivedToken() async throws -> ShortLivedTokenPair {
        guard let config, let key = apiKey else {
            throw HermesError.sessionExpired
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let pair = try await client.exchangeShortLivedToken(
            config: config,
            apiKey: key,
            deviceName: UIDevice.current.name,
            appVersion: version
        )
        if !isDemo {
            shortLivedTokenPair = pair
            KeychainStore.saveShortLivedTokenPair(pair)
        }
        return pair
    }

    /// 能力协商自动升级：服务端广告 short_lived_tokens=true 且本机未持票时自动换票
    func exchangeShortLivedTokenIfSupported() async {
        guard !isDemo, shortLivedTokenPair == nil, let config, let key = apiKey else { return }
        guard let caps = try? await client.capabilities(config: config, apiKey: key),
              caps.shortLivedTokensSupported == true else { return }
        _ = try? await enableShortLivedToken()
    }

    func clearShortLivedToken() {
        shortLivedTokenPair = nil
        if !isDemo {
            KeychainStore.deleteShortLivedTokenPair()
        }
    }

    private var password: String? {
        if isDemo { return "demo-password" }
        return KeychainStore.read(account: CredentialKey.password)
    }

    private var username: String? {
        if isDemo { return "" }
        return KeychainStore.read(account: CredentialKey.username)
    }

    // MARK: - 三步探活并连接

    /// 依次执行三步探活，onStep 在每步开始时回调（连接页画进度）。
    /// 全部通过才落 Keychain 并置 connected；任一步失败抛
    /// HermesError，凭据不落盘（不存坏凭据）。
    func connect(
        config: ServerConfig,
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
        try await client.login(config: config, username: config.username ?? "", password: password)
        onStep(.apiKey)
        let ids = try await client.models(config: config, apiKey: apiKey)
        if let first = ids.first {
            modelID = first
        }
        // 演示模式不落 Keychain：假凭据写进去会污染真实连接
        if !isDemo {
            KeychainStore.save(config.baseString, account: CredentialKey.baseURL)
            KeychainStore.save(password, account: CredentialKey.password)
            KeychainStore.save(apiKey, account: CredentialKey.apiKey)
            // §244：账号键退役（面板密码无账号概念），存量值清掉
            KeychainStore.delete(account: CredentialKey.username)
        }
        self.config = config
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
        phase = .connected
    }

    // MARK: - 引导四步连接（欢迎/登录/连接中/成功面）

    /// 引导·密码登录一步制（用户 2026-11-11 定版，覆盖
    /// 原型两步）：地址＋密码一步连上。链路全是现行生产
    /// 端点——健康检查（兼量延迟）→ 伴生登录桥
    /// web-login 验面板密码（§244 一把密码统一，桥在服
    /// 务器内部换 dashboard 会话 cookie）→
    /// /api/env/reveal 换取登录密钥 API_SERVER_KEY（服
    /// 务端代管下发）→ 用该钥验 /v1/models 并读服务信
    /// 息。全过才落 Keychain（三件套，与 connect 同口
    /// 径，performAdmin 静默重登靠它）；本方法不置
    /// phase——成功面先行展示，用户点「开始聊天」再由
    /// activatePreparedConnection 进主界面（杀进程在成
    /// 功面时 restore 照样凭 Keychain 成立）。
    func connectWithPassword(
        config: ServerConfig,
        username: String,
        password: String,
        onStep: @escaping (OnboardingStep) -> Void = { _ in }
    ) async throws -> ConnectionServiceInfo {
        var step: OnboardingStep = .serverReachable
        do {
            onStep(step)
            let started = Date()
            let health = try await client.health(config: config)
            guard ServiceHealth.from(health: health) == .up else {
                throw HermesError.healthCheckFailed(status: 200)
            }
            let latencyMs = Int(
                Date().timeIntervalSince(started) * 1000
            )
            step = .credentialValid
            onStep(step)
            try await client.login(
                config: config, username: username, password: password
            )
            step = .serviceInfo
            onStep(step)
            // 演示模式：reveal 在演示客户端是冻结面——
            // 用演示假钥（不出设备，与既有演示口径一致）
            let fetchedKey: String
            if isDemo {
                fetchedKey = "demo-api-key"
            } else {
                fetchedKey = try await client.revealEnvVar(
                    config: config, key: "API_SERVER_KEY"
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !fetchedKey.isEmpty else {
                throw OnboardingFailure(
                    step: .serviceInfo, kind: .keyUnavailable
                )
            }
            // 换来的钥必须真能用才算连上（不许拿空壳钥落盘）
            let ids = try await client.models(
                config: config, apiKey: fetchedKey
            )
            if let first = ids.first {
                modelID = first
            }
            let status = try? await client.status(config: config)
            let options = try? await client.modelOptions(config: config)
            if !isDemo {
                KeychainStore.save(
                    config.baseString, account: CredentialKey.baseURL
                )
                KeychainStore.save(username, account: CredentialKey.username)
                KeychainStore.save(password, account: CredentialKey.password)
                KeychainStore.save(fetchedKey, account: CredentialKey.apiKey)
            }
            self.config = config
            return ConnectionServiceInfo(
                host: config.host,
                hermesVersion: status?.version ?? health.version,
                modelCount: options?.count,
                latencyMs: latencyMs
            )
        } catch {
            throw OnboardingFailure.classify(step: step, error: error)
        }
    }

    /// 引导·密钥登录（后门保留，用户只持一把登录密钥）：
    /// 健康检查（兼量延迟）→ /v1/models 验钥 → 读服务
    /// 信息。无面板会话，模型目录数取不到就不显示
    /// （ConnectionServiceInfo 口径）；落盘与
    /// connectDirect 同口径（清旧账号/密码防静默重登
    /// 拿错凭据）。同样不置 phase，成功面后再激活。
    func connectWithKey(
        config: ServerConfig,
        apiKey: String,
        onStep: @escaping (OnboardingStep) -> Void = { _ in }
    ) async throws -> ConnectionServiceInfo {
        var step: OnboardingStep = .serverReachable
        do {
            onStep(step)
            let started = Date()
            let health = try await client.health(config: config)
            guard ServiceHealth.from(health: health) == .up else {
                throw HermesError.healthCheckFailed(status: 200)
            }
            let latencyMs = Int(
                Date().timeIntervalSince(started) * 1000
            )
            step = .credentialValid
            onStep(step)
            let ids = try await client.models(config: config, apiKey: apiKey)
            if let first = ids.first {
                modelID = first
            }
            step = .serviceInfo
            onStep(step)
            let status = try? await client.status(config: config)
            if !isDemo {
                KeychainStore.save(
                    config.baseString, account: CredentialKey.baseURL
                )
                KeychainStore.save(apiKey, account: CredentialKey.apiKey)
                KeychainStore.delete(account: CredentialKey.username)
                KeychainStore.delete(account: CredentialKey.password)
            }
            self.config = config
            return ConnectionServiceInfo(
                host: config.host,
                hermesVersion: status?.version ?? health.version,
                modelCount: nil,
                latencyMs: latencyMs
            )
        } catch {
            throw OnboardingFailure.classify(step: step, error: error)
        }
    }

    /// 引导成功面「开始聊天」：凭据已落盘、config 已备，
    /// 此处只翻连接态进主界面。
    func activatePreparedConnection() {
        guard config != nil else { return }
        phase = .connected
    }

    /// 设置页「重新测试连接」：存量三件套走三步探活；
    /// 直登连接（无面板密码）走两步（健康＋密钥），不改状态。
    func retestConnection(onStep: @escaping (ProbeStep) -> Void = { _ in }) async throws {
        guard let config, let apiKey else {
            throw HermesError.sessionExpired
        }
        if let password {
            try await connect(
                config: config, password: password,
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

    func readDashboardConfig() async throws -> [String: JSONValue] {
        try await performAdmin { client, config in
            try await client.rawConfig(config: config)
        }
    }

    func applyDashboardConfig(_ changes: [String: JSONValue]) async throws {
        try await performAdmin { client, config in
            try await client.updateConfig(config: config, newConfig: changes)
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
        } catch let error as HermesError where error.isHTTPUnauthorized {
            guard let password else {
                throw HermesError.sessionExpired
            }
            try await client.login(config: config, username: config.username ?? "", password: password)
            do {
                return try await operation(client, config)
            } catch let retryError as HermesError where retryError.isHTTPUnauthorized {
                throw HermesError.sessionExpired
            }
        }
    }

    // MARK: - 模型目录（0.2.2 获取制）

    /// §368 新鲜度门 TTL：300 秒。定档理由（§368.2）：
    /// 模型目录的变更源最窄——本机写全部走显式失效、
    /// 不靠 TTL 兜底；服务端侧变更低频且后果轻（目录
    /// 晚换新，顶栏回退链兜底、已选会话执行不受影响）。
    /// 仓内先例（身份 30s／伴生探测 60s／名单类 60s）
    /// 都是变更源更宽的面，不可比照短定
    static let modelCatalogTTL: TimeInterval = 300

    /// §368 载入时刻＋配置键（CronStore 的 hasLoaded/
    /// loadedForConfig 范本再加时刻件，凑成新鲜判定三
    /// 件套）；internal 供钉测拨时刻模拟过期
    var modelCatalogLoadedAt: Date?
    var modelCatalogLoadedForConfig: String?
    /// §368 失效代次：写/强制刷新递增；一轮载入只服
    /// 务于它的起始代次——载入期间被失效的轮次，落地
    /// 也不算新鲜
    private var modelCatalogEpoch = 0
    private var modelCatalogLoadedEpoch = -1
    private var modelCatalogAttemptEpoch = -1
    /// §368 单飞句柄：并发触发搭同一轮，不各拉各的
    private var modelCatalogLoadTask: Task<Void, Never>?

    /// §368 目录失效：模型写路径的成功点与强制刷新
    /// 调用；只动取数时机，目录消费语义一字不变
    func invalidateModelCatalog() {
        modelCatalogEpoch += 1
        modelCatalogLoadedAt = nil
    }

/// §416 新鲜度普查豁免：§368 已是门同口径（TTL＋配置键＋只许成功落账＋写失效），判定与 epoch/单飞焊死且有专属钉测，机械替换无口径收益（判定表见 DESIGN §416）
    private var modelCatalogIsFresh: Bool {
        guard modelCatalogLoadedEpoch == modelCatalogEpoch,
              modelCatalogLoadedForConfig == config?.baseString,
              let modelCatalogLoadedAt
        else { return false }
        return Date().timeIntervalSince(modelCatalogLoadedAt)
            < Self.modelCatalogTTL
    }

    /// 冷口（§368）：新鲜即 0 请求返回；过期/配置键
    /// 变才起一轮；在飞则搭在飞的一轮
    func refreshModelCatalog() async {
        guard phase == .connected else { return }
        if modelCatalogIsFresh { return }
        await awaitOneModelCatalogLoad()
    }

    /// 强制口（§368）：手动刷新/测连通走它——先失效，
    /// 再确保「失效后的一轮」落地，不许被 TTL 吞、
    /// 也不许被失效前已在飞的旧轮冒充
    func refreshModelCatalogForced() async {
        guard phase == .connected else { return }
        invalidateModelCatalog()
        let target = modelCatalogEpoch
        while modelCatalogLoadedEpoch != target,
              modelCatalogAttemptEpoch < target {
            await awaitOneModelCatalogLoad()
            guard phase == .connected else { return }
        }
    }

    /// 起一轮（或搭在飞的一轮）并等它落地；落 stamp
    /// 只在本轮有应答时（成功口径见 fetchModelCatalog）
    private func awaitOneModelCatalogLoad() async {
        if let task = modelCatalogLoadTask {
            await task.value
            return
        }
        let epochAtStart = modelCatalogEpoch
        let keyAtStart = config?.baseString
        modelCatalogAttemptEpoch = epochAtStart
        let task = Task { @MainActor in
            let answered = await self.fetchModelCatalog()
            if answered {
                self.modelCatalogLoadedAt = Date()
                self.modelCatalogLoadedForConfig = keyAtStart
                self.modelCatalogLoadedEpoch = epochAtStart
            }
        }
        modelCatalogLoadTask = task
        await task.value
        modelCatalogLoadTask = nil
    }

    /// 刷新默认模型与可切换目录（0.2.4）：当前值来自
    /// /api/config；候选只来自上游（ModelCatalog 口径）：
    /// /api/model/options 优先，为空回落近 30 天用量 ∪
    /// 当前值；网关 /v1/models 的返回只作别名集用于排除，
    /// 本身永不进候选（0.2.2 的并集口径是 bug 源头）。
    /// §368：本函数只管取数与落值，新鲜度门/单飞在
    /// refreshModelCatalog 两口；返回本轮是否有应答
    /// （rawConfig 与 modelOptionsRaw 任一成功）——两
    /// 口全灭（离线）不落 stamp，下次触发照旧重试，
    /// 失败恢复与修前一致
    private func fetchModelCatalog() async -> Bool {
        var answered = false
        var registryEntries: [ProviderRegistry.Entry] = []
        let rawResult = try? await performAdmin { client, config in
            try await client.rawConfig(config: config)
        }
        if rawResult != nil { answered = true }
        if let raw = rawResult, let current = raw["model"]?.stringValue {
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
            answered = true
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
            // §158：隐藏名单过滤只作用于呈现清单——
            // chatModelGroups 本体保留全量（枢纽模型
            // 区/恢复名单/默认解析都要拿全量对账），
            // 选择器消费端过 Core visibleGroups；含默
            // 认的组结构上不许被滤掉（Core 闸）
            chatModelGroups = groups
            // §390 H9：会商组同轮追加——拉到 MoA 配置
            // 且有预设时在目录尾加「多模型会商」组
            // （逐请求 provider=moa）；拉不到/无预设
            // 就不加，不拖垮目录（同拼装失败不覆盖）
            if !isDemo {
                let moa = try? await performAdmin { client, config in
                    try await client.moaConfig(config: config)
                }
                if let moa, !moa.presets.isEmpty {
                    chatModelGroups = groups + [moa.pickerGroup()]
                }
            }
        }
        // §153 旧全局选择一次性迁移：chatModelID 旧值
        // 播种给主线会话键（升级不丢用户既有选择）；
        // 此后旧键只读不写
        if !isDemo, !legacyChatModelMigrated {
            legacyChatModelMigrated = true
            if let legacy = AppPreferences.legacyChatModelID,
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
        return answered
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
        // §368：写后失效——下次触发必真拉（新值已同步
        // 进内存，失效只影响取数时机）
        invalidateModelCatalog()
    }

    /// 设置页在本页内写回 config 后同步内存态（避免两处口径漂移）。
    /// 网关别名不回填候选（它不是可选的上游模型）。
    func noteDefaultModel(_ model: String) {
        defaultModel = model
        if !availableModels.contains(model), !gatewayAliases.contains(model) {
            availableModels.insert(model, at: 0)
        }
        // §368：本口是写回后的同步口（三处调用全为写
        // 后），同步内存态的同时失效目录新鲜度
        invalidateModelCatalog()
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
            phase = .needsConnection
            return
        }
        if let config {
            client.clearCookies(config: config)
        }
        shortLivedTokenPair = nil
        KeychainStore.clearAll()
        config = nil
        phase = .needsConnection
    }
}
