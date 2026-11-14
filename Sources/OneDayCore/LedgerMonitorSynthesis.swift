import Foundation

/// 监测变化 → 活动条目的客户端合成（§217 枢纽收段）
///
/// 背景：枢纽七段收四段后，监测段撤出分段栏，其「变
/// 化事件」并入活动段。服务端台账采集器（companion
/// ledger.py）只有 sessions／kanban／write-gate／
/// cron 四源、暂无监测源——本纯函数在客户端把桥的
/// 监测变化记录（/monitors 的 changes 读面）合成为
/// 与服务端条目同形的 LedgerItem，让活动段的分组、
/// 排序、分页与服务端条目共用一套呈现（LedgerBoard
/// ／LedgerMerge）。合成条目的事实边界：
/// - id 带 `monitor-change:` 前缀，与服务端条目 id
///   空间（run:/task:/appr:/job:）不相撞；
/// - link 指回监测本体（kind=monitor、targetId=监
///   测 id），活动行点达监测详情、变化在详情内对号
///   呈现，不伪造服务端台账详情（合成条目不走台账
///   详情读面）；
/// - status 固定 .completed 只为占位同形——呈现层
///   对 kind=.monitor 有专门口径（LedgerText 词为
///   「监测」、LedgerBoard.subtitle 直给「监测变化
///   · 时刻」），不把事件冒充成「已完成的工作」；
/// - 标题优先变化摘要（桥的人话一句），摘要为空才
///   回落监测名，绝不拼造内容。
/// 服务端将来给台账加监测源后，本合成整体退役（条
/// 目改由服务端直供 kind=monitor），呈现层不用动。
public enum LedgerMonitorSynthesis {
    /// 合成条目 id 前缀（活动段识别合成条目的唯一据）
    public static let itemIDPrefix = "monitor-change:"

    public static func itemID(changeID: String) -> String {
        itemIDPrefix + changeID
    }

    public static func isSynthetic(itemID: String) -> Bool {
        itemID.hasPrefix(itemIDPrefix)
    }

    /// 单个变化的合成条目（标题回落与时刻口径见头注）
    public static func item(
        monitor: BridgeMonitor, change: BridgeMonitorChange
    ) -> LedgerItem {
        let summary = change.summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LedgerItem(
            id: itemID(changeID: change.id),
            kind: .monitor,
            source: .bridge,
            title: summary.isEmpty ? monitor.name : summary,
            titleSource: "monitor_change",
            status: .completed,
            startedAt: change.detectedAt,
            endedAt: change.detectedAt,
            lastEvidenceAt: change.detectedAt,
            origin: "bridge_self",
            link: LedgerLink(kind: "monitor", targetId: monitor.id),
            counts: [:],
            failReason: nil,
            evidenceLagging: false,
            lastSeq: 0,
            sessionId: nil,
            runId: nil,
            correctedBy: nil,
            history: []
        )
    }

    /// 批量合成：逐监测取最近的变化、全局按检出时刻
    /// 倒序后截总量上限——活动段是「最近发生了什么」
    /// 的流，老变化滚出与服务端条目的 maxItems 口径
    /// 同理。入参 changesByMonitor 缺某个监测视为该
    /// 监测本轮没拉到变化（不合成、不报错）
    public static func items(
        monitors: [BridgeMonitor],
        changesByMonitor: [String: [BridgeMonitorChange]],
        perMonitorLimit: Int = 20,
        totalLimit: Int = 50
    ) -> [LedgerItem] {
        var all: [(monitor: BridgeMonitor, change: BridgeMonitorChange)] = []
        for monitor in monitors {
            let changes = (changesByMonitor[monitor.id] ?? [])
                .sorted { $0.detectedAt > $1.detectedAt }
                .prefix(max(0, perMonitorLimit))
            for change in changes {
                all.append((monitor, change))
            }
        }
        all.sort { $0.change.detectedAt > $1.change.detectedAt }
        return all.prefix(max(0, totalLimit)).map {
            item(monitor: $0.monitor, change: $0.change)
        }
    }
}
