import Foundation

/// 旁聊真会话链接状态机（0.21.0，用户 2026-11-10
/// 00:07 点选「给旁聊建真会话，标题根治」）。
///
/// 背景（§47.3 坐实）：App 内新建旁聊此前走无状态
/// 重放发送（/v1/chat/completions 不带会话 id）、永
/// 不建服务端会话——服务端两段式 AI 标题（derived
/// →llm）无从回流，抽屉标题永远停在首消息派生值；
/// 切后台恢复也只能走「删半截重发」分支。本包把旁
/// 聊升为真服务端会话：发送前先建会话（POST /api/
/// sessions＋模型锁 require_model_lock，模型＝建时
/// 胶囊所选，研究档实测链背书），落 ChatThread.
/// serverSessionID 后转会话模式发送（请求头
/// X-Hermes-Session-Id 续会话、服务端持上下文、客
/// 户端只发本轮新消息）。
///
/// 状态机三相＋一瞬时相：
/// - 未链接（unlinked）：serverSessionID 为 nil 且
///   无失败记录——发送时先尝试链接；
/// - 链接中（linking）：瞬时相，一次发送内的建会
///   话请求在飞（ChatView 任务内持有，不落盘）；
/// - 已链接（linked）：serverSessionID 非 nil——
///   会话模式发送、标题走 DrawerThreadTitle 管线
///   回流、恢复走服务端补齐分支；
/// - 链接失败（linkFailed）：0.27.0 起链接失败＝
///   本轮不发（无头回退整类已删，见 SideChatSend-
///   Plan 注），失败计数与原因落线程留痕并在聊天
///   页/设置页可见，下次发送再试链接。
/// 本文件只管由持久字段（serverSessionID＋失败计
/// 数）派生相位与发送计划的纯判定，网络动作在
/// ChatView/HermesClient。
public enum SideChatLinkPhase: Equatable, Sendable {
    case unlinked
    case linkFailed(attempts: Int)
    case linked(sessionID: String)
}

/// 本轮发送计划（send 起手按绑定与种子位定形）：
/// - linkAndSeed：尚未完成链接（无绑定／绑的是合
///   并桶／自有会话但种子未落）——先执行链接（建
///   会话或导入种子），成功后本轮转会话模式发出；
///   失败整轮不发、无任何回退形态（0.27.0 串话热
///   修：无头重放回退就此整类删除——它在服务端按
///   对话开头派生合并落库，是主线/旁聊串话的入口，
///   诊断档 main-sidechat-bleed-diagnosis-20261110
///   判死）；
/// - session：已链接且种子已落——会话模式（仅本
///   轮新消息＋会话头，服务端持上下文）。
public enum SideChatSendPlan: Equatable, Sendable {
    case linkAndSeed
    case session(sessionID: String)
}

public enum SideChatLink {
    /// 旁聊服务端会话 id 的 App 生成格式（与主线
    /// oneday-main-<uuid> 同族；服务端若改派以回执
    /// 为准、生成值只是请求值）
    public static func newSessionID() -> String {
        "oneday-side-\(UUID().uuidString.lowercased())"
    }

    /// 持久字段 → 相位：已链接（id 非空）压过一切
    /// （含历史失败计数——成功即清零是写入侧纪律，
    /// 派生侧再兜一层）；未链接按失败计数分未链接
    /// 与失败留痕两相
    public static func phase(
        serverSessionID: String?, linkFailureCount: Int
    ) -> SideChatLinkPhase {
        if let serverSessionID, !serverSessionID.isEmpty {
            return .linked(sessionID: serverSessionID)
        }
        return linkFailureCount > 0
            ? .linkFailed(attempts: linkFailureCount)
            : .unlinked
    }

    /// 相位转移（链接尝试收尾）：成功恒入已链接；
    /// 失败入失败留痕相、计数在旧值上 +1
    public static func phase(afterAttemptSuccess sessionID: String)
        -> SideChatLinkPhase {
        .linked(sessionID: sessionID)
    }

    public static func phase(afterAttemptFailure previousCount: Int)
        -> SideChatLinkPhase {
        .linkFailed(attempts: failureCount(afterFailure: previousCount))
    }

    public static func failureCount(afterFailure previous: Int) -> Int {
        max(0, previous) + 1
    }

    /// App 自建会话 id 的统一前缀（主线 oneday-
    /// main-<uuid>、旁聊 oneday-side-<uuid>）：删除
    /// 归档闸与「自有会话」判定都只认这个前缀——
    /// 服务端派生会话（api-* 等）一律不是我方资产
    public static let ownSessionPrefix = "oneday-"

    public static func isOwnSessionID(_ id: String) -> Bool {
        id.hasPrefix(ownSessionPrefix)
    }

    /// 已判死的服务端合并桶（诊断档 2026-11-10：
    /// 无头重放按开头派生合并的落点，主线与同开头
    /// 旁聊共桶）。绑定指向这两条的线程一律按未链
    /// 接处理：发送前解绑、改链自有会话重新种子；
    /// 删除/管理动作对这两条零服务端写（导出留底
    /// 在 oneday-design-review/merge-buckets-export-
    /// 20261110，本体不许动）
    public static let mergeBucketSessionIDs: Set<String> = [
        "api-592647b9ae21ec54",
        "api-e8c923beeaebed9c",
    ]

    public static func isMergeBucket(_ id: String?) -> Bool {
        guard let id else { return false }
        return mergeBucketSessionIDs.contains(id)
    }

    /// 合并桶动作前的二次确认文案（管理页归档/删
    /// 除入口共用）：必须写明牵连主线历史——这两条
    /// 桶里混存着主线在服务端的记录，归档会让它从
    /// 未归档名单消失、删除是物理灭失
    public static let mergeBucketWarning =
        "这条会话是旧发送方式留下的合并记录，里面混存着主线与旁聊的历史。归档或删除它，会连带主线在服务端的记录一并被归档或删除。"

    /// 删除联动归档闸（0.27.0）：删本地线程时只许
    /// 对「本线程自建的 oneday- 会话」发归档 PATCH；
    /// 其余绑定（导入的服务端会话、合并桶、空）一
    /// 律只删本地、服务端零动作——防把共享/他方历
    /// 史误归档（合并桶里混着主线服务端记录）
    public static func mayArchiveOnDelete(sessionID: String?) -> Bool {
        guard let sessionID, !sessionID.isEmpty else { return false }
        return isOwnSessionID(sessionID)
    }

    /// 真删闸（0.50.30，管理收口包件二）：删本地线程
    /// 时只许对「本线程自建的旁聊会话」发围栏 DELETE
    /// 真删服务端本体。比归档闸严两档——删除不可恢
    /// 复：①主线会话本体永不许删（钦定 id 相等、或
    /// oneday-main- 前缀形态，一律拦下）；②合并桶零
    /// 服务端写（桶 id 非 oneday- 前缀、本就被自有闸
    /// 拦下，此处再明示一档）。其余绑定（导入的服务
    /// 端会话、空绑定）只删本地、服务端零动作
    public static func mayHardDeleteOnThreadDelete(
        sessionID: String?, mainSessionID: String?
    ) -> Bool {
        guard let sessionID, !sessionID.isEmpty else { return false }
        guard isOwnSessionID(sessionID) else { return false }
        guard !isMergeBucket(sessionID) else { return false }
        if let mainSessionID, sessionID == mainSessionID {
            return false
        }
        return !sessionID.hasPrefix("oneday-main-")
    }

    /// 发送计划（0.27.0 改判）：只看绑定与种子位，
    /// 主线/旁聊同口径（主线的绑定与种子位由
    /// SideChatStore 的钦定 id＋确认/种子位代入）：
    /// - 无绑定或空绑定 → 先链接；
    /// - 绑合并桶 → 先链接（解绑重链，桶本体不动）；
    /// - 自有会话但种子未落 → 先链接（补种子）；
    /// - 其余（自有已种子／导入的服务端会话——出
    ///   生即带服务端历史）→ 会话模式。
    /// 失败留痕不改计划：下次发送照样先试链接，但
    /// 链接失败整轮不发（无回退形态，见枚举注）。
    public static func sendPlan(
        serverSessionID: String?, serverSeeded: Bool
    ) -> SideChatSendPlan {
        guard let serverSessionID, !serverSessionID.isEmpty else {
            return .linkAndSeed
        }
        if isMergeBucket(serverSessionID) { return .linkAndSeed }
        if isOwnSessionID(serverSessionID), !serverSeeded {
            return .linkAndSeed
        }
        return .session(sessionID: serverSessionID)
    }

    /// 本轮出门载荷：链接完成后的发送恒为会话模式
    /// ——只带尾条（本轮新用户消息，含引用拼装与图
    /// 片 parts 的成品形态由调用方在全量上下文尾条
    /// 上备好）；历史由种子导入承载、不再随发送重
    /// 放（linkAndSeed 是链接前相位，链接收尾后调
    /// 用方以 .session 形态取形，本函数对其同样只
    /// 取尾条，防误把全量重放带上头重演合并）
    public static func payload<Element>(
        plan: SideChatSendPlan, fullContext: [Element]
    ) -> [Element] {
        switch plan {
        case .session, .linkAndSeed:
            return Array(fullContext.suffix(1))
        }
    }

    /// 已链接线程本轮是否需要重锁模型：只对我方链
    /// 接并落锁的线程（linkedModel 有记录）判定——
    /// 记录与当前胶囊不一致才推一次 POST /api/
    /// sessions/{id}/model；导入线程（linkedModel
    /// 为 nil、锁非我方所设）永不代推
    public static func needsModelRelock(
        linkedModel: String?, capsuleModel: String
    ) -> Bool {
        guard let linkedModel else { return false }
        return linkedModel != capsuleModel
    }
}

// MARK: - 种子与请求体（0.27.0，服务端契约实证）
//
// 建会话两路（step1-session-probe-20261110 判死＋
// 本包联调复证）：
// - 空历史：POST /api/sessions（网关面，nginx 精
//   确路由＋Bearer）——主线 {id, title}、旁聊
//   {id, model, require_model_lock:true}，201；
// - 有历史：POST /api/sessions/import（Dashboard
//   面 cookie 通道）一次落会话行＋全量消息——带头
//   发送的历史以 state.db 为准、body 只取尾条，
//   重放灌不进历史，种子只能走导入。围栏：
//   request_id 每发新铸、expected_revision 取锚点
//   当前 runtime_revision（新锚为 0），冲突 409
//   如实上抛、不许静默重试成无头发送。
// 锁的落法与网关建会话同构：model 本体＋
// model_config.browser_model_lock（import 的
// model/model_config 均为服务端透传列，源码实证）。

/// 种子一条（导入前的本地条目快照）
public struct SeedEntry: Equatable, Sendable {
    public let role: String
    public let content: String
    /// 条目本地时间（epoch 秒；nil 则导入不带时间
    /// 戳、由服务端落当前时刻）
    public let timestamp: Double?

    public init(role: String, content: String, timestamp: Double? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

extension SideChatLink {
    /// 种子转录过滤：只留 user/assistant 且正文非
    /// 空的条目（工具卡只呈现不进上下文、空条目不
    /// 落服务端），入序不变
    public static func seedTranscript(
        from entries: [SeedEntry]
    ) -> [SeedEntry] {
        entries.filter { entry in
            (entry.role == "user" || entry.role == "assistant")
                && !entry.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
        }
    }

    /// 网关建会话请求体（主线形态）：{id, title}
    public static func createSessionBody(
        id: String?, title: String?
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [:]
        if let id { body["id"] = .string(id) }
        if let title { body["title"] = .string(title) }
        return body
    }

    /// 网关建会话请求体（旁聊形态）：{id, model,
    /// require_model_lock:true}、不带 title（标题由
    /// 服务端两段式自生，0.21.0 口径不变）
    public static func linkedCreateSessionBody(
        id: String, model: String
    ) -> [String: JSONValue] {
        [
            "id": .string(id),
            "model": .string(model),
            "require_model_lock": .bool(true),
        ]
    }

    /// 浏览器模型锁配置（与网关建会话落库同构，
    /// import 透传用）：require_model_lock 落锁时
    /// confirmed=true、provider 空串（逐请求切上游
    /// 走聊天请求体的 provider 字段，与锁分工）
    public static func browserModelLockConfig(
        model: String, updatedAt: Double
    ) -> JSONValue {
        .object([
            "browser_model_lock": .object([
                "provider": .string(""),
                "model": .string(model),
                "model_options": .object([:]),
                "route_source": .string(""),
                "confirmed": .bool(true),
                "updated_at": .number(updatedAt),
            ]),
        ])
    }

    /// import 的单个会话字典：{id, source, title?,
    /// model?, model_config?, messages:[{role,
    /// content, timestamp?}]}
    public static func importSessionBody(
        id: String, title: String?, model: String?,
        messages: [SeedEntry], lockUpdatedAt: Double
    ) -> [String: JSONValue] {
        var session: [String: JSONValue] = [
            "id": .string(id),
            "source": .string("api_server"),
        ]
        if let title { session["title"] = .string(title) }
        if let model {
            session["model"] = .string(model)
            session["model_config"] = browserModelLockConfig(
                model: model, updatedAt: lockUpdatedAt
            )
        }
        session["messages"] = .array(messages.map { entry in
            var message: [String: JSONValue] = [
                "role": .string(entry.role),
                "content": .string(entry.content),
            ]
            if let timestamp = entry.timestamp {
                message["timestamp"] = .number(timestamp)
            }
            return .object(message)
        })
        return session
    }

    /// import 请求体：{request_id, expected_
    /// revision, sessions:[…]}
    public static func importRequestBody(
        requestID: String, expectedRevision: Int,
        sessions: [[String: JSONValue]]
    ) -> [String: JSONValue] {
        [
            "request_id": .string(requestID),
            "expected_revision": .number(Double(expectedRevision)),
            "sessions": .array(sessions.map { .object($0) }),
        ]
    }
}

// MARK: - 当前线程显式解析（0.27.0 硬化）
//
// 旧口径：currentThreadID 失配时静默回落「最近活
// 跃线程」——界面显示与发送落点都可能悄悄换一条
// 线程（诊断档列为必须硬化的口子）。新口径：解析
// 只认 id 精确命中；失配即定位失败、由调用方显式
// 上报，本函数不替任何人挑替补线程。

public enum CurrentThreadResolution {
    public enum EnsureDecision: Equatable, Sendable {
        /// 当前 id 精确命中，用它
        case useExisting
        /// 从未选过线程（currentID 为 nil）：新建是
        /// 正常首启路径、不是失配
        case createFresh
        /// id 已选但线程不存在：定位失败，发送须显
        /// 式报错、不许落到别的线程
        case mismatch
    }

    public static func resolve<ID: Equatable>(
        currentID: ID?, existingIDs: some Collection<ID>
    ) -> ID? {
        guard let currentID, existingIDs.contains(currentID) else {
            return nil
        }
        return currentID
    }

    public static func ensureDecision<ID: Equatable>(
        currentID: ID?, existingIDs: some Collection<ID>
    ) -> EnsureDecision {
        if currentID == nil { return .createFresh }
        return resolve(
            currentID: currentID, existingIDs: existingIDs
        ) != nil ? .useExisting : .mismatch
    }
}
