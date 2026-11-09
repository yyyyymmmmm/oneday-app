import Foundation

/// 旁聊语义（0.7.0，规格＝sidechat-research-20261109.md §6 三档草案）：
/// 主线钦定、旁聊分区、本地归档与回告入线的纯判定逻辑，
/// 与视图/存储层分离、单测把守。持久化在 App 层 SideChatStore。
///
/// 语义基线（一处定清，别处引用）：
/// - 主线只有一条：本地线程以 UUID 钦定，服务端以一条
///   App 指定 id 的会话承载；冷启永远先落主线。
/// - 主线不可归档不可删（UI 层约束）；旁聊可本地归档，
///   归档只改名单可见性、不删数据，服务端会话本体不动。
/// - 回告卡是呈现层拼装：只进主线聊天页，绝不写入
///   Hermes 会话（D4 红线）。

public enum SideChatZone: String, Equatable, Sendable {
    case main
    case side
}

/// 分区归类：本地线程与服务端会话各按钦定 id 判定
public enum SideChatClassifier {
    public static func zone(localThreadID: UUID, mainThreadID: UUID?) -> SideChatZone {
        guard let mainThreadID else { return .side }
        return localThreadID == mainThreadID ? .main : .side
    }

    /// 主线的服务端会话不进旁聊名单（它就是主线本体）
    public static func zone(serverSessionID: String, mainServerSessionID: String?) -> SideChatZone {
        guard let mainServerSessionID, !mainServerSessionID.isEmpty else { return .side }
        return serverSessionID == mainServerSessionID ? .main : .side
    }
}

/// 主线钦定解析（M2）：存量 id 在名单内沿用，不在则新建；
/// 服务端承载未确认过就走「先查后建」，确认过不再打扰服务端
public enum MainThreadDesignation {
    public enum LocalResolution: Equatable, Sendable {
        case existing(UUID)
        case needsCreation
    }

    public enum ServerEnsure: Equatable, Sendable {
        /// 已确认在服务端存在，跳过
        case skip
        /// GET 查存，不在则 POST 建（带 App 指定 id 与 title）
        case verifyOrCreate
    }

    public static func resolve(storedID: UUID?, existingIDs: some Collection<UUID>) -> LocalResolution {
        guard let storedID, existingIDs.contains(storedID) else { return .needsCreation }
        return .existing(storedID)
    }

    public static func serverEnsure(confirmed: Bool) -> ServerEnsure {
        confirmed ? .skip : .verifyOrCreate
    }
}

/// 本地归档（M2）：归档集合的键带命名空间前缀——本地线程
/// 用 `local:<uuid>`、服务端会话用 `server:<sessionID>`，
/// 两类名单共用一个持久集合而不互撞
public enum SideChatArchive {
    public static func localKey(_ id: UUID) -> String { "local:\(id.uuidString)" }
    public static func serverKey(_ id: String) -> String { "server:\(id)" }

    public static func isArchived(localThreadID: UUID, archivedKeys: Set<String>) -> Bool {
        archivedKeys.contains(localKey(localThreadID))
    }

    public static func isArchived(serverSessionID: String, archivedKeys: Set<String>) -> Bool {
        archivedKeys.contains(serverKey(serverSessionID))
    }

    /// 名单二分：可见区与归档区，入序保持不变
    public static func partition<T>(
        _ items: [T], key: (T) -> String, archivedKeys: Set<String>
    ) -> (visible: [T], archived: [T]) {
        var visible: [T] = []
        var archived: [T] = []
        for item in items {
            if archivedKeys.contains(key(item)) {
                archived.append(item)
            } else {
                visible.append(item)
            }
        }
        return (visible, archived)
    }
}

/// 回告入线判定（D4 红线）：回告卡只在主线聊天页由总览桥
/// 通知在呈现层拼装；非主线恒为空。只取未读、保入序、限量
public enum ReportCardPolicy {
    public static let defaultLimit = 3

    public static func cards(
        notifications: [OverviewNotification],
        isMainThread: Bool,
        limit: Int = defaultLimit
    ) -> [OverviewNotification] {
        guard isMainThread else { return [] }
        return Array(notifications.filter { !$0.read }.prefix(max(0, limit)))
    }
}
