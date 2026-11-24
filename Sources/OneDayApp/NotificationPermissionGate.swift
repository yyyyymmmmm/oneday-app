import OneDayCore
import UIKit

/// 通知授权门（权限段模板的引擎侧，连接页引导段用）：
/// UNUserNotificationCenter 没有同步读授权状态的 API
/// （只有带回调的 getNotificationSettings，§113 已登
/// 记），故状态一律经 NotificationEngine 的异步刷新
/// 现读——先读真状态、再过 Core 的 DevicePermission-
/// Gate 铁律判定，只有未决定才发那一次请求（铁律在
/// 异步读框架上的等价落法）。请求本体复用 Notifica-
/// tionEngine.requestAccess（其内部同样先过门），本
/// 门不另立第二套请求路径。
enum NotificationPermissionGate {

    /// 现读真状态（异步刷新＋回填引擎缓存，不触发
    /// 任何请求）
    static func currentState() async -> DevicePermissionState {
        await NotificationEngine.readSystemState()
    }

    /// 唯一一次授权请求（引擎内先读真状态过门：
    /// 已决定状态原样返回、绝不重走请求回调）
    static func requestAccess() async -> DevicePermissionState {
        await NotificationEngine().requestAccess()
    }

    /// 已拒绝态的唯一出路：去系统设置里开（段内不
    /// 请求、不纠缠）
    static func openSystemSettings() {
        guard let url = URL(
            string: UIApplication.openSettingsURLString
        ) else { return }
        UIApplication.shared.open(url)
    }
}
