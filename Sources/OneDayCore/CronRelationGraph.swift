import Foundation

/// 例程关系图（台账 174，OB-F2 降维版；DESIGN §391）：
/// 把定时任务与投递目标的关系组装成只读图数据——节点＝
/// 任务与投递目标、连线＝「任务投递到目标」。桌面节点画布
/// 不原样移植（审计定版）：手机形态＝两列节点＋连线、点
/// 任务节点进既有详情页。本型只做纯函数组装，呈现归 App。
///
/// 分组口径：投递目标按「人能分辨的目标」归一——平台形
/// （telegram:123）按平台聚合（与 CronPresentation.
/// deliverLabel 同口径：平台名＋「对话」、会话 id 不上
/// 行面）；origin/local/log 各自成一目标；deliver 缺失
/// 落「未指定投递」桶（服务端默认投递无字段可证、不猜）。
public struct CronRelationGraph: Equatable, Sendable {

    /// 投递目标节点
    public struct Target: Equatable, Sendable, Identifiable {
        /// 归一键（分组身份）
        public let id: String
        /// 屏上名（CronPresentation.deliverLabel 同口径）
        public let label: String
        /// 投递到此目标的任务 id（保任务入参序）
        public let jobIDs: [String]

        public init(id: String, label: String, jobIDs: [String]) {
            self.id = id
            self.label = label
            self.jobIDs = jobIDs
        }
    }

    /// 连线：任务 → 投递目标
    public struct Edge: Equatable, Sendable {
        public let jobID: String
        public let targetID: String

        public init(jobID: String, targetID: String) {
            self.jobID = jobID
            self.targetID = targetID
        }
    }

    /// 目标节点：按任务数降序、同数按屏上名字典序
    public let targets: [Target]
    /// 全部连线（按任务入参序）
    public let edges: [Edge]

    public init(targets: [Target], edges: [Edge]) {
        self.targets = targets
        self.edges = edges
    }

    /// 未指定投递桶的归一键与屏上名
    public static let unspecifiedTargetID = "deliver:unspecified"
    public static let unspecifiedTargetLabel = "未指定投递"

    /// 投递值 → 归一键＋屏上名（与详情页投递行同口径）
    public static func targetKey(
        forDeliver raw: String?
    ) -> (id: String, label: String) {
        guard let raw, !raw.isEmpty else {
            return (unspecifiedTargetID, unspecifiedTargetLabel)
        }
        if let sep = raw.firstIndex(of: ":"), sep != raw.startIndex {
            let platform = String(raw[..<sep])
            return (
                "deliver:platform:\(platform)",
                CronPresentation.deliverLabel(raw) ?? raw
            )
        }
        return (
            "deliver:\(raw)",
            CronPresentation.deliverLabel(raw) ?? raw
        )
    }

    /// 组装：每个任务恰一条边；目标按任务数降序、同数
    /// 按屏上名字典序；目标内任务保入参序
    public static func build(jobs: [CronJob]) -> CronRelationGraph {
        var order: [String] = []
        var labels: [String: String] = [:]
        var members: [String: [String]] = [:]
        var edges: [Edge] = []
        for job in jobs {
            let key = targetKey(forDeliver: job.deliver)
            if members[key.id] == nil {
                order.append(key.id)
                labels[key.id] = key.label
                members[key.id] = []
            }
            members[key.id]?.append(job.id)
            edges.append(Edge(jobID: job.id, targetID: key.id))
        }
        let targets = order
            .map { id in
                Target(
                    id: id,
                    label: labels[id] ?? id,
                    jobIDs: members[id] ?? []
                )
            }
            .sorted { a, b in
                if a.jobIDs.count != b.jobIDs.count {
                    return a.jobIDs.count > b.jobIDs.count
                }
                if a.label != b.label { return a.label < b.label }
                return a.id < b.id
            }
        return CronRelationGraph(targets: targets, edges: edges)
    }
}
