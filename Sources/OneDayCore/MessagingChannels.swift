import Foundation

// MARK: - 消息频道直连（API 直连 B 包，2026-11-14）
//
// 频道状态与凭据编排从 channels 桥迁到 Hermes Dashboard 原生面：
//   读  GET /api/messaging/platforms
//   写  PUT /api/messaging/platforms/{id}（enabled + env + clear_env）
//       + POST /api/gateway/restart 触发即时生效
// 契约以 Hermes 0.23.0 源码为准（hermes_cli/web_routers/messaging.py
// 的 _messaging_platform_payload / update_messaging_platform）：
// 本文件是载荷解码、桥目录镜像、状态口径映射与凭据 env 编排的
// 纯逻辑层，网络动作在 HermesClient 与 ChannelStatusStore。
//
// 与桥口径的差异（如实登记）：
// 1. 桥的写前真实验活（Telegram getMe / 飞书换 token / 邮箱真实
//    登录等）直连面没有对应物——Dashboard 官方流程同样是先落盘、
//    再由状态面与 /test 验连接；本层只保留格式校验，验活改由
//    保存后状态回读呈现（connected / error + error_message）。
// 2. sessionCount 无原生来源（桥数 state.db 会话表）：全仓无消费
//    方（2026-11-14 grep 实证），映射恒 0。
// 3. needsIdentity 由 env_vars 中 *_ALLOWED_USERS 的 is_set 推导
//    （桥的 identity_env 口径与目录逐家一致）。

// MARK: - Dashboard 载荷

/// GET /api/messaging/platforms 回执（只解 App 要用的字段，
/// 其余键忽略：name/description/docs_url/error_code/updated_at/
/// home_channel/relay_* 等呈现层不需要）
public struct MessagingPlatformsResponse: Decodable, Sendable {
    public let platforms: [MessagingPlatformEntry]

    public init(platforms: [MessagingPlatformEntry]) {
        self.platforms = platforms
    }
}

/// 单个平台的 Dashboard 状态载荷（字段名以 0.23.0 源码
/// _messaging_platform_payload 的输出键为准）
public struct MessagingPlatformEntry: Decodable, Sendable {
    public let id: String
    public let enabled: Bool
    public let configured: Bool
    public let gatewayRunning: Bool
    /// disabled / not_configured / pending_restart / 网关运行态
    /// 原值（connected / error / fatal / …）/ startup_failed /
    /// gateway_stopped
    public let state: String
    public let errorMessage: String?
    public let envVars: [MessagingEnvVar]

    public init(
        id: String, enabled: Bool, configured: Bool,
        gatewayRunning: Bool, state: String,
        errorMessage: String?, envVars: [MessagingEnvVar]
    ) {
        self.id = id
        self.enabled = enabled
        self.configured = configured
        self.gatewayRunning = gatewayRunning
        self.state = state
        self.errorMessage = errorMessage
        self.envVars = envVars
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, configured, state
        case gatewayRunning = "gateway_running"
        case errorMessage = "error_message"
        case envVars = "env_vars"
    }
}

/// env 键的存在性行（值永不下发：非列表型键 value 恒 null，
/// redacted_value 只是掩码预览，本层不解）
public struct MessagingEnvVar: Decodable, Sendable {
    public let key: String
    public let required: Bool
    public let isSet: Bool

    public init(key: String, required: Bool, isSet: Bool) {
        self.key = key
        self.required = required
        self.isSet = isSet
    }

    private enum CodingKeys: String, CodingKey {
        case key, required
        case isSet = "is_set"
    }
}

// MARK: - 平台目录（桥 PLATFORMS 表的镜像）

/// 频道目录：与伴生 channels_bridge 的 PLATFORMS 表逐项同构
/// （字段名是 App 表单键、env 是网关自家变量名）。kind/open 是
/// 产品面数据（哪些平台给配、怎么配），Dashboard 目录不带，
/// 只能留在客户端目录里。
public enum MessagingChannelCatalog {

    public struct FieldSpec: Sendable, Equatable {
        public let key: String
        public let env: String
        public let required: Bool

        public init(key: String, env: String, required: Bool) {
            self.key = key
            self.env = env
            self.required = required
        }
    }

    public struct PlatformSpec: Sendable, Equatable {
        public let id: String
        /// token | qr | frozen
        public let kind: String
        public let open: Bool
        public let fields: [FieldSpec]
        public let identityEnv: String?

        public init(
            id: String, kind: String, open: Bool,
            fields: [FieldSpec], identityEnv: String?
        ) {
            self.id = id
            self.kind = kind
            self.open = open
            self.fields = fields
            self.identityEnv = identityEnv
        }

        public func field(_ key: String) -> FieldSpec? {
            fields.first { $0.key == key }
        }
    }

    private static func f(
        _ key: String, _ env: String, _ required: Bool = false
    ) -> FieldSpec {
        FieldSpec(key: key, env: env, required: required)
    }

    public static let platforms: [PlatformSpec] = [
        PlatformSpec(
            id: "telegram", kind: "token", open: true,
            fields: [
                f("botToken", "TELEGRAM_BOT_TOKEN", true),
                f("allowedUsers", "TELEGRAM_ALLOWED_USERS"),
            ],
            identityEnv: "TELEGRAM_ALLOWED_USERS"),
        PlatformSpec(
            id: "whatsapp", kind: "qr", open: true,
            fields: [],
            identityEnv: "WHATSAPP_ALLOWED_USERS"),
        PlatformSpec(
            id: "feishu", kind: "token", open: true,
            fields: [
                f("appId", "FEISHU_APP_ID", true),
                f("appSecret", "FEISHU_APP_SECRET", true),
                f("allowedUsers", "FEISHU_ALLOWED_USERS"),
            ],
            identityEnv: "FEISHU_ALLOWED_USERS"),
        PlatformSpec(
            id: "dingtalk", kind: "token", open: true,
            fields: [
                f("clientId", "DINGTALK_CLIENT_ID", true),
                f("clientSecret", "DINGTALK_CLIENT_SECRET", true),
                f("allowedUsers", "DINGTALK_ALLOWED_USERS"),
            ],
            identityEnv: "DINGTALK_ALLOWED_USERS"),
        PlatformSpec(
            id: "qqbot", kind: "token", open: true,
            fields: [
                f("appId", "QQ_APP_ID", true),
                f("clientSecret", "QQ_CLIENT_SECRET", true),
                f("allowedUsers", "QQ_ALLOWED_USERS"),
            ],
            identityEnv: "QQ_ALLOWED_USERS"),
        PlatformSpec(
            id: "discord", kind: "token", open: true,
            fields: [
                f("botToken", "DISCORD_BOT_TOKEN", true),
                f("allowedUsers", "DISCORD_ALLOWED_USERS"),
            ],
            identityEnv: "DISCORD_ALLOWED_USERS"),
        PlatformSpec(
            id: "slack", kind: "token", open: true,
            fields: [
                f("botToken", "SLACK_BOT_TOKEN", true),
                f("appToken", "SLACK_APP_TOKEN", true),
                f("allowedUsers", "SLACK_ALLOWED_USERS"),
            ],
            identityEnv: "SLACK_ALLOWED_USERS"),
        PlatformSpec(
            id: "email", kind: "token", open: true,
            fields: [
                f("address", "EMAIL_ADDRESS", true),
                f("password", "EMAIL_PASSWORD", true),
                f("imapHost", "EMAIL_IMAP_HOST", true),
                f("imapPort", "EMAIL_IMAP_PORT"),
                f("smtpHost", "EMAIL_SMTP_HOST", true),
                f("smtpPort", "EMAIL_SMTP_PORT"),
            ],
            identityEnv: "EMAIL_ALLOWED_USERS"),
        PlatformSpec(
            id: "line", kind: "token", open: false,
            fields: [
                f("channelSecret", "LINE_CHANNEL_SECRET", true),
                f("channelAccessToken", "LINE_CHANNEL_ACCESS_TOKEN", true),
            ],
            identityEnv: nil),
        PlatformSpec(
            id: "matrix", kind: "token", open: false,
            fields: [
                f("homeserver", "MATRIX_HOMESERVER", true),
                f("accessToken", "MATRIX_ACCESS_TOKEN", true),
                f("allowedUsers", "MATRIX_ALLOWED_USERS"),
            ],
            identityEnv: "MATRIX_ALLOWED_USERS"),
        PlatformSpec(
            id: "signal", kind: "token", open: false,
            fields: [
                f("account", "SIGNAL_ACCOUNT", true),
                f("allowedUsers", "SIGNAL_ALLOWED_USERS"),
            ],
            identityEnv: "SIGNAL_ALLOWED_USERS"),
        PlatformSpec(
            id: "whatsapp_cloud", kind: "token", open: false,
            fields: [
                f("accessToken", "WHATSAPP_CLOUD_ACCESS_TOKEN", true),
                f("phoneNumberId", "WHATSAPP_CLOUD_PHONE_NUMBER_ID", true),
                f("appSecret", "WHATSAPP_CLOUD_APP_SECRET", true),
            ],
            identityEnv: nil),
        PlatformSpec(
            id: "yuanbao", kind: "token", open: false,
            fields: [], identityEnv: nil),
        PlatformSpec(
            id: "wecom", kind: "token", open: false,
            fields: [], identityEnv: nil),
        PlatformSpec(
            id: "weixin", kind: "frozen", open: false,
            fields: [], identityEnv: nil),
    ]

    /// 状态列表顺序（与桥 STATUS_ORDER 一致）
    public static let statusOrder: [String] = platforms.map(\.id)

    public static func spec(for id: String) -> PlatformSpec? {
        platforms.first { $0.id == id }
    }
}

// MARK: - 状态映射（Dashboard 载荷 -> App 频道状态口径）

/// App 频道状态快照：与桥回执 ChannelPlatformStatus 同形，
/// 由 ChannelStatusStore 逐字段转交，呈现层零改
public struct ChannelStatusSnapshot: Sendable, Equatable {
    public let platform: String
    public let kind: String
    public let open: Bool
    public let configured: Bool
    public let connected: Bool
    public let needsIdentity: Bool
    /// not_configured / pending_restart / connected / error /
    /// frozen（与桥状态词汇严格一致）
    public let state: String
    /// 直连面无此数据源（桥数 state.db），全仓无消费方，恒 0
    public let sessionCount: Int
    public let message: String?

    public init(
        platform: String, kind: String, open: Bool,
        configured: Bool, connected: Bool, needsIdentity: Bool,
        state: String, sessionCount: Int, message: String?
    ) {
        self.platform = platform
        self.kind = kind
        self.open = open
        self.configured = configured
        self.connected = connected
        self.needsIdentity = needsIdentity
        self.state = state
        self.sessionCount = sessionCount
        self.message = message
    }
}

public enum MessagingStatusMapping {

    /// 桥对 error_message 的截断口径
    private static let messageCap = 300

    /// 全量映射：只出产品目录内的平台（Dashboard 目录里的
    /// sms/mattermost/api_server 等非产品面平台不进 App 列表），
    /// 顺序按目录 statusOrder；载荷缺行的平台合成未配对行
    /// （与桥对每个 STATUS_ORDER 平台必出行的口径一致）
    public static func map(
        _ response: MessagingPlatformsResponse
    ) -> (gatewayRunning: Bool, statuses: [ChannelStatusSnapshot]) {
        let byID = Dictionary(
            uniqueKeysWithValues: response.platforms.map { ($0.id, $0) }
        )
        let statuses = MessagingChannelCatalog.platforms.map { spec in
            map(spec: spec, entry: byID[spec.id])
        }
        // 网关存活是全局判定（源码 resolve_gateway_liveness），
        // 任一载荷行同值；无行时按未运行
        let running = response.platforms.first?.gatewayRunning ?? false
        return (running, statuses)
    }

    private static func map(
        spec: MessagingChannelCatalog.PlatformSpec,
        entry: MessagingPlatformEntry?
    ) -> ChannelStatusSnapshot {
        if spec.kind == "frozen" {
            // 微信个人号冻结行：产品拍板口径，不看载荷
            return ChannelStatusSnapshot(
                platform: spec.id, kind: spec.kind, open: spec.open,
                configured: false, connected: false,
                needsIdentity: false, state: "frozen",
                sessionCount: 0,
                message: L10n.string("微信个人号暂不可用")
            )
        }
        guard let entry else {
            return ChannelStatusSnapshot(
                platform: spec.id, kind: spec.kind, open: spec.open,
                configured: false, connected: false,
                needsIdentity: false, state: "not_configured",
                sessionCount: 0, message: nil
            )
        }
        // 桥口径：configured = 必填 env 齐备 且 平台已启用；
        // Dashboard 的 configured 只看 env，enabled 单列，故合取
        let configured = entry.configured && entry.enabled
        let connected = entry.gatewayRunning && entry.state == "connected"
        let state: String
        if !configured {
            state = "not_configured"
        } else if connected {
            state = "connected"
        } else if ["error", "fatal", "startup_failed"].contains(entry.state)
            || (entry.gatewayRunning && entry.errorMessage != nil) {
            // 与桥的错误判定同构：运行态报错集，或网关在跑且
            // 带回错误原文。startup_failed 是网关停机后保留的
            // 上次失败裁决，桥读 gateway_state 原值同归 error
            state = "error"
        } else {
            state = "pending_restart"
        }
        var needsIdentity = false
        if configured, let identityEnv = spec.identityEnv {
            let isSet = entry.envVars
                .first { $0.key == identityEnv }?.isSet ?? false
            needsIdentity = !isSet
        }
        return ChannelStatusSnapshot(
            platform: spec.id, kind: spec.kind, open: spec.open,
            configured: configured, connected: connected,
            needsIdentity: needsIdentity, state: state,
            sessionCount: 0,
            message: state == "error"
                ? entry.errorMessage.map { String($0.prefix(messageCap)) }
                : nil
        )
    }
}

// MARK: - 凭据编排（表单字段 -> PUT env，桥 _set_credentials 的平移）

/// 编排失败：message 是给用户看的人话（与桥 400 文案逐句一致，
/// 经 L10n 目录取词）
public struct MessagingComposeError: Error, Sendable, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public enum MessagingCredentialsComposer {

    public struct Composed: Sendable, Equatable {
        public let env: [String: String]
        public let clearEnv: [String]

        public init(env: [String: String], clearEnv: [String]) {
            self.env = env
            self.clearEnv = clearEnv
        }
    }

    private static let telegramTokenPattern =
        #"^\d{5,16}:[A-Za-z0-9_-]{30,50}$"#
    private static let numericIDPattern = #"^\d+$"#
    private static let feishuIDPattern = #"^(ou|on)_[A-Za-z0-9_-]+$"#
    private static let emailPattern =
        #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
    private static let hostPattern =
        #"^(?=.{1,253}$)[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$"#

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    /// 表单字段 + 顶层白名单 -> PUT 的 env/clear_env。
    /// 校验口径与桥 _set_credentials + _validate_value 逐项平移
    /// （桥的写前真实验活不在此列，见文件头差异登记 1）。
    public static func compose(
        platform: String,
        fields: [String: String],
        allowedUserIds: [String]?
    ) throws -> Composed {
        guard let spec = MessagingChannelCatalog.spec(for: platform) else {
            throw MessagingComposeError(
                message: L10n.string("不认识的平台"))
        }
        if spec.kind == "frozen" {
            throw MessagingComposeError(
                message: L10n.string("微信个人号暂不可用，不能配对"))
        }
        if spec.kind == "qr" {
            throw MessagingComposeError(
                message: L10n.string("这个平台是扫码配对，不在这里填钥匙"))
        }
        if !spec.open {
            throw MessagingComposeError(
                message: L10n.string("这个平台还没开放配对，请等后续更新"))
        }
        if fields.isEmpty {
            throw MessagingComposeError(
                message: L10n.string("没有收到钥匙"))
        }
        let unknown = fields.keys.filter { spec.field($0) == nil }
        if !unknown.isEmpty {
            throw MessagingComposeError(message: L10n.format(
                "不认识的项：%@", unknown.sorted().joined(separator: ", ")
            ))
        }
        let fieldByKey = Dictionary(
            uniqueKeysWithValues: spec.fields.map { ($0.key, $0) }
        )
        var cleaned: [String: String] = [:]
        for (key, raw) in fields {
            guard let field = fieldByKey[key] else { continue }
            let value = raw.trimmingCharacters(
                in: .whitespacesAndNewlines)
            if value.isEmpty {
                // 必填空缺走 missing 口径；可选字段空值等于没填
                // （表单会把未填的可选项一并送来，桥时代靠表单
                // 守门，直连后在此收敛为「不送」）
                if field.required {
                    throw MessagingComposeError(
                        message: L10n.string("还差必填的钥匙"))
                }
                continue
            }
            try validateValue(platform: platform, field: key, value: value)
            cleaned[key] = value
        }
        let missing = spec.fields.filter {
            $0.required && cleaned[$0.key] == nil
        }
        if !missing.isEmpty {
            throw MessagingComposeError(
                message: L10n.string("还差必填的钥匙"))
        }
        var allowedEnvValue: String?
        if let allowedUserIds {
            if allowedUserIds.isEmpty {
                throw MessagingComposeError(message: L10n.string(
                    "允许的使用者名单格式不对"))
            }
            var ids: [String] = []
            for raw in allowedUserIds {
                let text = raw.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if platform == "email" {
                    if !matches(emailPattern, text) {
                        throw MessagingComposeError(message: L10n.string(
                            "允许发信的名单里有格式不对的邮箱地址"))
                    }
                } else if platform == "feishu" {
                    if !matches(feishuIDPattern, text) {
                        throw MessagingComposeError(message: L10n.string(
                            "飞书的使用者 ID 形如 ou_ 开头的一串字符（open_id），请确认后重新填写"))
                    }
                } else if !matches(numericIDPattern, text) {
                    throw MessagingComposeError(
                        message: L10n.string("Telegram 的使用者 ID 是纯数字"))
                }
                if !ids.contains(text) {
                    ids.append(text)
                }
            }
            allowedEnvValue = ids.joined(separator: ",")
        }
        if platform == "email", allowedEnvValue == nil {
            throw MessagingComposeError(message: L10n.string(
                "还差一项：请填允许给助手发信的邮箱地址，只有名单里的人发来的信会被处理"))
        }
        var env: [String: String] = [:]
        for (key, value) in cleaned {
            if let field = fieldByKey[key] {
                env[field.env] = value
            }
        }
        var clearEnv: [String] = []
        if let allowedEnvValue, let identityEnv = spec.identityEnv {
            env[identityEnv] = allowedEnvValue
        }
        if platform == "feishu" {
            // 桥钉死口径平移：长连接（websocket）投递＋从不
            // allow-all，与飞书适配器自己的设置向导同值
            env["FEISHU_CONNECTION_MODE"] = "websocket"
            env["FEISHU_ALLOW_ALL_USERS"] = "false"
        }
        if platform == "email" {
            // 桥的 preset 推导平移（App 从不送 preset，桥按
            // 域名推导）：gmail 钉严格 authserv 校验，其余走
            // from-header 信任＋白名单（必填已在上方守住）；
            // EMAIL_ALLOW_ALL_USERS 永远清除
            let address = cleaned["address"] ?? ""
            let domain = address.split(separator: "@").last
                .map { $0.lowercased() } ?? ""
            clearEnv.append("EMAIL_ALLOW_ALL_USERS")
            if domain == "gmail.com" || domain == "googlemail.com" {
                env["EMAIL_AUTHSERV_ID"] = "mx.google.com"
                clearEnv.append("EMAIL_TRUST_FROM_HEADER")
            } else {
                env["EMAIL_TRUST_FROM_HEADER"] = "true"
                clearEnv.append("EMAIL_AUTHSERV_ID")
            }
        }
        return Composed(env: env, clearEnv: clearEnv)
    }

    /// 单字段格式校验（桥 _validate_value 平移）
    private static func validateValue(
        platform: String, field: String, value: String
    ) throws {
        if value.count > 512
            || value.unicodeScalars.contains(where: { $0.value < 32 }) {
            throw MessagingComposeError(
                message: L10n.string("钥匙格式不对"))
        }
        if platform == "telegram", field == "botToken" {
            if !matches(telegramTokenPattern, value) {
                throw MessagingComposeError(message: L10n.string(
                    "这把钥匙的格式不对：Telegram 的连接钥匙形如一串数字、冒号、再一串字母数字，请从 @BotFather 处完整复制"))
            }
        }
        if platform == "email" {
            if field == "address", !matches(emailPattern, value) {
                throw MessagingComposeError(message: L10n.string(
                    "邮箱地址的格式不对，请填完整的邮箱地址"))
            }
            if field == "imapHost" || field == "smtpHost" {
                if !matches(hostPattern, value) {
                    throw MessagingComposeError(
                        message: L10n.string("服务器地址的格式不对"))
                }
            }
            if field == "imapPort" || field == "smtpPort" {
                // 桥口径是 isdigit + 范围（Int() 会放行 "+12"
                // 这类桥不收的形态，故先验纯数字）
                let port = Int(value)
                if !matches(numericIDPattern, value)
                    || port == nil || !(1...65535).contains(port!) {
                    throw MessagingComposeError(message: L10n.string(
                        "端口号不对，应是 1 到 65535 之间的数字"))
                }
            }
        }
    }
}
