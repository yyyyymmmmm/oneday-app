import Foundation

/// 服务健康统一派生（复杂化全清·第 9 项，2026-11-11）：
/// 「服务好不好」此前三套探测三种状态枚举各说各话——
/// 伴生探测（CompanionProbe 的 /api/companion/info）、
/// 本地服务目录探测（LocalServices 的 LocalService-
/// ProbeState）、提供商直连探针（存前验钥，目的不同、
/// 客户端保持独立），再加 HermesClient /health 被多处
/// 各自消费。本文件立全仓唯一的状态词表与派生口：
/// 输入各探针的原始结果、输出同一个 ServiceHealth，
/// 设置页版本组与连接器页都只许消费这一处派生，不许
/// 再自拼状态词。词表纪律沿各源既有口径：读不到不往
/// 好处猜（unknown/stale 单列）、用户自己关掉的不算
/// 异常（notConfigured 单列）、通了但功能打折单列
/// degraded，不与 down 混。
public enum ServiceHealth: Equatable, Sendable {
    /// 还没探完（首帧未回）
    case checking
    /// 本次检查成功、一切正常
    case up
    /// 通了但功能打折（模块降级／接口通但没返回目录）
    case degraded
    /// 本次检查失败／服务不可用
    case down
    /// 服务面不存在（伴生 info 面 404）
    case absent
    /// 登录信息未配置（客户端根本没发请求，不算异常）
    case notConfigured
    /// 读不到、下不了结论（网络不可达等）
    case unknown
    /// 只有缓存里的上次成功值，不是现况
    case stale

    /// 状态词表单一出处：三面（设置页/连接器页/模型
    /// 设置页）呈现的状态词只许出自这里
    public func label(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch self {
        case .checking:
            return L10n.string("读取中", locale: locale)
        case .up:
            return L10n.string("正常", locale: locale)
        case .degraded:
            return L10n.string("降级运行", locale: locale)
        case .down:
            return L10n.string("异常", locale: locale)
        case .absent:
            return L10n.string("未检测到", locale: locale)
        case .notConfigured:
            return L10n.string("未配置", locale: locale)
        case .unknown:
            return L10n.string("暂时读不到", locale: locale)
        case .stale:
            return L10n.string("上次读到", locale: locale)
        }
    }
}

// MARK: - 本地服务探测 → 统一词表

extension ServiceHealth {
    /// LocalServiceProbeState 四档 1:1 入表：本地服务
    /// 探测没有降级/缺面/缓存形态，对应档恒不出现
    public static func from(
        local state: LocalServiceProbeState
    ) -> ServiceHealth {
        switch state {
        case .loading: return .checking
        case .up: return .up
        case .down: return .down
        case .notConfigured: return .notConfigured
        }
    }
}

// MARK: - 伴生探测 → 统一词表

extension ServiceHealth {
    /// CompanionStatus 入表口径（逐项钉测）：
    /// - absent（info 面 404）→ absent；unknown → unknown
    /// - present 但来自缓存 → stale（不拿旧健康冒充现况，
    ///   与 CompanionStatus.isStale 同口径）
    /// - present 现读：健康 → up；只有降级模块 → degraded；
    ///   有不可用模块或 Hermes 联系不上 → down
    public static func from(
        companion status: CompanionStatus
    ) -> ServiceHealth {
        switch status.presence {
        case .absent: return .absent
        case .unknown: return .unknown
        case .present:
            if status.isStale { return .stale }
            if status.hermesUp == false { return .down }
            guard let health = status.health else { return .unknown }
            if !health.impairedModules.isEmpty { return .down }
            if !health.degradedModules.isEmpty { return .degraded }
            return .up
        }
    }
}

// MARK: - Hermes /health → 统一词表

extension ServiceHealth {
    /// /health 回执入表：status == "ok" 才算 up，其余
    /// 一律 down（与连接页三步探活的硬门同一判词——
    /// 此前各消费方有的查 isOK、有的只看不抛错，自此
    /// 只许经这一处取值）
    public static func from(health: HealthResponse) -> ServiceHealth {
        health.isOK ? .up : .down
    }
}

// MARK: - 提供商探针结局 → 统一词表

extension ProviderConnectionOutcome {
    /// 提供商直连探针（存前验钥）保持独立客户端，但
    /// 其结局的状态词并入本表：连通拿到目录 → up；
    /// 接口通了但没返回目录 → degraded（通了、功能
    /// 打折，与伴生模块降级同档）；没连上 → down
    public var serviceHealth: ServiceHealth {
        switch self {
        case .connected: return .up
        case .connectedNoCatalog: return .degraded
        case .failed: return .down
        }
    }
}
