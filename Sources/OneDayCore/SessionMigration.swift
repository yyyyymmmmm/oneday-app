import Foundation

/// 存量迁移的规划与结果折叠（0.18.0，旁聊立项档 A.3）：
/// 0.7.0 的本地绕行两件——服务端会话标题覆盖表
/// （SideChatStore.titleOverrides）与本地归档集合里的
/// 服务端键（"server:<id>"）——在「全部对话」管理页
/// 首开时一次性回写服务端本体（PATCH {title} /
/// {archived}，回读对账才算落定）：成功逐项从本地退
/// 役，失败逐项留痕、本地值保留待下次重试，不许静
/// 默吞。本文件只做纯逻辑（规划＋折叠，单测钉死），
/// 网络执行与留痕呈现归 App 层。
public enum SessionMigration {
    /// 一条待回写项：改名（带目标标题）或归档
    public struct Item: Equatable, Hashable, Sendable {
        public enum Kind: Equatable, Hashable, Sendable {
            case rename(title: String)
            case archive
        }

        public let sessionID: String
        public let kind: Kind

        public init(sessionID: String, kind: Kind) {
            self.sessionID = sessionID
            self.kind = kind
        }

        /// 留痕文案用的动作名
        public var actionLabel: String {
            switch kind {
            case .rename: return "改名回写"
            case .archive: return "归档回写"
            }
        }
    }

    /// 一条未落定项＋人话原因（管理页留痕区逐项呈现）
    public struct Failure: Equatable, Sendable {
        public let item: Item
        public let reason: String

        public init(item: Item, reason: String) {
            self.item = item
            self.reason = reason
        }
    }

    /// 折叠结果：退役后仍留在本地的覆盖表/归档键（只
    /// 含失败项与本地线程键等无关项）＋失败清单
    public struct Outcome: Equatable, Sendable {
        public let remainingTitleOverrides: [String: String]
        public let remainingArchivedKeys: Set<String>
        public let failures: [Failure]

        public init(
            remainingTitleOverrides: [String: String],
            remainingArchivedKeys: Set<String>,
            failures: [Failure]
        ) {
            self.remainingTitleOverrides = remainingTitleOverrides
            self.remainingArchivedKeys = remainingArchivedKeys
            self.failures = failures
        }
    }

    /// 规划：改名项（按会话 id 排序，空标题不入计划）
    /// 在前、归档项（只收 "server:" 前缀键、按 id 排
    /// 序）在后；本地线程键（"local:"）与迁移无关、不
    /// 入计划。顺序钉死保证执行与留痕可复现。
    public static func plan(
        titleOverrides: [String: String],
        archivedKeys: Set<String>
    ) -> [Item] {
        var items: [Item] = []
        for id in titleOverrides.keys.sorted() {
            guard let title = titleOverrides[id],
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            items.append(Item(sessionID: id, kind: .rename(title: title)))
        }
        let serverIDs = archivedKeys
            .filter { $0.hasPrefix("server:") }
            .map { String($0.dropFirst("server:".count)) }
            .sorted()
        for id in serverIDs {
            items.append(Item(sessionID: id, kind: .archive))
        }
        return items
    }

    /// 折叠：计划项不在 failureReasons 里即视为落定
    /// ——改名项从覆盖表删、归档项从归档键删；失败项
    /// 本地值原样保留并进 failures（按计划序）。
    public static func fold(
        plan: [Item],
        failureReasons: [Item: String],
        titleOverrides: [String: String],
        archivedKeys: Set<String>
    ) -> Outcome {
        var overrides = titleOverrides
        var keys = archivedKeys
        var failures: [Failure] = []
        for item in plan {
            if let reason = failureReasons[item] {
                failures.append(Failure(item: item, reason: reason))
                continue
            }
            switch item.kind {
            case .rename:
                overrides[item.sessionID] = nil
            case .archive:
                keys.remove(SideChatArchive.serverKey(item.sessionID))
            }
        }
        return Outcome(
            remainingTitleOverrides: overrides,
            remainingArchivedKeys: keys,
            failures: failures
        )
    }
}
