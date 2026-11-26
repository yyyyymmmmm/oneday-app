import Foundation
import UserNotifications
import OneDayCore

/// 本地通知（棒 2，对位 M3；拟案保底段）：待批新
/// 到时发本地通知，批准类带「批准/拒绝」动作按钮，
/// 点了直调网关裁决、不必先开窗。授权口径按 HIG
/// ——不在首启索要，首次真有待批出现时才请求。
/// 通知动作的裁决走 Keychain 里的登录三件套自组
/// 客户端（通知可能在批准窗未开时到达，不依赖任
/// 何界面状态店），与端内裁决同一组端点同一语义。
final class MacNotifier: NSObject, UNUserNotificationCenterDelegate,
    @unchecked Sendable {
    static let shared = MacNotifier()

    private static let execCategory = "exec-approval"
    private static let gateCategory = "gate-approval"
    private static let seenKey = "mac.notifiedApprovalIDs.v1"

    private override init() { super.init() }

    /// App 启动时装配：分类与动作先注册、代理先就位
    /// （授权请求不在此处，等首次待批出现）
    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let execApprove = UNNotificationAction(
            identifier: "exec-once", title: "批准",
            options: []
        )
        let execDeny = UNNotificationAction(
            identifier: "exec-deny", title: "拒绝",
            options: [.destructive]
        )
        let gateApprove = UNNotificationAction(
            identifier: "gate-approve", title: "批准",
            options: []
        )
        let gateReject = UNNotificationAction(
            identifier: "gate-reject", title: "驳回",
            options: [.destructive]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.execCategory,
                actions: [execApprove, execDeny],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Self.gateCategory,
                actions: [gateApprove, gateReject],
                intentIdentifiers: []
            ),
        ])
    }

    // MARK: - 新待批检测与投递（状态轮询喂入）

    /// 轮询每轮把当前待批 id 集喂进来：新出现的才发
    /// 通知（已见集落 UserDefaults，重启不重发旧账）
    func notePending(exec: [MacExecApproval], gate: [WriteGateRecord]) {
        var seen = Set(
            UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []
        )
        var freshExec: [MacExecApproval] = []
        var freshGate: [WriteGateRecord] = []
        for record in exec where !seen.contains("exec:\(record.id)") {
            seen.insert("exec:\(record.id)")
            freshExec.append(record)
        }
        for record in gate where !seen.contains("gate:\(record.id)") {
            seen.insert("gate:\(record.id)")
            freshGate.append(record)
        }
        guard !freshExec.isEmpty || !freshGate.isEmpty else { return }
        UserDefaults.standard.set(
            Array(seen.suffix(500)), forKey: Self.seenKey
        )
        Task {
            await ensureAuthorized()
            for record in freshExec { postExec(record) }
            for record in freshGate { postGate(record) }
        }
    }

    /// 首次有待批才请求授权（HIG：在首次使用时请求）
    private func ensureAuthorized() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }
        _ = try? await center.requestAuthorization(
            options: [.alert, .badge, .sound]
        )
    }

    private func postExec(_ record: MacExecApproval) {
        let content = UNMutableNotificationContent()
        content.title = "新的待批：执行命令"
        content.body = record.description.isEmpty
            ? record.command : record.description
        content.categoryIdentifier = Self.execCategory
        content.userInfo = ["family": "exec", "id": record.id]
        content.sound = .default
        deliver(content, id: "exec-\(record.id)")
    }

    private func postGate(_ record: WriteGateRecord) {
        let content = UNMutableNotificationContent()
        content.title = "新的待批：\(ApprovalCardCopy.question(for: record))"
        content.body = ApprovalCardCopy.summaryLine(for: record)
        content.categoryIdentifier = Self.gateCategory
        content.userInfo = [
            "family": "gate",
            "id": record.id,
            "subsystem": record.subsystem.pathSegment ?? "",
        ]
        content.sound = .default
        deliver(content, id: "gate-\(record.id)")
    }

    private func deliver(
        _ content: UNMutableNotificationContent, id: String
    ) {
        let request = UNNotificationRequest(
            identifier: id, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 通知动作裁决（前台呈现＋动作回执）

    /// App 在前台时通知照样呈横幅（常驻代理口径）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let family = info["family"] as? String,
              let id = info["id"] as? String else { return }
        switch (family, response.actionIdentifier) {
        case ("exec", "exec-once"):
            await resolve { client, config, key in
                try await client.resolveApproval(
                    config: config, apiKey: key, requestID: id,
                    choice: "once", reason: nil
                )
            }
        case ("exec", "exec-deny"):
            await resolve { client, config, key in
                try await client.resolveApproval(
                    config: config, apiKey: key, requestID: id,
                    choice: "deny", reason: nil
                )
            }
        case ("gate", "gate-approve"), ("gate", "gate-reject"):
            let approve = response.actionIdentifier == "gate-approve"
            let segment = info["subsystem"] as? String ?? ""
            let subsystem = WriteGateSubsystem(
                rawValue: segment
            ) ?? .unknown
            guard subsystem != .unknown else { return }
            await resolve { client, config, key in
                _ = try await client.writeGateDecide(
                    config: config, apiKey: key,
                    subsystem: subsystem, id: id, approve: approve
                )
            }
        default:
            return  // 点通知本体：只打开 App，不裁决
        }
    }

    /// 用 Keychain 登录三件套自组客户端执行一次裁决
    /// （凭据只读 Keychain、永不落盘不进日志）
    private func resolve(
        _ action: (HermesMacClient, ServerConfig, String) async throws
            -> Void
    ) async {
        guard let base = MacKeychain.read(
                  account: MacCredentialKey.baseURL
              ),
              let key = MacKeychain.read(
                  account: MacCredentialKey.apiKey
              ),
              let config = ServerConfig(rawInput: base)
        else { return }
        _ = try? await action(HermesMacClient(), config, key)
    }
}
