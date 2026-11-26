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
    var values: [String: String] = [:]

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
    let defaults: UserDefaults?
    /// 身份键存储（§330）：生产＝Keychain、演示＝内
    /// 存；UserDefaults 旧键是双轨镜像（读出口径见
    /// loadPersistedState，见 IdentityValueStore 注）
    let identityStore: IdentityValueStore
    /// 解码失败收集（§332）：loadPersistedState 期
    /// 间在册却解不出的键名落此（键缺席不算失败）；
    /// 读入收尾由 finalizeStateReadFailures 统一处
    /// 置（落痕＋明示＋自愈标记），不在解码点散处理
    var stateReadFailureKeys: [String] = []

    enum Key {
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
    func loadPersistedState() {
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
    func decode<T: Decodable>(
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
    func finalizeStateReadFailures() {
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

    func persist<T: Encodable>(_ value: T, _ key: String) {
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
    static func identityBool(
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
    static func migrateIdentityKeys(
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
    var visibleSessions: [ServerSession] = []
    /// 已归档段展示名单（archived=only 拉全、待删集
    /// 已过滤——旧 AllConversationsStore.archived-
    /// Sessions 的收编）
    var archivedSessions: [ServerSession] = []
    /// 可见段是否已有一轮全量结果（冷/热唯一判定：
    /// 拉到空集也是结果，不许每开一次抽屉重拉全量）
    var hasLoaded = false
    /// 两段全量刷新是否完成过（收养判定读账本名单
    /// 的凭据：未完成时收养路回落现拉 include）
    var hasLoadedFull = false
    /// 主线行兜底：两段都没拉到钦定 id 时的单查结果
    /// （旧 AllConversationsStore.mainFallback 收编）
    var mainFallback: ServerSession?
    /// 最近一轮全量刷新的存活集＋完整性（refresh 内
    /// 以未过滤两段构造；不完整时 completeness 带原
    /// 因、ids 只作留痕呈现、不许喂删除判定）
    var liveSessionIDs: Set<String> = []
    var liveCompleteness: LedgerCompleteness =
        .incomplete(reason: "尚未拉取")
    /// 可见段刷新在飞标记（多路触发合并成一轮）
    var isRefreshingVisible = false
    /// 可见段新鲜度门（§370，缓存 C3）：名单类标准
    /// 档 60s（§367.3 定档，与三店同口径）——落定/
    /// 回前台/预挂载三路读触发先过本门，新鲜直接用
    /// 已载名单、零请求；强制路（刷新令牌/行操作回
    /// 读）不经门、成功同样落账
    var listFreshness = FreshnessGate(
        ttl: FreshnessGate.standardListTTL
    )
    /// 名单失效代次（§370）：写事件落定即 invalidate
    /// 自增；刷新起手记代次、落账时对账——代次变了
    /// 说明拉取横跨一次写事件，本轮结果不许落账冒
    /// 充新鲜（与 C2 epoch 同式）
    var listFreshnessEpoch = 0

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


    // MARK: - 扩展域共享状态（由各扩展文件读写）

    var mainThreadID: UUID?
    var mainServerSessionID: String?
    var mainServerConfirmed = false
    var mainServerSeeded = false
    var mainLinkLastError: String?
    var mainClaimRecord: MainlineClaimRecord?
    var localStateReadFailureNote: String?
    var stateReadFailurePendingRediscovery = false
    var mainSyncStatus: MainSyncStatus?
    var archivedKeys: Set<String> = []
    var failedArchiveSessionIDs: [String] = []
    var ideaThreadIDs: [String: String] = [:]
    var goalThreadIDs: [String: String] = [:]
    var feedDiscussPostIDs: [String: String] = [:]
    var migrationFailures: [String] = []
    var isRunningMigration = false
}
