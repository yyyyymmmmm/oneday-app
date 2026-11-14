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
/// 引用改挂 AppState.pendingFeedQuotesByThread 按线
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
        let stored = sessionModelChoices[key]
        let effectiveStored: ChatModelChoice?
        if let serverSessionID,
           !serverSessionID.isEmpty,
           serverSessionID == sideChats.mainServerSessionID,
           let serverModel = serverSessionCatalog.visibleSessions
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
        let legacy = UserDefaults.standard.string(forKey: "chatModelID")
            ?? defaultModel ?? ChatModels.fallbackID
        return ChatModelChoice(
            model: ModelDisplayNames.canonicalID(for: legacy),
            providerField: ChatModels.contains(legacy) ? "custom" : nil
        )
    }

    // MARK: - §158 已隐藏服务商（本机呈现治理）

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
    /// 服务端会话全量目录（§198）：全部对话页分页拉
    /// 全的可见集共享缓存，全 App 只此一份——抽屉频
    /// 道显行闸改读它判显隐（与管理页频道段同源），
    /// 不再共用开抽屉的 100 条名单窗口
    let serverSessionCatalog = ServerSessionCatalog()

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
    /// 智能体身份名（0.6.1 立、§245 改缓存镜像）：全
    /// 局唯一呈现出口——胶囊/抽屉/活动页三处显示名都
    /// 读这里。真值在服务端 SOUL、本机只存带时间戳
    /// 的缓存副本（AgentProfileStore.nameCache），本
    /// 属性是缓存的只读镜像；刷新链以 Dashboard 回
    /// 读整份替换缓存，App 改名走写穿（renameAgent）。
    /// 旧「档案名翻译当标题」（default→默认档案）与
    /// 本机改名覆盖两套口径均已退役
    var identityName: String? { agentProfileStore.cachedName }
    private var identityNameResolved = false

    /// 身份名拉取（A2 直连，§245：档案列表 → 默认档
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
              }),
              let name = AgentName.resolve(soulContent: document.content)
        else { return nil }
        return (name, document.updatedAt)
    }

    /// 服务器名回读后的统一收尾（§245）：先处置迁移
    /// 待推——§245 迁移时本机旧改名胜出且与回读名不
    /// 同时，先经桥写口写穿服务端，成功后重读一次以
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
            } else if let config {
                let pushed = (try? await IdentityBridgeClient()
                    .setName(config: config, name: pending)) != nil
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
    /// 性解析的网络链。§245：这次编辑本身就是一次服
    /// 务端写入（服务器收到时刻＝当下），迁移待推就
    /// 此作废——末写胜按时间裁决，这次写最晚
    func reresolveIdentityName(soulContent: String) {
        identityNameResolved = true
        if let name = AgentName.resolve(soulContent: soulContent) {
            agentProfileStore.markNamePushed()
            agentProfileStore.applyName(name, serverUpdatedAt: Date())
        }
    }

    /// 智能体身份缓存（§245）：名字/头像的服务端单真
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

    /// 头像仓同步（P1 身份包、§245 改镜像口径）：触
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
    /// （OneDayCore.AgentDisplayName，§245 收敛后只剩
    /// 这一级链）
    var agentDisplayName: String {
        AgentDisplayName.resolve(
            cachedName: agentProfileStore.cachedName
        )
    }

    // MARK: - 身份写穿（§245：App 改名/换头像直达服务端单真值）
    //
    // 三个写口共用口径：走服务端既有窄口写穿（校验/
    // 备份/留痕在服务端），成功后以服务端回读/仓指
    // 针整份替换缓存——App 不留第二真值。失败原样抛
    // 回编辑器呈现（IdentityBridgeError 文案已过
    // §232 安全门）。演示模式无真服务端：只动缓存演
    // 示、不发网络（与演示数据同性子）。

    /// App 改名写穿
    func renameAgent(to newName: String) async throws {
        if isDemo {
            agentProfileStore.applyName(newName, serverUpdatedAt: nil)
            return
        }
        guard let config else { throw IdentityBridgeError.noKey }
        try await IdentityBridgeClient().setName(
            config: config, name: newName
        )
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
    /// 点子底栏角标已整套退役（§177，用户 2026-11-12
    /// 亲定点子不出现「待阅」呈现——分区/状态字/角标
    /// 一并下线）：§123 M3 的 ideasUnread 计数、已见
    /// 水位落盘与刷新/清零方法随角标删除，Core
    /// IdeasBadge 同步退役；旧落盘键 ideas.seenWatermark
    /// 不再读写（残值无害、不做迁移）

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
    /// 锚点点达请求（§165）：枢纽记录行/通知回执命中本
    /// 机锚时置位——目标线程＋锚定键（键为 nil＝只切线
    /// 程不定位）；ChatView 消费（切线程→滚动定位→点
    /// 亮→清零），与 hubDestinationRequest 分家：锚点
    /// 落点不在枢纽里、不经枢纽开启接力
    var approvalAnchorRequest: (
        threadID: UUID, approvalKey: String?
    )?

    /// 通知条目落点分发：把落点拆成各消费方能消费的
    /// 字段；返回 false 表示无落点（调用方不导航）。
    /// §165：锚点落点（approvalAnchor/approvalThread）
    /// 不进 hubDestinationRequest——它由通知页直接切聊
    /// 天格＋置 approvalAnchorRequest，ChatView 消费；
    /// 返回 true 表示落点成立（调用方关通知页即可，不
    /// 走枢纽接力）
    @discardableResult
    func requestHubDestination(
        _ destination: NotificationDestination
    ) -> Bool {
        switch destination {
        case .approvalDecision(let id):
            hubApprovalFocusID = id
        case .monitorChange(let monitorID, let changeID):
            monitorDeepLink = (monitorID, changeID)
        case .approvalAnchor(let threadID, let key):
            approvalAnchorRequest = (threadID, key)
            return destination.hasDestination
        case .approvalThread(let threadID):
            approvalAnchorRequest = (threadID, nil)
            return destination.hasDestination
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
    /// 动态讨论待发引用（§208 立制、§210 改挂）：按
    /// 线程寻址存放——引用挂在目标线程自己的待发
    /// 状态上（与 Telegram 草稿按 peer 存、Stream
    /// composer 长在 channel 上的主流形态同构），
    /// FeedView.discuss 在落点决定的同一动作内直写
    /// 本表，ChatView 按 currentThreadID 派生呈现：
    /// 不经全局种子事件消费、不依赖视图存亡与事件
    /// 顺序（§210 定因，见 discuss-quote-attach-
    /// report-20261113）。不经草稿账（setDraft 只许
    /// 亲笔，见 SideChatStore 隔离铁律）。只活在内
    /// 存：进程死亡即亡，与引用本身的生命周期一致
    /// （引用不落盘恢复，规格 §3.3）
    var pendingFeedQuotesByThread: [UUID: FeedPostQuote] = [:]
    /// 点子／文件待发引用（§219）：与上表同型——按
    /// 线程寻址存放，IdeasView.openIdeaChat 与 File-
    /// OpenView.requestResend 在落点决定的同一动作内
    /// 直写本表，ChatView 按 currentThreadID 派生呈
    /// 现。载荷是 SourceQuote 统一枚举，本表只承载
    /// .idea／.file 两族（.feed 族沿上表 §210 既有通
    /// 道，不在此重复存放）；槽位单一在场、后入覆盖
    /// 的互斥由 ChatView 呈现侧收口函数对两表交叉清
    /// 理兑现。只活在内存、进程死亡即亡（同上表）
    var pendingSourceQuotesByThread: [UUID: SourceQuote] = [:]
    /// 动态原帖回跳请求（§208）：聊天里点消息的动态
    /// 引用块时置位帖 id 并同行置 mainTabSwitch-
    /// Request=.feed 切格，FeedView 消费后定位原帖
    /// （查无此帖给诚实提示）并清零——置位—消费—
    /// 清零与 fileRevealPath 同式
    var feedOpenPostRequest: String?
    /// 点子回跳请求（§219）：聊天里点消息的点子引
    /// 用块时置位点子 id 并同行置 mainTabSwitch-
    /// Request=.ideas 切格，IdeasView 消费后开该点
    /// 子详情（查无此点子给诚实提示）并清零——与
    /// feedOpenPostRequest 同式
    var ideaOpenRequest: String?
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

    // MARK: - 引导四步连接（欢迎/登录/连接中/成功面）

    /// 引导·密码登录一步制（用户 2026-11-11 定版，覆盖
    /// 原型两步）：地址＋账号＋密码一步连上。链路全是现
    /// 行生产端点——健康检查（兼量延迟）→ Hermes 本体
    /// password-login 验密码 → /api/env/reveal 换取登录
    /// 密钥 API_SERVER_KEY（服务端代管下发）→ 用该钥验
    /// /v1/models 并读服务信息。伴生 front 8650 的双方式
    /// 登录查毕不可复用：它只发面板会话 cookie、明文凭
    /// 据从不出其 API、且其密码无账号概念（查证见
    /// DESIGN 引导线记账）。全过才落 Keychain（四件套，
    /// 与 connect 同口径，performAdmin 静默重登靠它）；
    /// 本方法不置 phase——成功面先行展示，用户点「开
    /// 始聊天」再由 activatePreparedConnection 进主界面
    /// （杀进程在成功面时 restore 照样凭 Keychain 成立）。
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
            self.username = username
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
            username = nil
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
            // §158：隐藏名单过滤只作用于呈现清单——
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
