import Foundation
import OneDayCore
import os

/// 滚动锚（轻保活 M1）：切走一条线程时记下的可见位置——
/// 在底部则记 atBottom，否则记首个可见条目 id，切回时恢复
struct SideChatScrollAnchor: Codable, Equatable {
    var entryID: UUID?
    var atBottom: Bool
}

/// 旁聊呈现保活的持久状态（0.7.0）：服务端标题覆盖
/// 表、上次停留线程、草稿与滚动锚，全部 UserDefaults
/// 落盘。判定逻辑在 Core（SideChat.swift），本类只管
/// 存取。演示模式走纯内存（persisted=false），不污染
/// 真实档案。
/// 第 90 条收尾（2026-11-16）：主线钦定、归档键（含
/// 失败留痕）与三张关联表（点子/目标/动态讨论）的持
/// 有已迁 SessionLedger（同键读写、持有者换人）——
/// 本店自此只管呈现保活与标题覆盖，不再记会话名单
/// 本体的账（施工图 §2.7 划界：草稿/滚动锚/last-
/// ThreadID 不并入账本）
@MainActor
@Observable
/// §416 新鲜度普查豁免：本地旁聊状态店（SwiftData），无远端新鲜度问题（判定表见 DESIGN §416）
final class SideChatStore {
    /// 主线固定标题（不被首条消息派生覆盖，M3 口径；
    /// 0.18.0 命名统一：旧称「主聊」就此退役，全仓
    /// 只用「主线」——Muse 定义里它是唯一指挥席）
    static let mainTitle = L10n.string("主线")

    /// 上次停留线程（0.30.0）：聊天页签的落点记忆——
    /// 冷启/视图重建时恢复上次对话（Muse 模型：页签
    /// 不与主线绑定，点页签回上次对话）。唯一写入点
    /// ＝ChatView 的 currentThreadID 变更回调（置空即
    /// 清记录），落点解析在 Core ChatLandingResolution
    private(set) var lastThreadID: UUID?
    private(set) var titleOverrides: [String: String] = [:]
    private var drafts: [String: String] = [:]
    private var scrollAnchors: [String: SideChatScrollAnchor] = [:]

    private let defaults: UserDefaults?

    private enum Key {
        static let lastThreadID = "sideChats.lastThreadID"
        static let titleOverrides = "sideChats.titleOverrides"
        static let drafts = "sideChats.drafts"
        static let scrollAnchors = "sideChats.scrollAnchors"
    }

    convenience init(persisted: Bool) {
        self.init(defaults: persisted ? .standard : nil)
    }

    /// 指定初始化器（§396 钉测注入口）：以给定
    /// UserDefaults 建店，落盘/解码语义与 persisted
    /// =true 逐字同——草稿跨实例读回（重启语义）的
    /// 把守测走本口、用独立 suite 不污染真实档案；
    /// 传 nil 即演示模式纯内存
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        guard let defaults else { return }
        if let raw = defaults.string(forKey: Key.lastThreadID) {
            lastThreadID = UUID(uuidString: raw)
        }
        titleOverrides = Self.decode([String: String].self, defaults, Key.titleOverrides) ?? [:]
        drafts = Self.decode([String: String].self, defaults, Key.drafts) ?? [:]
        scrollAnchors = Self.decode([String: SideChatScrollAnchor].self, defaults, Key.scrollAnchors) ?? [:]
    }

    /// 解码（§332 留痕级收口）：键缺席回 nil 不算
    /// 失败；在册解不出＝损坏，落诊断痕点名，不再
    /// 静默回空。本店三键（标题覆盖/草稿/滚动锚）
    /// 非身份状态，损坏代价限于本键语义——只留痕，
    /// 不进 SessionLedger 的明示＋重认领自愈链
    private static func decode<T: Decodable>(_ type: T.Type, _ defaults: UserDefaults, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            ChatDiagTrace.record(
                "本地状态读取失败：\(key) 解码失败，已按缺失处理"
            )
            return nil
        }
    }

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        guard let defaults else { return }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            // 编码失败留痕（§332）：跳过本次落盘、
            // 既有值保留，不许把 nil 写回去删值
            ChatDiagTrace.record(
                "本地状态写入失败：\(key) 编码失败，本次落盘已跳过"
            )
        }
    }

    // MARK: - 落点记忆（0.30.0）

    /// 记/清上次停留线程：传 nil 即清记录（当前线程
    /// 被删时由 ChatView 的变更回调统一落到这里），
    /// 下次落点按「记录失效回主线」解析，不留死键
    func setLastThreadID(_ id: UUID?) {
        lastThreadID = id
        if let id {
            defaults?.set(id.uuidString, forKey: Key.lastThreadID)
        } else {
            defaults?.removeObject(forKey: Key.lastThreadID)
        }
    }

    // MARK: - 标题覆盖（M3 本地绕行，0.18.0 起存量遗
    // 留：改名已改走服务端 PATCH 直达，本表只剩迁移
    // 输入——管理页首开时逐条回写服务端、对账落定
    // 后逐项清除；新改名不再写入本表）

    func setTitleOverride(_ title: String?, for serverSessionID: String) {
        if let title, !title.isEmpty {
            titleOverrides[serverSessionID] = title
        } else {
            titleOverrides[serverSessionID] = nil
        }
        persist(titleOverrides, Key.titleOverrides)
    }

    // MARK: - 轻保活（M1：草稿与滚动位置，进程内语义＋本地落盘）

    func draft(for threadID: UUID) -> String? {
        drafts[threadID.uuidString]
    }

    /// 草稿写入唯一口。**隔离铁律（§208 立、§219
    /// 全仓收口）**：本账只许收用户亲笔——调用方只
    /// 许是 ChatView 的切走回存、删线程清理与发送
    /// 后清键（三处同出亲笔生命周期，全仓 grep 对
    /// 账归零的基线）。系统注入（动态讨论／点子开
    /// 聊／文件重发之类要把上下文带进对话的）一律
    /// 走引用（按线程寻址待发状态）通道，不许经本
    /// 口进账：本账无来源标记，注入文进账即与亲笔
    /// 同形、被保活永久保护（动态讨论预填的病根，
    /// §208 堵讨论、§219 堵点子与文件两处后门）
    func setDraft(_ text: String, for threadID: UUID) {
        if text.isEmpty {
            drafts[threadID.uuidString] = nil
        } else {
            drafts[threadID.uuidString] = text
        }
        persist(drafts, Key.drafts)
    }

    // MARK: - 存量预填清扫（§208 包 3）

    private static let purgeLog = Logger(
        subsystem: "site.didichou.oneday",
        category: "feed-discuss-purge"
    )

    /// 一次性清扫 §208 前落盘的旧讨论预填草稿：只
    /// 扫有 FA-1 关联的线程，拿原帖（标题＋正文）
    /// 经 FeedDiscussDraftCleanup 逐字再生比对——
    /// 与机器输出逐字相等才清，用户改过一字即不
    /// 相等、不动；无关联线程的草稿、原帖已不在
    /// 本批名单（无从再生核验）的草稿一律不碰。
    /// 只清草稿文本，同帖线程本体保留（用户数据）。
    /// 调用点唯一：动态名单每次拉取成功后（Feed-
    /// Store.load）——逐字再生须拿原帖，这是最早
    /// 能严格核验的时点；清扫幂等（清后账上无此
    /// 草稿、复跑恒 0）。留痕走 os 日志计数，不上
    /// 屏打扰。关联表自第 90 条收尾归 SessionLedger
    /// 持有——本函数只管草稿，关联集由调用方注入
    /// （links＝线程 id 串→帖 id）
    @discardableResult
    func purgeLegacyFeedDiscussDrafts(
        posts: [BridgeFeedPost], links: [String: String]
    ) -> Int {
        guard !posts.isEmpty else { return 0 }
        let byID = Dictionary(
            uniqueKeysWithValues: posts.map { ($0.id, $0) }
        )
        var cleared = 0
        for (threadKey, postID) in links {
            guard let post = byID[postID],
                  let draft = drafts[threadKey] else { continue }
            if FeedDiscussDraftCleanup.isMachinePrefill(
                draft, title: post.title, body: post.body
            ) {
                drafts[threadKey] = nil
                cleared += 1
            }
        }
        if cleared > 0 {
            persist(drafts, Key.drafts)
        }
        Self.purgeLog.info(
            "存量预填清扫：扫 \(links.count) 条关联、清 \(cleared) 条"
        )
        return cleared
    }

    private static let ideaPurgeLog = Logger(
        subsystem: "site.didichou.oneday",
        category: "idea-prefill-purge"
    )

    /// 一次性清扫 §219 前落盘的旧点子预填草稿：只
    /// 扫有点子关联的线程，拿原点子经 IdeaPrefill-
    /// DraftCleanup 逐字再生比对——与机器输出逐字
    /// 相等才清，用户改过一字即不相等、不动；无关
    /// 联线程的草稿、原点子已不在本批名单（无从再
    /// 生核验）的草稿一律不碰。只清草稿文本，点子
    /// 线程本体与关联账保留。调用点唯一：点子名单
    /// 每次拉取成功后（IdeasStore.load）——与动态
    /// 清扫同式；清扫幂等。文件重发的旧预填无任何
    /// 关联账（重发从不登记线程↔文件对应），无从
    /// 严格核验、不在本清扫内（§219 报告明示）。
    /// 关联表自第 90 条收尾归 SessionLedger 持有，
    /// 由调用方注入（links＝点子 id→线程 id 串）
    @discardableResult
    func purgeLegacyIdeaDrafts(
        ideas: [BridgeIdea], links: [String: String]
    ) -> Int {
        guard !ideas.isEmpty else { return 0 }
        let byID = Dictionary(
            uniqueKeysWithValues: ideas.map { ($0.id, $0) }
        )
        var cleared = 0
        for (ideaID, threadKey) in links {
            guard let idea = byID[ideaID],
                  let draft = drafts[threadKey] else { continue }
            if IdeaPrefillDraftCleanup.isMachinePrefill(
                draft, idea: idea
            ) {
                drafts[threadKey] = nil
                cleared += 1
            }
        }
        if cleared > 0 {
            persist(drafts, Key.drafts)
        }
        Self.ideaPurgeLog.info(
            "点子存量预填清扫：扫 \(links.count) 条关联、清 \(cleared) 条"
        )
        return cleared
    }

    func scrollAnchor(for threadID: UUID) -> SideChatScrollAnchor? {
        scrollAnchors[threadID.uuidString]
    }

    func setScrollAnchor(_ anchor: SideChatScrollAnchor?, for threadID: UUID) {
        scrollAnchors[threadID.uuidString] = anchor
        persist(scrollAnchors, Key.scrollAnchors)
    }
}
