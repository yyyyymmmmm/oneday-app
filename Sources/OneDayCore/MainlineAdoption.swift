import Foundation

/// 网关面结构化错误码解析（主线收养包，DESIGN §220）：
/// 网关面拒请求的回包形如 {"error": {"code": "invalid_
/// title", "message": "…", "type": "invalid_request_
/// error"}}——取 error.code 本体。发送层旧形把响应体
/// 整个丢弃，这类码到不了客户端逻辑（删除 409 线已在
/// Dashboard 面以 detail 形解析同类问题，见 Hermes-
/// ServerErrorCode——两形并存，组版时可收编一处）。
/// 码本体只许字母/数字/下划线，其余形态一律 nil（不
/// 猜、不拼）。
public enum GatewayErrorCode {
    public static func parse(_ body: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: body),
            let dict = object as? [String: Any],
            let error = dict["error"] as? [String: Any],
            let code = error["code"] as? String
        else { return nil }
        guard !code.isEmpty,
              code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return nil }
        return code
    }
}

/// 收养候选（服务端会话名单的最小投影）：标题取服务
/// 端标题本体（state.db title 列的回包字段），活动时
/// 刻为 endedAt ?? startedAt 的 epoch 秒（名单投影无
/// last_activity 字段，以此为最近活动代理口径）
public struct MainlineAdoptionCandidate: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let lastActivityAt: TimeInterval?

    public init(id: String, title: String?, lastActivityAt: TimeInterval?) {
        self.id = id
        self.title = title
        self.lastActivityAt = lastActivityAt
    }
}

/// 主线建会话撞 invalid_title 时的收养分流（DESIGN
/// §220）：纯函数、单测把守，链接层只许照此执行。
/// 触发面严格限定：状态 400 且错误码恰为 invalid_
/// title——其余失败一律 .notApplicable（原错误照抛，
/// 不许拿收养掩盖真故障）；标题精确匹配（全等，不
/// 做包含/模糊）；零匹配 .noCandidate（原错误照抛）；
/// 恰一条直接收养；多条优先 oneday-main- 前缀池、
/// 池内取最近活动一条（活动同值按 id 升序定序，保
/// 证判定确定性），以 .adoptAmongMultiple 回报供调
/// 用方留痕。
public enum MainlineAdoptionDirective: Sendable, Equatable {
    /// 非 400/invalid_title：不触发收养
    case notApplicable
    /// 触发面成立但名单里无同标题会话：无从收养
    case noCandidate
    /// 恰一条同标题会话：收养它
    case adopt(sessionID: String)
    /// 多条同标题会话：已按前缀＋最近活动选定一条
    /// （matchCount 供调用方留痕）
    case adoptAmongMultiple(sessionID: String, matchCount: Int)

    public static func directive(
        status: Int, serverCode: String?, title: String,
        candidates: [MainlineAdoptionCandidate]
    ) -> MainlineAdoptionDirective {
        guard status == 400, serverCode == "invalid_title" else {
            return .notApplicable
        }
        let matches = candidates.filter { $0.title == title }
        switch matches.count {
        case 0:
            return .noCandidate
        case 1:
            return .adopt(sessionID: matches[0].id)
        default:
            let prefixed = matches.filter { $0.id.hasPrefix("oneday-main-") }
            let pool = prefixed.isEmpty ? matches : prefixed
            let pick = pool.sorted { lhs, rhs in
                let l = lhs.lastActivityAt ?? -.infinity
                let r = rhs.lastActivityAt ?? -.infinity
                if l != r { return l > r }
                return lhs.id < rhs.id
            }.first ?? pool[0]
            return .adoptAmongMultiple(
                sessionID: pick.id, matchCount: matches.count
            )
        }
    }
}

/// 主线模型回读判定（DESIGN §220 立项）：原
/// MainlineModelReconcile.serverModelToAdopt（以服务
/// 端会话 model 字段压本地写账）于 0.50.38 组版随
/// §227 冻结字段裁决退役——服务端字段是化石值、永
/// 不入本地选择账；回读比对改走 SessionModelTruth
/// 只读读数（SessionModelAccount.swift），不一致只
/// 留痕不写账。本注为退役墓志，防后人复活写账路。
