import OneDayCore
import UserNotifications

/// 通知中心委托（总表 138，DESIGN §397）：此前全仓无
/// UNUserNotificationCenterDelegate——App 在前台时到达
/// 的本地通知被系统静默（无横幅／无声音，连通知中心列
/// 表都不进），点按已送达通知也没有任何落点处理。本
/// 委托补这两件本地通知基建（与远程推送无关、不依赖
/// 付费账号）：
/// ① willPresent：自家通知前台也呈现（横幅／列表／声
///    音）；但 passive 中断级只入列表不弹横幅——与
///    §385 分级提醒的「静默入盒」级共存，按 content
///    的 interruptionLevel 判，不依赖对方内部实现；
/// ② didReceive：userInfo 经 Core 解析器成路由（批
///    4b payload 契约），交转接盒转 PushRegistration-
///    Store 落点；本地通知不带路由键，一律 .none＝只
///    打开 App，不假装有落点。
/// 回调均为 nonisolated 系统域入口：只碰 Sendable 值与
/// 纯函数解析，不碰任何 actor 隔离状态（回调隔离铁律）。
/// 无可变状态（两回调只读入参、只转交 Sendable 值），
/// 故 @unchecked Sendable 成立——单例靠本类静态持有
/// 强引用（center.delegate 是弱引用，不持有会失效）
final class NotificationCenterDelegate: NSObject,
    UNUserNotificationCenterDelegate, @unchecked Sendable {

    static let shared = NotificationCenterDelegate()

    /// 安装点只有一个：OneDayApp.init（任何通知到达前）
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.interruptionLevel
            == .passive {
            return [.list]
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = PushNotificationRouteResolver.resolve(
            userInfo: response.notification.request.content.userInfo
        )
        PushRegistrationCenter.deliver(route: route)
    }
}
