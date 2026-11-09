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
/// - 链接失败（linkFailed）：仍按未链接发送（回退
///   无状态重放把消息发出去、不许挡消息），失败
///   计数与原因落线程留痕，下次发送再试链接。
/// 本文件只管由持久字段（serverSessionID＋失败计
/// 数）派生相位与发送计划的纯判定，网络动作在
/// ChatView/HermesClient。
public enum SideChatLinkPhase: Equatable, Sendable {
    case unlinked
    case linkFailed(attempts: Int)
    case linked(sessionID: String)
}

/// 本轮发送计划（send 起手按相位定形）：
/// - legacyReplay：主线钦定线程专用——主线的建/发
///   本体不在本包范围（只复用不重构），恒走旧全量
///   重放、无会话头；
/// - linkAndSeed：未链接旁聊——先建会话；成功则
///   本轮为种子轮（全量重放载荷＋会话头把上下文
///   带过去），失败则回退无状态重放（无头、整份
///   载荷，消息照常发出）；
/// - session：已链接旁聊——会话模式（仅本轮新消
///   息＋会话头，服务端持上下文）。
public enum SideChatSendPlan: Equatable, Sendable {
    case legacyReplay
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

    /// 发送计划：主线恒旧链（本体不动）；旁聊已链
    /// 接走会话模式；未链接（含失败留痕）走先链接
    /// 再种子——失败留痕不改计划，下次发送照样再试
    public static func sendPlan(
        serverSessionID: String?, isMainThread: Bool
    ) -> SideChatSendPlan {
        if isMainThread { return .legacyReplay }
        if let serverSessionID, !serverSessionID.isEmpty {
            return .session(sessionID: serverSessionID)
        }
        return .linkAndSeed
    }

    /// 本轮出门载荷：会话模式只带尾条（本轮新用户
    /// 消息——含引用拼装与图片 parts 的成品形态由
    /// 调用方在全量上下文尾条上备好）；种子轮与旧
    /// 链整份出门（上下文不断链）
    public static func payload<Element>(
        plan: SideChatSendPlan, fullContext: [Element]
    ) -> [Element] {
        switch plan {
        case .session:
            return Array(fullContext.suffix(1))
        case .legacyReplay, .linkAndSeed:
            return fullContext
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
