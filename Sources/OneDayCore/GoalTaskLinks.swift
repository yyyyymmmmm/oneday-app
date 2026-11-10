/// 目标↔任务关联（0.40.0，规格 three-pages-mechanism-v2
/// 第三章 3.1 欠账补落）：kanban 卡面没有 goalId 字段、
/// 也没有通用 metadata 位（0.39.0 已核查），目标委派出的
/// 任务与目标的关联只能落在桥侧 goal_task_links 集合。
/// App 的委派流程与点子采纳同形：先经任务板通道建卡拿到
/// 任务 id，再把关联回写桥（POST /goals/{id}/task-links）；
/// 关联段呈现时在本文件按桥现值拼装，零本地副本账

/// 关联记录：completionEntryAt 是桥的「已记完成条目」
/// 戳——桥轮询任务板发现关联任务完成时，只写一条事实
/// 进展条目（来源 agent）并落此戳，保证恰好一次
public struct BridgeGoalTaskLink: Decodable, Equatable, Identifiable,
    Sendable {
    public let id: String
    public let goalId: String
    public let taskId: String
    /// 委派时挂的里程碑；没挂为 nil
    public let milestoneId: String?
    /// epoch 秒（float）
    public let createdAt: Double
    /// 桥已为「任务完成」写过进展条目的时刻；未写为 nil
    public let completionEntryAt: Double?

    public init(
        id: String, goalId: String, taskId: String,
        milestoneId: String? = nil, createdAt: Double,
        completionEntryAt: Double? = nil
    ) {
        self.id = id
        self.goalId = goalId
        self.taskId = taskId
        self.milestoneId = milestoneId
        self.createdAt = createdAt
        self.completionEntryAt = completionEntryAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, goalId, taskId, milestoneId, createdAt
        case completionEntryAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        goalId = try container.decode(String.self, forKey: .goalId)
        taskId = try container.decode(String.self, forKey: .taskId)
        milestoneId = try container.decodeIfPresent(
            String.self, forKey: .milestoneId
        )
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
        completionEntryAt = try container.decodeIfPresent(
            Double.self, forKey: .completionEntryAt
        )
    }
}

public struct BridgeGoalTaskLinksResponse: Decodable, Equatable,
    Sendable {
    public let items: [BridgeGoalTaskLink]

    public init(items: [BridgeGoalTaskLink]) {
        self.items = items
    }
}

/// POST /goals/{id}/task-links 请求体：{taskId, milestoneId?}
/// ——milestoneId 为 nil 时不落键（合成 Encodable 对
/// Optional 走 encodeIfPresent）
public struct BridgeGoalTaskLinkCreateRequest: Encodable, Equatable,
    Sendable {
    public let taskId: String
    public let milestoneId: String?

    public init(taskId: String, milestoneId: String? = nil) {
        self.taskId = taskId
        self.milestoneId = milestoneId
    }
}

/// 关联段拼装（纯函数，单测钉死）：三路都只读桥/任务板
/// 现值——点子按 goalId 过滤（idea.goalId 是桥字段）、
/// 监测按 goalId 过滤（monitor.goalId 同）、任务经 links
/// 反查任务板现值补标题与状态；任务板没取到时标题/状态
/// 如实落 nil（呈现层给兜底文案），不拿关联记录脑补
public enum GoalAssociations {
    /// 关联任务一行：关联记录＋任务板现值（任务板没取到
    /// 或任务已不在板上时 task 为 nil，呈现层如实兜底，
    /// 不拿关联记录脑补标题/状态）
    public struct LinkedTask: Equatable, Sendable {
        public let link: BridgeGoalTaskLink
        public let task: KanbanTask?

        public init(link: BridgeGoalTaskLink, task: KanbanTask?) {
            self.link = link
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

    public static func linkedTasks(
        links: [BridgeGoalTaskLink], tasks: [KanbanTask]
    ) -> [LinkedTask] {
        let byID = Dictionary(
            tasks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return links.map { link in
            LinkedTask(link: link, task: byID[link.taskId])
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
