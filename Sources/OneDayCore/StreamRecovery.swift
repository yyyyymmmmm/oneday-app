import Foundation

/// 流式失败的归因分型（0.20.0，用户 2026-11-09 23:42
/// 定性纠正）：用户在回复生成中切到别的 App 再切回，
/// 流断了、界面却报「无网络/连不上服务器」——查实链
/// 路：发送任务是 ChatView 里的裸 Task、不观察
/// scenePhase；切后台后系统挂起进程、URLSession 流
/// 连接被系统/网络路径掐断，抛出的瞬断类 URLError
/// 与前台 Wi-Fi 抖动在错误层同形。分型必须结合
/// 「本轮是否经历过后台」这一事实：经历过后台的瞬
/// 断＝生命周期中断（回前台对账恢复，不许报网络
/// 错）；未经历后台的瞬断＝真网络瞬断（文案纠正＋
/// 未产出时自动重试一次）；其余失败＝真失败照实报。
public enum StreamFailureKind: Sendable {
    /// 切后台杀流：回前台探活＋对账恢复（服务端历史
    /// 命中则补齐、否则自动重发一次），不报网络错
    case lifecycleInterrupted
    /// 前台网络瞬断：中性文案＋条件自动重试
    case transient
    /// 鉴权/状态码/解码等真失败：照实报错
    case fatal
}

public enum StreamFailure {
    public static func kind(
        error: HermesError, wasBackgrounded: Bool
    ) -> StreamFailureKind {
        guard error.isTransient else { return .fatal }
        return wasBackgrounded ? .lifecycleInterrupted : .transient
    }
}

/// 对账恢复路线（0.20.0 在 ChatView 内联两分支，
/// 0.21.0 收敛为纯判定）：线程有真服务端会话（主
/// 线钦定/导入/0.21.0 起 App 内旁聊链接后）→ 先拉
/// 服务端历史补齐完整回复；无会话 → 删半截后以原
/// 上下文自动重发一次。已链接只决定「先走哪条」，
/// 服务端拉不到本轮回复时调用方仍可落重发兜底
/// （0.20.0 既有语义不变）。
public enum StreamRecoveryRoute: Equatable, Sendable {
    case completeFromServer(sessionID: String)
    case resendLocal
}

public enum StreamRecovery {
    public static func route(
        linkedSessionID: String?
    ) -> StreamRecoveryRoute {
        if let linkedSessionID, !linkedSessionID.isEmpty {
            return .completeFromServer(sessionID: linkedSessionID)
        }
        return .resendLocal
    }
}
