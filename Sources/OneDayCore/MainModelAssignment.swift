import Foundation

/// 全局默认模型的归属（§141）：Dashboard `GET
/// /api/model/options` 的结构化回读解析。拍平的
/// `/api/config` GET 只给模型名、看不到 provider，
/// 「默认在哪家」只认这条回读口径（回读为准，不靠
/// App 本地记账猜）。回执形态（2026-11-11 生产实测）：
/// 顶层 {provider, model, providers:[{slug,
/// is_current, models}]}；具名服务商行 slug＝注册表
/// 键原名，当前默认所在行 is_current=true；顶层
/// provider 是落盘 slug（裸 custom 或 custom:<名>）。
public struct MainModelAssignment: Equatable, Sendable {

    public enum Owner: Equatable, Sendable {
        /// 默认走网关主通道（裸 custom，或注册表里的
        /// Gateway 具名条目——它就是主通道的具名身份，
        /// §141 服务端前置注册，归主卡不另立卡）
        case gateway
        /// 默认在一家具名服务商（注册表键原名）
        case named(String)
        /// 默认在注册表外的 provider（内置服务商等，
        /// 归一化 slug 原样带回，呈现层只作说明）
        case other(String)
        /// 回读里没有任何可用指向
        case unknown
    }

    public var owner: Owner
    public var model: String?

    public init(owner: Owner, model: String?) {
        self.owner = owner
        self.model = model
    }

    /// 服务商名 → Hermes 归一化 slug（与服务端
    /// runtime_provider_custom 的口径逐字对齐：
    /// strip＋小写＋空格→连字符）
    public static func slug(forProviderName name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    /// 是否网关身份（注册表里的 Gateway 条目＝网关
    /// 主通道的具名登记，呈现上并入默认服务商卡）
    public static func isGatewayIdentity(_ name: String) -> Bool {
        slug(forProviderName: name) == "gateway"
    }

    /// 解析 /api/model/options 回执。判定优先序：
    /// providers 行里 is_current 的 slug ＞ 顶层
    /// provider 字段（行是服务端按当前归属标的，
    /// 顶层是落盘原值，两者同源、行更直接）。
    public static func parse(
        optionsRoot: JSONValue, providerNames: [String]
    ) -> MainModelAssignment {
        guard case .object(let root) = optionsRoot else {
            return MainModelAssignment(owner: .unknown, model: nil)
        }
        let model = root["model"]?.stringValue.flatMap {
            $0.isEmpty ? nil : $0
        }
        var slugRaw: String?
        if case .array(let rows) = root["providers"] ?? .null {
            for row in rows {
                guard case .object(let fields) = row,
                      case .bool(true) = fields["is_current"] ?? .null
                else { continue }
                slugRaw = fields["slug"]?.stringValue
                break
            }
        }
        if slugRaw == nil {
            slugRaw = root["provider"]?.stringValue
        }
        guard let slugRaw, !slugRaw.isEmpty else {
            return MainModelAssignment(owner: .unknown, model: model)
        }
        return MainModelAssignment(
            owner: owner(forSlug: slugRaw, providerNames: providerNames),
            model: model
        )
    }

    private static func owner(
        forSlug raw: String, providerNames: [String]
    ) -> Owner {
        let lowered = raw.trimmingCharacters(in: .whitespaces)
            .lowercased()
        if lowered == "custom" { return .gateway }
        let namedSlug: String
        if lowered.hasPrefix("custom:") {
            namedSlug = String(lowered.dropFirst("custom:".count))
                .trimmingCharacters(in: .whitespaces)
        } else {
            // 行 slug 是注册表键原名（未归一），走同一
            // 归一化再比对
            namedSlug = slug(forProviderName: raw)
        }
        if namedSlug == "gateway" { return .gateway }
        if let match = providerNames.first(where: {
            slug(forProviderName: $0) == namedSlug
        }) {
            return .named(match)
        }
        return .other(namedSlug)
    }
}
