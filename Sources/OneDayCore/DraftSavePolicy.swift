import Foundation

/// 草稿落盘点政策（基础止血包 P3）：旧口径草稿只在
/// 「切换线程」一刻落盘——切后台接电话、进程被系统
/// 杀掉（都不触发切线程）时，当前线程打了一半的字
/// 就此丢失。本政策钉死落盘点集合的判定：离开活动
/// 态（切后台/被杀前最后的机会）且有当前线程、线
/// 程仍在名单内（防给已删线程留死键，与切线程落盘
/// 的既有纪律同款），即落盘。
public enum DraftSavePolicy {

    /// scenePhase 离开 .active 时是否应把当前输入
    /// 存回当前线程的草稿
    public static func shouldSaveOnLeavingActive(
        hasCurrentThread: Bool, threadStillExists: Bool
    ) -> Bool {
        hasCurrentThread && threadStillExists
    }
}
