import XCTest
@testable import OneDayCore

/// 频道直连（API 直连 B 包）：Dashboard 载荷解码、
/// 状态映射口径、凭据 env 编排与格式校验——映射/
/// 编排口径逐项对桥 channels_bridge 的既有行为
final class MessagingChannelsTests: XCTestCase {

    // MARK: - 载荷解码（0.23.0 _messaging_platform_payload 形状）

    func testPayloadDecodesSnakeCaseFields() throws {
        let json = """
        {"env_path": "/root/.hermes/.env",
         "gateway_start_command": "hermes gateway run",
         "platforms": [
           {"id": "telegram", "enabled": true, "configured": true,
            "gateway_running": true, "state": "connected",
            "error_code": null, "error_message": null,
            "env_vars": [
              {"key": "TELEGRAM_BOT_TOKEN", "required": true,
               "is_set": true, "redacted_value": "1234...cdef"},
              {"key": "TELEGRAM_ALLOWED_USERS", "required": false,
               "is_set": false, "redacted_value": null}
            ]}
         ]}
        """
        let decoded = try JSONDecoder().decode(
            MessagingPlatformsResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.platforms.count, 1)
        let entry = decoded.platforms[0]
        XCTAssertEqual(entry.id, "telegram")
        XCTAssertTrue(entry.gatewayRunning)
        XCTAssertEqual(entry.state, "connected")
        XCTAssertNil(entry.errorMessage)
        XCTAssertEqual(entry.envVars.count, 2)
        XCTAssertFalse(entry.envVars[1].isSet)
    }

    // MARK: - 状态映射

    private func entry(
        _ id: String, enabled: Bool = true, configured: Bool = true,
        running: Bool = true, state: String = "connected",
        error: String? = nil, envVars: [MessagingEnvVar] = []
    ) -> MessagingPlatformEntry {
        MessagingPlatformEntry(
            id: id, enabled: enabled, configured: configured,
            gatewayRunning: running, state: state,
            errorMessage: error, envVars: envVars
        )
    }

    func testConnectedMappingAndIdentityFlag() {
        let response = MessagingPlatformsResponse(platforms: [
            entry("telegram", envVars: [
                MessagingEnvVar(
                    key: "TELEGRAM_ALLOWED_USERS",
                    required: false, isSet: false),
            ]),
        ])
        let mapped = MessagingStatusMapping.map(response)
        XCTAssertTrue(mapped.gatewayRunning)
        let telegram = mapped.statuses.first { $0.platform == "telegram" }
        XCTAssertEqual(telegram?.state, "connected")
        XCTAssertEqual(telegram?.configured, true)
        XCTAssertEqual(telegram?.connected, true)
        // 已配对但白名单没填：needsIdentity（桥 identity 口径）
        XCTAssertEqual(telegram?.needsIdentity, true)
        XCTAssertEqual(telegram?.sessionCount, 0)
    }

    func testDisabledPlatformIsNotConfigured() {
        // env 齐备但平台被停用：桥口径 configured=false
        let response = MessagingPlatformsResponse(platforms: [
            entry("feishu", enabled: false, state: "disabled"),
        ])
        let mapped = MessagingStatusMapping.map(response)
        let feishu = mapped.statuses.first { $0.platform == "feishu" }
        XCTAssertEqual(feishu?.configured, false)
        XCTAssertEqual(feishu?.state, "not_configured")
    }

    func testErrorStatesCarryMessage() {
        let response = MessagingPlatformsResponse(platforms: [
            entry("telegram", state: "error", error: "unauthorized"),
            entry("feishu", running: false,
                  state: "startup_failed", error: "boom"),
        ])
        let mapped = MessagingStatusMapping.map(response)
        let telegram = mapped.statuses.first { $0.platform == "telegram" }
        XCTAssertEqual(telegram?.state, "error")
        XCTAssertEqual(telegram?.message, "unauthorized")
        // 网关停机但保留上次失败裁决：桥读原值同归 error
        let feishu = mapped.statuses.first { $0.platform == "feishu" }
        XCTAssertEqual(feishu?.state, "error")
    }

    func testConfiguredButGatewayDownIsPendingRestart() {
        let response = MessagingPlatformsResponse(platforms: [
            entry("slack", running: false, state: "gateway_stopped"),
        ])
        let mapped = MessagingStatusMapping.map(response)
        XCTAssertFalse(mapped.gatewayRunning)
        let slack = mapped.statuses.first { $0.platform == "slack" }
        XCTAssertEqual(slack?.state, "pending_restart")
        XCTAssertNil(slack?.message)
    }

    func testMissingPlatformSynthesizedAndOrderFollowsCatalog() {
        let response = MessagingPlatformsResponse(platforms: [
            entry("sms"),  // 非产品目录平台：不进 App 列表
            entry("telegram"),
        ])
        let mapped = MessagingStatusMapping.map(response)
        XCTAssertEqual(
            mapped.statuses.map(\.platform),
            MessagingChannelCatalog.statusOrder
        )
        XCTAssertFalse(mapped.statuses.contains { $0.platform == "sms" })
        let email = mapped.statuses.first { $0.platform == "email" }
        XCTAssertEqual(email?.state, "not_configured")
        XCTAssertEqual(email?.configured, false)
        // 微信冻结行恒在（产品拍板口径）
        let weixin = mapped.statuses.first { $0.platform == "weixin" }
        XCTAssertEqual(weixin?.state, "frozen")
        XCTAssertEqual(weixin?.kind, "frozen")
    }

    // MARK: - 凭据编排

    private let telegramToken = "123456789:AAEaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    func testTelegramCompose() throws {
        let composed = try MessagingCredentialsComposer.compose(
            platform: "telegram",
            fields: ["botToken": telegramToken],
            allowedUserIds: ["123", "456", "123"]
        )
        XCTAssertEqual(composed.env["TELEGRAM_BOT_TOKEN"], telegramToken)
        // 去重＋逗号拼接（桥口径）
        XCTAssertEqual(composed.env["TELEGRAM_ALLOWED_USERS"], "123,456")
        XCTAssertTrue(composed.clearEnv.isEmpty)
    }

    func testTelegramRejectsBadTokenShape() {
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "telegram",
            fields: ["botToken": "not-a-token"],
            allowedUserIds: nil
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("这把钥匙的格式不对：Telegram 的连接钥匙形如一串数字、冒号、再一串字母数字，请从 @BotFather 处完整复制")
            )
        }
    }

    func testTelegramRejectsNonNumericAllowedID() {
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "telegram",
            fields: ["botToken": telegramToken],
            allowedUserIds: ["ou_abc"]
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("Telegram 的使用者 ID 是纯数字")
            )
        }
    }

    func testFeishuComposePinsConnectionMode() throws {
        let composed = try MessagingCredentialsComposer.compose(
            platform: "feishu",
            fields: ["appId": "cli_x", "appSecret": "sec"],
            allowedUserIds: ["ou_abc123"]
        )
        XCTAssertEqual(composed.env["FEISHU_APP_ID"], "cli_x")
        XCTAssertEqual(composed.env["FEISHU_ALLOWED_USERS"], "ou_abc123")
        // 桥钉死口径：长连接＋从不 allow-all
        XCTAssertEqual(composed.env["FEISHU_CONNECTION_MODE"], "websocket")
        XCTAssertEqual(composed.env["FEISHU_ALLOW_ALL_USERS"], "false")
    }

    func testFeishuRejectsNumericAllowedID() {
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "feishu",
            fields: ["appId": "cli_x", "appSecret": "sec"],
            allowedUserIds: ["12345"]
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("飞书的使用者 ID 形如 ou_ 开头的一串字符（open_id），请确认后重新填写")
            )
        }
    }

    func testGenericFieldsAllowedUsersMapsToIdentityEnv() throws {
        let composed = try MessagingCredentialsComposer.compose(
            platform: "dingtalk",
            fields: [
                "clientId": "ding_x", "clientSecret": "sec",
                "allowedUsers": "staff-1, staff-2",
            ],
            allowedUserIds: nil
        )
        XCTAssertEqual(composed.env["DINGTALK_CLIENT_ID"], "ding_x")
        XCTAssertEqual(
            composed.env["DINGTALK_ALLOWED_USERS"], "staff-1, staff-2")
    }

    func testEmailGmailPreset() throws {
        let composed = try MessagingCredentialsComposer.compose(
            platform: "email",
            fields: [
                "address": "me@gmail.com", "password": "pw",
                "imapHost": "imap.gmail.com", "smtpHost": "smtp.gmail.com",
            ],
            allowedUserIds: ["boss@example.com"]
        )
        XCTAssertEqual(composed.env["EMAIL_AUTHSERV_ID"], "mx.google.com")
        XCTAssertEqual(composed.env["EMAIL_ALLOWED_USERS"], "boss@example.com")
        XCTAssertTrue(composed.clearEnv.contains("EMAIL_TRUST_FROM_HEADER"))
        XCTAssertTrue(composed.clearEnv.contains("EMAIL_ALLOW_ALL_USERS"))
        XCTAssertNil(composed.env["EMAIL_TRUST_FROM_HEADER"])
    }

    func testEmailCustomDomainPreset() throws {
        let composed = try MessagingCredentialsComposer.compose(
            platform: "email",
            fields: [
                "address": "me@corp.example", "password": "pw",
                "imapHost": "imap.corp.example", "imapPort": "993",
                "smtpHost": "smtp.corp.example",
            ],
            allowedUserIds: ["boss@corp.example"]
        )
        XCTAssertEqual(composed.env["EMAIL_TRUST_FROM_HEADER"], "true")
        XCTAssertTrue(composed.clearEnv.contains("EMAIL_AUTHSERV_ID"))
        XCTAssertEqual(composed.env["EMAIL_IMAP_PORT"], "993")
    }

    func testEmailRequiresAllowlist() {
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "email",
            fields: [
                "address": "me@gmail.com", "password": "pw",
                "imapHost": "imap.gmail.com", "smtpHost": "smtp.gmail.com",
            ],
            allowedUserIds: nil
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("还差一项：请填允许给助手发信的邮箱地址，只有名单里的人发来的信会被处理")
            )
        }
    }

    func testEmailRejectsBadPort() {
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "email",
            fields: [
                "address": "me@gmail.com", "password": "pw",
                "imapHost": "imap.gmail.com", "imapPort": "99999",
                "smtpHost": "smtp.gmail.com",
            ],
            allowedUserIds: ["boss@example.com"]
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("端口号不对，应是 1 到 65535 之间的数字")
            )
        }
    }

    func testComposeGuards() {
        // 扫码平台不走填钥匙
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "whatsapp", fields: ["x": "y"],
            allowedUserIds: nil
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("这个平台是扫码配对，不在这里填钥匙"))
        }
        // 冻结平台
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "weixin", fields: ["x": "y"],
            allowedUserIds: nil
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("微信个人号暂不可用，不能配对"))
        }
        // 未开放平台
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "line",
            fields: ["channelSecret": "s", "channelAccessToken": "t"],
            allowedUserIds: nil
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("这个平台还没开放配对，请等后续更新"))
        }
        // 缺必填
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "slack", fields: ["botToken": "xoxb-1"],
            allowedUserIds: nil
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.string("还差必填的钥匙"))
        }
        // 未知字段（邮箱没有 allowedUsers 表单项，桥同拒）
        XCTAssertThrowsError(try MessagingCredentialsComposer.compose(
            platform: "email",
            fields: [
                "address": "me@gmail.com", "password": "pw",
                "imapHost": "imap.gmail.com", "smtpHost": "smtp.gmail.com",
                "allowedUsers": "boss@example.com",
            ],
            allowedUserIds: ["boss@example.com"]
        )) { error in
            XCTAssertEqual(
                (error as? MessagingComposeError)?.message,
                L10n.format("不认识的项：%@", "allowedUsers"))
        }
    }
}
