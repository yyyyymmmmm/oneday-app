import Foundation

/// 留痕回响呈现口径（P0 App 侧，2026-11-13；P2 首链
/// 「自开旁聊」）：AI 内部动作的留痕以回响卡回到对话
/// 里——落脚点必须在主线或对应旁聊、看得见能接着聊
/// （闭环标准）。卡只在呈现层拼装、绝不写入任何
/// Hermes 会话（与回告卡 ReportCardPolicy 同纪律）。
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
    /// 主线回响上限（流尾呈现，取最近若干条即可，
    /// 全账在桥侧留痕接口）
    public static let defaultLimit = 10

    /// 当前对话应呈现的回响卡（按时间正序：越新的越
    /// 靠近流尾，与对话的阅读方向一致）。入参 traces
    /// 顺序不限（桥回最新在前、本函数自排）
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
