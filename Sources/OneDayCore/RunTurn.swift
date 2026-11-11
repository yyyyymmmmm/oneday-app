import Foundation

/// 任务制生成通道（/v1/runs）的客户端契约与状态机
/// （0.31.0，DESIGN-V4 §58）。本质依据：生成与连接分
/// 家——提交返回 run_id、生成在服务端独立跑完、结果
/// 落服务端会话 transcript；客户端断线/切后台/被杀
/// 都不取消生成，回来只做对账（status 轮询＋events
/// 重挂＋transcript 落定）。判定与实证见
/// oneday-design-review/hermes-generation-lifecycle-
/// analysis-20261110.md 与 §58 探针实录。
///
/// 本文件全部为纯值类型/纯函数：线上 DTO 的宽容解
/// 码、events SSE 帧解析、轮次状态机转移、待对账账
/// 本的增删查、transcript 本轮落定提取。网络动作在
/// App 层 HermesClient，驱动在 ChatView。

// MARK: - Run 状态

/// GET /v1/runs/{id} 与终态事件共用的状态词表（生
/// 产实测：queued/running/waiting_for_approval/
/// stopping/completed/failed/cancelled/interrupted）。
/// 未知词一律归 .unknown，不猜。
public enum RunStatusKind: String, Sendable, Equatable {
    case queued
    case running
    case waitingForApproval = "waiting_for_approval"
    case stopping
    case completed
    case failed
    case cancelled
    case interrupted
    case unknown

    public static func from(_ raw: String?) -> RunStatusKind {
        guard let raw, let kind = RunStatusKind(rawValue: raw)
        else { return .unknown }
        return kind
    }

    /// 服务端终态：轮次命运已定，可进对账落定
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .interrupted:
            return true
        case .queued, .running, .waitingForApproval,
             .stopping, .unknown:
            return false
        }
    }

    /// 仍在生成系（含等待审批与停止中）：不可当完成、
    /// 也不可当失败
    public var isActive: Bool {
        switch self {
        case .queued, .running, .waitingForApproval, .stopping:
            return true
        case .completed, .failed, .cancelled, .interrupted,
             .unknown:
            return false
        }
    }
}

// MARK: - 线上 DTO

/// POST /v1/runs 的 202 回执（生产实测形态：
/// {run_id, status: "started", replayed: bool}；幂等
/// 重演时 status 带当下状态、replayed=true）
public struct RunSubmitResponse: Decodable, Sendable, Equatable {
    public let runID: String
    public let statusRaw: String
    public let replayed: Bool

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case statusRaw = "status"
        case replayed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        runID = try container.decode(String.self, forKey: .runID)
        statusRaw = try container.decodeIfPresent(
            String.self, forKey: .statusRaw
        ) ?? ""
        replayed = try container.decodeIfPresent(
            Bool.self, forKey: .replayed
        ) ?? false
    }

    public init(runID: String, statusRaw: String, replayed: Bool) {
        self.runID = runID
        self.statusRaw = statusRaw
        self.replayed = replayed
    }
}

/// GET /v1/runs/{id} 的状态回执（宽容解码：字段随
/// 轮次阶段增减，缺失不打死整页）。status 之外，
/// output 是终态的完整回复（也是 failed 时服务端给
/// 的人话说明），error 为失败原文。
public struct RunStatusResponse: Decodable, Sendable, Equatable {
    public let runID: String?
    public let status: RunStatusKind
    public let output: String?
    public let error: String?
    public let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
        case output
        case error
        case sessionID = "session_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        runID = try container.decodeIfPresent(
            String.self, forKey: .runID
        )
        status = RunStatusKind.from(
            try container.decodeIfPresent(
                String.self, forKey: .status
            )
        )
        output = try container.decodeIfPresent(
            String.self, forKey: .output
        )
        error = try container.decodeIfPresent(
            String.self, forKey: .error
        )
        sessionID = try container.decodeIfPresent(
            String.self, forKey: .sessionID
        )
    }

    public init(
        runID: String?, status: RunStatusKind, output: String?,
        error: String?, sessionID: String?
    ) {
        self.runID = runID
        self.status = status
        self.output = output
        self.error = error
        self.sessionID = sessionID
    }
}

/// 一轮 run 的输入：纯文本走字符串形态；带图尾条走
/// 单元素消息数组形态（服务端 _run_user_message 取
/// 末元素 content，parts 数组原样透传——0.31.0 探针
/// 实测图片问答成立）。编码产物直接作请求体的
/// "input" 值。
public enum RunInput: Sendable {
    case text(String)
    case message(ChatMessage)

    public func encodedValue() throws -> Any {
        switch self {
        case .text(let text):
            return text
        case .message(let message):
            let data = try JSONEncoder().encode(message)
            let object = try JSONSerialization
                .jsonObject(with: data)
            guard let dict = object as? [String: Any] else {
                return [["role": message.role,
                         "content": message.content]]
            }
            return [dict]
        }
    }
}

// MARK: - Events 流

/// runs events 的一帧（data: JSON，键序为线上格式：
/// {event, run_id, timestamp, ...fields, seq}）。
/// 与现行渲染的映射（§58 探针实测）：
/// - message.delta＝正文增量；message.interim＝工具
///   旁白正文（现行 chat 通道里同为正文增量、无从区
///   分，合并同路）；
/// - tool.started/completed＝工具卡的起/落（complet-
///   ed 带 ≤500 字结果预览，全文以 transcript 为准）；
/// - reasoning.available＝思考的 500 字有损预览（生
///   产 admission 路径实测不发；思考全文以 transcr-
///   ipt 的 reasoning_content 对账回填为准）；
/// - run.<终态>＝轮次终态（completed 带 output）。
public enum RunStreamEvent: Sendable, Equatable {
    case contentDelta(String)
    case interim(String)
    case toolStarted(id: String, name: String, preview: String)
    case toolCompleted(
        id: String, name: String, preview: String, failed: Bool
    )
    case reasoningPreview(String)
    case terminal(kind: RunStatusKind, output: String?)
    case other(name: String)
}

public struct RunEventEnvelope: Sendable, Equatable {
    public let seq: Int?
    public let event: RunStreamEvent

    public init(seq: Int?, event: RunStreamEvent) {
        self.seq = seq
        self.event = event
    }
}

/// runs events 的逐行解析器（SSE：data: 行承 JSON、
/// id: 行与注释行忽略——seq 以 JSON 内字段为准，
/// 实测每帧都带）。解不出的数据行回 nil，不打死整
/// 条流。
public struct RunEventParser: Sendable {
    public init() {}

    public mutating func consume(
        line: String
    ) -> RunEventEnvelope? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5)
            .trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization
                .jsonObject(with: data),
              let dict = object as? [String: Any],
              let name = dict["event"] as? String
        else { return nil }
        let seq = (dict["seq"] as? NSNumber)?.intValue
        func string(_ key: String) -> String? {
            dict[key] as? String
        }
        let event: RunStreamEvent
        switch name {
        case "message.delta":
            event = .contentDelta(string("delta") ?? "")
        case "message.interim":
            event = .interim(string("text") ?? "")
        case "tool.started":
            event = .toolStarted(
                id: string("tool_call_id") ?? "",
                name: string("tool") ?? "",
                preview: string("preview") ?? ""
            )
        case "tool.completed":
            event = .toolCompleted(
                id: string("tool_call_id") ?? "",
                name: string("tool") ?? "",
                preview: string("preview") ?? "",
                failed: (dict["error"] as? Bool) ?? false
            )
        case "reasoning.available":
            event = .reasoningPreview(string("text") ?? "")
        case "run.completed":
            event = .terminal(
                kind: .completed, output: string("output")
            )
        case "run.failed":
            event = .terminal(
                kind: .failed, output: string("output")
            )
        case "run.cancelled":
            event = .terminal(kind: .cancelled, output: nil)
        case "run.interrupted":
            event = .terminal(kind: .interrupted, output: nil)
        default:
            event = .other(name: name)
        }
        return RunEventEnvelope(seq: seq, event: event)
    }
}

// MARK: - 轮次状态机

/// 一轮 run 在客户端的相位（0.31.0，与 0.20.0 的
/// 切后台对账合并为一套——旧 PendingStreamRecovery
/// 与「删半截重发」整类退役，见 §58）。铁律：生成
/// 阶段的流断/切后台永远先进 .unknown（结果未知），
/// 绝不映射成网络错误、绝不自动重发；落定只认
/// transcript。
public enum RunTurnPhase: Sendable, Equatable {
    /// 提交中（POST 未回执，含同 key 重演提交）
    case submitting
    /// 生成中（已受理；stopping＝已发停止、等终态）
    case generating(stopping: Bool)
    /// 结果未知（流断/后台/进程中断后待对账）
    case unknown
    /// 对账中（查状态/拉 transcript 落定）
    case reconciling
    /// 完成（成品已落定本地）
    case finished
    /// 失败（服务端终态 failed 或提交被拒）
    case failed
    /// 真取消（stop 落定/中断终态）
    case cancelled
}

public enum RunTurnEvent: Sendable, Equatable {
    case submitAccepted
    /// 提交被明确拒绝（鉴权/参数/状态码类真失败）
    case submitRejected
    /// 提交结果不明（超时/瞬断：服务端可能已受理，
    /// 靠同 Idempotency-Key 重演或对账定性）
    case submitAmbiguous
    /// events 流断开（切后台被系统掐断同路）
    case streamLost
    case foregrounded
    /// 对账得知仍在生成
    case statusRunning
    /// 对账/事件得知服务端终态
    case statusTerminal(RunStatusKind)
    /// 状态记录查不到（过期/404：转 transcript 定性）
    case statusMissing
    /// transcript 已含本轮落定段
    case transcriptSettled
    /// transcript 尚无本轮落定段
    case transcriptPending
    case stopRequested
    /// 对账预算耗尽：停在未知（体面出口，非错误）
    case settleExhausted
}

public struct RunTurnStateMachine: Sendable, Equatable {
    public private(set) var phase: RunTurnPhase = .submitting
    /// 已知的服务端终态（落定走向据此分 finished/
    /// failed/cancelled）；nil＝尚无终态证据
    public private(set) var terminalKind: RunStatusKind?
    public private(set) var stopRequested = false

    public init() {}

    public var isSettled: Bool {
        switch phase {
        case .finished, .failed, .cancelled: return true
        case .submitting, .generating, .unknown,
             .reconciling: return false
        }
    }

    @discardableResult
    public mutating func apply(
        _ event: RunTurnEvent
    ) -> RunTurnPhase {
        if isSettled { return phase }
        switch (phase, event) {
        // MARK: 提交中
        case (.submitting, .submitAccepted):
            phase = .generating(stopping: stopRequested)
        case (.submitting, .submitRejected):
            phase = .failed
        case (.submitting, .submitAmbiguous),
             (.submitting, .streamLost):
            phase = .unknown
        case (.submitting, .stopRequested):
            stopRequested = true
        // MARK: 生成中
        case (.generating, .streamLost):
            phase = .unknown
        case (.generating, .stopRequested):
            stopRequested = true
            phase = .generating(stopping: true)
        case (.generating, .statusTerminal(let kind)):
            terminalKind = kind
            phase = .reconciling
        case (.generating, .statusRunning):
            break
        // MARK: 未知
        case (.unknown, .foregrounded),
             (.unknown, .submitAccepted):
            phase = .reconciling
        case (.unknown, .statusRunning):
            phase = .generating(stopping: stopRequested)
        case (.unknown, .statusTerminal(let kind)):
            terminalKind = kind
            phase = .reconciling
        case (.unknown, .stopRequested):
            stopRequested = true
        case (.unknown, .statusMissing),
             (.unknown, .settleExhausted):
            break
        // MARK: 对账中
        case (.reconciling, .statusRunning):
            phase = .generating(stopping: stopRequested)
        case (.reconciling, .statusTerminal(let kind)):
            terminalKind = kind
        case (.reconciling, .transcriptSettled):
            phase = settledPhase
        case (.reconciling, .settleExhausted):
            phase = .unknown
        case (.reconciling, .stopRequested):
            stopRequested = true
        case (.reconciling, .transcriptPending),
             (.reconciling, .statusMissing),
             (.reconciling, .foregrounded):
            break
        default:
            break
        }
        return phase
    }

    /// transcript 落定时的终局相位：优先服务端终态，
    /// 其次停止意图，最后按完成处理（transcript-only
    /// 定性路径）
    private var settledPhase: RunTurnPhase {
        switch terminalKind {
        case .completed, .none: return .finished
        case .failed: return .failed
        case .cancelled, .interrupted: return .cancelled
        case .queued, .running, .waitingForApproval,
             .stopping, .unknown:
            return stopRequested ? .cancelled : .finished
        }
    }
}

// MARK: - 待对账账本

/// 一轮未落定 run 的持久记账（杀进程可恢复）：提交
/// 前先落账（runID 可后补）、落定即删。重演提交与
/// 对账所需的全部凭据在此——Idempotency-Key＋服务
/// 端会话＋本轮用户条目锚点。落盘在 App 层
/// （UserDefaults JSON，与 SideChatStore 同模式）。
public struct RunLedgerEntry: Codable, Sendable, Equatable {
    public var threadID: String
    public var sessionID: String
    public var runID: String?
    public var idempotencyKey: String
    public var userEntryID: String
    public var submittedAt: Date
    public var stopRequested: Bool

    public init(
        threadID: String, sessionID: String, runID: String?,
        idempotencyKey: String, userEntryID: String,
        submittedAt: Date, stopRequested: Bool = false
    ) {
        self.threadID = threadID
        self.sessionID = sessionID
        self.runID = runID
        self.idempotencyKey = idempotencyKey
        self.userEntryID = userEntryID
        self.submittedAt = submittedAt
        self.stopRequested = stopRequested
    }
}

public enum RunLedger {
    /// 同线程只留一条（新一轮覆盖旧账——发送互斥保
    /// 证同线程同时至多一轮未落定）
    public static func upsert(
        _ entries: [RunLedgerEntry], _ entry: RunLedgerEntry
    ) -> [RunLedgerEntry] {
        var next = entries.filter { $0.threadID != entry.threadID }
        next.append(entry)
        return next
    }

    public static func entry(
        forThreadID id: String, in entries: [RunLedgerEntry]
    ) -> RunLedgerEntry? {
        entries.first { $0.threadID == id }
    }

    public static func removing(
        threadID: String, from entries: [RunLedgerEntry]
    ) -> [RunLedgerEntry] {
        entries.filter { $0.threadID != threadID }
    }
}

// MARK: - Transcript 落定

/// 本轮在服务端 transcript 里的落定段（对账提取）：
/// 锚点＝transcript 最后一条 user 行之后的段（同会
/// 话同时至多一轮在飞，末尾 user 行必属本轮）。工
/// 具卡走 ToolCardBuilder 既有配对拼装；思考取各
/// assistant 行 reasoning_content 拼接（实测思考挂
/// 在工具调用行上、终答行常为空）；正文取段内全部
/// 非空 assistant 正文按序拼接（与直播合并成一条
/// 的现行呈现同构）；failed_turn 行＝服务端失败边
/// 界（不当答案呈现）；hidden 行不呈现。
public struct SettledRunTurn: Sendable, Equatable {
    /// 段内已有本轮产物（工具行/正文/思考/失败行任一）
    public var found: Bool
    public var toolCards: [ToolCard]
    public var reasoning: String?
    public var finalText: String?
    public var failed: Bool
    /// 服务端失败边界行原文（横幅文案兜底）
    public var failureText: String?

    public init(
        found: Bool, toolCards: [ToolCard], reasoning: String?,
        finalText: String?, failed: Bool, failureText: String?
    ) {
        self.found = found
        self.toolCards = toolCards
        self.reasoning = reasoning
        self.finalText = finalText
        self.failed = failed
        self.failureText = failureText
    }

    public static let notFound = SettledRunTurn(
        found: false, toolCards: [], reasoning: nil,
        finalText: nil, failed: false, failureText: nil
    )
}

public enum RunTranscriptSettle {
    public static func settle(
        messages: [SessionMessage]
    ) -> SettledRunTurn {
        guard let lastUserIndex = messages.lastIndex(
            where: { $0.role == "user" }
        ) else { return .notFound }
        let segment = Array(messages[(lastUserIndex + 1)...])
        let hasTurnRows = segment.contains {
            $0.role == "assistant" || $0.role == "tool"
        }
        guard hasTurnRows else { return .notFound }

        if let failedRow = segment.first(
            where: { $0.displayKind == "failed_turn" }
        ) {
            let text = failedRow.content.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return SettledRunTurn(
                found: true, toolCards: [], reasoning: nil,
                finalText: nil, failed: true,
                failureText: text.isEmpty ? nil : text
            )
        }

        let cards = ToolCardBuilder.build(from: segment)
            .compactMap { item -> ToolCard? in
                if case .toolCard(let card, _) = item {
                    return card
                }
                return nil
            }
        let reasoningParts = segment
            .filter { $0.role == "assistant" }
            .map {
                ($0.reasoningContent ?? $0.reasoning ?? "")
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
            }
            .filter { !$0.isEmpty }
        let textParts = segment
            .filter {
                $0.role == "assistant"
                    && $0.displayKind != "hidden"
            }
            .map {
                $0.content.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { !$0.isEmpty }
        guard !cards.isEmpty || !textParts.isEmpty
                || !reasoningParts.isEmpty
        else { return .notFound }
        return SettledRunTurn(
            found: true,
            toolCards: cards,
            reasoning: reasoningParts.isEmpty
                ? nil : reasoningParts.joined(separator: "\n\n"),
            finalText: textParts.isEmpty
                ? nil : textParts.joined(separator: "\n\n"),
            failed: false, failureText: nil
        )
    }

    /// 落定对账补缺（0.36.29，题 B 自愈）：服务端存档
    /// 里有、本地线程里缺的 user 条目清单——新建旁聊
    /// 首发出现过「服务端存档完好、本地线程只剩助手
    /// 回复」的丢失（诊断定案等级中：发送/落盘/导入/
    /// 落定四链静态排除，时序缝未证死），落定时以存
    /// 档为锚自愈，不依赖先证死竞态。
    /// 匹配口径：内容（去首尾空白）＋时间窗——服务
    /// 端 user 行与本地 user 条目按时间序贪心配对，
    /// 同文重复发送（如连发两句「你好」）靠配对消耗
    /// 区分、不误补不漏补；hidden 行与空白行不作锚
    /// （与服务端读面口径同）；**只补 user**——助手
    /// 条目由 settle 段落定自理，此处永不补造
    /// 0.46.1（§116）规范形判同：比对键不再用原文——
    /// 服务端 user 行存的是网关展开全文、本地条目是
    /// 干净正文，原文永不相等会把已在场的条目判缺、
    /// 再补一份展开块进来双份并存（用户截图实证）。
    /// 两边同过 user 规范化（SessionHistoryImport.
    /// normalizedUserContent）比（干净正文＋附件路径
    /// 集）：任一侧路径集为空时只比正文（本地发送条
    /// 目不落文件路径、集恒空，不因缺记录判异），两
    /// 侧都有路径时须全等，防同文异附件错配
    public static func missingUserMessages(
        messages: [SessionMessage],
        localUserEntries: [(content: String, createdAt: Date)],
        timeWindow: TimeInterval = 600
    ) -> [SessionMessage] {
        reconcileUserMessages(
            messages: messages,
            localUserEntries: localUserEntries.map {
                (content: $0.content, createdAt: $0.createdAt,
                 filePaths: [String](), imagePaths: [String]())
            },
            timeWindow: timeWindow
        ).missing
    }

    /// 对账回填（§121 题二 a）：配上对的本地条目缺
    /// 服务端附件路径时，产出一条回填指令——App 侧
    /// 据（text=本地条目规范正文、createdAt）定位条
    /// 目，把服务端路径集写入其落盘字段。发送链已于
    /// §121 改为发送即回填，本结构管存量与导入外条
    /// 目（下一次落定对账自动补牌）
    public struct PathBackfill: Equatable {
        /// 本地条目的规范正文（去首尾空白）
        public let text: String
        /// 本地条目的创建时间（配对锚，与 App 侧传入
        /// 的 createdAt 同值）
        public let createdAt: Date
        /// 服务端条目的文件路径集（规范化 fileRefs）
        public let filePaths: [String]
        /// 服务端条目的图片路径集（规范化 imagePaths）
        public let imagePaths: [String]

        public init(
            text: String, createdAt: Date,
            filePaths: [String], imagePaths: [String]
        ) {
            self.text = text
            self.createdAt = createdAt
            self.filePaths = filePaths
            self.imagePaths = imagePaths
        }
    }

    /// 对账结果：判缺清单＋路径回填清单（互斥——回
    /// 填只对配上对的条目产出）
    public struct UserMessageReconcile {
        public let missing: [SessionMessage]
        public let pathBackfills: [PathBackfill]

        public init(
            missing: [SessionMessage],
            pathBackfills: [PathBackfill]
        ) {
            self.missing = missing
            self.pathBackfills = pathBackfills
        }
    }

    /// 落定对账全量版（§121）：判同口径与 missing-
    /// UserMessages 完全一致（规范形正文＋路径集＋
    /// 时间窗、贪心配对消耗），两点扩围——①本地条
    /// 目已落盘的附件路径（filePaths/imagePaths 入
    /// 参）并入配对路径集：发送回填后本地与服务端
    /// 路径全等、配对更严（同文异附件双非空仍判
    /// 异、不错配）；②配上对但本地缺服务端路径时
    /// 产出 PathBackfill（本地已全持有则不产出）
    public static func reconcileUserMessages(
        messages: [SessionMessage],
        localUserEntries: [(
            content: String, createdAt: Date,
            filePaths: [String], imagePaths: [String]
        )],
        timeWindow: TimeInterval = 600
    ) -> UserMessageReconcile {
        let serverUsers = messages.filter {
            $0.role == "user" && $0.displayKind != "hidden"
                && !$0.content.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        }
        var locals = localUserEntries.map { entry in
            let normalized = SessionHistoryImport
                .normalizedUserContent(entry.content)
            return (
                text: normalized.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                paths: Set(normalized.allPaths)
                    .union(entry.filePaths)
                    .union(entry.imagePaths),
                filePaths: Set(normalized.fileRefs)
                    .union(entry.filePaths),
                imagePaths: Set(normalized.imagePaths)
                    .union(entry.imagePaths),
                createdAt: entry.createdAt
            )
        }.sorted { $0.createdAt < $1.createdAt }
        var missing: [SessionMessage] = []
        var backfills: [PathBackfill] = []
        for server in serverUsers {
            let normalized = SessionHistoryImport
                .normalizedUserContent(server.content)
            let serverText = normalized.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let serverPaths = Set(normalized.allPaths)
            let pairedIndex = locals.firstIndex { local in
                guard local.text == serverText else {
                    return false
                }
                guard serverPaths.isEmpty || local.paths.isEmpty
                        || serverPaths == local.paths
                else { return false }
                guard let serverDate = server.date else {
                    return true
                }
                return abs(
                    local.createdAt.timeIntervalSince(serverDate)
                ) <= timeWindow
            }
            if let pairedIndex {
                let local = locals.remove(at: pairedIndex)
                // 配上对：服务端路径本地未全持有才回填
                // （fileRefs/imagePaths 分开核，任一缺
                // 即整条产出，App 侧按字段各自补缺）
                if !Set(normalized.fileRefs)
                        .isSubset(of: local.filePaths)
                    || !Set(normalized.imagePaths)
                        .isSubset(of: local.imagePaths) {
                    backfills.append(PathBackfill(
                        text: local.text,
                        createdAt: local.createdAt,
                        filePaths: normalized.fileRefs,
                        imagePaths: normalized.imagePaths
                    ))
                }
            } else {
                missing.append(server)
            }
        }
        return UserMessageReconcile(
            missing: missing, pathBackfills: backfills
        )
    }
}
