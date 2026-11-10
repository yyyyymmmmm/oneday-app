import Foundation
import Network
import os

/// 网络路径变化观察（0.36.20，§86.4，治审计 R3）：全
/// App 只启一份、与 App 同寿。口径照苹果官方定版
/// （WWDC19-712/713）：path 只看路由不是互联网——本
/// 观察器**只做触发器**：路径恢复可达或接口切换
/// （WiFi↔蜂窝）时通知上层立刻重探活＋聊天对账；永
/// 不预判/拦截请求、永不凭它单独置离线呈现（在线判
/// 定只认 Core ConnectionLiveness 的多信号迟滞）。
///
/// 回调隔离（硬验收，AGENTS 铁律同族）：NWPathMonitor
/// 在自家队列投递 pathUpdateHandler——本类是非隔离的
/// 普通类，handler 闭包不继承任何 actor 隔离，只碰
/// OSAllocatedUnfairLock 护着的转手盒状态，跨界通知
/// 走注册方提供的 @Sendable 闭包（由注册方自行跳回
/// 主隔离），闭包内不直接碰任何 @MainActor 状态。
final class NetworkPathObserver: @unchecked Sendable {
    static let shared = NetworkPathObserver()

    /// 转手盒状态：上一次 path 快照，只在锁内读写、
    /// 只由 monitor 队列的 handler 碰
    private struct PathSnapshot {
        var started = false
        var satisfied: Bool?
        var interfaceSignature: [String] = []
    }

    private let box = OSAllocatedUnfairLock(
        initialState: PathSnapshot()
    )
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "site.didichou.oneday.path-observer"
    )

    private init() {}

    /// 启动（幂等：只认第一次注册的回调，重复调用无
    /// 动作——监听与 App 同寿、只启一次）。首次 path
    /// 回报只播种基线、不触发；此后「由不可达变可达」
    /// 或「可达状态下接口集合变化」才触发 onRecovered
    func start(onRecovered: @escaping @Sendable () -> Void) {
        let shouldStart = box.withLock { state -> Bool in
            if state.started { return false }
            state.started = true
            return true
        }
        guard shouldStart else { return }
        monitor.pathUpdateHandler = { [box] path in
            // 本闭包在 monitor 队列执行、非隔离：只读
            // path、只写锁盒，触发与否在锁内一次判完
            let nowSatisfied = path.status == .satisfied
            let signature = path.availableInterfaces
                .map { String(describing: $0.type) }
                .sorted()
            let recovered = box.withLock { state -> Bool in
                let wasSatisfied = state.satisfied
                let wasSignature = state.interfaceSignature
                state.satisfied = nowSatisfied
                state.interfaceSignature = signature
                guard let wasSatisfied else {
                    // 首报只播种，不触发
                    return false
                }
                if nowSatisfied && !wasSatisfied {
                    return true
                }
                return nowSatisfied
                    && signature != wasSignature
            }
            if recovered {
                onRecovered()
            }
        }
        monitor.start(queue: queue)
    }
}
