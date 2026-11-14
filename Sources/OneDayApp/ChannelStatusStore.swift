import Foundation
import OneDayCore

/// 频道配对状态店（频道扩展一期）：抽屉频道行与配
/// 对引导页共用的状态读口——状态只来自网关自家记
/// 录的回读（API 直连 B 包起经 Dashboard 原生面
/// /api/messaging/platforms），读不到就报读不到，
/// 绝不在本地猜一个状态出来。演示模式给本地合成
/// 态（Telegram、飞书均未配对，与真机零接入基线
/// 同形），不发网络请求。
@MainActor
@Observable
final class ChannelStatusStore {
    private(set) var statuses: [String: ChannelPlatformStatus] = [:]
    private(set) var gatewayRunning = false
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let client = ChannelsDirectClient()

    func status(for platform: String) -> ChannelPlatformStatus? {
        statuses[platform]
    }

    func load(appState: AppState) async {
        if appState.isDemo {
            statuses = Self.demoStatuses
            gatewayRunning = true
            loadError = nil
            return
        }
        guard appState.config != nil else {
            loadError = L10n.string("还没有连上服务器")
            return
        }
        isLoading = true
        do {
            let response = try await client.status(appState: appState)
            statuses = Dictionary(
                uniqueKeysWithValues: response.platforms.map {
                    ($0.platform, $0)
                }
            )
            gatewayRunning = response.gatewayRunning
            loadError = nil
        } catch let error as ChannelsBridgeError {
            loadError = Self.message(for: error)
        } catch {
            loadError = L10n.string("频道状态没读下来，请稍后再试")
        }
        isLoading = false
    }

    func submitTelegram(
        appState: AppState, token: String, allowedUserIds: [String]?
    ) async throws -> ChannelCredentialsReceipt {
        guard appState.config != nil else {
            throw ChannelsBridgeError.failed(
                L10n.string("还没有连上服务器"))
        }
        let receipt = try await client.submitCredentials(
            appState: appState, platform: "telegram",
            fields: ["botToken": token],
            allowedUserIds: allowedUserIds
        )
        // 保存落定后立刻回读一次状态，让页面与抽屉行
        // 都按网关记录说话（回执的 pending 是流程态，
        // status 才是事实源）
        await load(appState: appState)
        return receipt
    }

    /// 通用凭据提交（二期令牌四家）：字段逐家不同、
    /// 白名单走 fields 内 allowedUsers（顶层
    /// allowedUserIds 的纯数字口径是 Telegram 专用，
    /// 钉钉员工 ID/QQ OpenID/Slack 成员 ID 均非纯数
    /// 字，见令牌批报告 §1.5）。提交后同样立刻回读
    /// 状态，事实只认 status
    func submitCredentials(
        appState: AppState, platform: String,
        fields: [String: String]
    ) async throws -> ChannelCredentialsReceipt {
        guard appState.config != nil else {
            throw ChannelsBridgeError.failed(
                L10n.string("还没有连上服务器"))
        }
        let receipt = try await client.submitCredentials(
            appState: appState, platform: platform,
            fields: fields, allowedUserIds: nil
        )
        await load(appState: appState)
        return receipt
    }

    /// 飞书提交（二期）：字段是应用凭证两项（App ID
    /// ＋App Secret），白名单填的是 open_id——与 TG
    /// 的数字 ID 不同，校验在 App 侧编排层按平台分型
    /// （OneDayCore MessagingCredentialsComposer）
    func submitFeishu(
        appState: AppState, appID: String, appSecret: String,
        allowedUserIds: [String]?
    ) async throws -> ChannelCredentialsReceipt {
        guard appState.config != nil else {
            throw ChannelsBridgeError.failed(
                L10n.string("还没有连上服务器"))
        }
        let receipt = try await client.submitCredentials(
            appState: appState, platform: "feishu",
            fields: ["appId": appID, "appSecret": appSecret],
            allowedUserIds: allowedUserIds
        )
        await load(appState: appState)
        return receipt
    }

    static func message(for error: ChannelsBridgeError) -> String {
        switch error {
        case .noKey, .unauthorized:
            return L10n.string("频道服务还没连上，请稍后再试")
        case .failed(let message):
            return message
        }
    }

    /// 演示合成态：与生产零接入基线同形
    static let demoStatuses: [String: ChannelPlatformStatus] = [
        "telegram": ChannelPlatformStatus(
            platform: "telegram", kind: "token", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
        "feishu": ChannelPlatformStatus(
            platform: "feishu", kind: "token", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
        "dingtalk": ChannelPlatformStatus(
            platform: "dingtalk", kind: "token", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
        "qqbot": ChannelPlatformStatus(
            platform: "qqbot", kind: "token", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
        "discord": ChannelPlatformStatus(
            platform: "discord", kind: "token", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
        "slack": ChannelPlatformStatus(
            platform: "slack", kind: "token", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
    ]
}
