import Foundation

/// 审批锚点（§156，规格 approval-anchor-spec-20261111 §3/§4）：
/// 伴生 write-gate 桥（1.0.19 起）在 /pending 与 /decisions
/// 出口为每条记录算时序关联 anchor——把审批回执关联回
/// 它发起的那段对话（服务端会话 id）。App 消费锚做三件
/// 事：①把记录物化成发起对话流里对应时刻的一条锚定条
/// 目（卡回原对话）；②枢纽记录行与通知回执点按时优先
/// 点达这条锚定条目；③锚缺失/无对应本地线程时如实降级
/// （流末尾出卡＋枢纽兜底），不许假定位。
///
/// 纪律（规格 §3 冻结口径＋§4.5 降级总口径）：
/// - anchor 是纯加法字段：旧桥无此字段解码为 nil，行为
///   与今天逐字一致；
/// - 同一记录在本机首次落锚后终身不迁移（本文件只做
///   规划，不做迁移——迁移拦截在物化侧的已有键检查）；
/// - 本机找不到绑定该服务端会话的线程 → 不物化、不建
///   空线程（与 GoalEcho 只对既有绑定物化同口径）；
/// - 已决回溯窗口 30 天，更早的只在枢纽历史里。
public struct WriteGateAnchor: Decodable, Equatable, Sendable {
    /// 服务端会话 id（state.db sessions.id 原值）
    public let sessionId: String
    /// 关联等级原值（"T1"/"T2"/"T3"）：只作排障与记账，
    /// 呈现层不分级——有锚即锚、无锚即降级
    public let tier: String?

    public init(sessionId: String, tier: String? = nil) {
        self.sessionId = sessionId
        self.tier = tier
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, tier
    }
}

public enum ApprovalAnchor {
    /// 锚定条目去重键（落盘在 ChatEntry.approvalKey，跨
    /// 启动稳定）：子系统＋记录 id 全 App 唯一
    public static func key(
        subsystem: WriteGateSubsystem, id: String
    ) -> String {
        "wg:\(subsystem.rawValue):\(id)"
    }

    /// 已决回溯窗口（规格 §4.2）：30 天
    public static let backfillWindow: TimeInterval = 30 * 24 * 3600

    /// 一条待物化锚定条目（规划结果，落盘在 App 层）
    public struct Planned: Equatable, Sendable {
        public let key: String
        /// 目标线程的服务端会话 id（App 层据此找本地线程）
        public let sessionID: String
        /// 条目时刻＝记录的 created_at（排序键定位，规格
        /// §4.1：靠 sortedEntries 排序落进对应轮次，不做
        /// 数组中段手术）
        public let createdAt: Date
        /// 卡面快照标题（桥 headline 结构化字段拼装，与
        /// 现行卡面同源；呈现以实时记录为准，本值只作
        /// 记录两处皆无时的失效行标题兜底）
        public let headline: String

        public init(
            key: String, sessionID: String, createdAt: Date,
            headline: String
        ) {
            self.key = key
            self.sessionID = sessionID
            self.createdAt = createdAt
            self.headline = headline
        }
    }

    /// 物化规划（纯函数）：pending 与 decisions 两集入
    /// 参，输出还没落过的锚定条目。规则：
    /// - 只收带 anchor 的记录；anchor 为 nil（未关联/
    ///   旧桥）一律不规划——降级走现行形态；
    /// - pending 记录无时刻门（待批就是现在的事）；
    ///   decisions 记录须在回溯窗口内（decidedAt 优先、
    ///   缺失回落 createdAt、再缺失不规划——无时刻不许
    ///   猜位置）；
    /// - 同一记录两集同在（裁决刚落账的竞态）只规划一
    ///   条，pending 侧优先（时刻同源、无实质差别）；
    /// - existingKeys 里已有的整条跳过——这既是去重，
    ///   也是冻结口径的执行点：已落锚的记录后续 anchor
    ///   怎么变（变 null/变另一会话）都不再规划、不迁移。
    public static func plan(
        pending: [WriteGateRecord],
        decisions: [WriteGateDecisionRecord],
        existingKeys: Set<String>,
        now: Date
    ) -> [Planned] {
        var planned: [Planned] = []
        var seen = existingKeys
        for record in pending {
            guard let anchor = record.anchor,
                  let createdAt = record.createdAt
            else { continue }
            let k = key(subsystem: record.subsystem, id: record.id)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            planned.append(Planned(
                key: k, sessionID: anchor.sessionId,
                createdAt: createdAt, headline: record.headline
            ))
        }
        for item in decisions {
            guard let anchor = item.anchor else { continue }
            let stamp = item.decidedAt ?? item.createdAt
            guard let stamp,
                  now.timeIntervalSince(stamp) <= backfillWindow
            else { continue }
            let k = key(subsystem: item.subsystem, id: item.id)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            // 已决条目的落位时刻仍取记录 created_at（它
            // 发起的那一轮）；createdAt 缺失时以裁决时
            // 刻落位（桥现行两值同出，此为宽容兜底）
            planned.append(Planned(
                key: k, sessionID: anchor.sessionId,
                createdAt: item.createdAt ?? stamp,
                headline: item.headline
            ))
        }
        return planned
    }

    /// 锚定行呈现态（规格 §4.3 单源）：同一记录在全部
    /// 聊天面只出现一处——本机已落锚的记录由锚定行承
    /// 载（pending→完整卡、decisions→已决行）；数据未
    /// 就位（store 还没成功拉过/正在刷新）→加载中行，
    /// 不许在数据没到时就判已决或失效；两处皆无且缺
    /// 席满两轮→已失效灰行；未落锚的记录维持流末尾
    /// 区出卡（不经本判定）。
    public enum RowState: Equatable, Sendable {
        case pending(WriteGateRecord)
        case decided(WriteGateDecisionRecord)
        /// 两处皆无且缺席满两轮：上游已丢弃/账本已滚
        /// 出——诚实灰行，不删行、不冒充已决
        case stale
        /// 审批数据还没成功拉到（段未就绪）：行位先占
        /// 一行加载态，等刷新落位后自然翻成上面三态
        case loading
    }

    public static func rowState(
        recordID: String,
        dataReady: Bool,
        pending: [WriteGateRecord],
        decisions: [WriteGateDecisionRecord],
        missCount: Int
    ) -> RowState {
        if let record = pending.first(where: { $0.id == recordID }) {
            return .pending(record)
        }
        if let item = decisions.first(where: { $0.id == recordID }) {
            return .decided(item)
        }
        guard dataReady else { return .loading }
        if isStale(missCount: missCount) { return .stale }
        // 缺席未满两轮且无据：多半是裁决刚落账、账本
        // 刷新未跟上的一拍——维持加载态等下一轮对账，
        // 不提前判死、也不假装已决
        return .loading
    }

    /// 流末尾区（ChatApprovalZone）的排除集：本机任一
    /// 线程已落锚的记录 id——已锚记录无论当前打开的是
    /// 不是它的锚定线程，都不在流末尾重复出卡（规格
    /// §4.3 单源口径）
    public static func anchoredRecordIDs(
        keys: some Collection<String>
    ) -> Set<String> {
        var ids: Set<String> = []
        for key in keys {
            if let id = recordID(fromKey: key) {
                ids.insert(id)
            }
        }
        return ids
    }

    /// 键 → 记录 id：键形态 wg:<subsystem>:<id>；id 本
    /// 体是桥的 8 位十六进制、无冒号，按三段切分取尾
    /// 段；形态不对返回 nil（不猜）
    public static func recordID(fromKey key: String) -> String? {
        let parts = key.split(
            separator: ":", omittingEmptySubsequences: false
        )
        guard parts.count == 3, parts[0] == "wg",
              !parts[2].isEmpty
        else { return nil }
        return String(parts[2])
    }

    /// 物化后连续缺席轮数：记录在 pending 与 decisions
    /// 两处皆无的刷新轮数达 2 才转「已失效」（规格
    /// §4.2：一轮缺席可能是刷新竞态/分页截断，不许一
    /// 轮就判死）
    public static func missCountAfterRefresh(
        previous: Int, present: Bool
    ) -> Int {
        present ? 0 : previous + 1
    }

    public static func isStale(missCount: Int) -> Bool {
        missCount >= 2
    }
}
