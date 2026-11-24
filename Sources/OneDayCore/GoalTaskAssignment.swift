import Foundation

/// 任务的 goalId 字段（DESIGN §308 单轨）：目标↔看板
/// 任务关联的唯一真值。桥是目标域属主——Hermes 看板卡
/// 是固定列 schema、没有 goalId 也没有通用元数据槽，
/// 字段只能落在桥侧任务属性账里（taskId → 一条归属，
/// 天然单值：一件事只归一个目标）。App 一切关联判定
/// （目标页分组、任务归属、进展计数）只读这一条，
/// 不再有第二本关联账、不做本地推断。
public struct BridgeTaskGoalAssignment: Codable, Equatable, Sendable {
    public var taskId: String
    /// 归属目标 id；nil＝未归类
    public var goalId: String?
    /// 归属落字时刻（epoch 秒）；未归类时为 nil
    public var assignedAt: Double?

    public init(
        taskId: String, goalId: String?,
        assignedAt: Double? = nil
    ) {
        self.taskId = taskId
        self.goalId = goalId
        self.assignedAt = assignedAt
    }
}

/// PUT /tasks/{taskId}/goal 请求体。goalId 是必填键：
/// 传 null＝明确清除归属，所以编码必须显式写出 null，
/// 不能按 Encodable 合成口径把 nil 键省略掉（桥靠
/// 「键在不在」区分清除与漏传，漏传是 400）
public struct BridgeTaskGoalWrite: Encodable, Sendable {
    public var goalId: String?

    public init(goalId: String?) {
        self.goalId = goalId
    }

    private enum CodingKeys: String, CodingKey {
        case goalId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let goalId {
            try container.encode(goalId, forKey: .goalId)
        } else {
            try container.encodeNil(forKey: .goalId)
        }
    }
}

/// POST /goals/{id}/delegate 请求体（§308）：一次调用
/// 里桥建卡＋写 goalId 字段，取代旧「App 直连看板建卡
/// → 再回桥补关联」的两步两账。idempotencyKey 透传给
/// 看板建卡的幂等键、同时作桥侧委派键：同键重试直接
/// 回原归属，不重复建卡
public struct BridgeGoalDelegateRequest: Encodable, Sendable {
    public var title: String
    public var idempotencyKey: String?

    public init(
        title: String,
        idempotencyKey: String? = nil
    ) {
        self.title = title
        self.idempotencyKey = idempotencyKey
    }
}

/// POST /goals/{id}/delegate 回执：新建任务的归属全形
/// ＋标题（调用方回读目标任务面确认行出现即可）
public struct BridgeGoalDelegateResponse: Decodable, Equatable, Sendable {
    public var taskId: String
    public var goalId: String?
    public var assignedAt: Double?
    public var title: String?

    public init(
        taskId: String, goalId: String?,
        assignedAt: Double? = nil,
        title: String? = nil
    ) {
        self.taskId = taskId
        self.goalId = goalId
        self.assignedAt = assignedAt
        self.title = title
    }
}

/// 关联段拼装（纯函数，单测钉死）：三路都只读桥/任务板
/// 现值——点子按 goalId 过滤（idea.goalId 是桥字段）、
/// 监测按 goalId 过滤（monitor.goalId 同）、任务只认
/// GD-2 行自带的 goalId 字段（§308 单轨），行序即归属
/// 落字序，再与任务板现值拼标题与状态；任务板没取到
/// 时标题/状态如实落 nil（呈现层给兜底文案），不拿
/// 归属行脑补
public enum GoalAssociations {
    /// 关联任务一行：归属行＋任务板现值（任务板没取到
    /// 或任务已不在板上时 task 为 nil，呈现层如实兜底）
    public struct LinkedTask: Equatable, Sendable {
        public let row: BridgeGoalTask
        public let task: KanbanTask?

        public init(row: BridgeGoalTask, task: KanbanTask?) {
            self.row = row
            self.task = task
        }

        public var title: String? { task?.title }
        /// 任务板原生状态串（triage/todo/.../done）
        public var status: String? { task?.status }
    }

    public static func ideas(
        for goalID: String, in ideas: [BridgeIdea]
    ) -> [BridgeIdea] {
        ideas.filter { $0.goalId == goalID }
    }

    public static func monitors(
        for goalID: String, in monitors: [BridgeMonitor]
    ) -> [BridgeMonitor] {
        monitors.filter { $0.goalId == goalID }
    }

    /// 目标的关联任务：行按桥下发序（归属落字升序），
    /// 行自带 goalId 再核一道——只认字段、不认推断；
    /// 同一任务只出一次
    public static func linkedTasks(
        goalID: String, rows: [BridgeGoalTask],
        tasks: [KanbanTask]
    ) -> [LinkedTask] {
        let byID = Dictionary(
            tasks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        return rows.compactMap { row in
            guard row.goalId == goalID,
                  seen.insert(row.taskId).inserted
            else { return nil }
            return LinkedTask(row: row, task: byID[row.taskId])
        }
    }

    /// 关联段是否全空（呈现层据此整段收起，不留空壳标题）
    public static func isEmpty(
        ideas: [BridgeIdea], tasks: [LinkedTask],
        monitors: [BridgeMonitor]
    ) -> Bool {
        ideas.isEmpty && tasks.isEmpty && monitors.isEmpty
    }
}
