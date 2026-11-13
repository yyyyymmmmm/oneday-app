import Foundation
import OneDayCore

/// 频道配对状态店（频道扩展一期）：抽屉频道行与配
/// 对引导页共用的状态读口——状态只来自伴生频道桥
/// 的回读（网关自家记录），读不到就报读不到，绝不
/// 在本地猜一个状态出来。演示模式给本地合成态
/// （Telegram、飞书均未配对，与真机零接入基线同
/// 形），不发网络请求。
@MainActor
@Observable
final class ChannelStatusStore {
    private(set) var statuses: [String: ChannelPlatformStatus] = [:]
    private(set) var gatewayRunning = false
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let client = ChannelsBridgeClient()

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
        guard let config = appState.config else {
            loadError = L10n.string("还没有连上服务器")
            return
        }
        isLoading = true
        do {
            let response = try await client.status(config: config)
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
        guard let config = appState.config else {
            throw ChannelsBridgeError.failed(
                L10n.string("还没有连上服务器"))
        }
        let receipt = try await client.submitCredentials(
            config: config, platform: "telegram",
            fields: ["botToken": token],
            allowedUserIds: allowedUserIds
        )
        // 保存落定后立刻回读一次状态，让页面与抽屉行
        // 都按网关记录说话（回执的 pending 是流程态，
        // status 才是事实源）
        await load(appState: appState)
        return receipt
    }

    /// 飞书提交（二期）：字段是应用凭证两项（App ID
    /// ＋App Secret），白名单填的是 open_id——与 TG
    /// 的数字 ID 不同，校验在伴生侧按平台分型
    func submitFeishu(
        appState: AppState, appID: String, appSecret: String,
        allowedUserIds: [String]?
    ) async throws -> ChannelCredentialsReceipt {
        guard let config = appState.config else {
            throw ChannelsBridgeError.failed(
                L10n.string("还没有连上服务器"))
        }
        let receipt = try await client.submitCredentials(
            config: config, platform: "feishu",
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
    ]
}
