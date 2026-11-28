import Foundation

/// 工作台账读面契约模型（规格 work-ledger-design-
/// 20261110.md §5，伴生 oneday 模块 1.0.3 读面）：
/// GET /ledger（?since=seq 增量）／GET /ledger/summary
/// ／GET /ledger/{id}，均挂 /api/oneday-bridge 下、
/// 单钥口径不变。伴生源码（companion/modules/
/// ledger.py 的 item_view／_ledger_list_view／
/// _ledger_counts_view）为字段真源；解码一律宽容：
/// 可选字段缺失给缺省、未知枚举原文保留不炸表、
/// 时间戳按桥侧 _ledger_norm_ts 同口径归一（毫秒
/// 级数值 ÷1000）。本文件只放 DTO＋纯派生，网络
/// 与状态在 App 层。

// MARK: - 时刻归一

public enum LedgerTime {
    /// epoch 秒归一：桥内时间戳本为 epoch 秒（float），
    /// 防御外来面混入毫秒级数值（>1e11 判毫秒，与桥
    /// 侧 _ledger_norm_ts 的阈值同值）
    public static func normalize(_ value: Double) -> Double {
        value > 1e11 ? value / 1000 : value
    }
}

// MARK: - 状态／类别／来源

/// 台账七态（规格 §3.1）：queued 排队／running 进行
/// 中／blocked_approval 待审批阻塞／completed 完成
/// ／failed 失败／cancelled 已取消／stale 失联待核。
/// 未知原文落 .other 保留，不许解码失败整表丢弃
public enum LedgerStatus: Equatable, Sendable {
    case queued
    case running
    case blockedApproval
    case completed
    case failed
    case cancelled
    case stale
    case other(String)

    public init(rawValue: String?) {
        switch rawValue {
        case "queued": self = .queued
        case "running": self = .running
        case "blocked_approval": self = .blockedApproval
        case "completed": self = .completed
        case "failed": self = .failed
        case "cancelled": self = .cancelled
        case "stale": self = .stale
        default: self = .other(rawValue ?? "")
        }
    }

    public var rawValue: String {
        switch self {
        case .queued: return "queued"
        case .running: return "running"
        case .blockedApproval: return "blocked_approval"
        case .completed: return "completed"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .stale: return "stale"
        case .other(let raw): return raw
        }
    }

    /// 活跃态：还在干／在等／在排——图标与已耗时通道
    /// 的判据（stale 是可逆非终态、单独成类不算活跃：
    /// 它已停转，见 §2.4）
    public var isActive: Bool {
        switch self {
        case .queued, .running, .blockedApproval: return true
        default: return false
        }
    }

    /// 终态（不可逆，除对账以更强证据纠正）
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }
}

/// 条目类别（规格 §5.1 kind）
public enum LedgerKind: Equatable, Sendable {
    case run
    case kanban
    case job
    case approval
    case device
    /// 监测变化（§217 枢纽收段新增）：A-05 台账单流
    /// 起由服务端台账直供（伴生采集器监测源，见
    /// LedgerMonitorChange 的 id 契约）；此前客户端合
    /// 成（LedgerMonitorSynthesis）已退役
    case monitor
    case other(String)

    public init(rawValue: String?) {
        switch rawValue {
        case "run": self = .run
        case "kanban": self = .kanban
        case "job": self = .job
        case "approval": self = .approval
        case "device": self = .device
        case "monitor": self = .monitor
        default: self = .other(rawValue ?? "")
        }
    }

    public var rawValue: String {
        switch self {
        case .run: return "run"
        case .kanban: return "kanban"
        case .job: return "job"
        case .approval: return "approval"
        case .device: return "device"
        case .monitor: return "monitor"
        case .other(let raw): return raw
        }
    }
}

/// 监测变化条目的 id 契约（A-05 台账单流）：服务端
/// 台账直供的 kind=monitor 条目，id 恒为
/// `monitor-change:<变化 id>`，与服务端条目 id 空间
/// （run:/task:/appr:/job:）不相撞。两个消费点靠它：
/// 通知深链聚焦按 itemID(changeID:) 换算落点；详情
/// 分发按 isMonitorChange 识别「不走台账详情面」
/// （监测条目的详情本体是监测详情）。§217 的客户
/// 端合成（LedgerMonitorSynthesis）退役后，本契约
/// 是该 id 式的唯一持有处；条目本体由伴生
/// _ledger_monitor_item 按同式产出（字段真源在彼）
public enum LedgerMonitorChange {
    public static let itemIDPrefix = "monitor-change:"

    public static func itemID(changeID: String) -> String {
        itemIDPrefix + changeID
    }

    public static func isMonitorChange(itemID: String) -> Bool {
        itemID.hasPrefix(itemIDPrefix)
    }
}

/// 条目来源（规格 §5.1 source）
public enum LedgerSource: Equatable, Sendable {
    case app
    case dashboard
    case cron
    case api
    case bridge
    case device
    case other(String)

    public init(rawValue: String?) {
        switch rawValue {
        case "app": self = .app
        case "dashboard": self = .dashboard
        case "cron": self = .cron
        case "api": self = .api
        case "bridge": self = .bridge
        case "device": self = .device
        default: self = .other(rawValue ?? "")
        }
    }

    public var rawValue: String {
        switch self {
        case .app: return "app"
        case .dashboard: return "dashboard"
        case .cron: return "cron"
        case .api: return "api"
        case .bridge: return "bridge"
        case .device: return "device"
        case .other(let raw): return raw
        }
    }
}

// MARK: - 条目部件

/// 下钻目标（桥侧恒为 {kind, targetId}；kind 取值
/// session／kanban／approval／device 等，原文保留）
public struct LedgerLink: Equatable, Sendable {
    public let kind: String
    public let targetId: String

    public init(kind: String, targetId: String) {
        self.kind = kind
        self.targetId = targetId
    }
}

/// 失败／取消原因（规格 §4.4）：category 是桥侧已
/// 分类的六类之一（上游出错／超时／被审批中止／
/// 用户停止／执行被打断／原因未明），excerpt 是原
/// 始错误摘录（桥侧 ≤160 字）。客户端不二次分类
public struct LedgerFailReason: Equatable, Sendable {
    public let category: String
    public let excerpt: String?

    public init(category: String, excerpt: String?) {
        self.category = category
        self.excerpt = excerpt
    }
}

/// 状态变迁流水一行（详情面）：from 为 nil 是建账行；
/// corrected＝对账纠正、conflict＝弱证据冲突被拒留痕
public struct LedgerHistoryEntry: Equatable, Sendable {
    public let at: Double
    public let from: String?
    public let to: String?
    public let by: String?
    public let note: String?
    public let corrected: Bool
    public let conflict: Bool

    public init(
        at: Double, from: String?, to: String?, by: String?,
        note: String?, corrected: Bool, conflict: Bool
    ) {
        self.at = at
        self.from = from
        self.to = to
        self.by = by
        self.note = note
        self.corrected = corrected
        self.conflict = conflict
    }
}

/// 语义步一行（服务端 2.25.0 契约，条目出口
/// stepsHuman）：与条目原始步骤按序一一对应的模型
/// 人话步——humanTitle 是步名（详情步名解析链的第
/// 一优先），humanNote 是可选的步下副行（说清这步
/// 做了什么）。服务端未生成时整段缺省，客户端步名
/// 走回落链（步自带名→规则名），不许拿空标题顶位
public struct LedgerHumanStep: Equatable, Sendable {
    public let humanTitle: String
    public let humanNote: String?

    public init(humanTitle: String, humanNote: String?) {
        self.humanTitle = humanTitle
        self.humanNote = humanNote
    }
}

// MARK: - 条目

public struct LedgerItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: LedgerKind
    public let source: LedgerSource
    public let title: String
    /// 标题来源原文（server_llm／user_excerpt／
    /// job_name／task_title／record_excerpt／fallback）
    public let titleSource: String
    /// 人话标题（服务端生成，客户端优先渲染；缺省时
    /// 回退 title 原样）
    public let titleHuman: String?
    /// 人话摘要（<=120 字，服务端生成；缺省时回退现
    /// 行 rowParts 拼装副题）
    public let summary: String?
    public let status: LedgerStatus
    /// epoch 秒（已归一）
    public let startedAt: Double
    public let endedAt: Double?
    public let lastEvidenceAt: Double?
    /// 记账来源原文（reported／bridge_self／reconciled）
    public let origin: String
    public let link: LedgerLink?
    /// 子计数原典（toolCalls／subTasks 等）：桥侧拿
    /// 不到时整段缺省——缺省即不显示，不填 0 冒充
    public let counts: [String: Int]
    public let failReason: LedgerFailReason?
    /// 证据迟滞标（§2.4：45 秒无新证据，状态不变只标龄）
    public let evidenceLagging: Bool
    /// 账内序（增量游标的对账位）
    public let lastSeq: Int
    public let sessionId: String?
    public let runId: String?
    public let correctedBy: String?
    /// 仅详情面带（列表面桥侧剥除）
    public let history: [LedgerHistoryEntry]
    /// 收口总结段（服务端 2.25.0 契约）：与标题同一
    /// 条生成线产出的整段人话总结（做了什么、结果
    /// 如何），详情页首位渲染、有段时顶替现行一句
    /// 话摘要。旧服务端无此字段恒 nil，视图回落现
    /// 行 detailSummary 一句话口径，不许空白
    public let detailSummary: String?
    /// 语义步（服务端 2.25.0 契约）：与本条目原始
    /// 步骤按序对应的模型人话步；未生成时为空数组，
    /// 步名走回落链（见 LedgerBoard.threadStepRows）
    public let stepsHuman: [LedgerHumanStep]

    /// 内部系统任务判定（§名下状态行改造 2026-11-26 定规）：
    /// 动态调研/内部系统流程等不进活动流水——按标题特征判别
    /// （含"动态"/"调研"关键词且来源为 bridge/cron 的条目）
    public var isInternalSystemTask: Bool {
        let keywords = ["动态", "调研"]
        let matchesKeyword = keywords.contains { title.contains($0) }
            || (titleHuman.map { humanTitle in
                keywords.contains { humanTitle.contains($0) }
            } ?? false)
        let isSystemSource = source == .bridge || source == .cron
        return matchesKeyword && isSystemSource
    }

    public init(
        id: String, kind: LedgerKind, source: LedgerSource,
        title: String, titleSource: String,
        titleHuman: String? = nil, summary: String? = nil,
        status: LedgerStatus,
        startedAt: Double, endedAt: Double?,
        lastEvidenceAt: Double?, origin: String,
        link: LedgerLink?, counts: [String: Int],
        failReason: LedgerFailReason?, evidenceLagging: Bool,
        lastSeq: Int, sessionId: String?, runId: String?,
        correctedBy: String?, history: [LedgerHistoryEntry],
        detailSummary: String? = nil,
        stepsHuman: [LedgerHumanStep] = []
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.titleSource = titleSource
        self.titleHuman = titleHuman
        self.summary = summary
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastEvidenceAt = lastEvidenceAt
        self.origin = origin
        self.link = link
        self.counts = counts
        self.failReason = failReason
        self.evidenceLagging = evidenceLagging
        self.lastSeq = lastSeq
        self.sessionId = sessionId
        self.runId = runId
        self.correctedBy = correctedBy
        self.history = history
        self.detailSummary = detailSummary
        self.stepsHuman = stepsHuman
    }

    /// 工具调用子计数（缺省 nil＝未结算，不显示）
    public var toolCalls: Int? { counts["toolCalls"] }
    /// 子任务子计数（缺省 nil＝未结算，不显示）
    public var subTasks: Int? { counts["subTasks"] }
    /// 是否对账补记条目（列表面小标「补记」的判据）
    public var isReconciled: Bool { origin == "reconciled" }
}

// MARK: - 计数摘要

/// GET /ledger 的 counts 与 GET /ledger/summary 共
/// 用一形：前者是桥 summary() 原形（无 degraded），
/// 后者多带 degraded／collector 段——同一结构宽容
/// 解码，缺失按缺省收
public struct LedgerSummary: Equatable, Sendable {
    /// 正在进行（queued＋running，桥侧口径；待审批
    /// 不混入，见规格 §4.2）
    public let inProgress: Int
    public let blockedApproval: Int
    public let stale: Int
    public let todayCompleted: Int
    public let todayFailed: Int
    public let todayCancelled: Int
    public let total: Int
    public let byStatus: [String: Int]
    /// 台账降级（事件账损坏隔离中）——仅 summary 面带
    public let degraded: Bool
    public let collectorHeartbeatAt: Double?
    public let ledgerUpdatedAt: Double?
    public let serverNow: Double?
    /// 采集器最后一轮对账时刻（仅 summary 面带）
    public let collectorLastRunAt: Double?

    public init(
        inProgress: Int, blockedApproval: Int, stale: Int,
        todayCompleted: Int, todayFailed: Int,
        todayCancelled: Int, total: Int,
        byStatus: [String: Int], degraded: Bool,
        collectorHeartbeatAt: Double?,
        ledgerUpdatedAt: Double?, serverNow: Double?,
        collectorLastRunAt: Double?
    ) {
        self.inProgress = inProgress
        self.blockedApproval = blockedApproval
        self.stale = stale
        self.todayCompleted = todayCompleted
        self.todayFailed = todayFailed
        self.todayCancelled = todayCancelled
        self.total = total
        self.byStatus = byStatus
        self.degraded = degraded
        self.collectorHeartbeatAt = collectorHeartbeatAt
        self.ledgerUpdatedAt = ledgerUpdatedAt
        self.serverNow = serverNow
        self.collectorLastRunAt = collectorLastRunAt
    }
}

/// GET /ledger 回执（全量与 ?since 增量同形：增量时
/// items 只含变更条目，snapshotSeq 为当前账序）
public struct LedgerListResponse: Equatable, Sendable {
    public let items: [LedgerItem]
    public let snapshotSeq: Int
    public let ledgerUpdatedAt: Double?
    public let collectorHeartbeatAt: Double?
    public let serverNow: Double?
    public let counts: LedgerSummary?

    public init(
        items: [LedgerItem], snapshotSeq: Int,
        ledgerUpdatedAt: Double?,
        collectorHeartbeatAt: Double?, serverNow: Double?,
        counts: LedgerSummary?
    ) {
        self.items = items
        self.snapshotSeq = snapshotSeq
        self.ledgerUpdatedAt = ledgerUpdatedAt
        self.collectorHeartbeatAt = collectorHeartbeatAt
        self.serverNow = serverNow
        self.counts = counts
    }
}

// MARK: - 线程详情（GET /ledger/threads/{id}）

/// 线程原始步一行（服务端 _ledger_thread_steps 的
/// 异形字典宽容收口）：运行步＝{tool, preview, ok?}、
/// 审批步＝{action, object, result}、变迁步＝
/// {action: "from → to", at, by, note?}、截断尾行＝
/// {summary}。字段全可选、缺哪个省哪个——步的呈现
/// 派生（步名解析链/相位/步长）在 LedgerBoard，
/// 本处只如实搬运端点给了什么
public struct LedgerThreadStep: Equatable, Sendable {
    public let tool: String?
    public let preview: String?
    /// 工具结果成败（结果未回/未记录时缺省 nil）
    public let ok: Bool?
    public let action: String?
    public let object: String?
    public let result: String?
    /// epoch 秒（只有变迁步带；运行步端点无时刻）
    public let at: Double?
    public let by: String?
    public let note: String?
    /// 截断尾行文案（「共 N 步，仅显示前 50 步」）
    public let summary: String?
    /// 步自带人话名（防御位：步字典自带 humanTitle/
    /// title/label 时，步名解析链排规则名之前）
    public let ownTitle: String?
    /// 失败标记（字符串原文或 {category} 字典，两形
    /// 归一到一串分类词；无失败为 nil）
    public let failReason: String?

    public init(
        tool: String?, preview: String?, ok: Bool?,
        action: String?, object: String?, result: String?,
        at: Double?, by: String?, note: String?,
        summary: String?, ownTitle: String?,
        failReason: String?
    ) {
        self.tool = tool
        self.preview = preview
        self.ok = ok
        self.action = action
        self.object = object
        self.result = result
        self.at = at
        self.by = by
        self.note = note
        self.summary = summary
        self.ownTitle = ownTitle
        self.failReason = failReason
    }
}

/// 线程详情回执（服务端 _ledger_thread_detail 同
/// 形）：线程本体字段＋steps（原始步，上限 50）＋
/// stepsTotal＋items（成员条目详情）。2.25.0 契约
/// 字段两处都宽容接：线程级 stepsHuman/detail-
/// Summary 与成员条目自带同名字段（解析优先序在
/// LedgerThreading）；旧服务端两处皆无，步名与摘
/// 要全走回落链，页面不许因此空白或倒退
public struct LedgerThreadDetail: Equatable, Sendable {
    public let threadId: String
    public let prototype: String?
    public let inProgress: Bool
    /// 线程状态原文（代表条目的 status）
    public let status: String?
    public let startedAt: Double?
    public let endedAt: Double?
    public let steps: [LedgerThreadStep]
    public let stepsTotal: Int
    /// 线程级语义步（与 steps 按序对应；服务端若把
    /// 语义步挂在成员条目上，本字段为空、由
    /// LedgerThreading 按成员序拼接）
    public let stepsHuman: [LedgerHumanStep]
    /// 线程级总结段（成员条目自带同名字段时优先
    /// 成员，见 LedgerThreading.detailSummary）
    public let detailSummary: String?
    public let items: [LedgerItem]

    public init(
        threadId: String, prototype: String?,
        inProgress: Bool, status: String?,
        startedAt: Double?, endedAt: Double?,
        steps: [LedgerThreadStep], stepsTotal: Int,
        stepsHuman: [LedgerHumanStep],
        detailSummary: String?, items: [LedgerItem]
    ) {
        self.threadId = threadId
        self.prototype = prototype
        self.inProgress = inProgress
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.steps = steps
        self.stepsTotal = stepsTotal
        self.stepsHuman = stepsHuman
        self.detailSummary = detailSummary
        self.items = items
    }
}

/// 线程身份与契约字段解析（与服务端 activity_feed
/// 的 classify_item＋thread_key 逐条同规——服务端
/// 按此把条目组进线程，客户端按此反算 threadId 去
/// 拉详情；两边必须同规，改一处先对另一处）
public enum LedgerThreading {
    /// 条目所属线程的 threadId；服务端不组线程的条
    /// 目（job/monitor/device/未知类别、无会话锚或
    /// 网关无状态会话的运行/审批）返回 nil——这类条
    /// 目详情页不发线程请求、步区走 history 回落
    public static func threadID(for item: LedgerItem) -> String? {
        switch item.kind {
        case .run:
            // classify：无会话锚或 run_ 网关会话不入流
            guard let sessionId = item.sessionId,
                  !sessionId.isEmpty,
                  !sessionId.hasPrefix("run_")
            else { return nil }
            let runId: String
            if item.id.hasPrefix("run:") {
                runId = nonEmpty(item.runId)
                    ?? String(item.id.dropFirst("run:".count))
            } else {
                runId = nonEmpty(item.runId) ?? item.id
            }
            return "thread:run:\(runId)"
        case .approval:
            // classify：审批同样以会话锚为准入（锚即
            // thread_key 的 anchor 第一优先）
            guard let sessionId = item.sessionId,
                  !sessionId.isEmpty,
                  !sessionId.hasPrefix("run_")
            else { return nil }
            return "thread:appr:\(sessionId)"
        case .kanban:
            let taskId = nonEmpty(item.link?.targetId)
                ?? (item.id.hasPrefix("task:")
                    ? String(item.id.dropFirst("task:".count))
                    : item.id)
            return "thread:kanban:\(taskId)"
        default:
            return nil
        }
    }

    /// 语义步解析：线程级整段优先；缺省时按成员序
    /// （回执 items 与 steps 的拼接序同为 itemIds
    /// 序）拼接各成员自带 stepsHuman——两处都空回
    /// 空数组，步名全走回落链
    public static func humanSteps(
        for detail: LedgerThreadDetail
    ) -> [LedgerHumanStep] {
        if !detail.stepsHuman.isEmpty {
            return detail.stepsHuman
        }
        return detail.items.flatMap { $0.stepsHuman }
    }

    /// 总结段解析：本条目成员自带优先，其次线程级
    /// 同名字段；空白段视为无段（回 nil 走旧口径）
    public static func detailSummary(
        for detail: LedgerThreadDetail, itemID: String
    ) -> String? {
        if let member = detail.items.first(where: {
            $0.id == itemID
        }), let text = nonEmpty(member.detailSummary) {
            return text
        }
        return nonEmpty(detail.detailSummary)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty
        else { return nil }
        return value
    }
}

// MARK: - 伴生探测（/api/companion/info）

public struct CompanionModuleInfo: Equatable, Sendable {
    /// 模块状态原文（up／down／degraded 等，面板口径）
    public let state: String
    public let detail: String?
    public let degraded: Bool?

    public init(state: String, detail: String?, degraded: Bool?) {
        self.state = state
        self.detail = detail
        self.degraded = degraded
    }
}

/// 伴生信息面（front 的 build_info）：版本对齐两行
/// 口径的数据源；App 侧只读探测，读不到不臆断
public struct CompanionInfo: Equatable, Sendable {
    public let companionVersion: String?
    public let apiLevel: Int?
    public let minAppVersion: String?
    public let hermesUp: Bool?
    public let modules: [String: CompanionModuleInfo]
    public let generatedAt: String?

    public init(
        companionVersion: String?, apiLevel: Int?,
        minAppVersion: String?, hermesUp: Bool?,
        modules: [String: CompanionModuleInfo],
        generatedAt: String?
    ) {
        self.companionVersion = companionVersion
        self.apiLevel = apiLevel
        self.minAppVersion = minAppVersion
        self.hermesUp = hermesUp
        self.modules = modules
        self.generatedAt = generatedAt
    }

    /// oneday 模块（台账读面宿主）的状态原文
    public var onedayModuleState: String? {
        modules["oneday"]?.state
    }
}

// MARK: - 上报请求体（POST /ledger/report）

/// App 主通道上报体（规格 §2.1，桥 apply_app_report
/// 口径）：runId 必填；开始／心跳（stillRunning）／
/// 终态（terminal）三形态共用一形，桥按字段分流。
/// failReason 的 category 只许桥侧六类原文，拿不准
/// 时走 error 原文让桥分类，不在客户端硬归类
public struct LedgerReportRequest: Encodable, Sendable {
    public var runId: String
    public var sessionId: String?
    public var startedAt: Double?
    public var titleSeed: String?
    public var queued: Bool?
    public var stillRunning: Bool?
    /// completed／failed／cancelled（桥校验 TERMINAL）
    public var terminal: String?
    public var endedAt: Double?
    public var failCategory: String?
    public var failExcerpt: String?
    public var error: String?

    public init(
        runId: String, sessionId: String? = nil,
        startedAt: Double? = nil, titleSeed: String? = nil,
        queued: Bool? = nil, stillRunning: Bool? = nil,
        terminal: String? = nil, endedAt: Double? = nil,
        failCategory: String? = nil, failExcerpt: String? = nil,
        error: String? = nil
    ) {
        self.runId = runId
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.titleSeed = titleSeed
        self.queued = queued
        self.stillRunning = stillRunning
        self.terminal = terminal
        self.endedAt = endedAt
        self.failCategory = failCategory
        self.failExcerpt = failExcerpt
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case runId, sessionId, startedAt, titleSeed, queued
        case stillRunning, terminal, endedAt, failReason, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runId, forKey: .runId)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(titleSeed, forKey: .titleSeed)
        try container.encodeIfPresent(queued, forKey: .queued)
        try container.encodeIfPresent(
            stillRunning, forKey: .stillRunning
        )
        try container.encodeIfPresent(terminal, forKey: .terminal)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        if let failCategory {
            var reason = container.nestedContainer(
                keyedBy: FailReasonKeys.self, forKey: .failReason
            )
            try reason.encode(failCategory, forKey: .category)
            try reason.encodeIfPresent(
                failExcerpt, forKey: .excerpt
            )
        }
        try container.encodeIfPresent(error, forKey: .error)
    }

    private enum FailReasonKeys: String, CodingKey {
        case category, excerpt
    }
}

// MARK: - 宽容解码底座

/// 动态键容器：同一字段多键候选（camelCase 为桥侧
/// 正形，snake_case 为防御候选）取第一个命中的
private struct LedgerAnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func ledgerContainer(
    _ decoder: Decoder
) throws -> KeyedDecodingContainer<LedgerAnyKey> {
    try decoder.container(keyedBy: LedgerAnyKey.self)
}

private func ledgerString(
    _ container: KeyedDecodingContainer<LedgerAnyKey>,
    _ keys: [String]
) -> String? {
    for key in keys {
        if let value = try? container.decode(
            String.self, forKey: LedgerAnyKey(key)
        ) {
            return value
        }
    }
    return nil
}

private func ledgerDouble(
    _ container: KeyedDecodingContainer<LedgerAnyKey>,
    _ keys: [String]
) -> Double? {
    for key in keys {
        if let value = try? container.decode(
            Double.self, forKey: LedgerAnyKey(key)
        ) {
            return value
        }
        if let value = try? container.decode(
            Int.self, forKey: LedgerAnyKey(key)
        ) {
            return Double(value)
        }
    }
    return nil
}

private func ledgerInt(
    _ container: KeyedDecodingContainer<LedgerAnyKey>,
    _ keys: [String]
) -> Int? {
    for key in keys {
        if let value = try? container.decode(
            Int.self, forKey: LedgerAnyKey(key)
        ) {
            return value
        }
        if let value = try? container.decode(
            Double.self, forKey: LedgerAnyKey(key)
        ) {
            return Int(value)
        }
    }
    return nil
}

private func ledgerBool(
    _ container: KeyedDecodingContainer<LedgerAnyKey>,
    _ keys: [String]
) -> Bool? {
    for key in keys {
        if let value = try? container.decode(
            Bool.self, forKey: LedgerAnyKey(key)
        ) {
            return value
        }
    }
    return nil
}

private func ledgerEpoch(
    _ container: KeyedDecodingContainer<LedgerAnyKey>,
    _ keys: [String]
) -> Double? {
    ledgerDouble(container, keys).map(LedgerTime.normalize)
}

// MARK: - Decodable 实现

extension LedgerLink: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        kind = ledgerString(container, ["kind", "type"]) ?? ""
        targetId = ledgerString(
            container, ["targetId", "target_id", "id"]
        ) ?? ""
    }
}

extension LedgerFailReason: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        let raw = ledgerString(container, ["category"]) ?? ""
        category = raw.isEmpty ? "原因未明" : raw
        excerpt = ledgerString(container, ["excerpt"])
    }
}

extension LedgerHistoryEntry: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        at = ledgerEpoch(container, ["at"]) ?? 0
        from = ledgerString(container, ["from"])
        to = ledgerString(container, ["to"])
        by = ledgerString(container, ["by"])
        note = ledgerString(container, ["note"])
        corrected = ledgerBool(container, ["corrected"]) ?? false
        conflict = ledgerBool(container, ["conflict"]) ?? false
    }
}

extension LedgerItem: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        id = ledgerString(container, ["id"]) ?? ""
        kind = LedgerKind(rawValue: ledgerString(container, ["kind"]))
        source = LedgerSource(
            rawValue: ledgerString(container, ["source"])
        )
        title = ledgerString(container, ["title"]) ?? ""
        titleSource = ledgerString(
            container, ["titleSource", "title_source"]
        ) ?? ""
        titleHuman = ledgerString(
            container, ["titleHuman", "title_human"]
        )
        summary = ledgerString(container, ["summary"])
        status = LedgerStatus(
            rawValue: ledgerString(container, ["status"])
        )
        startedAt = ledgerEpoch(
            container, ["startedAt", "started_at"]
        ) ?? 0
        endedAt = ledgerEpoch(container, ["endedAt", "ended_at"])
        lastEvidenceAt = ledgerEpoch(
            container, ["lastEvidenceAt", "last_evidence_at"]
        )
        origin = ledgerString(container, ["origin"]) ?? ""
        if container.contains(LedgerAnyKey("link")),
           !(try container.decodeNil(forKey: LedgerAnyKey("link"))) {
            link = try container.decode(
                LedgerLink.self, forKey: LedgerAnyKey("link")
            )
        } else {
            link = nil
        }
        counts = (try? container.decode(
            [String: Int].self, forKey: LedgerAnyKey("counts")
        )) ?? [:]
        if container.contains(LedgerAnyKey("failReason")),
           !(try container.decodeNil(
               forKey: LedgerAnyKey("failReason")
           )) {
            failReason = try container.decode(
                LedgerFailReason.self, forKey: LedgerAnyKey("failReason")
            )
        } else {
            failReason = nil
        }
        evidenceLagging = ledgerBool(
            container, ["evidenceLagging", "evidence_lagging"]
        ) ?? false
        lastSeq = ledgerInt(container, ["lastSeq", "seq"]) ?? 0
        sessionId = ledgerString(
            container, ["sessionId", "session_id"]
        )
        runId = ledgerString(container, ["runId", "run_id"])
        correctedBy = ledgerString(container, ["correctedBy"])
        history = (try? container.decode(
            [LedgerHistoryEntry].self, forKey: LedgerAnyKey("history")
        )) ?? []
        detailSummary = ledgerString(
            container, ["detailSummary", "detail_summary"]
        )
        stepsHuman = (try? container.decode(
            [LedgerHumanStep].self,
            forKey: LedgerAnyKey("stepsHuman")
        )) ?? (try? container.decode(
            [LedgerHumanStep].self,
            forKey: LedgerAnyKey("steps_human")
        )) ?? []
    }
}

extension LedgerHumanStep: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        humanTitle = ledgerString(
            container, ["humanTitle", "human_title"]
        ) ?? ""
        humanNote = ledgerString(
            container, ["humanNote", "human_note"]
        )
    }
}

extension LedgerThreadStep: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        tool = ledgerString(container, ["tool"])
        preview = ledgerString(container, ["preview"])
        ok = ledgerBool(container, ["ok"])
        action = ledgerString(container, ["action"])
        object = ledgerString(container, ["object"])
        result = ledgerString(container, ["result"])
        at = ledgerEpoch(container, ["at"])
        by = ledgerString(container, ["by"])
        note = ledgerString(container, ["note"])
        summary = ledgerString(container, ["summary"])
        ownTitle = ledgerString(
            container, ["humanTitle", "human_title", "title", "label"]
        )
        // failReason 两形：字符串原文直收；字典形取
        // category（与条目 failReason 同口径）
        if let text = ledgerString(container, ["failReason"]) {
            failReason = text
        } else if container.contains(LedgerAnyKey("failReason")),
                  !(try container.decodeNil(
                      forKey: LedgerAnyKey("failReason")
                  )) {
            failReason = try container.decode(
                LedgerFailReason.self,
                forKey: LedgerAnyKey("failReason")
            ).category
        } else {
            failReason = nil
        }
    }
}

extension LedgerThreadDetail: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        threadId = ledgerString(
            container, ["threadId", "thread_id"]
        ) ?? ""
        prototype = ledgerString(container, ["prototype"])
        inProgress = ledgerBool(
            container, ["inProgress", "in_progress"]
        ) ?? false
        status = ledgerString(container, ["status"])
        startedAt = ledgerEpoch(
            container, ["startedAt", "started_at"]
        )
        endedAt = ledgerEpoch(container, ["endedAt", "ended_at"])
        steps = (try? container.decode(
            [LedgerThreadStep].self, forKey: LedgerAnyKey("steps")
        )) ?? []
        stepsTotal = ledgerInt(
            container, ["stepsTotal", "steps_total"]
        ) ?? steps.count
        stepsHuman = (try? container.decode(
            [LedgerHumanStep].self,
            forKey: LedgerAnyKey("stepsHuman")
        )) ?? (try? container.decode(
            [LedgerHumanStep].self,
            forKey: LedgerAnyKey("steps_human")
        )) ?? []
        detailSummary = ledgerString(
            container, ["detailSummary", "detail_summary"]
        )
        items = (try? container.decode(
            [LedgerItem].self, forKey: LedgerAnyKey("items")
        )) ?? []
    }
}

extension LedgerSummary: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        inProgress = ledgerInt(container, ["inProgress"]) ?? 0
        blockedApproval = ledgerInt(
            container, ["blockedApproval"]
        ) ?? 0
        stale = ledgerInt(container, ["stale"]) ?? 0
        todayCompleted = ledgerInt(
            container, ["todayCompleted"]
        ) ?? 0
        todayFailed = ledgerInt(container, ["todayFailed"]) ?? 0
        todayCancelled = ledgerInt(
            container, ["todayCancelled"]
        ) ?? 0
        total = ledgerInt(container, ["total"]) ?? 0
        byStatus = (try? container.decode(
            [String: Int].self, forKey: LedgerAnyKey("byStatus")
        )) ?? [:]
        degraded = ledgerBool(container, ["degraded"]) ?? false
        collectorHeartbeatAt = ledgerEpoch(
            container, ["collectorHeartbeatAt"]
        )
        ledgerUpdatedAt = ledgerEpoch(
            container, ["ledgerUpdatedAt"]
        )
        serverNow = ledgerEpoch(container, ["serverNow"])
        if container.contains(LedgerAnyKey("collector")) {
            let nested = try? container.nestedContainer(
                keyedBy: LedgerAnyKey.self,
                forKey: LedgerAnyKey("collector")
            )
            collectorLastRunAt = nested.flatMap {
                ledgerEpoch($0, ["lastRunAt"])
            }
        } else {
            collectorLastRunAt = nil
        }
    }
}

extension LedgerListResponse: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        items = (try? container.decode(
            [LedgerItem].self, forKey: LedgerAnyKey("items")
        )) ?? []
        snapshotSeq = ledgerInt(
            container, ["snapshotSeq", "seq"]
        ) ?? 0
        ledgerUpdatedAt = ledgerEpoch(
            container, ["ledgerUpdatedAt"]
        )
        collectorHeartbeatAt = ledgerEpoch(
            container, ["collectorHeartbeatAt"]
        )
        serverNow = ledgerEpoch(container, ["serverNow"])
        if container.contains(LedgerAnyKey("counts")),
           !(try container.decodeNil(forKey: LedgerAnyKey("counts"))) {
            counts = try container.decode(
                LedgerSummary.self, forKey: LedgerAnyKey("counts")
            )
        } else {
            counts = nil
        }
    }
}

extension CompanionModuleInfo: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        state = ledgerString(container, ["state"]) ?? ""
        detail = ledgerString(container, ["detail"])
        degraded = ledgerBool(container, ["degraded"])
    }
}

extension CompanionInfo: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try ledgerContainer(decoder)
        companionVersion = ledgerString(
            container, ["companionVersion", "version"]
        )
        apiLevel = ledgerInt(container, ["apiLevel"])
        minAppVersion = ledgerString(container, ["minAppVersion"])
        hermesUp = ledgerBool(container, ["hermesUp"])
        modules = (try? container.decode(
            [String: CompanionModuleInfo].self,
            forKey: LedgerAnyKey("modules")
        )) ?? [:]
        generatedAt = ledgerString(container, ["generatedAt"])
    }
}
