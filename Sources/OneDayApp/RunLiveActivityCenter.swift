import ActivityKit
import Foundation
import OneDayCore

/// 实时活动中心（总表 163，DESIGN §385.3）：聊天一
/// 轮运行的进行态上锁屏与灵动岛——只做 App 内发起
/// 形态（本地 request/update/end），不做 APNs 远程
/// 更新（付费账号搁置在案）。单点管理、全程尽力而
/// 为：开关关／系统未开实时活动／系统拒收，全部静
/// 默跳过，绝不挡运行本体。可用性只读
/// ActivityAuthorizationInfo 同步状态，本中心不发
/// 任何权限请求。
/// 形态口径（Swift 6 区域隔离）：Activity 非
/// Sendable，存属性取出即断开区域、异步调用报
/// 「sending risks data races」——本中心只存活动
/// id（String），update/end 时从 Activity.activities
/// 现查现调（现取的值在本区域内、直调合法，已实测）。
@MainActor
final class RunLiveActivityCenter {

    static let shared = RunLiveActivityCenter()

    /// 设置页总开关键（与 NotificationSettingsView
    /// 的 @AppStorage 同键）
    static let enabledKey = "notify.liveActivity.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey)
            as? Bool ?? true
    }

    /// 任务名截断口径：锁屏一行放不下长标题，40 字封顶
    static let taskNameLimit = 40

    private var currentActivityID: String?
    private var currentTaskName: String?
    private var currentPhase: RunLiveActivityAttributes.Phase?

    private init() {}

    private func currentActivity()
        -> Activity<RunLiveActivityAttributes>? {
        guard let currentActivityID else { return nil }
        return Activity<RunLiveActivityAttributes>.activities
            .first { $0.id == currentActivityID }
    }

    /// 起跑沿：一轮开始时调用。已有同名活动在跑则
    /// 只校阶段；异名活动先收旧再起新；本进程未跟
    /// 踪的存量活动（上次进程被杀留置）一并收掉，
    /// 不许双活动并存
    func begin(taskName rawTaskName: String) async {
        guard Self.isEnabled else { return }
        guard ActivityAuthorizationInfo()
            .areActivitiesEnabled else { return }
        let taskName = Self.clippedTaskName(rawTaskName)
        if currentActivity() != nil,
           currentTaskName == taskName {
            await update(phase: .preparing)
            return
        }
        await endImmediately()
        for stale in Activity<RunLiveActivityAttributes>
            .activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        let state = RunLiveActivityAttributes.ContentState(
            phase: .preparing, phaseStartedAt: Date()
        )
        do {
            let created = try Activity.request(
                attributes: RunLiveActivityAttributes(
                    taskName: taskName
                ),
                content: ActivityContent(
                    state: state,
                    staleDate: Date().addingTimeInterval(600)
                ),
                pushType: nil
            )
            currentActivityID = created.id
            currentTaskName = taskName
            currentPhase = .preparing
        } catch {
            currentActivityID = nil
            currentTaskName = nil
            currentPhase = nil
        }
    }

    /// 阶段推进（流式上升沿切生成中）：阶段未变不重发。
    /// 活动对象只许以 for 迭代形态现取现调（经函数/
    /// 闭包返回值即跨区域翻红——区域隔离实测口径）
    func update(phase: RunLiveActivityAttributes.Phase) async {
        guard let currentActivityID,
              currentPhase != phase else { return }
        for activity in Activity<RunLiveActivityAttributes>
            .activities where activity.id == currentActivityID {
            currentPhase = phase
            let state = RunLiveActivityAttributes.ContentState(
                phase: phase, phaseStartedAt: Date()
            )
            await activity.update(
                ActivityContent(
                    state: state,
                    staleDate: Date().addingTimeInterval(600)
                )
            )
            return
        }
    }

    /// 退出沿：一轮落定（含失败／取消一切出口）即
    /// 收——dismissalPolicy .immediate，任务结束自
    /// 动收不在锁屏留置
    func end() async {
        await endImmediately()
    }

    private func endImmediately() async {
        let closingID = currentActivityID
        currentActivityID = nil
        currentTaskName = nil
        currentPhase = nil
        guard let closingID else { return }
        for activity in Activity<RunLiveActivityAttributes>
            .activities where activity.id == closingID {
            await activity.end(nil, dismissalPolicy: .immediate)
            return
        }
    }

    static func clippedTaskName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return "OneDay" }
        return String(trimmed.prefix(taskNameLimit))
    }
}
