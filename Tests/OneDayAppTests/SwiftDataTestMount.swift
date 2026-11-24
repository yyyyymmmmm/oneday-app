import Foundation
import SwiftData

/// §184 容器租约（2026-11-15，第二版）。
///
/// 第一版（挂载即 retain、tearDown 先拆窗→排空 0.6s→再放容器）
/// 在 CI 第一轮（run 43627222674）被证伪：宿主仍崩 10 次，
/// 同签名（EXC_BREAKPOINT／SIGTRAP，通知投递内读已销毁线程）。
/// 实测反证：`ChatReliabilityOfflineTests.testBareImagePath`
/// 挂载后经 tearDown 排空仍通过，但下一测 `testMarkPending`
/// 在其播种 save 时被崩——残留观察者存活 ≥20 秒；自家回归
/// `testRepeatedMountTeardownThenSaveDoesNotTrap` 同样在第二轮
/// 播种时崩。结论：挂载树的 @Query 观察者由框架侧持有，
/// 其寿命不受 tearDown 的拆窗＋排空控制，任何有限时长的
/// 排空都不能保证它已死；容器一死即 reset 销毁实例，之后
/// 任意一次 save 的通知投递都会唤醒它并崩溃。
///
/// 第二版改不变量：**容器一旦挂载即进入进程级持有、永不释放**。
/// 崩溃的必要条件是实例被 reset 销毁；容器不死，就没有
/// reset、没有已销毁实例可读——残留观察者再被唤醒也只读到
/// 活实例。隔离性不受损：每测仍用自己的容器（只是不析构；
/// 内存库每库仅数条线程，测试进程的泄漏量可忽略；文件库
/// 落临时目录，随 runner 清理）。
///
/// 用法：挂载即 `retain(_:)`；tearDown 先拆窗再 `release()`
/// （只清实例引用、不析构容器）。未 retain 时 release 为空操作。
/// `release()` 保留 async 签名（调用点已是 `await`），内部不再悬停。
///
/// 第三轮兜底（2026-11-15）：目标内所有建 ChatThread 容器的类
/// 一并收编——含不挂载视图的六类（BasicsFixBatch／BasicsStopgap／
/// DeleteCloseout／DeleteOptimistic／GoalQuoteEntry／TraceEcho），
/// 不变量升级为「进程内无任何容器死亡」，使 §184 在结构上
/// 不可能（第二轮余 1 崩的来源未定位到具体类，兜底收编是最
/// 小代价的闭合）。空容器壳（TabBarFloat／HubSegments／
/// TopBarHit）仍不收编：容器里不存在 ChatThread 实例。
@MainActor
final class SwiftDataTestMount {

    /// 进程级持有：只增不减。@MainActor 隔离，无需锁。
    private static var liveContainers: [ModelContainer] = []

    private var container: ModelContainer?

    /// 挂载即持有：容器进入进程级持有。
    func retain(_ container: ModelContainer) {
        self.container = container
        Self.liveContainers.append(container)
    }

    /// 是否正持有某容器（实例引用）。
    var isRetained: Bool { container != nil }

    /// 进程级已持有容器数（回归断言用）。
    static var retainedCount: Int { liveContainers.count }

    /// 释放实例引用；容器本身留在进程级持有中、永不析构。
    func release() async {
        container = nil
    }
}
