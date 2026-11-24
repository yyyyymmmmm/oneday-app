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
        case .unreachable, .transientNetwork, .notSentOffline,
             .healthCheckFailed:
            // notSentOffline（§414 增补分型）：保形同
            // 落——拆分前经 transientNetwork 归本型
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
    /// 服务器 host（如 your-hermes.example.com）
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

// MARK: - 引导段与 needed() 判定（nanoMuse 引导线学习，2026-11-21）

/// 引导段（连接页首连流程的段位全集，声明顺序即呈
/// 现顺序）：连接段解决「这台手机凭什么连上我的
/// Hermes」，通知段把通知权限做成有理由的一课。段
/// 位只增不改序——needed() 的返回顺序就是流程顺序。
public enum GuideSegment: String, CaseIterable, Sendable {
    case connect
    case notifications
}

/// 引导的 needed() 判定（学 nanoMuse 的重入规则：
/// 引导只补缺口、已完成的段不重复出现）——纯函数，
/// 单测钉死全矩阵：
/// - connect：没有可用连接时才需要；
/// - notifications：仅当通知授权**未决定**时才需
///   要。已授权没什么可问；已拒绝不在引导里重问
///   （系统授权铁律：已决定状态不重问——想开的人
///   走系统设置或既有权限面，引导不纠缠）。
public enum OnboardingGuide {
    public static func neededSegments(
        hasConnection: Bool,
        notificationState: DevicePermissionState
    ) -> [GuideSegment] {
        var segments: [GuideSegment] = []
        if !hasConnection {
            segments.append(.connect)
        }
        if notificationState == .notDetermined {
            segments.append(.notifications)
        }
        return segments
    }
}

/// 权限请求段的主按钮动作（模板的状态机半边）：由
/// DevicePermissionGate 的铁律判定翻译成段内动作
/// ——未决定才发那一次请求；已授权只继续；已拒绝
/// 只给「去系统设置开启」的路，绝不在段里重走请
/// 求回调。
public enum PermissionSegmentAction: Equatable, Sendable {
    case requestOnce
    case continueNext
    case openSettings
}

/// 权限段的一条具体用途（图标名＋标题＋一行说明）：
/// 模板只许列具体用途、不许泛泛要权限（nanoMuse
/// 通知页口径：一页只解释两个用途、各配一行）。
public struct GuidePermissionUse: Equatable, Sendable {
    public let symbol: String
    public let title: String
    public let detail: String

    public init(symbol: String, title: String, detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// 通知权限段模板（学 nanoMuse 通知页：用途先行、
/// 两条具体用途、主按钮随状态变、可跳过、细字给
/// 退路）。动作判定与全部文案收在这一处：连接页
/// 引导段是第一个消费方，后续任何权限申请面共用
/// 同一套口径，不许各面自拟一套话术。
public enum NotificationGuideSegment {

    /// 状态 → 主按钮动作（过 DevicePermissionGate
    /// 铁律判定，不在本处另立第二套状态机）
    public static func action(
        for state: DevicePermissionState
    ) -> PermissionSegmentAction {
        switch DevicePermissionGate.decision(for: state) {
        case .proceed: return .continueNext
        case .requestOnce: return .requestOnce
        case .degrade: return .openSettings
        }
    }

    public static func title(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        L10n.string("通知", locale: locale)
    }

    /// 为什么先行：先讲清手机为什么醒不来、通知
    /// 补的是哪一步，再列用途，不先要权限。
    public static func intro(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        L10n.string(
            "任务在你的服务器上跑，手机锁屏后自己醒不来。这两种时刻，用一条通知把你带回来：",
            locale: locale
        )
    }

    /// 两条具体用途（与 Hermes 的真实能力对齐：
    /// 定时任务在服务端按时跑、长任务在服务端继
    /// 续跑——通知补的是「把人带回来」这一步）
    public static func useCases(
        locale: Locale = AppLocale.uiLocale
    ) -> [GuidePermissionUse] {
        [
            GuidePermissionUse(
                symbol: "clock",
                title: L10n.string("定时任务到点", locale: locale),
                detail: L10n.string(
                    "例行任务和目标检查点在服务器上按时运行，到点提醒你回来看结果。",
                    locale: locale
                )
            ),
            GuidePermissionUse(
                symbol: "checkmark.circle",
                title: L10n.string("长任务完成", locale: locale),
                detail: L10n.string(
                    "交给智能体的活干完后第一时间告诉你，不用守在旁边等。",
                    locale: locale
                )
            ),
        ]
    }

    /// 主按钮文案（随动作变；continueNext 的文案是
    /// 段内缺省词，宿主面可按自己在流程中的位置换
    /// 成终点词，如连接页换「开始聊天」）
    public static func primaryButtonTitle(
        for action: PermissionSegmentAction,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch action {
        case .requestOnce:
            return L10n.string("允许通知", locale: locale)
        case .continueNext:
            return L10n.string("继续", locale: locale)
        case .openSettings:
            return L10n.string("去系统设置开启", locale: locale)
        }
    }

    public static func skipTitle(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        L10n.string("暂时跳过", locale: locale)
    }

    /// 细字退路：没有它一切照常＋想开时去哪开，
    /// 两句说清，不施压。
    public static func finePrint(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        L10n.string(
            "没有通知，其他一切照常可用。想开时，在 iOS 设置 → OneDay 里随时开启。",
            locale: locale
        )
    }

    /// 已授权态的确认行（段内请求成功后呈现，给
    /// 这一步一个落定感再继续）
    public static func enabledNote(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        L10n.string("通知已开启", locale: locale)
    }
}

/// 聊天空态建议的冷启回落池：§455 起常态建议由
/// StarterSuggestionsEngine 以用户当下真实状态现算
/// （待批/目标/定时/资源库），本池只在上下文未就绪
/// 或真数据凑不满三条时补位。文案是给智能体的真实
/// 问句，不编造能力。
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
