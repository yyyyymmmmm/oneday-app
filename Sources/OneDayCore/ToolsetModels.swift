import Foundation

/// 工具集治理模型（Hermes 台账 34，部署包 1.4.0；DESIGN §358）：
/// 手机会话（api_server 平台）的工具集真值面——读面
/// GET /v1/toolsets（8642 Bearer）逐行 enabled/configured，
/// 启停走 34-S 新端点 PUT /v1/toolsets/{name}（写
/// platform_toolsets.api_server，对新构建的 run 立即生效、
/// 存量 run 不受影响，34-S 真行为验收实证）；细调走 9119
/// 会话面（provider/model/终端后端，写全局 config、全平台
/// 生效）。字段口径以 blueprint-phase1-recon §2.1 与
/// hermes-batch34s-execution 实测为准，逐条钉死：
/// - 9119 既有启停写口只写 cli 平台、对手机会话不生效，
///   本面结构上不接（接了即僵尸开关）；
/// - config-only 集（生产实测 stt）：8642 读面 enabled 按
///   平台集成员计、恒报 false，其真值在 config 的
///   stt.enabled——呈现与回读判定都以 config 为准（见
///   ToolsetStateResolution），不许显与真实相反的状态；
/// - env 密钥只回 is_set 布尔、永不回值；录入一期不做
///   （凭据纪律），本面只显状态。

// MARK: - 列表读面（GET /v1/toolsets）

/// 一个工具集行：name 是服务端稳定键（兼 Identifiable.id
/// 与启停/回读的比对键）；tools 是逐工具粒度清单（治理
/// 转正的对账载体——验收按逐行＋逐 tools 对账，不按
/// 「59 条」功能计数造行）
public struct ToolsetRow: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let label: String
    public let description: String
    /// 平台集成员口径的启用态（config-only 集恒 false，
    /// 真值看 ToolsetStateResolution 的合成结果）
    public let enabled: Bool
    /// 是否已配置（如所需密钥/后端就绪）
    public let configured: Bool
    public let tools: [String]

    public var id: String { name }

    /// 呈现名：label 缺失时回落 name 本体，不编造
    public var displayLabel: String {
        label.isEmpty ? name : label
    }

    enum CodingKeys: String, CodingKey {
        case name, label, description, enabled, configured, tools
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        label = try container.decodeIfPresent(
            String.self, forKey: .label
        ) ?? ""
        description = try container.decodeIfPresent(
            String.self, forKey: .description
        ) ?? ""
        enabled = try container.decodeIfPresent(
            Bool.self, forKey: .enabled
        ) ?? false
        configured = try container.decodeIfPresent(
            Bool.self, forKey: .configured
        ) ?? false
        tools = try container.decodeIfPresent(
            [String].self, forKey: .tools
        ) ?? []
    }

    public init(
        name: String, label: String = "", description: String = "",
        enabled: Bool, configured: Bool = false, tools: [String] = []
    ) {
        self.name = name
        self.label = label
        self.description = description
        self.enabled = enabled
        self.configured = configured
        self.tools = tools
    }
}

/// GET /v1/toolsets 回包：{object: "list", platform:
/// "api_server", data: [...]}；platform 是本面真值归属的
/// 自报（非 api_server 时呈现层须警觉——本面只治手机面）
public struct ToolsetsListResponse: Decodable, Equatable, Sendable {
    public let object: String?
    public let platform: String?
    public let data: [ToolsetRow]

    public func row(named name: String) -> ToolsetRow? {
        data.first { $0.name == name }
    }

    enum CodingKeys: String, CodingKey {
        case object, platform, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(
            String.self, forKey: .object
        )
        platform = try container.decodeIfPresent(
            String.self, forKey: .platform
        )
        data = try container.decodeIfPresent(
            [ToolsetRow].self, forKey: .data
        ) ?? []
    }

    public init(
        object: String? = "list", platform: String? = "api_server",
        data: [ToolsetRow]
    ) {
        self.object = object
        self.platform = platform
        self.data = data
    }
}

// MARK: - 状态合成（config-only 集真值）

/// 工具集有效状态合成（DESIGN §358）：8642 读面的
/// enabled 是平台集成员口径——普通集即真值；config-only
/// 集（config 里有自家节且节内带 enabled 键者，生产实测
/// stt）不在平台集内、读面恒 false，真值以 config 节
/// enabled 为准。合成规则：config 节带 enabled 键的行，
/// 有效态＝config 值；其余行＝读面值。config 没读到
/// （nil）时不合成、回落读面值，呈现层另行标注未确认。
public enum ToolsetStateResolution {
    /// 从全量 config 里抽「节内带 enabled 键」的集名→值
    /// 映射（config-only 集的真值表）
    public static func configBackedEnabled(
        in config: [String: JSONValue]?
    ) -> [String: Bool] {
        guard let config else { return [:] }
        var result: [String: Bool] = [:]
        for (name, section) in config {
            guard case .object(let fields) = section,
                  let enabled = fields["enabled"]?.boolValue
            else { continue }
            result[name] = enabled
        }
        return result
    }

    /// 该行是否 config 承托（真值在 config 节、非平台集）
    public static func isConfigBacked(
        _ row: ToolsetRow, configEnabled: [String: Bool]
    ) -> Bool {
        configEnabled[row.name] != nil
    }

    /// 有效启用态：config 承托行以 config 为准，其余以
    /// 读面为准
    public static func effectiveEnabled(
        _ row: ToolsetRow, configEnabled: [String: Bool]
    ) -> Bool {
        configEnabled[row.name] ?? row.enabled
    }

    /// 有效启用计数（目录副行「已启用 N/总行数」的 N）
    public static func enabledCount(
        in response: ToolsetsListResponse,
        configEnabled: [String: Bool]
    ) -> Int {
        response.data.filter {
            effectiveEnabled($0, configEnabled: configEnabled)
        }.count
    }
}

// MARK: - 启停（PUT /v1/toolsets/{name}，34-S）

/// 启停请求体组装（34-S 契约：body {"enabled": bool}；
/// 组装走 Core 纯函数、单测把守形态）
public struct ToolsetToggleRequest: Encodable, Equatable, Sendable {
    public let enabled: Bool

    public static func set(_ enabled: Bool) -> ToolsetToggleRequest {
        ToolsetToggleRequest(enabled: enabled)
    }
}

/// PUT /v1/toolsets/{name} 200 回执：{ok, name, platform:
/// "api_server", enabled}——回执只作留痕/测试钉，成败终局
/// 以事后回读为准（见 ToolsetReadback）
public struct ToolsetToggleReceipt: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let name: String
    public let platform: String?
    public let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case ok, name, platform, enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(
            Bool.self, forKey: .ok
        ) ?? false
        name = try container.decodeIfPresent(
            String.self, forKey: .name
        ) ?? ""
        platform = try container.decodeIfPresent(
            String.self, forKey: .platform
        )
        enabled = try container.decodeIfPresent(
            Bool.self, forKey: .enabled
        ) ?? false
    }

    public init(
        ok: Bool, name: String, platform: String? = "api_server",
        enabled: Bool
    ) {
        self.ok = ok
        self.name = name
        self.platform = platform
        self.enabled = enabled
    }
}

/// 启停失败分类器（DESIGN §358，照 GrantRevokeDirective
/// 同构）：码字面以 34-S 实测为准——未知集 400
/// unknown_toolset；enabled 非 bool 400 invalid_enabled
/// （客户端组装恒 bool、发生即呈现层 bug，如实报）；无
/// 鉴权 401。其余一律 .failed 如实上抛，不盲重试
public enum ToolsetToggleDirective: Sendable, Equatable {
    /// 2xx：服务端已写——进回读确认步
    case done
    /// 400 unknown_toolset：这个集已不在服务端清单里
    /// （多为服务端版本变化）——回读刷新对齐，不算失败
    case unknownToolset
    /// 400 invalid_enabled：请求体形态错（客户端 bug）
    case invalidRequest
    /// 401/403：登录密钥被拒
    case unauthorized
    /// 其余（服务器错/未知码）：如实上抛
    case failed

    public static func directive(
        status: Int, serverCode: String?
    ) -> ToolsetToggleDirective {
        if (200...299).contains(status) {
            return .done
        }
        switch status {
        case 400:
            switch serverCode {
            case "unknown_toolset": return .unknownToolset
            case "invalid_enabled": return .invalidRequest
            default: return .failed
            }
        case 401, 403:
            return .unauthorized
        default:
            return .failed
        }
    }
}

// MARK: - 细调读面（9119 会话面）

/// env 变量状态行：服务端只回 is_set 布尔、永不回值；
/// default 是服务端给的缺省提示（形态不一，宽容收口为
/// 字符串或 nil），本面只显状态不做录入
public struct ToolsetEnvVar: Decodable, Equatable, Sendable {
    public let key: String
    public let prompt: String
    public let url: String?
    public let isSet: Bool

    enum CodingKeys: String, CodingKey {
        case key, prompt, url
        case isSet = "is_set"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(
            String.self, forKey: .key
        ) ?? ""
        prompt = try container.decodeIfPresent(
            String.self, forKey: .prompt
        ) ?? ""
        url = try container.decodeIfPresent(
            String.self, forKey: .url
        )
        isSet = try container.decodeIfPresent(
            Bool.self, forKey: .isSet
        ) ?? false
    }

    public init(
        key: String, prompt: String = "", url: String? = nil,
        isSet: Bool
    ) {
        self.key = key
        self.prompt = prompt
        self.url = url
        self.isSet = isSet
    }
}

/// provider 一行：细调第一层（选服务商）。env_vars 是该
/// 服务商的密钥状态清单；is_active 与面板 active_provider
/// 互为印证，回读判定以 active_provider 为准
public struct ToolsetProvider: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let badge: String
    public let tag: String
    public let envVars: [ToolsetEnvVar]
    public let requiresNousAuth: Bool
    public let isActive: Bool
    public let status: String

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, badge, tag, status
        case envVars = "env_vars"
        case requiresNousAuth = "requires_nous_auth"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(
            String.self, forKey: .name
        ) ?? ""
        badge = try container.decodeIfPresent(
            String.self, forKey: .badge
        ) ?? ""
        tag = try container.decodeIfPresent(
            String.self, forKey: .tag
        ) ?? ""
        envVars = try container.decodeIfPresent(
            [ToolsetEnvVar].self, forKey: .envVars
        ) ?? []
        requiresNousAuth = try container.decodeIfPresent(
            Bool.self, forKey: .requiresNousAuth
        ) ?? false
        isActive = try container.decodeIfPresent(
            Bool.self, forKey: .isActive
        ) ?? false
        status = try container.decodeIfPresent(
            String.self, forKey: .status
        ) ?? ""
    }

    public init(
        name: String, badge: String = "", tag: String = "",
        envVars: [ToolsetEnvVar] = [], requiresNousAuth: Bool = false,
        isActive: Bool = false, status: String = ""
    ) {
        self.name = name
        self.badge = badge
        self.tag = tag
        self.envVars = envVars
        self.requiresNousAuth = requiresNousAuth
        self.isActive = isActive
        self.status = status
    }
}

/// GET /api/tools/toolsets/{name}/config 回包：provider
/// 矩阵＋当前服务商。post_setup（安装长任务）二期后置，
/// 本模型不承接
public struct ToolsetConfigPanel: Decodable, Equatable, Sendable {
    public let name: String
    public let hasCategory: Bool
    public let providers: [ToolsetProvider]
    public let activeProvider: String?

    public func provider(named name: String) -> ToolsetProvider? {
        providers.first { $0.name == name }
    }

    enum CodingKeys: String, CodingKey {
        case name, providers
        case hasCategory = "has_category"
        case activeProvider = "active_provider"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(
            String.self, forKey: .name
        ) ?? ""
        hasCategory = try container.decodeIfPresent(
            Bool.self, forKey: .hasCategory
        ) ?? false
        providers = try container.decodeIfPresent(
            [ToolsetProvider].self, forKey: .providers
        ) ?? []
        activeProvider = try container.decodeIfPresent(
            String.self, forKey: .activeProvider
        )
    }

    public init(
        name: String, hasCategory: Bool = false,
        providers: [ToolsetProvider], activeProvider: String? = nil
    ) {
        self.name = name
        self.hasCategory = hasCategory
        self.providers = providers
        self.activeProvider = activeProvider
    }
}

/// 模型目录里的一行（仅 image_gen/video_gen 等有目录
/// 集）：strengths 服务端或字符串或数组、price 或字符
/// 串或数字——宽容收口为展示字符串，不因形态漂移解码
/// 失败
public struct ToolsetModelOption: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let display: String
    public let speed: String
    public let strengths: String
    public let price: String

    public var displayName: String {
        display.isEmpty ? id : display
    }

    enum CodingKeys: String, CodingKey {
        case id, display, speed, strengths, price
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(
            String.self, forKey: .id
        ) ?? ""
        display = try container.decodeIfPresent(
            String.self, forKey: .display
        ) ?? ""
        speed = try container.decodeIfPresent(
            String.self, forKey: .speed
        ) ?? ""
        if let text = try? container.decodeIfPresent(
            String.self, forKey: .strengths
        ) ?? nil {
            strengths = text
        } else if let list = try? container.decodeIfPresent(
            [String].self, forKey: .strengths
        ) ?? nil {
            strengths = list.joined(separator: "、")
        } else {
            strengths = ""
        }
        if let text = try? container.decodeIfPresent(
            String.self, forKey: .price
        ) ?? nil {
            price = text
        } else if let number = try? container.decodeIfPresent(
            Double.self, forKey: .price
        ) ?? nil {
            price = String(number)
        } else {
            price = ""
        }
    }

    public init(
        id: String, display: String = "", speed: String = "",
        strengths: String = "", price: String = ""
    ) {
        self.id = id
        self.display = display
        self.speed = speed
        self.strengths = strengths
        self.price = price
    }
}

/// GET /api/tools/toolsets/{name}/models 回包：has_models
/// 为 false 的集没有模型细调，详情页不显模型段（不造
/// 空段冒充可调）
public struct ToolsetModelCatalog: Decodable, Equatable, Sendable {
    public let name: String
    public let hasModels: Bool
    public let provider: String?
    public let models: [ToolsetModelOption]
    public let current: String?
    public let defaultModel: String?

    enum CodingKeys: String, CodingKey {
        case name, provider, models, current
        case hasModels = "has_models"
        case defaultModel = "default"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(
            String.self, forKey: .name
        ) ?? ""
        hasModels = try container.decodeIfPresent(
            Bool.self, forKey: .hasModels
        ) ?? false
        provider = try container.decodeIfPresent(
            String.self, forKey: .provider
        )
        models = try container.decodeIfPresent(
            [ToolsetModelOption].self, forKey: .models
        ) ?? []
        current = try container.decodeIfPresent(
            String.self, forKey: .current
        )
        defaultModel = try container.decodeIfPresent(
            String.self, forKey: .defaultModel
        )
    }

    public init(
        name: String, hasModels: Bool = false,
        provider: String? = nil, models: [ToolsetModelOption] = [],
        current: String? = nil, defaultModel: String? = nil
    ) {
        self.name = name
        self.hasModels = hasModels
        self.provider = provider
        self.models = models
        self.current = current
        self.defaultModel = defaultModel
    }
}

/// 终端后端健康状态（服务端原样三态＋未知原样保留）：
/// 呈现层按 kind 给人话，未知值不猜不拼
public enum TerminalBackendStatus: Sendable, Equatable {
    case ready
    case needsSetup
    case unavailable
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "ready": self = .ready
        case "needs_setup": self = .needsSetup
        case "unavailable": self = .unavailable
        default: self = .other(rawValue)
        }
    }

    /// 只有 ready 的后端允许被选中——选一个未就绪的后端
    /// 是假动作，呈现层据此置灰并给原因
    public var isSelectable: Bool {
        self == .ready
    }
}

/// 终端后端一行（GET /api/tools/terminal/backends）
public struct TerminalBackend: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let label: String
    public let description: String
    public let active: Bool
    public let status: TerminalBackendStatus
    public let detail: String

    public var id: String { name }

    public var displayLabel: String {
        label.isEmpty ? name : label
    }

    enum CodingKeys: String, CodingKey {
        case name, label, description, active, status, detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(
            String.self, forKey: .name
        ) ?? ""
        label = try container.decodeIfPresent(
            String.self, forKey: .label
        ) ?? ""
        description = try container.decodeIfPresent(
            String.self, forKey: .description
        ) ?? ""
        active = try container.decodeIfPresent(
            Bool.self, forKey: .active
        ) ?? false
        status = TerminalBackendStatus(
            rawValue: try container.decodeIfPresent(
                String.self, forKey: .status
            ) ?? ""
        )
        detail = try container.decodeIfPresent(
            String.self, forKey: .detail
        ) ?? ""
    }

    public init(
        name: String, label: String = "", description: String = "",
        active: Bool = false, status: TerminalBackendStatus,
        detail: String = ""
    ) {
        self.name = name
        self.label = label
        self.description = description
        self.active = active
        self.status = status
        self.detail = detail
    }
}

/// GET /api/tools/terminal/backends 回包：{active, backends}
public struct TerminalBackends: Decodable, Equatable, Sendable {
    public let active: String?
    public let backends: [TerminalBackend]

    public func backend(named name: String) -> TerminalBackend? {
        backends.first { $0.name == name }
    }

    enum CodingKeys: String, CodingKey {
        case active, backends
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decodeIfPresent(
            String.self, forKey: .active
        )
        backends = try container.decodeIfPresent(
            [TerminalBackend].self, forKey: .backends
        ) ?? []
    }

    public init(active: String? = nil, backends: [TerminalBackend]) {
        self.active = active
        self.backends = backends
    }
}

// MARK: - 写后回读判定

/// 写后回读判定（DESIGN §358）：一切写口的成败不认回执
/// 自报、只认事后重拉的真源——启停认合成有效态（普通集
/// 看平台集成员、config-only 集看 config 节），细调三写
/// 分别认面板 active_provider／目录 current／后端 active
public enum ToolsetReadback {
    public static func isToggleConfirmed(
        name: String, target: Bool,
        in refreshed: ToolsetsListResponse,
        configEnabled: [String: Bool]
    ) -> Bool {
        guard let row = refreshed.row(named: name) else {
            return false
        }
        return ToolsetStateResolution.effectiveEnabled(
            row, configEnabled: configEnabled
        ) == target
    }

    public static func isProviderConfirmed(
        _ panel: ToolsetConfigPanel, provider: String
    ) -> Bool {
        panel.activeProvider == provider
    }

    public static func isModelConfirmed(
        _ catalog: ToolsetModelCatalog, model: String
    ) -> Bool {
        catalog.current == model
    }

    public static func isBackendConfirmed(
        _ backends: TerminalBackends, name: String
    ) -> Bool {
        backends.active == name
    }
}
