import Foundation

/// 伴生连接记录（0.37.0 模型包·云电脑配置面）：数据
/// 走伴生 front 的 connections 契约（2026-11-11 实测
/// 在产可用）：GET /api/companion/connections、
/// POST /api/companion/connections（只许建云电脑）、
/// POST /{id}/credential、/{id}/verify、/{id}/disconnect。
/// 凭据只经此通道提交一次、落用户自己的服务端，任何
/// 读面永不回传已存凭据的值（front 契约 conn_public
/// 只出 configured 布尔与验活记录，本模型同口径）。
public struct CompanionConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// service / cloud_computer / mcp_registration
    public var kind: String
    /// github / notion / simular_box / vps_agent / gateway / hermes_mcp
    public var provider: String
    public var name: String
    /// 凭据是否已配置（nil＝服务端没给准话，不猜）
    public var configured: Bool?
    public var lastVerify: VerifyRecord?
    /// 生效态原文（如「已配置 · 待生效」），呈现优先用它
    public var effective: String?
    public var note: String?
    /// 非敏感展示元数据（主机/端口/系统/认证方式/公钥等，永不含密码或私钥）
    public var meta: ConnectionMeta?

    public struct ConnectionMeta: Codable, Equatable, Sendable {
        public var host: String?
        public var port: Int?
        public var username: String?
        public var osType: String?
        public var authType: String?
        public var publicKey: String?
        public var mcpUrl: String?

        public init(
            host: String? = nil, port: Int? = nil, username: String? = nil,
            osType: String? = nil, authType: String? = nil,
            publicKey: String? = nil, mcpUrl: String? = nil
        ) {
            self.host = host
            self.port = port
            self.username = username
            self.osType = osType
            self.authType = authType
            self.publicKey = publicKey
            self.mcpUrl = mcpUrl
        }
    }

    public struct VerifyRecord: Codable, Equatable, Sendable {
        /// ISO 时间字符串（原文呈现，相对化在视图层做）
        public var at: String
        public var ok: Bool
        public var detail: String

        public init(at: String, ok: Bool, detail: String) {
            self.at = at
            self.ok = ok
            self.detail = detail
        }
    }

    public init(
        id: String, kind: String, provider: String, name: String,
        configured: Bool?, lastVerify: VerifyRecord?,
        effective: String?, note: String?,
        meta: ConnectionMeta? = nil
    ) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.name = name
        self.configured = configured
        self.lastVerify = lastVerify
        self.effective = effective
        self.note = note
        self.meta = meta
    }

    public var isCloudComputer: Bool { kind == "cloud_computer" }

    /// 电脑类型人话（添加流与详情共用）
    public var providerWording: String {
        switch provider {
        case "simular_box": return "托管云电脑"
        case "vps_ssh", "vps_agent":
            if meta?.osType == "windows" { return "Windows VPS / NAT" }
            if meta?.osType == "linux" { return "Linux VPS / NAT" }
            return "VPS / NAT 主机"
        case "reverse_node": return "内网穿透节点"
        default: return provider
        }
    }
}

public struct ReverseNodePairing: Codable, Equatable, Sendable {
    public let linuxCommand: String
    public let windowsCommand: String
    public let recommendedCommand: String

    public init(linuxCommand: String, windowsCommand: String, recommendedCommand: String) {
        self.linuxCommand = linuxCommand
        self.windowsCommand = windowsCommand
        self.recommendedCommand = recommendedCommand
    }
}

public struct SSHKeygenReceipt: Equatable, Sendable {
    public let publicKey: String
    public let installCommand: String
    public let connection: CompanionConnection?

    public init(publicKey: String, installCommand: String, connection: CompanionConnection?) {
        self.publicKey = publicKey
        self.installCommand = installCommand
        self.connection = connection
    }
}

/// 连接状态词表（与伴生面板同一套词，cloud-computer
/// 规格 §7：双前端不许各说各的）：自记录字段派生一句
/// 状态——优先服务端的 effective 原文，缺失才按
/// configured＋lastVerify 拼，拼不出就如实说未配置。
public enum ConnectionStatusWording {
    public enum Tone: Equatable, Sendable {
        case ok       // 已连接
        case pending  // 待生效 / 待修正
        case bad      // 验活失败 / 已断开
        case unknown  // 未配置
    }

    public static func evaluate(
        _ connection: CompanionConnection
    ) -> (text: String, tone: Tone) {
        if let effective = connection.effective,
           !effective.isEmpty {
            if effective.contains("待生效") || effective.contains("待打通") {
                return (effective, .pending)
            }
            if effective.contains("未安装") {
                return (effective, .unknown)
            }
            return (effective, .ok)
        }
        if let verify = connection.lastVerify, !verify.ok {
            if verify.detail.contains("已断开") {
                return ("已断开", .bad)
            }
            return ("连接没通过", .bad)
        }
        switch connection.configured {
        case .some(true):
            return ("已连接", .ok)
        case .some(false):
            return ("未配置", .unknown)
        case .none:
            return ("状态未知", .unknown)
        }
    }
}

// MARK: - 凭据载荷（字段名与 front 契约逐字对齐）

/// 云电脑凭据下发载荷（2.21.0 新端点）
public struct BoxCredentialPayload: Codable, Equatable, Sendable {
    public var apiKey: String
    public var mcpUrl: String?

    public init(apiKey: String, mcpUrl: String? = nil) {
        self.apiKey = apiKey
        self.mcpUrl = mcpUrl
    }
}

// MARK: - 凭据与创建载荷（字段名与 front 契约逐字对齐）

public enum ConnectionPayloads {
    /// 创建云电脑/远程主机：provider ∈ {simular_box, vps_ssh, vps_agent, reverse_node}
    public static func create(
        provider: String, name: String, osType: String? = nil
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "kind": .string("cloud_computer"),
            "provider": .string(provider),
            "name": .string(name),
        ]
        if let osType, !osType.isEmpty {
            body["osType"] = .string(osType)
        }
        return body
    }

    /// 托管类凭据：{apiKey, mcpUrl?}
    public static func simularCredential(
        apiKey: String, mcpUrl: String? = nil
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = ["apiKey": .string(apiKey)]
        if let mcpUrl = mcpUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !mcpUrl.isEmpty {
            body["mcpUrl"] = .string(mcpUrl)
        }
        return body
    }

    /// VPS / NAT 主机凭据（支持 Linux & Windows、自定义端口、SSH 密钥或密码）
    public static func vpsHostCredential(
        host: String, port: Int, username: String,
        osType: String, authType: String,
        privateKey: String? = nil, password: String? = nil
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "host": .string(host),
            "port": .number(Double(port)),
            "username": .string(username),
            "osType": .string(osType),
            "authType": .string(authType),
        ]
        if let privateKey, !privateKey.isEmpty {
            body["privateKey"] = .string(privateKey)
        }
        if let password, !password.isEmpty {
            body["password"] = .string(password)
        }
        return body
    }

    /// 兼容旧签名的 Windows 登录凭据
    public static func windowsCredential(
        host: String, username: String, password: String
    ) -> [String: JSONValue] {
        [
            "host": .string(host),
            "username": .string(username),
            "password": .string(password),
        ]
    }

    /// VPS 类凭据（内部形态，伴生面板与存量记录仍用此
    /// 契约；App 表单自收口包起不再引用）：{endpointUrl, token}
    public static func vpsCredential(
        endpointUrl: String, token: String
    ) -> [String: JSONValue] {
        [
            "endpointUrl": .string(endpointUrl),
            "token": .string(token),
        ]
    }

    /// VPS 配置串拆分（内部形态保留，App 表单不用；
    /// 原云电脑档 §3.2：安装器打印的地址＋
    /// 令牌打包成一串，粘贴自动拆）：容忍三种形态——
    /// JSON 对象、两行（地址行＋令牌行）、空格分隔。
    /// 拆不出返回 nil，表单回落逐字段手填。
    public static func parseConfigString(
        _ raw: String
    ) -> (endpointUrl: String, token: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data),
           case .object(let fields) = value,
           let url = fields["endpointUrl"]?.stringValue
            ?? fields["url"]?.stringValue,
           let token = fields["token"]?.stringValue, !token.isEmpty {
            return (url, token)
        }
        let parts = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              parts[0].hasPrefix("http://") || parts[0].hasPrefix("https://")
        else { return nil }
        return (parts[0], parts[1])
    }

    /// VPS 地址校验（内部形态保留，App 表单不用；
    /// front 同口径：必须 http(s) 开头）
    public static func isPlausibleEndpoint(_ raw: String) -> Bool {
        let url = raw.trimmingCharacters(in: .whitespaces)
        return (url.hasPrefix("http://") && url.count > 7)
            || (url.hasPrefix("https://") && url.count > 8)
    }
}

// MARK: - Windows 登录三样校验（收口规格 §2.1）

/// VPS 型表单只收 IP＋账户名＋密码（2026-11-11 15:58
/// 定版）：host 只认「哪台电脑」的写法——合法 IPv4 或
/// 主机名；带 ://、路径或空白的串一律拦下，不让内部
/// 端点概念借校验口漏回用户面。服务端会再验一遍，这
/// 里只管表单能不能提交（口径与伴生 front 同源）。
public enum WindowsLoginInput {
    public static func isValidHost(_ raw: String) -> Bool {
        let host = raw.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty,
              !host.contains("://"), !host.contains("/"),
              !host.contains(where: \.isWhitespace)
        else { return false }
        // 纯数字与点组成的串只能按 IPv4 判（999.1.1.1
        // 这类不许借主机名口径混过去）
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            return isValidIPv4(host)
        }
        return isValidIPv4(host) || isValidHostname(host)
    }

    public static func isValidIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
                && (Int(part).map { $0 <= 255 } ?? false)
        }
    }

    public static func isValidHostname(_ host: String) -> Bool {
        guard !host.hasPrefix("-"), !host.hasPrefix("."),
              !host.hasSuffix("-"), !host.hasSuffix("."),
              !host.contains("..")
        else { return false }
        return host.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "."
        }
    }

    public static func isReady(
        host: String, username: String, password: String
    ) -> Bool {
        isValidHost(host)
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }
}

// MARK: - 验活状态机（添加流/凭据提交共用）

/// 验活流程的呈现状态机：提交→服务端验活→成/败都带
/// 人话 detail 回显（front 回执 {ok, detail} 原样是
/// 人话，失败含「已经把刚才的改动撤回」这类回滚说明，
/// 直接呈现、不加工）。状态转移收口在此，视图只渲染。
public enum CredentialFlowPhase: Equatable, Sendable {
    case idle
    case submitting
    case verified(detail: String)
    case failed(detail: String)

    public var isBusy: Bool { self == .submitting }

    /// 事件：开始提交／回执到达（ok＋detail）／网络层
    /// 失败（detail 为本地人话）。非法转移（如 idle 直
    /// 接受回执）忽略并保持原态——状态机不许被乱序回
    /// 执带偏。
    public static func next(
        from phase: CredentialFlowPhase,
        submitted: Bool = false,
        receipt: (ok: Bool, detail: String)? = nil
    ) -> CredentialFlowPhase {
        if submitted {
            switch phase {
            case .idle, .verified, .failed:
                return .submitting
            case .submitting:
                return phase
            }
        }
        if let receipt {
            guard case .submitting = phase else { return phase }
            return receipt.ok
                ? .verified(detail: receipt.detail)
                : .failed(detail: receipt.detail)
        }
        return phase
    }
}
}
