import Foundation

/// oneday-bridge 冻结契约模型（0.11.0，P4 目标＋P5 点子）：
/// 桥是同机 sidecar 的目标/点子仓，基址为当前服务器的
/// `/api/oneday-bridge`，鉴权复用 write-gate 钥匙（与
/// 总览桥同一把、用户零新增粘贴）。契约逐字冻结：
///
/// - GET    /goals → {items:[Goal]}；POST /goals → 201 Goal
/// - PATCH  /goals/{id}（milestones 全量替换）；DELETE → {ok:true}
/// - GET    /ideas → {items:[Idea]}；POST /ideas → 201 Idea
/// - DELETE /ideas/{id} → {ok:true}
/// - 时间一律 epoch 秒（float）；title 空 → 400、id 不存在 → 404
///
/// 本文件只放 DTO＋请求体组装＋纯派生（进度/勾选计划/
/// 转任务计划/本地已转标记编解码），网络与状态在 App 层。

// MARK: - 目标 DTO

public struct BridgeMilestone: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let done: Bool

    public init(id: String, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}

public struct BridgeGoal: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 契约全形带 note；缺失/null 按空串收（不因备注
    /// 字段漂移整表解码失败）
    public let note: String
    public let milestones: [BridgeMilestone]
    /// epoch 秒（float）
    public let createdAt: Double
    public let updatedAt: Double

    public init(
        id: String, title: String, note: String,
        milestones: [BridgeMilestone],
        createdAt: Double, updatedAt: Double
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.milestones = milestones
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, note, milestones, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        milestones = try container.decodeIfPresent(
            [BridgeMilestone].self, forKey: .milestones
        ) ?? []
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
        updatedAt = try container.decodeIfPresent(
            Double.self, forKey: .updatedAt
        ) ?? 0
    }
}

public struct BridgeGoalsResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeGoal]

    public init(items: [BridgeGoal]) {
        self.items = items
    }
}

// MARK: - 点子 DTO

public struct BridgeIdea: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// 契约全形带 detail；缺失/null 按空串收（同 note 口径）
    public let detail: String
    /// 挂靠目标 id；未挂为 nil
    public let goalId: String?
    /// epoch 秒（float）
    public let createdAt: Double

    public init(
        id: String, title: String, detail: String,
        goalId: String?, createdAt: Double
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.goalId = goalId
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, goalId, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(
            String.self, forKey: .detail
        ) ?? ""
        goalId = try container.decodeIfPresent(String.self, forKey: .goalId)
        createdAt = try container.decodeIfPresent(
            Double.self, forKey: .createdAt
        ) ?? 0
    }
}

public struct BridgeIdeasResponse: Decodable, Equatable, Sendable {
    public let items: [BridgeIdea]

    public init(items: [BridgeIdea]) {
        self.items = items
    }
}

public struct BridgeOKResponse: Decodable, Equatable, Sendable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

// MARK: - 请求体（POST 新建目标）

/// 新建目标时里程碑只有标题（id 与 done 由服务端定）
public struct BridgeMilestoneDraft: Encodable, Equatable, Sendable {
    public let title: String

    public init(title: String) {
        self.title = title
    }
}

/// POST /goals 请求体：{title, note?, milestones?}——
/// 可选字段为 nil 时不落键（合成 Encodable 对 Optional
/// 走 encodeIfPresent）
public struct BridgeGoalCreateRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let note: String?
    public let milestones: [BridgeMilestoneDraft]?

    public init(
        title: String, note: String?,
        milestones: [BridgeMilestoneDraft]?
    ) {
        self.title = title
        self.note = note
        self.milestones = milestones
    }

    /// 表单口径收口：标题/备注去首尾空白，备注空→不带
    /// 字段、里程碑空标题行剔除、全空→不带字段
    public static func make(
        title: String, note: String, milestoneTitles: [String]
    ) -> BridgeGoalCreateRequest {
        let trimmedNote = note.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let drafts = milestoneTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { BridgeMilestoneDraft(title: $0) }
        return BridgeGoalCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            milestones: drafts.isEmpty ? nil : drafts
        )
    }
}

// MARK: - 请求体（PATCH 目标：milestones 全量替换）

/// PATCH 里程碑全量替换的单条：已有条带 id（服务端
/// 按 id 对齐）、新建条 id 为 nil 不落键（服务端发新 id）
public struct BridgeMilestonePatch: Encodable, Equatable, Sendable {
    public let id: String?
    public let title: String
    public let done: Bool

    public init(id: String?, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}

/// PATCH /goals/{id} 请求体：标题＋备注＋里程碑全量。
/// 冻结合约只点名 milestones 全量替换；标题/备注编辑
/// 同走本端点（编辑保存一次 PATCH 送全形）
public struct BridgeGoalPatchRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let note: String
    public let milestones: [BridgeMilestonePatch]

    public init(
        title: String, note: String,
        milestones: [BridgeMilestonePatch]
    ) {
        self.title = title
        self.note = note
        self.milestones = milestones
    }
}

/// 编辑草稿里的一条里程碑（详情编辑器与计划组装共用形）
public struct MilestoneDraftState: Equatable, Sendable {
    /// 已有条带服务端 id；新建条为 nil
    public let id: String?
    public var title: String
    public var done: Bool

    public init(id: String?, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}

/// PATCH 体组装计划（纯函数，单测钉死）：勾选与编辑
/// 保存共用同一条全量替换口径——不做增量 PATCH，
/// 每次都把标题/备注/里程碑全量送出，服务端以此为准
public enum GoalPatchPlan {
    /// 勾选翻转：以服务端现值为底，只翻目标条的 done，
    /// 其余条 id/标题/done 原样全量带回。id 不存在 → nil
    /// （调用方不发请求、不假装成功）
    public static func toggle(
        goal: BridgeGoal, milestoneID: String
    ) -> BridgeGoalPatchRequest? {
        guard goal.milestones.contains(where: { $0.id == milestoneID })
        else { return nil }
        let milestones = goal.milestones.map { milestone in
            BridgeMilestonePatch(
                id: milestone.id,
                title: milestone.title,
                done: milestone.id == milestoneID
                    ? !milestone.done : milestone.done
            )
        }
        return BridgeGoalPatchRequest(
            title: goal.title, note: goal.note, milestones: milestones
        )
    }

    /// 编辑保存：标题/备注取草稿（去首尾空白），里程碑
    /// 取草稿全量（空标题行剔除，与新建口径一致）
    public static func update(
        title: String, note: String, milestones: [MilestoneDraftState]
    ) -> BridgeGoalPatchRequest {
        let kept = milestones
            .map {
                MilestoneDraftState(
                    id: $0.id,
                    title: $0.title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    done: $0.done
                )
            }
            .filter { !$0.title.isEmpty }
        return BridgeGoalPatchRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            milestones: kept.map {
                BridgeMilestonePatch(id: $0.id, title: $0.title, done: $0.done)
            }
        )
    }
}

// MARK: - 进度派生

/// 目标进度（列表卡 x/y 与进度条共用，全 App 只此一处算）
public enum GoalProgress {
    public static func counts(of goal: BridgeGoal) -> (done: Int, total: Int) {
        (
            done: goal.milestones.count(where: { $0.done }),
            total: goal.milestones.count
        )
    }

    /// 进度条填充比例；无里程碑为 0（不拿 0/0 说成完成）
    public static func fraction(of goal: BridgeGoal) -> Double {
        let counts = counts(of: goal)
        guard counts.total > 0 else { return 0 }
        return Double(counts.done) / Double(counts.total)
    }

    /// 列表卡进度短文案：「2/5」
    public static func text(of goal: BridgeGoal) -> String {
        let counts = counts(of: goal)
        return "\(counts.done)/\(counts.total)"
    }
}

// MARK: - 请求体（POST 新建点子）

/// POST /ideas 请求体：{title, detail?, goalId?}——
/// 可选字段为 nil 时不落键
public struct BridgeIdeaCreateRequest: Encodable, Equatable, Sendable {
    public let title: String
    public let detail: String?
    public let goalId: String?

    public init(title: String, detail: String?, goalId: String?) {
        self.title = title
        self.detail = detail
        self.goalId = goalId
    }

    /// 表单口径收口：标题/详情去首尾空白，详情空→不带字段
    public static func make(
        title: String, detail: String, goalId: String?
    ) -> BridgeIdeaCreateRequest {
        let trimmedDetail = detail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return BridgeIdeaCreateRequest(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
            goalId: goalId
        )
    }
}

// MARK: - 点子转任务计划

/// 点子 → kanban 任务的载荷组装（纯函数，单测钉死）：
/// 标题直用点子标题；正文＝详情（有才带行）＋关联目标
/// 行（挂了且目标名可解析才带）＋来源行。任务本体经
/// P3 KanbanStore.createTask 落板并回读确认，本计划
/// 只管「建成什么样」，不管成没成
public enum IdeaTaskPlan {
    public static func make(
        idea: BridgeIdea, goalTitle: String?
    ) -> (title: String, body: String) {
        var lines: [String] = []
        let detail = idea.detail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !detail.isEmpty {
            lines.append(detail)
        }
        if idea.goalId != nil, let goalTitle, !goalTitle.isEmpty {
            lines.append("关联目标：\(goalTitle)")
        }
        lines.append("来源：点子")
        return (title: idea.title, body: lines.joined(separator: "\n"))
    }
}

// MARK: - 已转任务本地标记

/// 「已转任务」标记只存本地（冻结合约无此字段，不许
/// 硬塞服务端）：UserDefaults 落排序后的 id 数组，
/// 编解码收口在此供单测钉死（去重＋排序＋容脏）
public enum IdeaConversionMarks {
    public static func encode(_ ids: Set<String>) -> [String] {
        ids.sorted()
    }

    public static func decode(_ raw: [String]?) -> Set<String> {
        guard let raw else { return [] }
        return Set(raw.filter { !$0.isEmpty })
    }
}
