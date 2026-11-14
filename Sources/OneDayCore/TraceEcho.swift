import Foundation

/// 留痕回响呈现口径（P0 App 侧，2026-11-13；P2 首链
/// 「自开旁聊」）：AI 内部动作的留痕以回响回到对话
/// 里——落脚点必须在主线或对应旁聊、看得见能接着聊
/// （闭环标准）。绝不写入任何 Hermes 会话（与回告
/// 卡 ReportCardPolicy 同纪律）。
///
/// §217（2026-11-14）起呈现改物化形态：回响不再是
/// 呈现层流尾拼装卡，而是经 TraceEchoMaterializa-
/// tion 规划、由 App 层落盘的真条目（createdAt＝事
/// 件时间、进 sortedEntries 时间轴归位、新消息自
/// 然顶上去——与 §165 审批锚定条目同构）；本文件
/// 的 Policy 只余作用域/窗口收窄职能（物化规划的
/// 输入闸），Copy 仍是文案单源（快照落盘时成句）。
///
/// 呈现范围：
/// - 主线＝留痕的总账面：全部动作在此回响（用户在这
///   里下令，AI 在这里交代）；
/// - 旁聊＝只回响指向本会话的留痕（它的出生卡、以及
///   日后对它做的动作）；
/// - 其余上下文一律不出卡。
/// 失败与成功同级：failed 记录不许被任何过滤静默
/// 掉，失败原文原样上卡（P0 契约）。
public enum TraceEchoPolicy {
    /// 回响窗口（§217 改义：单次刷新的物化窗口——
    /// 每轮只把作用域内最近若干条未落盘留痕规划成
    /// 条目；已落盘条目是永久历史行、不受此数约束。
    /// 全账在桥侧留痕接口）
    public static let defaultLimit = 10

    /// 当前对话作用域内的回响（按时间正序：越新的
    /// 越靠后，与对话的阅读方向一致；§217 起本函数
    /// 是物化规划的作用域/窗口闸，不再直接驱动呈现
    /// 拼装）。入参 traces 顺序不限（桥回最新在前、
    /// 本函数自排）
    public static func cards(
        traces: [BridgeTrace],
        isMainThread: Bool,
        currentServerSessionID: String?,
        limit: Int = defaultLimit
    ) -> [BridgeTrace] {
        let scoped: [BridgeTrace]
        if isMainThread {
            scoped = traces
        } else if let sessionID = currentServerSessionID,
                  !sessionID.isEmpty {
            scoped = traces.filter { $0.target.id == sessionID }
        } else {
            return []
        }
        let chronological = scoped.sorted {
            ($0.at, $0.id) < ($1.at, $1.id)
        }
        return Array(chronological.suffix(max(0, limit)))
    }
}

/// 回响卡文案（五要素的成句口）：动作名→人话短句的
/// 映射只此一处；未登记的动作不许静默——回落中性
/// 句式，结果/失败行仍原样带出动作的实情。
public enum TraceEchoCopy {
    /// 卡头行：「<智能体名> <动作短句>」
    public static func headline(
        trace: BridgeTrace, agentName: String
    ) -> String {
        "\(agentName) \(actionPhrase(trace.action))"
    }

    /// 动作短句（登记表）：新动作门面落地时在此加行；
    /// 未登记回落「做了一件事」（卡面结果行有实情，
    /// 不因缺登记而消失）
    public static func actionPhrase(_ action: String) -> String {
        switch action {
        case "sessions.create": return "新开了一个旁聊"
        case "goals.list": return "查看了目标列表"
        case "goals.create": return "新建了一个目标"
        case "goals.add_entry": return "给目标写了一条进展"
        case "goals.update": return "更新了一个目标"
        default: return "做了一件事"
        }
    }

    /// 结果行：成功＝result 原样、失败＝error 原文
    /// （不折叠、不改写、不收进详情——P0 契约）
    public static func outcomeLine(_ trace: BridgeTrace) -> String {
        if trace.isFailed {
            return trace.error ?? ""
        }
        return trace.result ?? ""
    }

    /// 可点达的会话 id：只有 session 类对象且 id 非空
    /// 才给点达（点卡经宿主走既有续聊通道进该会话）；
    /// 其余 kind 一期只呈现不导航
    public static func openableSessionID(
        _ trace: BridgeTrace
    ) -> String? {
        guard trace.target.kind == "session",
              !trace.target.id.isEmpty else { return nil }
        return trace.target.id
    }
}


/// 回响条目呈现快照（§217）：物化落盘时把卡面要素
/// 成句定格（主句／对象名／点达会话／结果行／失败
/// 标记），随条目存 ChatEntry.traceEchoData——条目
/// 自包含：日后桥侧留痕滚出拉取窗口、智能体改名，
/// 历史行的样子都不漂移（与 §165 锚定条目落盘 head-
/// line 快照同口径）。成句只走 TraceEchoCopy 单源，
/// 本结构只存结果、不自带拼装逻辑。
public struct TraceEchoSnapshot: Codable, Equatable, Sendable {
    /// 主句（「<智能体名> <动作短句>」，落盘时定格）
    public let headline: String
    /// 对象名（会话标题等；可为空串）
    public let targetLabel: String
    /// 可点达的会话 id（仅会话类对象且 id 非空，
    /// 判据在 TraceEchoCopy.openableSessionID）
    public let openableSessionID: String?
    /// 结果行：成功＝result 原样、失败＝error 原文
    /// （P0 契约：不折叠、不改写；可为空串）
    public let outcome: String
    /// 失败标记（失败与成功同级呈现、原文照上）
    public let isFailed: Bool

    public init(
        headline: String, targetLabel: String,
        openableSessionID: String?, outcome: String,
        isFailed: Bool
    ) {
        self.headline = headline
        self.targetLabel = targetLabel
        self.openableSessionID = openableSessionID
        self.outcome = outcome
        self.isFailed = isFailed
    }

    /// 由留痕成句（文案单源 TraceEchoCopy 的唯一组装点）
    public init(trace: BridgeTrace, agentName: String) {
        self.init(
            headline: TraceEchoCopy.headline(
                trace: trace, agentName: agentName),
            targetLabel: trace.target.label,
            openableSessionID: TraceEchoCopy.openableSessionID(trace),
            outcome: TraceEchoCopy.outcomeLine(trace),
            isFailed: trace.isFailed
        )
    }
}

/// 回响物化规划（§217，纯函数）：把一轮拉到的留痕
/// 规划成待落盘条目——与 §165 ApprovalAnchor.plan
/// 同构（去重键＋createdAt 改写事件时间），差异在
/// 去重口径按线程（见 planned 的 existingKeys 注）。
public enum TraceEchoMaterialization {
    /// 条目去重键（落盘在 ChatEntry.traceKey，跨启
    /// 动稳定）：留痕 id 全桥唯一，前缀与 goalTask:/
    /// wg: 两族键隔离
    public static func key(traceID: String) -> String {
        "trace:\(traceID)"
    }

    /// 一条待物化回响条目（规划结果，落盘在 App 层）
    public struct Planned: Equatable, Sendable {
        public let key: String
        /// 条目时刻＝留痕事件时间（trace.at）：sorted-
        /// Entries 按它排序，条目落进事件发生的那一
        /// 轮、新消息自然顶上去（§165 同款定位法，
        /// 不做数组中段手术）
        public let createdAt: Date
        /// 呈现快照（落盘时定格，见 TraceEchoSnapshot）
        public let snapshot: TraceEchoSnapshot

        public init(
            key: String, createdAt: Date,
            snapshot: TraceEchoSnapshot
        ) {
            self.key = key
            self.createdAt = createdAt
            self.snapshot = snapshot
        }
    }

    /// 物化规划（纯函数）：输出还没落过盘的回响条目。规则：
    /// - 作用域与窗口走 TraceEchoPolicy.cards 单源
    ///   （主线全量／旁聊只认指向本会话；每轮最近
    ///   limit 条）——窗口外的旧留痕不追补，与旧呈
    ///   现「只见最近若干条」等价；
    /// - existingKeys 是**目标线程**既有的 traceKey
    ///   集（去重按线程：同一留痕在主线与它指向的
    ///   旁聊各落一条、与旧双面可见语义一致；同线
    ///   程内永不重复——已物化过的旧回响不重出）；
    /// - 无时刻（at≤0）的留痕不规划：没有事件时间
    ///   就没有位置可归，不许猜（同 §165 缺时刻不
    ///   规划的纪律）；
    /// - 失败留痕与成功同级入规划（作用域闸本就不
    ///   按状态过滤），快照 outcome 存失败原文。
    public static func plan(
        traces: [BridgeTrace],
        isMainThread: Bool,
        currentServerSessionID: String?,
        existingKeys: Set<String>,
        agentName: String,
        limit: Int = TraceEchoPolicy.defaultLimit
    ) -> [Planned] {
        let window = TraceEchoPolicy.cards(
            traces: traces,
            isMainThread: isMainThread,
            currentServerSessionID: currentServerSessionID,
            limit: limit
        )
        var seen = existingKeys
        var planned: [Planned] = []
        for trace in window {
            guard trace.at > 0 else { continue }
            let k = key(traceID: trace.id)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            planned.append(Planned(
                key: k,
                createdAt: trace.date,
                snapshot: TraceEchoSnapshot(
                    trace: trace, agentName: agentName)
            ))
        }
        return planned
    }
}
