import Foundation

/// 引导连接四步（引导线预制，蓝本＝用户 2026-11-11 亲递
/// 原型 oneday-prototype.html 的 connecting 面）：地址格
/// 式／服务器可达／凭据有效／读取服务信息。每步状态只
/// 来自真实请求结果，不许定时动画假走（原型 runConnect
/// 的 setTimeout 推进是演示手法、产品不学）。
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case addressFormat
    case serverReachable
    case credentialValid
    case serviceInfo

    public func label(locale: Locale = AppLocale.uiLocale) -> String {
        switch self {
        case .addressFormat: return L10n.string("地址格式", locale: locale)
        case .serverReachable: return L10n.string("服务器可达", locale: locale)
        case .credentialValid: return L10n.string("凭据有效", locale: locale)
        case .serviceInfo: return L10n.string("读取服务信息", locale: locale)
        }
    }
}

/// 连接失败分型（失败面按型给话与出口：重试／改信息／
/// 看帮助三出口恒在，文案按型分）。判定只认结构信号
/// （步位＋错误种类），不靠错误文案文本猜。
public enum OnboardingFailureKind: String, Sendable, Equatable {
    /// 地址格式不合法（本地校验，未发请求）
    case invalidAddress
    /// 服务器无响应：连不上／超时／健康检查不过
    case unreachable
    /// 凭据被拒：账号密码不对，或密钥无效
    case credentialRejected
    /// 密码验证已过，但服务器没能交出登录密钥
    /// （/api/env/reveal 取不到 API_SERVER_KEY）——
    /// 密码一步制整链的诚实降级点，不许假装连上
    case keyUnavailable
    /// 其余失败（如实呈现，不编造原因）
    case other
}

/// 一次连接失败的完整定性：倒在哪一步、属哪一型。
public struct OnboardingFailure: Error, Sendable, Equatable {
    public let step: OnboardingStep
    public let kind: OnboardingFailureKind

    public init(step: OnboardingStep, kind: OnboardingFailureKind) {
        self.step = step
        self.kind = kind
    }

    /// HermesError → 分型（步位由调用方给：同一种错误
    /// 落在哪一步语义不同——如 unreachable 在可达步是
    /// 「找不到服务器」、在凭据步是链路中途断，如实归
    /// unreachable 型即可，失败面文案不细究步位）。
    public static func classify(
        step: OnboardingStep, error: HermesError
    ) -> OnboardingFailure {
        let kind: OnboardingFailureKind
        switch error {
        case .invalidServerAddress:
            kind = .invalidAddress
        case .unreachable, .transientNetwork, .healthCheckFailed:
            kind = .unreachable
        case .loginRejected, .apiKeyRejected:
            kind = .credentialRejected
        case .cancelled:
            kind = .other
        default:
            kind = .other
        }
        return OnboardingFailure(step: step, kind: kind)
    }

    /// 任意错误 → 分型（HermesError 走上表；已是本型
    /// 直通；其余归 other，不编造）
    public static func classify(
        step: OnboardingStep, error: Error
    ) -> OnboardingFailure {
        if let failure = error as? OnboardingFailure { return failure }
        if let hermes = error as? HermesError {
            return classify(step: step, error: hermes)
        }
        return OnboardingFailure(step: step, kind: .other)
    }

    /// 失败面标题（按型）
    public func headline(locale: Locale = AppLocale.uiLocale) -> String {
        switch kind {
        case .invalidAddress:
            return L10n.string("地址看起来不对", locale: locale)
        case .unreachable:
            return L10n.string("找不到这台服务器", locale: locale)
        case .credentialRejected:
            return L10n.string("凭据未通过验证", locale: locale)
        case .keyUnavailable:
            return L10n.string("服务器没有交出登录密钥", locale: locale)
        case .other:
            return L10n.string("连接没成功", locale: locale)
        }
    }

    /// 失败面说明（按型，只说已知事实与可操作建议）
    public func advice(locale: Locale = AppLocale.uiLocale) -> String {
        switch kind {
        case .invalidAddress:
            return L10n.string(
                "请输入完整地址，例如 https://hermes.example.com。",
                locale: locale
            )
        case .unreachable:
            return L10n.string(
                "请确认地址正确、服务器已启动，并且当前网络可以访问。企业网络或代理可能拦截请求。",
                locale: locale
            )
        case .credentialRejected:
            return L10n.string(
                "请确认填的凭据与服务器上的一致，是否已被撤销或改过，然后重试。",
                locale: locale
            )
        case .keyUnavailable:
            return L10n.string(
                "你的账号密码是对的，但这台服务器没有返回登录密钥（API_SERVER_KEY）。请检查服务器配置，或改用密钥登录。",
                locale: locale
            )
        case .other:
            return L10n.string(
                "可以重试一次；还不行就修改连接信息，或看看连接帮助。",
                locale: locale
            )
        }
    }
}

/// 连接成功面的服务信息（全部取本次连接实测值；取不
/// 到的项为 nil、呈现层整项不显示、不编造——如密钥登
/// 录没有面板会话、读不到模型目录数，就不显示模型数）。
public struct ConnectionServiceInfo: Sendable, Equatable {
    /// 服务器 host（如 hermes.didichou.site）
    public let host: String
    /// Hermes 版本（/health 或 /api/status 实测）
    public let hermesVersion: String?
    /// 可用模型数（/api/model/options 实测；仅密码登录
    /// 链有面板会话可读，密钥链为 nil）
    public let modelCount: Int?
    /// 健康检查往返延迟（毫秒，本次实测）
    public let latencyMs: Int?

    public init(
        host: String, hermesVersion: String?,
        modelCount: Int?, latencyMs: Int?
    ) {
        self.host = host
        self.hermesVersion = hermesVersion
        self.modelCount = modelCount
        self.latencyMs = latencyMs
    }

    /// 摘要行：只拼有值的项，「Hermes 0.23.0 · 12 个
    /// 可用模型 · 延迟 82 ms」；全空返回空串（整行不显）
    public func summaryLine(locale: Locale = AppLocale.uiLocale) -> String {
        var parts: [String] = []
        if let hermesVersion, !hermesVersion.isEmpty {
            parts.append("Hermes \(hermesVersion)")
        }
        if let modelCount {
            parts.append(
                L10n.format("%lld 个可用模型", locale: locale, modelCount)
            )
        }
        if let latencyMs {
            parts.append(
                L10n.format("延迟 %lld ms", locale: locale, latencyMs)
            )
        }
        return parts.joined(separator: " · ")
    }
}

/// 首次聊天空态的建议条（原型 chat 面三条）：点按即
/// 发送。文案是给智能体的真实问句，不编造能力。
public enum EmptyChatSuggestions {
    public static let texts: [String] = [
        "今天服务器状态怎么样？",
        "把这周的会议整理成纪要",
        "有哪些定时任务在跑？",
    ]

    /// 与 texts 同序的 SF Symbols 名（呈现层用）
    public static let symbols: [String] = [
        "server.rack", "doc.text", "clock",
    ]
}
