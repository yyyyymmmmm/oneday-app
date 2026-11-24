import Foundation
import OneDayCore
import SwiftData

/// 身份键值存储口（根治版包 1，DESIGN §330）：主线
/// 钦定身份键（线程/服务端会话 id＋链接确认位）的
/// 底层存储——生产＝Keychain（与登录凭据同级）、演
/// 示/测试＝内存。身份键只许经本口读写；UserDefa-
/// ults 旧键（sideChats.main*）退为一版双轨镜像（写
/// 路径同拍回写、读出旧键在册优先/本口兜底，停写
/// 归下一大版本，与归档列同口径）。布尔以 "1"/"0"
/// 字符串落存储（string(forKey:) 非空即「在册」，
/// 迁移的在册判定靠它）
protocol IdentityValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func set(_ value: String?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
}

/// Keychain 形态（生产）：薄封 KeychainStore，键名
/// 见 IdentityKey
final class KeychainIdentityValueStore: IdentityValueStore {
    func string(forKey key: String) -> String? {
        KeychainStore.read(account: key)
    }

    func bool(forKey key: String) -> Bool {
        KeychainStore.read(account: key) == "1"
    }

    func set(_ value: String?, forKey key: String) {
        if let value {
            KeychainStore.save(value, account: key)
        } else {
            KeychainStore.delete(account: key)
        }
    }

    func set(_ value: Bool, forKey key: String) {
        KeychainStore.save(value ? "1" : "0", account: key)
    }
}

/// 内存形态（演示模式与测试注入）：进程内字典，不
/// 落任何持久介质
final class MemoryIdentityValueStore: IdentityValueStore {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        values[key]
    }

    func bool(forKey key: String) -> Bool {
        values[key] == "1"
    }

    func set(_ value: String?, forKey key: String) {
        values[key] = value
    }

    func set(_ value: Bool, forKey key: String) {
        values[key] = value ? "1" : "0"
    }
}

/// 主线认领记录（§330）：认领事件的落痕——认领到
/// 哪条、消息数、最近活动、认领当刻的归档位、同标
/// 题候选数。设置页「主线会话」呈现；归档位同时是
/// 「打开时解档」的一次性凭据（解档落定即清位）。
/// 非身份键，UserDefaults 存放
struct MainlineClaimRecord: Codable, Equatable {
    var sessionID: String
    var messageCount: Int?
    var lastActivityAt: TimeInterval?
    var isArchived: Bool
    var candidateCount: Int
    var claimedAt: TimeInterval
}

/// 主线发送闸（根治版包 2，DESIGN §331）：发送只
/// 认「会话 id 已知」——id 在手即 ready（来源＝认
/// 领落存或冷启动铸造，与种子落没落无关）；id 未
/// 知才 needsIdentity（先走认领/建立）。0.27.0 的
/// 「confirmed && seeded」双位硬门就此废除：种子
/// 位降为纯记账（mainServerSeeded 仍在，只是不再
/// 进发送判据）
enum MainSendGate: Equatable {
    case ready(sessionID: String)
    case needsIdentity
}

/// 主线历史同步快照（§331）：主线线程的回补/种子
/// 记账镜像——ChatView 在同步动作落点更新，设置
/// 页「主线会话」据此安静呈现（已齐/补齐中/未同
/// 步/仅文本），不另开 SwiftData 读面
struct MainSyncStatus: Equatable {
    var historyUnsynced: Bool
    var historyLoaded: Int
    var historyTotal: Int
    var seedState: SeedSyncState
}

/// 认领一轮的结局（§330）：调用方（链接链/设置页）
/// 据此决定下一步——只有 .noCandidateOnServer 许走
/// 冷启动铸造，.directoryUnavailable 必须停手待重试
enum MainlineClaimOutcome: Equatable {
    /// 本地身份缓存已有 id（或重新发现时现任仍在目
    /// 录里）：不打扰服务端、不改指针
    case alreadyKnown
    /// 认领落定：id 已落存＋确认位已置＋记录已留痕
    case claimed(
        sessionID: String, candidateCount: Int, isArchived: Bool
    )
    /// 目录里确无同标题主线：服务端无主线已证
    case noCandidateOnServer
    /// 未登录或目录拉不到：身份未定，不许铸造
    case directoryUnavailable
}

/// 会话账本（第 67 条收口包一，2026-11-15）：「我有
/// 哪些会话」的单店——全 App 唯一拉取者＋合并名单
/// 持有者。底层存储零迁移：SwiftData ChatThread（本
/// 体）、Hermes /api/sessions（服务端真源）、User-
/// Defaults 侧账（原键）都不动，换的是记账的人。
///
/// 读口：records（合并名单，本地线程由各面 @Query
/// 在刷新/呈现时注入——账本不自持 ModelContext）与
/// 其投影（LedgerProjection 纯函数，本店只做转发）。
/// 存活集只许连完整性一并交出（liveSet）：complete
/// 才可用于对账删除判定，incomplete 只可留痕/呈现。
///
/// 写路径：包一只开同步（refresh/refreshVisible）；
/// 包二起删除引擎（SessionDeletionEngine）归本店
/// 持有——删除走账本单管线，SessionDeletionCoordi-
/// nator 降为转发壳；归档/改名仍走动作层写穿（调
/// 用方改读账本）。ServerSessionCatalog 自包一起
/// 降为转发壳（publish/remove/refreshIfCold 转本
/// 店），外部调用方一字不改。
///
/// 第 90 条收尾（账本余三件＋B-07）：①存量迁移挂
/// 载点迁入——runMigration 触发改挂本店 refresh
/// 归档段同步完成点，执行本体与失败留痕归本店；
/// ②主线钦定（五键）与三张关联表（点子/目标/动
/// 态讨论）持有迁入——同键读写、持有者换人，草
/// 稿/滚动锚/lastThreadID 不并入（留 SideChat-
/// Store）；③归档键持有迁入——原键读入、写路径
/// 仍回写原键（双轨一版保回滚：旧版 App 读同键
/// 即恢复全功能），归档失败留痕随归档列收编；
/// B-07：分页装配核（fetchAll/fetchAllPages＋完
/// 整性判定）迁入本店，ServerSessionCatalog 转
/// 发壳整件删除、调用方改直连本店。
@MainActor
@Observable
final class SessionLedger {
    /// 侧账落盘口（第 90 条收尾）：与 SideChatStore
    /// 同口径——演示模式纯内存（persisted=false），
    /// 不污染真实档案；键名全部沿用 sideChats.* 原
    /// 键（持有者换人、键不变，升级/回滚零翻译）
    private let defaults: UserDefaults?
    /// 身份键存储（§330）：生产＝Keychain、演示＝内
    /// 存；UserDefaults 旧键是双轨镜像（读出口径见
    /// loadPersistedState，见 IdentityValueStore 注）
    private let identityStore: IdentityValueStore
    /// 解码失败收集（§332）：loadPersistedState 期
    /// 间在册却解不出的键名落此（键缺席不算失败）；
    /// 读入收尾由 finalizeStateReadFailures 统一处
    /// 置（落痕＋明示＋自愈标记），不在解码点散处理
    private var stateReadFailureKeys: [String] = []

    private enum Key {
        static let mainThreadID = "sideChats.mainThreadID"
        static let mainServerSessionID =
            "sideChats.mainServerSessionID"
        static let mainServerConfirmed =
            "sideChats.mainServerConfirmed"
        static let mainServerSeeded = "sideChats.mainServerSeeded"
        static let mainLinkLastError =
            "sideChats.mainLinkLastError"
        static let mainClaimRecord =
            "sideChats.mainClaimRecord"
        static let archivedKeys = "sideChats.archivedKeys"
        static let failedArchiveSessionIDs =
            "sideChats.failedArchiveSessionIDs"
        static let ideaThreadIDs = "sideChats.ideaThreadIDs"
        static let goalThreadIDs = "sideChats.goalThreadIDs"
        static let feedDiscussPostIDs =
            "sideChats.feedDiscussPostIDs"
    }

    init(persisted: Bool = true) {
        defaults = persisted ? .standard : nil
        identityStore = persisted
            ? KeychainIdentityValueStore()
            : MemoryIdentityValueStore()
        loadPersistedState()
    }

    /// 测试口（§330）：注入侧账口与身份存储——验身
    /// 份键迁移（旧值搬运＋幂等）与认领落存，不碰真
    /// 实 Keychain 与标准侧账
    init(defaults: UserDefaults?, identityStore: IdentityValueStore) {
        self.defaults = defaults
        self.identityStore = identityStore
        loadPersistedState()
    }

    /// 落盘状态读入（两口共用）：身份键先过一次性搬
    /// 运、再以身份存储为权威读出；其余侧账仍读
    /// UserDefaults 原键（持有迁入口径不变）
    private func loadPersistedState() {
        if let defaults {
            Self.migrateIdentityKeys(
                from: defaults, to: identityStore
            )
        }
        // 身份键读出口径（§330）：旧键在册时以旧键为
        // 准——双轨写恒同步、不一致只来自旧版期间写
        // 入（末写胜）；且 Keychain 在无权益环境（未
        // 签名测试宿主等）写不进时旧键是唯一可靠落
        // 点。旧键缺席（被清/损坏）才读身份存储——迁
        // 移已把旧值搬入，那时靠它保身份不丢
        if let raw = defaults?.string(forKey: Key.mainThreadID)
            ?? identityStore.string(
                forKey: IdentityKey.mainThreadID
            ) {
            if let parsed = UUID(uuidString: raw) {
                mainThreadID = parsed
            } else {
                // §332：在册但解不出＝损坏，不许静默
                // 当缺失——与 decode 失败同账收尾处理
                stateReadFailureKeys.append(Key.mainThreadID)
            }
        }
        mainServerSessionID = defaults?.string(
            forKey: Key.mainServerSessionID
        ) ?? identityStore.string(
            forKey: IdentityKey.mainServerSessionID
        )
        mainServerConfirmed = Self.identityBool(
            legacy: defaults, legacyKey: Key.mainServerConfirmed,
            store: identityStore,
            identityKey: IdentityKey.mainServerConfirmed
        )
        mainServerSeeded = Self.identityBool(
            legacy: defaults, legacyKey: Key.mainServerSeeded,
            store: identityStore,
            identityKey: IdentityKey.mainServerSeeded
        )
        guard let defaults else {
            finalizeStateReadFailures()
            return
        }
        mainLinkLastError = defaults.string(
            forKey: Key.mainLinkLastError
        )
        mainClaimRecord = decode(
            MainlineClaimRecord.self, Key.mainClaimRecord
        )
        archivedKeys = Set(
            defaults.stringArray(forKey: Key.archivedKeys) ?? []
        )
        failedArchiveSessionIDs = decode(
            [String].self, Key.failedArchiveSessionIDs
        ) ?? []
        ideaThreadIDs = decode(
            [String: String].self, Key.ideaThreadIDs
        ) ?? [:]
        goalThreadIDs = decode(
            [String: String].self, Key.goalThreadIDs
        ) ?? [:]
        feedDiscussPostIDs = decode(
            [String: String].self, Key.feedDiscussPostIDs
        ) ?? [:]
        finalizeStateReadFailures()
    }

    /// 侧账解码（§332 改明示）：键缺席＝从未写过、
    /// 回 nil 不算失败；键在册但解码失败＝数据损
    /// 坏——键名记入 stateReadFailureKeys，读入收
    /// 尾统一落痕＋明示＋置自愈标记（finalizeState-
    /// ReadFailures），不许再 try? 静默回空装作无事
    private func decode<T: Decodable>(
        _ type: T.Type, _ key: String
    ) -> T? {
        guard let defaults,
              let data = defaults.data(forKey: key) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            stateReadFailureKeys.append(key)
            return nil
        }
    }

    /// 解码失败收尾（§332）：任一键失败即三件同拍
    /// ——诊断痕留底（键名点名）、人话提示置位（设
    /// 置页「主线会话」呈现）、自愈标记置位（进主
    /// 线链接时向服务端重新发现对账，见 rediscover-
    /// AfterStateReadFailure）。本地状态自此按「未
    /// 认领」对待：恢复动作是向服务端发现认领，不
    /// 是静默清零后本地铸造新 id
    private func finalizeStateReadFailures() {
        guard !stateReadFailureKeys.isEmpty else { return }
        ChatDiagTrace.record(
            "本地状态读取失败："
                + stateReadFailureKeys.joined(separator: "、")
                + " 解码失败，已按未认领处理，将向服务端重新发现认领"
        )
        localStateReadFailureNote =
            "本地状态读取失败，已按未认领处理（将自动向服务器重新确认）"
        stateReadFailurePendingRediscovery = true
    }

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        guard let defaults else { return }
        do {
            defaults.set(
                try JSONEncoder().encode(value), forKey: key
            )
        } catch {
            // 编码失败留痕（§332）：不许静默，更不许
            // 把失败的 nil 写回去删掉既有值——跳过本
            // 次落盘、原值保留
            ChatDiagTrace.record(
                "本地状态写入失败：\(key) 编码失败，本次落盘已跳过"
            )
        }
    }

    /// 身份布尔读出（§330）：旧键在册以旧键为准（同
    /// 字符串口径），缺席读身份存储
    private static func identityBool(
        legacy defaults: UserDefaults?, legacyKey: String,
        store: IdentityValueStore, identityKey: String
    ) -> Bool {
        if let defaults,
           defaults.object(forKey: legacyKey) != nil {
            return defaults.bool(forKey: legacyKey)
        }
        return store.bool(forKey: identityKey)
    }

    /// 身份键一次性搬运（§330）：旧 UserDefaults 值
    /// 与身份存储不一致时以旧值覆写存储——新版写路
    /// 径双轨同写、两处恒同步，不一致只可能来自「旧
    /// 版 App 期间（降级往返）的写入」，那时旧值就是
    /// 最后写入值（末写胜）；两处一致时本函数无动作
    /// ——重复执行幂等。旧键不删：作一版双轨镜像保回
    /// 滚（停写/清键归下一大版本，与归档列同口径）
    private static func migrateIdentityKeys(
        from defaults: UserDefaults, to store: IdentityValueStore
    ) {
        let stringPairs = [
            (Key.mainThreadID, IdentityKey.mainThreadID),
            (Key.mainServerSessionID,
             IdentityKey.mainServerSessionID),
        ]
        for (legacyKey, identityKey) in stringPairs {
            guard let legacy = defaults.string(forKey: legacyKey),
                  store.string(forKey: identityKey) != legacy
            else { continue }
            store.set(legacy, forKey: identityKey)
        }
        let boolPairs = [
            (Key.mainServerConfirmed,
             IdentityKey.mainServerConfirmed),
            (Key.mainServerSeeded, IdentityKey.mainServerSeeded),
        ]
        for (legacyKey, identityKey) in boolPairs {
            guard defaults.object(forKey: legacyKey) != nil
            else { continue }
            let legacy = defaults.bool(forKey: legacyKey)
            if store.bool(forKey: identityKey) != legacy {
                store.set(legacy, forKey: identityKey)
            }
        }
    }
    /// 删除引擎（包二归属）：待删队列/墓碑/后台围
    /// 栏删/落定收口/失败恢复全在此一台，队列是待
    /// 删集的唯一真相（各面过滤只读本队列，经本店
    /// 构建名单时一处过滤）
    let deletions = SessionDeletionEngine()
    /// 可见段展示名单（archived=exclude 拉全、待删
    /// 集已过滤——与旧 ServerSessionCatalog.visible-
    /// Sessions 逐字同义，目录壳转发读本列）
    private(set) var visibleSessions: [ServerSession] = []
    /// 已归档段展示名单（archived=only 拉全、待删集
    /// 已过滤——旧 AllConversationsStore.archived-
    /// Sessions 的收编）
    private(set) var archivedSessions: [ServerSession] = []
    /// 可见段是否已有一轮全量结果（冷/热唯一判定：
    /// 拉到空集也是结果，不许每开一次抽屉重拉全量）
    private(set) var hasLoaded = false
    /// 两段全量刷新是否完成过（收养判定读账本名单
    /// 的凭据：未完成时收养路回落现拉 include）
    private(set) var hasLoadedFull = false
    /// 主线行兜底：两段都没拉到钦定 id 时的单查结果
    /// （旧 AllConversationsStore.mainFallback 收编）
    private(set) var mainFallback: ServerSession?
    /// 最近一轮全量刷新的存活集＋完整性（refresh 内
    /// 以未过滤两段构造；不完整时 completeness 带原
    /// 因、ids 只作留痕呈现、不许喂删除判定）
    private(set) var liveSessionIDs: Set<String> = []
    private(set) var liveCompleteness: LedgerCompleteness =
        .incomplete(reason: "尚未拉取")
    /// 可见段刷新在飞标记（多路触发合并成一轮）
    private var isRefreshingVisible = false
    /// 可见段新鲜度门（§370，缓存 C3）：名单类标准
    /// 档 60s（§367.3 定档，与三店同口径）——落定/
    /// 回前台/预挂载三路读触发先过本门，新鲜直接用
    /// 已载名单、零请求；强制路（刷新令牌/行操作回
    /// 读）不经门、成功同样落账
    private var listFreshness = FreshnessGate(
        ttl: FreshnessGate.standardListTTL
    )
    /// 名单失效代次（§370）：写事件落定即 invalidate
    /// 自增；刷新起手记代次、落账时对账——代次变了
    /// 说明拉取横跨一次写事件，本轮结果不许落账冒
    /// 充新鲜（与 C2 epoch 同式）
    private var listFreshnessEpoch = 0

    /// 名单写事件落定的失效口（§370.2）：删除摘行/
    /// 旁聊一轮落地/改名·置顶·归档回读落定都经此把
    /// 新鲜度作废——下一次读触发必真拉，写后一致性
    /// 优先于省请求
    func invalidateListFreshness() {
        listFreshnessEpoch += 1
        listFreshness = FreshnessGate(
            ttl: FreshnessGate.standardListTTL
        )
    }

    // MARK: - 主线钦定（第 90 条收尾：持有迁入，同键）

    private(set) var mainThreadID: UUID?
    private(set) var mainServerSessionID: String?
    private(set) var mainServerConfirmed = false
    /// 主线种子已落位（0.27.0）：主线本地历史已导入
    /// 钦定会话——确认位与种子位由 markMainLinked
    /// 一并置真（链接流程把「会话存在」与「历史已
    /// 导入」一次做完，不再分两段各确认一半）
    private(set) var mainServerSeeded = false
    /// 主线最近一次链接失败原因（0.27.0）：链接失败
    /// 不许再静默——原文落此、设置页「服务器与连接」
    /// 区如实展示，链接成功即清
    private(set) var mainLinkLastError: String?
    /// 主线认领记录（§330）：最近一次认领落定的留痕
    /// （认领到哪条/消息数/最近活动/归档位/候选数），
    /// 设置页「主线会话」呈现；归档位同时是「打开时
    /// 解档」的一次性凭据（解档落定即清位）
    private(set) var mainClaimRecord: MainlineClaimRecord?
    /// 本地状态读取失败的人话提示（§332）：启动读
    /// 入时任一侧账解码失败即置位，设置页「主线会
    /// 话」呈现；自愈对账完成（目录可达）后清，诊
    /// 断痕永久留底
    private(set) var localStateReadFailureNote: String?
    /// 解码失败待自愈标记（§332）：ChatView 进主
    /// 线链接时消费一次——向服务端重新发现对账
    /// （rediscoverAfterStateReadFailure）；未登录
    /// 时不消费、留待登录后
    private(set) var stateReadFailurePendingRediscovery = false

    func designateMainThread(_ id: UUID) {
        mainThreadID = id
        identityStore.set(
            id.uuidString, forKey: IdentityKey.mainThreadID
        )
        // 双轨镜像：旧键同拍回写（§330，停写归下一版）
        defaults?.set(id.uuidString, forKey: Key.mainThreadID)
    }

    /// 主线的服务端会话 id：已有落存直接返回；缺失时
    /// 本地生成并持久化——§330 起本函数降为冷启动最
    /// 后手段：调用方必须先走 discoverAndClaimMain-
    /// line 确认服务端无主线（或认领落存）才许到这
    /// 里，生成值最终以服务端建会话回执为准改存
    func ensureMainServerSessionID() -> String {
        if let mainServerSessionID { return mainServerSessionID }
        let generated = "oneday-main-\(UUID().uuidString.lowercased())"
        setMainServerSessionID(generated)
        return generated
    }

    func setMainServerSessionID(_ id: String) {
        mainServerSessionID = id
        identityStore.set(
            id, forKey: IdentityKey.mainServerSessionID
        )
        defaults?.set(id, forKey: Key.mainServerSessionID)
    }

    func confirmMainServer() {
        mainServerConfirmed = true
        identityStore.set(
            true, forKey: IdentityKey.mainServerConfirmed
        )
        defaults?.set(true, forKey: Key.mainServerConfirmed)
    }

    /// 主线发送闸派生（§331）：id 已知即 ready——
    /// 发送路径的单点判据，种子/回补状态一律不进
    /// （它们是后台义务、不是发送前置）
    func mainSendGate() -> MainSendGate {
        guard let mainServerSessionID, !mainServerSessionID.isEmpty
        else { return .needsIdentity }
        return .ready(sessionID: mainServerSessionID)
    }

    /// 主线同步快照（§331，内存面不落盘：呈现素材，
    /// 进程重启后由下一轮同步动作重建）
    private(set) var mainSyncStatus: MainSyncStatus?

    /// 同步动作落点回写快照（ChatView 的回补/种子
    /// 调度收口调用；数值口径与主线线程三字段同源）
    func updateMainSyncStatus(
        historyUnsynced: Bool, historyLoaded: Int,
        historyTotal: Int, seedState: SeedSyncState
    ) {
        mainSyncStatus = MainSyncStatus(
            historyUnsynced: historyUnsynced,
            historyLoaded: historyLoaded,
            historyTotal: historyTotal,
            seedState: seedState
        )
    }

    /// 主线链接落定（0.27.0）：会话存在＋种子已落
    /// 一并确认、失败留痕清零。§331 后种子位只剩
    /// 记账意义（发送闸见 mainSendGate），本函数仍
    /// 是「链接＋种子同轮落定」时的收口
    func markMainLinked() {
        confirmMainServer()
        mainServerSeeded = true
        identityStore.set(
            true, forKey: IdentityKey.mainServerSeeded
        )
        defaults?.set(true, forKey: Key.mainServerSeeded)
        mainLinkLastError = nil
        defaults?.removeObject(forKey: Key.mainLinkLastError)
    }

    /// 主线链接失败留痕（0.27.0）：原因原文落盘，
    /// 设置页展示；不置任何确认位，下次进页/发送
    /// 重试链接
    func noteMainLinkError(_ message: String) {
        mainLinkLastError = message
        defaults?.set(message, forKey: Key.mainLinkLastError)
    }

    // MARK: - 发现与认领（根治版包 1，DESIGN §330）

    /// 登录后发现与认领（第一动作）：本地身份缓存已
    /// 有 id 时不打扰服务端（.alreadyKnown）；缺失时
    /// 拉目录过纯函数判定——认领到则落存 id＋确认位
    /// ＋认领记录；目录确无主线回 .noCandidateOn-
    /// Server（调用方才许走冷启动铸造）；未登录/目
    /// 录不可达回 .directoryUnavailable（调用方不许
    /// 铸造、留未认领态待重试）。本函数永不铸造 id、
    /// 永不写服务端
    @discardableResult
    func discoverAndClaimMainline(
        appState: AppState
    ) async -> MainlineClaimOutcome {
        guard mainServerSessionID == nil else {
            return .alreadyKnown
        }
        guard appState.config != nil else {
            return .directoryUnavailable
        }
        guard let rows = await claimSessions(appState: appState)
        else { return .directoryUnavailable }
        return applyMainlineClaim(rows: rows)
    }

    /// 设置页手动重新发现（§330）：不短路现任 id——
    /// 现任仍在目录里回 .alreadyKnown（无事）；不在
    /// 目录里且有同标题候选则改认候选（指针接错/服
    /// 务端换代的支持面恢复路，改认在认领记录与诊
    /// 断痕里留名）；不在且无候选保留现任指针不清
    /// 空（名单未必完整、清空是破坏动作），原因落
    /// mainLinkLastError 呈现
    @discardableResult
    func rediscoverMainline(
        appState: AppState
    ) async -> MainlineClaimOutcome {
        guard appState.config != nil,
              let rows = await claimSessions(appState: appState)
        else {
            noteMainLinkError(
                "重新发现没完成：会话目录拉取失败，请检查连接后重试"
            )
            return .directoryUnavailable
        }
        if let current = mainServerSessionID,
           rows.contains(where: { $0.session.id == current }) {
            return .alreadyKnown
        }
        let outcome = applyMainlineClaim(rows: rows)
        if outcome == .noCandidateOnServer,
           mainServerSessionID != nil {
            noteMainLinkError(
                "服务器目录里没找到当前主线，也没有同名会话可认领——已保留现有绑定"
            )
        }
        return outcome
    }

    /// 解码失败自愈消费（§332）：ChatView 进主线
    /// 链接（ensureMainLink）入口调用——标记在册
    /// 且已登录时走一轮重新发现对账（复用 redis-
    /// coverMainline：现任在册无事、失效改认候选、
    /// 无候选保留现任不清指针）；目录不可达时提
    /// 示保留待下次启动再对账。标记一轮只消费一
    /// 次，不许每进一次主线都重拉目录
    func rediscoverAfterStateReadFailure(
        appState: AppState
    ) async {
        guard stateReadFailurePendingRediscovery else { return }
        guard appState.config != nil else { return }
        stateReadFailurePendingRediscovery = false
        let outcome = await rediscoverMainline(appState: appState)
        if outcome != .directoryUnavailable {
            localStateReadFailureNote = nil
        }
    }

    /// 认领候选行（与 adoptionSessions 同源、另带归
    /// 档位与行本体）：账本两段齐全时按段定归档位
    /// （可见段 false、归档段 true）；未齐全回落现拉
    /// include 全量、归档位读行本体。只用于候选检
    /// 索、不驱动删除，不需完整性闸（不完整至多漏
    /// 候选、方向保守）；拉不到返回 nil
    private func claimSessions(
        appState: AppState
    ) async -> [(session: ServerSession, isArchived: Bool)]? {
        if hasLoadedFull {
            var seen = Set<String>()
            var rows: [(session: ServerSession, isArchived: Bool)] = []
            for session in visibleSessions
            where seen.insert(session.id).inserted {
                rows.append((session, session.isArchived ?? false))
            }
            for session in archivedSessions
            where seen.insert(session.id).inserted {
                rows.append((session, true))
            }
            return rows
        }
        guard let sessions = try? await Self.fetchAll(
            appState: appState, archived: "include"
        ).sessions else { return nil }
        return sessions.map { ($0, $0.isArchived ?? false) }
    }

    /// 身份对账取数（H1-d 体检第四组）：现拉一份服务
    /// 端目录全量（含归档段）连同完整性口径回给体检
    /// 面——对账认的是刚拉到的服务端目录，不拿本地
    /// 缓存投影冒充服务端所报。与 claimSessions 的区
    /// 别：那边为候选检索可读缓存、完整性不设闸；这
    /// 边是判定数据源，完整性口径必须原样带出（没拉
    /// 全就不下结论）。只读：不写服务端、不动本地账
    func identityCatalogSnapshot(
        appState: AppState
    ) async throws -> FetchResult {
        try await Self.fetchAll(
            appState: appState, archived: "include"
        )
    }

    /// 本机账本的目录投影条数（可见＋归档两段去重）：
    /// 只作对账时的漂移提示、不作判据；账本没整表加
    /// 载过时为 nil（没缓存就不提缓存的事）
    var localCatalogProjectionCount: Int? {
        guard hasLoadedFull else { return nil }
        var seen = Set<String>()
        for session in visibleSessions { seen.insert(session.id) }
        for session in archivedSessions { seen.insert(session.id) }
        return seen.count
    }

    /// 认领判定与落存（两口共用）：候选投影交 Core
    /// 纯函数（标题全等＋删除账排除＋既定序）；落存
    /// 只写本地身份缓存与认领记录——不写服务端、不
    /// 解档（归档位随记录留存，解档归打开动作）
    private func applyMainlineClaim(
        rows: [(session: ServerSession, isArchived: Bool)]
    ) -> MainlineClaimOutcome {
        let candidates = rows.map {
            MainlineAdoptionCandidate(
                id: $0.session.id, title: $0.session.serverTitle,
                lastActivityAt: $0.session.endedAt
                    ?? $0.session.startedAt,
                isArchived: $0.isArchived
            )
        }
        // 防复活：本地删除账（删除引擎待删队列——删
        // 除未落定的会话服务端仍有其行）在册 id 先排
        // 除，判定本体在 Core 纯函数内过滤
        switch MainlineClaimDirective.directive(
            title: SideChatStore.mainTitle,
            candidates: candidates,
            excludedIDs: deletions.queue.sessionIDs
        ) {
        case .noCandidate:
            return .noCandidateOnServer
        case .claim(let id, let isArchived):
            return recordMainlineClaim(
                sessionID: id, candidateCount: 1,
                isArchived: isArchived, rows: rows
            )
        case .claimAmongMultiple(let id, let count, let isArchived):
            return recordMainlineClaim(
                sessionID: id, candidateCount: count,
                isArchived: isArchived, rows: rows
            )
        }
    }

    /// 认领落存：id 落身份缓存＋确认位置真＋认领记
    /// 录留痕（诊断痕＋设置页记录同源）；改认（原绑
    /// 定非空且不同）时在诊断痕里点名原绑定
    private func recordMainlineClaim(
        sessionID: String, candidateCount: Int,
        isArchived: Bool,
        rows: [(session: ServerSession, isArchived: Bool)]
    ) -> MainlineClaimOutcome {
        let previous = mainServerSessionID
        setMainServerSessionID(sessionID)
        confirmMainServer()
        let row = rows.first { $0.session.id == sessionID }?.session
        let record = MainlineClaimRecord(
            sessionID: sessionID,
            messageCount: row?.messageCount,
            lastActivityAt: row?.endedAt ?? row?.startedAt,
            isArchived: isArchived,
            candidateCount: candidateCount,
            claimedAt: Date().timeIntervalSince1970
        )
        mainClaimRecord = record
        persist(record, Key.mainClaimRecord)
        var trace = "主线认领：服务端目录认领既有会话 \(sessionID)"
            + "（消息 \(record.messageCount.map(String.init) ?? "未知") 条"
            + "、同标题候选 \(candidateCount) 条"
            + (isArchived ? "、归档态保持" : "")
            + "）"
        if let previous, previous != sessionID {
            trace += "；原绑定 \(previous) 已改认"
        }
        ChatDiagTrace.record(trace)
        return .claimed(
            sessionID: sessionID,
            candidateCount: candidateCount,
            isArchived: isArchived
        )
    }

    /// 认领归档态的一次性解档（§330 主线裁定）：认
    /// 领时保持归档，用户打开主线（链接落定）时才
    /// 解——只认认领记录的归档位，落定即清位，用户
    /// 此后自行归档与本路无关；解档失败不清位、下
    /// 次打开再试
    func unarchiveClaimedMainlineIfNeeded(
        appState: AppState
    ) async {
        guard let record = mainClaimRecord, record.isArchived,
              record.sessionID == mainServerSessionID
        else { return }
        let outcome = await ServerSessionActions.setArchived(
            appState: appState, id: record.sessionID,
            archived: false
        )
        guard case .verified = outcome else { return }
        var updated = record
        updated.isArchived = false
        mainClaimRecord = updated
        persist(updated, Key.mainClaimRecord)
        unarchive(serverSessionID: record.sessionID)
        ChatDiagTrace.record(
            "主线认领归档已随打开解档：\(record.sessionID)"
        )
    }

    // MARK: - 归档列（第 90 条收尾：持有迁入＋双轨回写）

    /// 本地归档键集（`local:<uuid>` 与 `server:<id>`
    /// 双命名空间共用一集）：账本读入建归档列，写
    /// 路径仍回写原键 sideChats.archivedKeys——双轨
    /// 一版保回滚（旧版 App 读同键即恢复全功能），
    /// 停写/清键归下一大版本
    private(set) var archivedKeys: Set<String> = []
    /// 删除归档失败留痕（0.21.0）：本地线程已删、关
    /// 联服务端会话归档 PATCH 失败待对账的会话 id
    /// 集（口径见 noteFailedSessionArchive）——随归
    /// 档列收编（施工图 §4.2）
    private(set) var failedArchiveSessionIDs: [String] = []

    func archive(localThreadID: UUID) {
        archivedKeys.insert(SideChatArchive.localKey(localThreadID))
        persistArchived()
    }

    func archive(serverSessionID: String) {
        archivedKeys.insert(SideChatArchive.serverKey(serverSessionID))
        persistArchived()
    }

    func unarchive(localThreadID: UUID) {
        archivedKeys.remove(SideChatArchive.localKey(localThreadID))
        persistArchived()
    }

    func unarchive(serverSessionID: String) {
        archivedKeys.remove(SideChatArchive.serverKey(serverSessionID))
        persistArchived()
    }

    private func persistArchived() {
        defaults?.set(Array(archivedKeys), forKey: Key.archivedKeys)
    }

    /// 抽屉删本地线程时关联服务端会话做归档（PATCH
    /// archived:true）——本地删除不被服务端动作阻
    /// 塞、归档尽力而为；失败不许静默吞：会话 id 落
    /// 此账留痕，该会话在管理页未归档段仍可见、可
    /// 手动归档收尾；日后归档成功（本表对账）由
    /// clearFailedSessionArchive 销账
    func noteFailedSessionArchive(_ sessionID: String) {
        guard !failedArchiveSessionIDs.contains(sessionID) else {
            return
        }
        failedArchiveSessionIDs.append(sessionID)
        persist(failedArchiveSessionIDs, Key.failedArchiveSessionIDs)
    }

    func clearFailedSessionArchive(_ sessionID: String) {
        guard failedArchiveSessionIDs.contains(sessionID) else {
            return
        }
        failedArchiveSessionIDs.removeAll { $0 == sessionID }
        persist(failedArchiveSessionIDs, Key.failedArchiveSessionIDs)
    }

    /// 真删落定后的本地清账（0.50.30）：服务端会话已
    /// 回查确认不存在，按其 id 挂在本地的账一并清掉
    /// ——标题覆盖、服务端形态归档键、归档失败留痕，
    /// 不留残影（id 若日后重现也不许被旧账染指）。
    /// 第 90 条收尾随归档列迁入本店：标题覆盖仍归
    /// SideChatStore 持有，经 appState 清项
    func purgeServerSessionRecords(
        _ sessionID: String, appState: AppState
    ) {
        appState.sideChats.setTitleOverride(nil, for: sessionID)
        unarchive(serverSessionID: sessionID)
        clearFailedSessionArchive(sessionID)
    }

    // MARK: - 关联表（第 90 条收尾：持有迁入，同键）

    /// 点子→旁聊关联（0.48.0，§122）：采纳时建的旁聊
    /// 线程 id 按点子 id 落盘，「打开对话」回同一条；
    /// 线程被删后关联失效、点按时补建并改写本表
    private(set) var ideaThreadIDs: [String: String] = [:]
    /// 目标→旁聊绑定（§123 H1）：目标 id → 线程 id 串。
    /// 用户在目标里「安排一件事」时创建/复用并落盘，
    /// 委派任务的进展与完成回响落进这个线程（绑定模式
    /// 与点子采纳的 ideaThreadIDs 同形，§122）
    private(set) var goalThreadIDs: [String: String] = [:]
    /// 动态讨论待发信号（FA-1）：线程 id → 帖 id。
    /// 点「讨论」建旁聊时落盘；该线程第一条用户消息
    /// 发出后 ChatView 据此发一记 discuss 信号并销
    /// 账——信号只认首句（note 取首句自述偏好句），
    /// 漏发/永不发送的关联留着无副作用（下次该线程
    /// 首发仍是首句）
    private(set) var feedDiscussPostIDs: [String: String] = [:]

    func threadID(forIdeaID id: String) -> UUID? {
        ideaThreadIDs[id].flatMap { UUID(uuidString: $0) }
    }

    func linkThread(_ threadID: UUID, forIdeaID id: String) {
        ideaThreadIDs[id] = threadID.uuidString
        persist(ideaThreadIDs, Key.ideaThreadIDs)
    }

    /// 目标绑定的旁聊线程 id；未绑（还没在这个目标里
    /// 安排过事）为 nil
    func threadID(forGoalID goalID: String) -> UUID? {
        goalThreadIDs[goalID].flatMap(UUID.init(uuidString:))
    }

    func linkThread(_ threadID: UUID, forGoalID goalID: String) {
        goalThreadIDs[goalID] = threadID.uuidString
        persist(goalThreadIDs, Key.goalThreadIDs)
    }

    /// 讨论建聊时登记：线程的第一条用户消息要替这
    /// 篇帖发一记 discuss 信号
    func linkFeedDiscussThread(_ threadID: UUID, postID: String) {
        // 一帖一线程：同帖改挂新线程（旧线程已删后
        // 补建）时先摘其他线程的同帖关联，否则反查
        // 会捞回已删线程、discuss 每次都新建（去重
        // 失效、空会话堆积复发）
        for key in feedDiscussPostIDs
            .filter({ $0.value == postID }).map(\.key)
            where key != threadID.uuidString {
            feedDiscussPostIDs.removeValue(forKey: key)
        }
        feedDiscussPostIDs[threadID.uuidString] = postID
        persist(feedDiscussPostIDs, Key.feedDiscussPostIDs)
    }

    func feedDiscussPostID(forThreadID threadID: UUID) -> String? {
        feedDiscussPostIDs[threadID.uuidString]
    }

    /// 反查（§208 讨论去重）：这篇帖已有的讨论线程
    /// ——discuss() 先查本口，有则复用、不再堆空会话
    /// （与点子流「先查 link」同形）；关联在但线程
    /// 已删时由调用方校验存在性后决定补建
    func threadID(forFeedDiscussPostID postID: String) -> UUID? {
        feedDiscussPostIDs.first(where: {
            $0.value == postID
        }).flatMap { UUID(uuidString: $0.key) }
    }

    /// 信号发出即销账：一线程只报一次，note 只认
    /// 首句——销账先行于网络调用，失败不补发第二句
    func clearFeedDiscuss(forThreadID threadID: UUID) {
        guard feedDiscussPostIDs[threadID.uuidString] != nil else {
            return
        }
        feedDiscussPostIDs[threadID.uuidString] = nil
        persist(feedDiscussPostIDs, Key.feedDiscussPostIDs)
    }

    // MARK: - 读口

    /// 合并名单：账本段名单＋注入的本地线程现场重
    /// 演 join 与合并（合并/分类/投影全在 Core 纯函
    /// 数，本店只摘侧账输入）
    func records(
        appState: AppState, localThreads: [ChatThread]
    ) -> [SessionRecord] {
        SessionLedgerMerge.records(
            visible: visibleSessions,
            archived: archivedSessions,
            localThreads: localThreads.map(LedgerLocalThread.init),
            inputs: SessionLedgerMerge.Inputs(
                mainThreadID: mainThreadID,
                mainServerSessionID: mainServerSessionID,
                archivedKeys: archivedKeys,
                pendingDeletionIDs: deletions.queue.sessionIDs,
                firstUserMessages: appState.sessionTitles
                    .firstUserMessages
            )
        )
    }

    /// 存活集＋完整性（B-1 闸的接口级形态）
    func liveSet() -> (ids: Set<String>,
                       completeness: LedgerCompleteness) {
        (liveSessionIDs, liveCompleteness)
    }

    func drawerSideRows(
        appState: AppState, localThreads: [ChatThread]
    ) -> [SessionRecord] {
        LedgerProjection.drawerSideRows(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func managementVisible(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.managementVisible(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func managementArchived(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.managementArchived(
            records(appState: appState, localThreads: localThreads)
        )
    }

    func channelList(
        appState: AppState, localThreads: [ChatThread],
        channelID: String
    ) -> [ServerSession] {
        LedgerProjection.channelList(
            records(appState: appState, localThreads: localThreads),
            channelID: channelID
        )
    }

    func hubSessions(
        appState: AppState, localThreads: [ChatThread]
    ) -> [ServerSession] {
        LedgerProjection.hubSessions(
            records(appState: appState, localThreads: localThreads)
        )
    }

    // MARK: - 同步（唯一拉取者）

    /// 全量刷新（管理页 load 的收编）：两段拉全→合
    /// 并落位→完整时对账回收（B-1 闸：任一段不完整
    /// 跳过对账并留痕，宁可不清、不可误清）→主线兜
    /// 底单查→标题回落素材。§233 归档缓存回写已退
    /// 役（包二）：归档态直接读记录归档列（过回写
    /// 闸的绑定以服务端段为准、余者以本地键为准，
    /// archiveSource 如实分列），不再把服务端态反
    /// 向改写本地键。时序与旧 AllConversationsStore
    /// .load 逐拍一致：可见段拉成即落位（不被归档
    /// 段失败连坐）；任一段 throw 由调用方转人话错误
    func refresh(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async throws {
        let epochAtStart = listFreshnessEpoch
        let visibleFetch = try await Self
            .fetchAll(appState: appState, archived: "exclude")
        let visible = visibleFetch.sessions
        // §232：待删集不进展示与目录（服务端此刻仍
        // 有其行，不过滤会被重拉带回）；对账存活集
        // 用未过滤全集（待删会话在服务端尚存活，其
        // 墓碑线程不许被对账误清）
        let pendingDeletions = deletions.queue.sessionIDs
        visibleSessions = visible.filter {
            !pendingDeletions.contains($0.id)
        }
        hasLoaded = true
        // §370：可见段已按现值落位——新鲜度同拍落账
        // （代次未变才落，横跨写事件不冒充新鲜）；此
        // 后归档段/对账若摘行失效，保守作废、下次读
        // 触发真拉
        if epochAtStart == listFreshnessEpoch {
            listFreshness.stamp(
                configKey: appState.config?.baseString,
                now: Date()
            )
        }
        let archivedFetch = try await Self
            .fetchAll(appState: appState, archived: "only")
        let archived = archivedFetch.sessions
        archivedSessions = archived.filter {
            !pendingDeletions.contains($0.id)
        }
        // §223 名单对账＋B-1 防护闸（2026-11-14）
        if visibleFetch.isComplete && archivedFetch.isComplete {
            liveSessionIDs = Set(visible.map(\.id))
                .union(archived.map(\.id))
            liveCompleteness = .complete
            DeletedSessionCloseout.reconcileLocalThreads(
                threads: localThreads,
                liveSessionIDs: liveSessionIDs,
                appState: appState, modelContext: modelContext
            )
        } else {
            liveCompleteness = .incomplete(
                reason: "可见段："
                    + (visibleFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "；归档段："
                    + (archivedFetch.incompleteReason?
                        .traceLabel ?? "完整")
            )
            ChatDiagTrace.record(
                "全部对话名单对账跳过：名单不完整"
                    + "（可见段："
                    + (visibleFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "；归档段："
                    + (archivedFetch.incompleteReason?
                        .traceLabel ?? "完整")
                    + "），本地线程本轮不动"
            )
        }
        if let mainID = mainServerSessionID,
           !visible.contains(where: { $0.id == mainID }),
           !archived.contains(where: { $0.id == mainID }) {
            mainFallback = try? await appState.performAdmin {
                client, config in
                try await client.serverSession(
                    config: config, id: mainID
                )
            }
        } else {
            mainFallback = nil
        }
        hasLoadedFull = true
        // 标题回落素材：无服务端标题者才拉消息派生
        await appState.sessionTitles.ensureTitles(
            for: visible + archived, appState: appState,
            budget: 12
        )
        // 存量迁移挂载点（第 90 条收尾）：归档段同步
        // 完成即触发点——触发从管理页首开迁到此处，
        // 此后每次全量刷新完成都会顺带跑一次（计划
        // 为空即无事；失败项留痕＋本地值保留，下轮
        // 刷新再试）
        await runMigrationIfNeeded(
            appState: appState, localThreads: localThreads,
            modelContext: modelContext
        )
    }

    /// 可见段刷新（抽屉/频道页触发点的收编）：旧抽
    /// 屉 loadDrawerData 每开必拉第一页喂 source/标
    /// 题映射；本路改拉可见段全量落账本（现存规模
    /// 下与一页同价），source/标题改读记录列。只喂
    /// 显示、不驱动任何删除——名单不完整也照常落
    /// 位（防护闸只拦以名单为存活集的删除/回收）。
    /// 标题回落素材补拉同在本路（包二：名单面的标
    /// 题补拉只许在账本内发生）。返回是否拉到名单
    /// （频道页据此呈现失败态）
    @discardableResult
    func refreshVisible(
        appState: AppState, localThreads: [ChatThread],
        now: Date = Date()
    ) async -> Bool {
        guard !isRefreshingVisible else { return false }
        isRefreshingVisible = true
        defer { isRefreshingVisible = false }
        let epochAtStart = listFreshnessEpoch
        guard let result = try? await Self
            .fetchAll(appState: appState, archived: "exclude")
        else { return false }
        let pending = deletions.queue.sessionIDs
        visibleSessions = result.sessions.filter {
            !pending.contains($0.id)
        }
        hasLoaded = true
        await appState.sessionTitles.ensureTitles(
            for: result.sessions, appState: appState,
            budget: 12
        )
        // §370：名单＋标题补拉整轮成功才落账新鲜度
        // （失败不落账、不拿旧时刻冒充）；拉取横跨写
        // 事件（代次已变）不落账——下一读触发照旧真
        // 拉对账
        if epochAtStart == listFreshnessEpoch {
            listFreshness.stamp(
                configKey: appState.config?.baseString,
                now: now
            )
        }
        return true
    }

    /// 读触发入口（§370 新鲜度门）：抽屉落定/回前
    /// 台/预挂载三路先过本门——TTL 内且配置键没变
    /// 直接用已载名单、零请求；首载/过期/被写事件
    /// 失效/换服务器才走 refreshVisible 全量。强
    /// 制路（drawerRefreshTick 令牌、行操作
    /// onChanged、频道页）不经此门、直调
    /// refreshVisible（成功同样落账）
    func refreshVisibleIfNeeded(
        appState: AppState, localThreads: [ChatThread],
        now: Date = Date()
    ) async {
        guard !listFreshness.isFresh(
            configKey: appState.config?.baseString, now: now
        ) else { return }
        await refreshVisible(
            appState: appState, localThreads: localThreads,
            now: now
        )
    }

    /// 冷缓存补拉（目录壳 refreshIfCold 的收编）：
    /// 已热或在飞直接返回；失败不置 hasLoaded（下次
    /// 触发重试）、不抛错
    func refreshVisibleIfCold(
        appState: AppState, localThreads: [ChatThread]
    ) async {
        guard !hasLoaded, !isRefreshingVisible else { return }
        await refreshVisible(
            appState: appState, localThreads: localThreads
        )
    }

    /// 收养判定名单（ChatView adoptOnTitleConflict
    /// 的收编）：账本两段齐全时读账本名单（含已归
    /// 档段——占名者可能已归档）；未齐全回落现拉
    /// include 全量。只用于候选检索、不驱动删除，
    /// 不需完整性闸（不完整至多漏候选、方向保守）；
    /// 拉不到返回 nil（调用方照抛原错误、不收养）
    func adoptionSessions(
        appState: AppState
    ) async -> [ServerSession]? {
        if hasLoadedFull {
            var seen = Set<String>()
            return (visibleSessions + archivedSessions).filter {
                seen.insert($0.id).inserted
            }
        }
        return try? await Self.fetchAll(
            appState: appState, archived: "include"
        ).sessions
    }

    // MARK: - 名单写回面（旧 Catalog.publish/remove 语义逐字）

    /// 写回（旧 publish）：调用方已付分页代价且已过
    /// 待删过滤，同份可见集落本店
    func publishVisible(_ visible: [ServerSession]) {
        visibleSessions = visible
        hasLoaded = true
    }

    /// 摘行（旧 Catalog.remove＋管理页 removeLocal
    /// 的合一）：服务端会话已确认删除/不存在，两段
    /// 名单与主线兜底同拍摘除，不等下一轮全量拉取
    func removeSession(sessionID: String) {
        // §370：删除落定即名单写事件——新鲜度作废，
        // 下一次读触发必真拉对账（摘行本身仍即时）
        invalidateListFreshness()
        visibleSessions.removeAll { $0.id == sessionID }
        archivedSessions.removeAll { $0.id == sessionID }
        if mainFallback?.id == sessionID { mainFallback = nil }
    }

    // MARK: - 标题读点（包二：冲突处理归账本一处）

    /// 服务端行标题的唯一读点：存量本地覆盖（迁移
    /// 未排空的遗留改名）优先，其后统一管线（服务
    /// 端标题＞派生＞人话名）。管理页/频道页行标题
    /// 都经本口，不许各面再直读覆盖表与解析器
    func title(
        for session: ServerSession, appState: AppState
    ) -> String {
        appState.sideChats.titleOverrides[session.id]
            ?? appState.sessionTitles.title(for: session)
    }

    // MARK: - 删除落定收口（包二：收口归账本门面）

    /// 单条落定收口（转发 §223 共享收口实现）：服
    /// 务端删除已回查落定后清侧账＋账本摘行＋删绑
    /// 定线程。删除引擎的落定段与名单对账都经账本
    /// 内部路径至此，外部面不许再直调收口件
    func closeoutDeletedSession(
        sessionID: String, appState: AppState,
        threads: [ChatThread], modelContext: ModelContext
    ) {
        DeletedSessionCloseout.apply(
            sessionID: sessionID, appState: appState,
            threads: threads, modelContext: modelContext
        )
    }

    /// 点开已消失会话的防御收口（转发 §223）：清侧
    /// 账＋账本摘行，行即消失
    func noteOpenedSessionMissing(
        sessionID: String, appState: AppState
    ) {
        DeletedSessionCloseout.handleOpenedSessionMissing(
            sessionID: sessionID, appState: appState
        )
    }

    // MARK: - 存量迁移（第 90 条收尾：挂载点迁入）

    /// 迁移失败留痕（逐项人话行）：管理页迁移区直
    /// 读本列呈现；成功落定后由下一轮迁移结果覆盖
    private(set) var migrationFailures: [String] = []
    /// 迁移在飞标记：迁移尾步的重拉（refresh）会再
    /// 到触发点，靠本标记防自触发重入
    private var isRunningMigration = false

    /// 归档段同步完成事件的挂载口（refresh 尾步调
    /// 用）：每次全量刷新完成都顺带执行一次待迁计
    /// 划；迁移本体自带在飞守卫防自触发重入
    private func runMigrationIfNeeded(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async {
        await runMigration(
            appState: appState, localThreads: localThreads,
            modelContext: modelContext
        )
    }

    /// 存量迁移执行（自管理页 AllConversationsStore
    /// 迁入，语义逐字）：计划走 Core 纯函数
    /// （SessionMigration.plan），逐项经动作层回写＋
    /// 回读对账；折叠后成功项清本地（覆盖表删项、
    /// 归档键删项），失败项逐项留痕＋本地值保留。
    /// 迁移后名单重拉（归档项的服务端状态已变）；
    /// 尾步重拉的 refresh 会再到挂载点，靠在飞守
    /// 卫挡下（失败项的再试留给下一轮外部刷新，不
    /// 在本轮内自旋）
    func runMigration(
        appState: AppState, localThreads: [ChatThread],
        modelContext: ModelContext
    ) async {
        guard !isRunningMigration else { return }
        isRunningMigration = true
        defer { isRunningMigration = false }
        let sideChats = appState.sideChats
        let overrides = sideChats.titleOverrides
        let keys = archivedKeys
        let plan = SessionMigration.plan(
            titleOverrides: overrides, archivedKeys: keys
        )
        guard !plan.isEmpty else { return }
        var failureReasons: [SessionMigration.Item: String] = [:]
        for item in plan {
            let outcome: ServerSessionActions.Outcome
            switch item.kind {
            case .rename(let title):
                outcome = await ServerSessionActions.rename(
                    appState: appState, id: item.sessionID, title: title
                )
            case .archive:
                outcome = await ServerSessionActions.setArchived(
                    appState: appState, id: item.sessionID, archived: true
                )
            }
            if case .failed(let reason) = outcome {
                failureReasons[item] = reason
            }
        }
        let outcome = SessionMigration.fold(
            plan: plan, failureReasons: failureReasons,
            titleOverrides: overrides, archivedKeys: keys
        )
        // 退役成功项：本地只删「计划内且已落定」的键
        for id in overrides.keys
        where outcome.remainingTitleOverrides[id] == nil {
            sideChats.setTitleOverride(nil, for: id)
        }
        for key in keys
        where !outcome.remainingArchivedKeys.contains(key)
            && key.hasPrefix("server:") {
            unarchive(
                serverSessionID: String(key.dropFirst("server:".count))
            )
        }
        migrationFailures = outcome.failures.map { failure in
            "「\(failure.item.sessionID)」\(failure.item.actionLabel)没改成：\(failure.reason)"
        }
        try? await refresh(
            appState: appState, localThreads: localThreads,
            modelContext: modelContext
        )
    }

    // MARK: - 分页装配核（B-07：自转发壳迁入）

    /// 名单不完整的判定原因（B-1 防护，2026-11-14
    /// 同类横扫定案）：三类信号任一出现即判不完整
    enum IncompleteReason: Equatable {
        /// 10 页上限走满仍未见名单尽头——旧形态在
        /// 此静默截断，尾部整段无声消失
        case pageCapReached
        /// 服务端报的总数与实拉唯一行数对不上（含
        /// 拉取途中总数漂移：多页报数互不一致）
        case totalMismatch(reported: Int, fetched: Int)
        /// 页内/跨页出现重复行——offset 位移的指纹
        /// （拉取途中名单增删）：有重必有漏
        case duplicateRows(count: Int)

        /// 留痕用人话短句（不带状态码原文）
        var traceLabel: String {
            switch self {
            case .pageCapReached:
                return "分页上限走满、名单未见尽头"
            case .totalMismatch(let reported, let fetched):
                return "总数对不上（服务端报 \(reported)、实拉 \(fetched)）"
            case .duplicateRows(let count):
                return "分页出现重复行 \(count) 条"
            }
        }
    }

    /// 拉全结果：名单本体＋完整性判定。完整性是防
    /// 护闸的唯一凭据——以名单为存活集做删除/回收
    /// 的消费点必须先查 isComplete，不完整即跳过动
    /// 作并留痕（宁可不清、不可误清）；只喂显示的
    /// 消费点可直接取 sessions
    struct FetchResult {
        var sessions: [ServerSession]
        var incompleteReason: IncompleteReason?
        var isComplete: Bool { incompleteReason == nil }
    }

    /// 分页拉全：limit 100 逐页至不足一页或达 total，
    /// 上限 10 页（防服务端分页异常时无界拉取）——
    /// 本函数是全 App 唯一实现，两处不许再各抄一份。
    /// B-1 防护（2026-11-14）：旧形态 append 累加、
    /// 无去重、无对账、上限处静默截断，下游对账以
    /// 此名单为存活集清本地线程——截断/漏行会被误
    /// 判「服务端已删」造成数据丢失。本形态：装配
    /// 时去重（保首现序）、全程对账，任一不完整信
    /// 号（上限走满/总数对不上或漂移/出现重行）即
    /// 在结果上打标并留痕，删除向消费点据标跳过
    static func fetchAll(
        appState: AppState, archived: String
    ) async throws -> FetchResult {
        let result = try await appState.performAdmin {
            client, config in
            try await Self.fetchAllPages { offset in
                try await client.serverSessionsPage(
                    config: config, limit: 100,
                    offset: offset, archived: archived
                )
            }
        }
        if let reason = result.incompleteReason {
            ChatDiagTrace.record(
                "会话名单不完整（archived=\(archived)）："
                    + reason.traceLabel
                    + "——以名单为存活集的删除/回收本轮跳过"
            )
        }
        return result
    }

    /// 分页装配核（页取口注入，单测以脚本页直驱）：
    /// 与 fetchAll 同一实现，不许另抄一份。offset 按
    /// 原始页行数推进（与服务端分页口径一致）；唯
    /// 一行集保首现序去重
    static func fetchAllPages(
        fetchPage: (Int) async throws -> SessionsPage
    ) async throws -> FetchResult {
        var all: [ServerSession] = []
        var seen = Set<String>()
        var duplicateCount = 0
        var reportedTotals = Set<Int>()
        var lastReportedTotal: Int?
        var offset = 0
        var ranOutOfPages = true
        for _ in 0..<10 {
            let page = try await fetchPage(offset)
            if let total = page.total {
                reportedTotals.insert(total)
                lastReportedTotal = total
            }
            for session in page.sessions {
                if seen.insert(session.id).inserted {
                    all.append(session)
                } else {
                    duplicateCount += 1
                }
            }
            if page.sessions.count < 100 {
                ranOutOfPages = false
                break
            }
            if let total = page.total, all.count >= total {
                ranOutOfPages = false
                break
            }
            offset += 100
        }
        let reason: IncompleteReason?
        if duplicateCount > 0 {
            reason = .duplicateRows(count: duplicateCount)
        } else if reportedTotals.count > 1 {
            reason = .totalMismatch(
                reported: lastReportedTotal ?? all.count,
                fetched: all.count
            )
        } else if let total = lastReportedTotal, total != all.count {
            reason = .totalMismatch(
                reported: total, fetched: all.count
            )
        } else if ranOutOfPages {
            reason = .pageCapReached
        } else {
            reason = nil
        }
        return FetchResult(
            sessions: all, incompleteReason: reason
        )
    }
}

/// ChatThread → 账本快照（合并注入形）：逐字段摘
/// 出，账本与 Core 合并函数不直碰 SwiftData 本体
extension LedgerLocalThread {
    init(_ thread: ChatThread) {
        self.init(
            id: thread.id, title: thread.title,
            titleIsManual: thread.titleIsManual,
            serverSessionID: thread.serverSessionID,
            isPendingDeletion: thread.isPendingDeletion,
            isPinned: thread.isPinned,
            updatedAt: thread.updatedAt,
            createdAt: thread.createdAt,
            linkFailureCount: thread.linkFailureCount,
            linkLastError: thread.linkLastError
        )
    }
}
