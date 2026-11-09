import Foundation
import OneDayCore

/// 滚动锚（轻保活 M1）：切走一条线程时记下的可见位置——
/// 在底部则记 atBottom，否则记首个可见条目 id，切回时恢复
struct SideChatScrollAnchor: Codable, Equatable {
    var entryID: UUID?
    var atBottom: Bool
}

/// 旁聊语义的持久状态（0.7.0）：主线钦定 id、归档集合、
/// 服务端标题覆盖表、草稿与滚动锚，全部 UserDefaults 落盘。
/// 判定逻辑在 Core（SideChat.swift），本类只管存取。
/// 演示模式走纯内存（persisted=false），不污染真实档案。
@MainActor
@Observable
final class SideChatStore {
    /// 主线固定标题（不被首条消息派生覆盖，M3 口径；
    /// 0.18.0 命名统一：旧称「主聊」就此退役，全仓
    /// 只用「主线」——Muse 定义里它是唯一指挥席）
    static let mainTitle = "主线"

    private(set) var mainThreadID: UUID?
    private(set) var mainServerSessionID: String?
    private(set) var mainServerConfirmed = false
    private(set) var archivedKeys: Set<String> = []
    /// 删除归档失败留痕（0.21.0）：本地线程已删、关
    /// 联服务端会话归档 PATCH 失败待对账的会话 id
    /// 集（口径见 noteFailedSessionArchive）
    private(set) var failedArchiveSessionIDs: [String] = []
    private(set) var titleOverrides: [String: String] = [:]
    private var drafts: [String: String] = [:]
    private var scrollAnchors: [String: SideChatScrollAnchor] = [:]

    private let defaults: UserDefaults?

    private enum Key {
        static let mainThreadID = "sideChats.mainThreadID"
        static let mainServerSessionID = "sideChats.mainServerSessionID"
        static let mainServerConfirmed = "sideChats.mainServerConfirmed"
        static let archivedKeys = "sideChats.archivedKeys"
        static let failedArchiveSessionIDs =
            "sideChats.failedArchiveSessionIDs"
        static let titleOverrides = "sideChats.titleOverrides"
        static let drafts = "sideChats.drafts"
        static let scrollAnchors = "sideChats.scrollAnchors"
    }

    init(persisted: Bool) {
        defaults = persisted ? .standard : nil
        guard let defaults else { return }
        if let raw = defaults.string(forKey: Key.mainThreadID) {
            mainThreadID = UUID(uuidString: raw)
        }
        mainServerSessionID = defaults.string(forKey: Key.mainServerSessionID)
        mainServerConfirmed = defaults.bool(forKey: Key.mainServerConfirmed)
        archivedKeys = Set(defaults.stringArray(forKey: Key.archivedKeys) ?? [])
        failedArchiveSessionIDs = Self.decode(
            [String].self, defaults, Key.failedArchiveSessionIDs
        ) ?? []
        titleOverrides = Self.decode([String: String].self, defaults, Key.titleOverrides) ?? [:]
        drafts = Self.decode([String: String].self, defaults, Key.drafts) ?? [:]
        scrollAnchors = Self.decode([String: SideChatScrollAnchor].self, defaults, Key.scrollAnchors) ?? [:]
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ defaults: UserDefaults, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persist<T: Encodable>(_ value: T, _ key: String) {
        guard let defaults else { return }
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    // MARK: - 主线钦定

    func designateMainThread(_ id: UUID) {
        mainThreadID = id
        defaults?.set(id.uuidString, forKey: Key.mainThreadID)
    }

    /// 主线的服务端会话 id：首次由 App 生成并持久化，
    /// 之后以服务端回执为准（服务端若改派 id 以回执改存）
    func ensureMainServerSessionID() -> String {
        if let mainServerSessionID { return mainServerSessionID }
        let generated = "oneday-main-\(UUID().uuidString.lowercased())"
        setMainServerSessionID(generated)
        return generated
    }

    func setMainServerSessionID(_ id: String) {
        mainServerSessionID = id
        defaults?.set(id, forKey: Key.mainServerSessionID)
    }

    func confirmMainServer() {
        mainServerConfirmed = true
        defaults?.set(true, forKey: Key.mainServerConfirmed)
    }

    // MARK: - 归档（M2）

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

    // MARK: - 删除归档留痕（0.21.0）

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

    func setDraft(_ text: String, for threadID: UUID) {
        if text.isEmpty {
            drafts[threadID.uuidString] = nil
        } else {
            drafts[threadID.uuidString] = text
        }
        persist(drafts, Key.drafts)
    }

    func scrollAnchor(for threadID: UUID) -> SideChatScrollAnchor? {
        scrollAnchors[threadID.uuidString]
    }

    func setScrollAnchor(_ anchor: SideChatScrollAnchor?, for threadID: UUID) {
        scrollAnchors[threadID.uuidString] = anchor
        persist(scrollAnchors, Key.scrollAnchors)
    }
}
