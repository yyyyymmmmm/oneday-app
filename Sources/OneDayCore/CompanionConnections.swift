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
        effective: String?, note: String?
    ) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.name = name
        self.configured = configured
        self.lastVerify = lastVerify
        self.effective = effective
        self.note = note
    }

    public var isCloudComputer: Bool { kind == "cloud_computer" }

    /// 电脑类型人话（添加流与详情共用）
    public var providerWording: String {
        switch provider {
        case "simular_box": return "托管云电脑"
        case "vps_agent": return "我的 VPS"
        default: return provider
        }
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
            if effective.contains("待生效") {
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

// MARK: - 凭据与创建载荷（字段名与 front 契约逐字对齐）

public enum ConnectionPayloads {
    /// 创建云电脑：front 只许 kind=cloud_computer 且
    /// provider ∈ {simular_box, vps_agent}
    public static func create(
        provider: String, name: String
    ) -> [String: JSONValue] {
        [
            "kind": .string("cloud_computer"),
            "provider": .string(provider),
            "name": .string(name),
        ]
    }

    /// 托管类凭据：{apiKey}
    public static func simularCredential(apiKey: String) -> [String: JSONValue] {
        ["apiKey": .string(apiKey)]
    }

    /// VPS 类凭据：{endpointUrl, token}
    public static func vpsCredential(
        endpointUrl: String, token: String
    ) -> [String: JSONValue] {
        [
            "endpointUrl": .string(endpointUrl),
            "token": .string(token),
        ]
    }

    /// VPS 配置串拆分（规格 §3.2：安装器打印的地址＋
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

    /// VPS 地址校验（front 同口径：必须 http(s) 开头；
    /// 公网明文的风险提示在表单层按 §5.5 给）
    public static func isPlausibleEndpoint(_ raw: String) -> Bool {
        let url = raw.trimmingCharacters(in: .whitespaces)
        return (url.hasPrefix("http://") && url.count > 7)
            || (url.hasPrefix("https://") && url.count > 8)
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
