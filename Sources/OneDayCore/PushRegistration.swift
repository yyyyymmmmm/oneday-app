import Foundation

/// 推送登记契约与就绪派生（总表 138／G-21，DESIGN §397）。
///
/// 定位先说清：远程推送的服务端半边（令牌登记端点＋APNs
/// 发送）属部署包批 4b，随付费开发者账号解锁（用户令搁
/// 置）；本文件是 App 侧准备面的纯逻辑单源——令牌编码、
/// 环境判定、登记契约（批 4b §4.1 草案）、失败分型与就
/// 绪报告派生全在此，App 层只做系统接线与状态持有，不
/// 许在视图／存储层另拼口径。服务端未装机前，登记上送
/// 的真回执是 404——按 serverNotReady 如实分型呈现，
/// 不许冒充已登记。

// MARK: - 环境与令牌编码

/// APNs 环境（随令牌存、发送时选主机，批 4b §3 全件 3）：
/// 环境是令牌的属性——开发签名包走 sandbox、TestFlight/
/// 正式包走 production，混发回 BadDeviceToken
public enum PushEnvironment: String, Codable, Equatable, Sendable {
    case sandbox
    case production

    /// 就绪面人话
    public var label: String {
        switch self {
        case .sandbox: return "沙盒"
        case .production: return "生产"
        }
    }
}

/// APNs 令牌的线格式：Data 的小写 hex 串（通行口径，
/// 服务端存储与 /3/device/<token> 路径都用此形）
public enum PushTokenHex {
    public static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// hex 串回 Data：空串／奇数长／非 hex 字符一律 nil，
    /// 不许截断凑数
    public static func decode(_ hex: String) -> Data? {
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
        var data = Data()
        data.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16)
            else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

/// 从 embedded.mobileprovision 读推送环境：描述文件是
/// 带 CMS 签名包裹的 plist，正文嵌一段 XML plist——先
/// 截出 XML 段再解析 Entitlements.aps-environment（通
/// 行做法）。读不到／无此键／值不认识一律 nil：环境不
/// 明就不许上送登记（拿猜的环境登记＝给服务端埋错令牌）
public enum PushProvisionReader {
    public static func apsEnvironment(
        fromProvisionData data: Data
    ) -> PushEnvironment? {
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.range(of: "<?xml"),
              let end = text.range(
                of: "</plist>",
                range: start.lowerBound..<text.endIndex
              ) else { return nil }
        let xml = String(text[start.lowerBound..<end.upperBound])
        guard let plist = try? PropertyListSerialization
                .propertyList(
                    from: Data(xml.utf8), options: [], format: nil
                ) as? [String: Any],
              let entitlements = plist["Entitlements"]
                as? [String: Any],
              let raw = entitlements["aps-environment"]
                as? String else { return nil }
        switch raw {
        case "development": return .sandbox
        case "production": return .production
        default: return nil
        }
    }
}

// MARK: - 登记契约（批 4b §4.1 草案）

/// POST /v1/push/tokens 请求体（批 4b §4.1 草案契约：
/// 按 device_token upsert、回 {registered: true}）
public struct PushTokenRegistrationBody: Encodable, Equatable, Sendable {
    public let deviceToken: String
    public let environment: PushEnvironment
    public let bundleID: String
    public let appVersion: String

    public init(
        deviceToken: String, environment: PushEnvironment,
        bundleID: String, appVersion: String
    ) {
        self.deviceToken = deviceToken
        self.environment = environment
        self.bundleID = bundleID
        self.appVersion = appVersion
    }

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case environment
        case bundleID = "bundle_id"
        case appVersion = "app_version"
    }
}

/// POST /v1/push/tokens 成功回执（批 4b §4.1 草案）
public struct PushTokenRegisteredResponse: Decodable, Equatable, Sendable {
    public let registered: Bool

    public init(registered: Bool) {
        self.registered = registered
    }
}

// MARK: - 登记状态机

/// 登记失败分型：每型一句人话（就绪面直用），系统错误
/// 原文不进呈现——只进诊断记录（防英文原文甩给用户）
public enum PushRegistrationFailure: Equatable, Sendable {
    /// 安装包没有 aps-environment 权益（免费侧载签不出，
    /// 卡付费开发者账号——批 4b §0 定性）
    case noEntitlement
    /// 描述文件读不出推送环境，令牌未上送
    case environmentUnknown
    /// 服务端回 404：登记端点未装机（批 4b 待装）
    case serverNotReady
    /// 服务端回了非 200 且非鉴权问题，或回执不认
    case serverRejected
    /// 401/403：服务端不认这把登录密钥
    case unauthorizedByServer
    /// 传输层失败（detail 已是人话层文案）
    case network(String)
    /// 其余系统失败（原文进诊断、不进呈现）
    case system

    public var label: String {
        switch self {
        case .noEntitlement:
            return "当前安装包没有推送权益——要等付费开发者账号签发的安装包"
        case .environmentUnknown:
            return "读不出这台设备的推送环境，令牌没有上送"
        case .serverNotReady:
            return "服务端还没开通推送登记（部署包批 4b 待装机）"
        case .serverRejected:
            return "服务端没接受这次登记"
        case .unauthorizedByServer:
            return "服务端不认这把登录密钥，登记被拒"
        case .network:
            return "网络不通，登记没送出去"
        case .system:
            return "系统没能完成推送登记"
        }
    }
}

/// 登记流水线状态（App 层 PushRegistrationStore 持有，
/// 就绪派生只读本枚举＋权限＋快照，不另立第二套状态）
public enum PushRegistrationPhase: Equatable, Sendable {
    /// 未发起（权限未到位／未连接／演示模式）
    case idle
    /// 已向系统发起登记、等回调
    case registering
    /// 令牌已到手、未上送成功（无连接或待重试）
    case uploadPending
    /// 服务端已回 registered: true（真回读才进此态）
    case registered
    case failed(PushRegistrationFailure)
}

/// 令牌快照（本机落盘形态）：令牌＋环境＋版本＋时间；
/// 每次启动以快照为起点重走上送（upsert 幂等），不许
/// 拿「上次登记过」冒充服务端现行状态
public struct PushRegistrationSnapshot: Codable, Equatable, Sendable {
    public var tokenHex: String
    public var environment: PushEnvironment
    public var appVersion: String
    public var updatedAt: Date

    public init(
        tokenHex: String, environment: PushEnvironment,
        appVersion: String, updatedAt: Date
    ) {
        self.tokenHex = tokenHex
        self.environment = environment
        self.appVersion = appVersion
        self.updatedAt = updatedAt
    }
}

/// 系统登记失败回调的分型（纯函数，吃错误描述串）：
/// 权益类错误（描述含 aps-environment／entitlement）
/// 归 noEntitlement，其余归 system（原文由调用方记诊
/// 断，呈现只走 label）
public enum PushFailureClassifier {
    public static func classify(
        systemErrorDescription: String
    ) -> PushRegistrationFailure {
        let text = systemErrorDescription.lowercased()
        if text.contains("aps-environment")
            || text.contains("entitlement") {
            return .noEntitlement
        }
        return .system
    }
}

// MARK: - 就绪报告（状态呈现单源）

public struct PushReadinessRow: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case ok
        case pending
        case blocked
        case info
    }

    public let title: String
    public let statusText: String
    public let tone: Tone

    public init(title: String, statusText: String, tone: Tone) {
        self.title = title
        self.statusText = statusText
        self.tone = tone
    }
}

public struct PushReadinessReport: Equatable, Sendable {
    public let summary: String
    public let rows: [PushReadinessRow]

    public init(summary: String, rows: [PushReadinessRow]) {
        self.summary = summary
        self.rows = rows
    }
}

/// 就绪报告派生：三行——通知权限／远程推送登记／服务
/// 端推送。总括如实说 G-21 现状：登记未成前，消息到达
/// 仍靠长轮询，不许把「准备中」说成「已开通」
public enum PushReadiness {
    public static func report(
        permission: DevicePermissionState,
        phase: PushRegistrationPhase,
        snapshot: PushRegistrationSnapshot?
    ) -> PushReadinessReport {
        var rows: [PushReadinessRow] = []

        switch permission {
        case .granted:
            rows.append(PushReadinessRow(
                title: "通知权限", statusText: "已授权", tone: .ok
            ))
        case .notDetermined:
            rows.append(PushReadinessRow(
                title: "通知权限",
                statusText: "还没决定——允许通知后，推送登记才会启动",
                tone: .pending
            ))
        case .denied:
            rows.append(PushReadinessRow(
                title: "通知权限",
                statusText: "已被拒绝——去系统设置里开启后才会登记推送",
                tone: .blocked
            ))
        case .restricted:
            rows.append(PushReadinessRow(
                title: "通知权限",
                statusText: "受系统限制，暂时用不了",
                tone: .blocked
            ))
        case .limited, .writeOnly, .notApplicable:
            rows.append(PushReadinessRow(
                title: "通知权限",
                statusText: permission.label, tone: .info
            ))
        }

        switch phase {
        case .idle:
            rows.append(PushReadinessRow(
                title: "远程推送登记",
                statusText: permission == .granted
                    ? "尚未启动" : "等通知授权后启动",
                tone: .info
            ))
        case .registering:
            rows.append(PushReadinessRow(
                title: "远程推送登记",
                statusText: "正在向系统登记…", tone: .pending
            ))
        case .uploadPending:
            rows.append(PushReadinessRow(
                title: "远程推送登记",
                statusText: "令牌已取得，等连接恢复后上送服务端",
                tone: .pending
            ))
        case .registered:
            let envText = snapshot.map {
                "（\($0.environment.label)环境）"
            } ?? ""
            rows.append(PushReadinessRow(
                title: "远程推送登记",
                statusText: "令牌已登记到服务端\(envText)",
                tone: .ok
            ))
        case .failed(let failure):
            rows.append(PushReadinessRow(
                title: "远程推送登记",
                statusText: failure.label, tone: .blocked
            ))
        }

        if phase == .registered {
            rows.append(PushReadinessRow(
                title: "服务端推送",
                statusText: "登记端点已开通；真正推送到手机还差发送侧验收（部署包批 4b）",
                tone: .info
            ))
        } else if case .failed(.serverNotReady) = phase {
            rows.append(PushReadinessRow(
                title: "服务端推送",
                statusText: "未开通——登记端点还没装机（部署包批 4b，随付费开发者账号一并推进）",
                tone: .blocked
            ))
        } else {
            rows.append(PushReadinessRow(
                title: "服务端推送",
                statusText: "未验——令牌登记成功后才知道端点是否开通",
                tone: .info
            ))
        }

        let summary: String
        if phase == .registered {
            summary = "推送准备已就绪大半：令牌已登记到服务端；等批 4b 发送侧验收过后，待批与任务完成就能真推到这台手机。"
        } else {
            summary = "现在消息到达仍靠长轮询。推送在准备中：逐行看上面三项卡在哪一步。"
        }
        return PushReadinessReport(summary: summary, rows: rows)
    }
}

// MARK: - 点按路由（批 4b §4.2 payload 契约）

/// 推送点按落点：payload 自定义键 kind＋业务 id（批
/// 4b §4.2 定版）——approval 带 request_id、run 带
/// session_id；本地通知（notify_post／分级提醒）不带
/// 这些键，一律 .none（打开 App 即可，不假装有落点）
public enum PushNotificationRoute: Equatable, Sendable {
    case approval(requestID: String?)
    case session(sessionID: String)
    case none
}

public enum PushNotificationRouteResolver {
    public static func resolve(
        userInfo: [AnyHashable: Any]
    ) -> PushNotificationRoute {
        guard let kind = userInfo["kind"] as? String
        else { return .none }
        switch kind {
        case "approval":
            return .approval(
                requestID: userInfo["request_id"] as? String
            )
        case "run":
            if let sessionID = userInfo["session_id"] as? String,
               !sessionID.isEmpty {
                return .session(sessionID: sessionID)
            }
            return .none
        default:
            return .none
        }
    }
}
