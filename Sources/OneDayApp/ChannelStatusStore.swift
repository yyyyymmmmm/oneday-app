import Foundation
import OneDayCore

/// 频道配对状态店（频道扩展一期）：抽屉频道行与配
/// 对引导页共用的状态读口——状态只来自伴生频道桥
/// 的回读（网关自家记录），读不到就报读不到，绝不
/// 在本地猜一个状态出来。演示模式给本地合成态
/// （Telegram 未配对、微信冻结，与真机零接入基线
/// 同形），不发网络请求。
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

    /// 邮箱提交（特殊批）：表单字段原样交伴生（验钥
    /// 在伴生侧——IMAP/SMTP 各真登录一次才落盘）；
    /// preset 标识随行，桥据此定入站信任档
    func submitEmail(
        appState: AppState, fields: [String: String],
        preset: String, allowedUserIds: [String]
    ) async throws -> ChannelCredentialsReceipt {
        guard let config = appState.config else {
            throw ChannelsBridgeError.failed(
                L10n.string("还没有连上服务器"))
        }
        let receipt = try await client.submitCredentials(
            config: config, platform: "email",
            fields: fields,
            allowedUserIds: allowedUserIds,
            preset: preset
        )
        await load(appState: appState)
        return receipt
    }

    // MARK: - 扫码配对（WhatsApp）

    /// 当前配对会话（配对层事实；平台连接状态仍看
    /// statuses，两层不混）
    private(set) var qrSession: ChannelQRSession?
    private(set) var qrError: String?

    func startQR(appState: AppState) async {
        if appState.isDemo {
            qrSession = Self.demoQRSession
            qrError = nil
            return
        }
        guard let config = appState.config else {
            qrError = L10n.string("还没有连上服务器")
            return
        }
        do {
            qrSession = try await client.qrStart(config: config)
            qrError = nil
        } catch let error as ChannelsBridgeError {
            qrError = Self.message(for: error)
        } catch {
            qrError = L10n.string("配对没能开始，请稍后再试")
        }
    }

    /// 轮询一次：会话到 connected 且伴生已启用时，
    /// 顺带回读平台状态（抽屉行与引导页按运行时
    /// 记录翻面）。返回最新会话供呈现层决定去留
    @discardableResult
    func pollQR(appState: AppState) async -> ChannelQRSession? {
        if appState.isDemo {
            return qrSession
        }
        guard let config = appState.config else { return qrSession }
        do {
            let session = try await client.qrStatus(config: config)
            qrSession = session
            qrError = nil
            if session.status == "connected" {
                await load(appState: appState)
            }
            return session
        } catch let error as ChannelsBridgeError {
            qrError = Self.message(for: error)
            return qrSession
        } catch {
            qrError = L10n.string("配对状态没读下来，请稍后再试")
            return qrSession
        }
    }

    func cancelQR(appState: AppState) async {
        defer { qrSession = nil }
        if appState.isDemo { return }
        guard let config = appState.config else { return }
        _ = try? await client.qrCancel(config: config)
    }

    /// 演示合成配对会话：等待扫码态、演示载荷（演示
    /// 模式不发网络请求，与演示状态同口径）
    static let demoQRSession = ChannelQRSession(
        platform: "whatsapp", pairingId: "demo",
        status: "waiting", qrPayload: "oneday-demo-whatsapp",
        mode: "self-chat", accountName: nil, accountPhone: nil,
        applied: false, applyError: nil, error: nil
    )

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
        "whatsapp": ChannelPlatformStatus(
            platform: "whatsapp", kind: "qr", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
        "email": ChannelPlatformStatus(
            platform: "email", kind: "token", open: true,
            configured: false, connected: false,
            needsIdentity: false, state: "not_configured",
            sessionCount: 0, message: nil
        ),
        "weixin": ChannelPlatformStatus(
            platform: "weixin", kind: "frozen", open: false,
            configured: false, connected: false,
            needsIdentity: false, state: "frozen",
            sessionCount: 0, message: nil
        ),
    ]
}
