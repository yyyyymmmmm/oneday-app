import Foundation

/// 三步探活与各接口的失败口径：每个 case 自带「人话」文案，
/// 连接页与各功能页直接显示 userMessage，不许把状态码甩给用户。
public enum HermesError: Error, Sendable {
    /// 地址归一化失败（连接页表单层）
    case invalidServerAddress
    /// 网络层失败：连不上、超时、DNS 等（附系统错误简述）
    case unreachable(String)
    /// 网络瞬断类失败（0.20.0）：连接被中途掐断/系统
    /// 报无网/超时/连不上主机——多为 Wi-Fi 抖动、旁路
    /// 由代理路径瞬断一类可恢复故障，与「地址配错」是
    /// 两回事：文案只提示重试、不许甩锅让用户查地址
    /// （用户 2026-11-09 23:35 真机实证：顶栏胶囊走总
    /// 览桥轮询显示「在线」、发送请求却在此类失败上被
    /// 旧文案误导去查地址）。发送链对此类失败自动重
    /// 试一次（未产出任何内容时，见 ChatView.runStream）
    case transientNetwork
    /// 第一步 /health 非 200
    case healthCheckFailed(status: Int)
    /// 第二步登录被拒：账号或密码不对（401/403/422）
    case loginRejected
    /// 第二步登录返回了非预期状态
    case loginFailed(status: Int)
    /// 第三步 API 密钥被拒（401/403）
    case apiKeyRejected
    /// 接口返回非预期状态（附接口名与状态码）
    case unexpectedStatus(endpoint: String, status: Int)
    /// 会话删除被服务端以 session_busy 拒（有 turn 在
    /// 跑或排队，围栏契约下不许删，见删除 409 热修
    /// 报告 §1.3）：与裸状态码是两回事——文案必须让
    /// 用户知道是「还在运行中」而不是「服务器出错」
    case sessionBusy
    /// 服务端以结构化错误码拒（网关面 {"error":
    /// {"code":…}}，DESIGN §220）：状态码＋码本体随
    /// 错误上行，供 invalid_title 收养等按码分流判
    /// 定；文案与 unexpectedStatus 同口径（用户面无
    /// 变化）。旧形发送层丢响应体、码到不了逻辑层
    case serverError(endpoint: String, status: Int, code: String)
    /// 响应解码失败（版本不匹配的典型信号）
    case decodingFailed(endpoint: String)
    /// 会话过期且自动重登失败
    case sessionExpired
    /// 模型不在上游候选集内（网关别名等），写入已被拦截
    case modelNotUpstream(String)
    /// 用户主动停止生成 / 取消任务
    case cancelled
    /// 演示模式空态信号（复杂化全清·第 4 项，演示面
    /// 冻结清单）：清单外接口在 DemoHermesClient 不再
    /// 逐个写假实现，统一抛此信号；界面呈现统一文案
    /// 一条（userMessage），不许各面自拼演示文案。
    /// C-13 接口面冻结（2026-11-14）后，此信号同时是
    /// HermesClientProtocol 新增方法在 Demo 侧的唯一
    /// 合法桩形态（overcomplexity-audit-20261114 C-13）
    case demoLimitReached
    /// run 生成失败·账户余额或额度不足（基础止血包
    /// P5）：服务端终态原文只作分型输入（RunFailure-
    /// Classifier），界面只许呈现本档人话——原文直通
    /// 曾让用户对着英文报错、且有敏感回显先例，整路
    /// 禁绝（原文只进诊断日志）
    case runBillingExhausted
    /// run 生成失败·服务端/网关侧错误（5xx 家族）
    case runServiceUnavailable
    /// run 生成失败·超时
    case runTimedOut
    /// run 生成失败·网络断开
    case runNetworkInterrupted
    /// run 生成失败·分型判不出（兜底档，与旧「生成
    /// 失败，请稍后再试。」同义但走人话层单源）
    case runFailedGeneric

    public var userMessage: String {
        userMessage(locale: AppLocale.uiLocale)
    }

    /// 人话文案的目录取词形（0.42.1 国际化长尾包）：
    /// 状态码经 %@ 形目录键拼入（显示文本与旧版逐字
    /// 一致）；endpoint 名是调用方给的接口人话名，随
    /// 调用方的语言解析
    public func userMessage(locale: Locale) -> String {
        switch self {
        case .invalidServerAddress:
            return L10n.string(
                "服务器地址看起来不对，检查一下再试。", locale: locale
            )
        case .unreachable(let detail):
            return L10n.format(
                "连不上服务器（%@）。检查地址是否正确、服务器是否在线。",
                locale: locale, detail
            )
        case .transientNetwork:
            return L10n.string(
                "网络好像断了一下，这条没发出去。等网络稳一点，再发一次试试。",
                locale: locale
            )
        case .healthCheckFailed(let status):
            return L10n.format(
                "服务器健康检查没通过（状态 %@），可能不是 Hermes 服务，或版本太旧。",
                locale: locale, String(status)
            )
        case .loginRejected:
            return L10n.string("登录被拒：面板账号或密码不对。", locale: locale)
        case .loginFailed(let status):
            return L10n.format(
                "登录失败（状态 %@），请稍后再试。",
                locale: locale, String(status)
            )
        case .apiKeyRejected:
            return L10n.string(
                "API 密钥被拒：检查密钥是否填对、是否已被撤销。", locale: locale
            )
        case .unexpectedStatus(let endpoint, let status):
            return L10n.format(
                "%@ 返回了状态 %@，请稍后再试。",
                locale: locale, endpoint, String(status)
            )
        case .sessionBusy:
            return L10n.string(
                "这条会话还在运行中，等它跑完再删。", locale: locale
            )
        case .serverError(let endpoint, let status, _):
            return L10n.format(
                "%@ 返回了状态 %@，请稍后再试。",
                locale: locale, endpoint, String(status)
            )
        case .decodingFailed(let endpoint):
            return L10n.format(
                "%@ 的返回看不懂，可能是服务端版本与 App 不匹配。",
                locale: locale, endpoint
            )
        case .sessionExpired:
            return L10n.string("登录已过期，重新登录后再试。", locale: locale)
        case .modelNotUpstream(let model):
            return L10n.format(
                "「%@」是网关内部的别名，不能设为默认模型，这次没有写入。",
                locale: locale, model
            )
        case .cancelled:
            return L10n.string("已取消。", locale: locale)
        case .demoLimitReached:
            return L10n.string(
                "演示模式到此为止，连接你的服务器后可用。",
                locale: locale
            )
        case .runBillingExhausted:
            return L10n.string(
                "生成失败：账户余额或额度不足，处理好后再试。",
                locale: locale
            )
        case .runServiceUnavailable:
            return L10n.string(
                "生成失败：服务器那边出了点问题，稍后再试。",
                locale: locale
            )
        case .runTimedOut:
            return L10n.string(
                "生成超时了，稍后再试一次。",
                locale: locale
            )
        case .runNetworkInterrupted:
            return L10n.string(
                "网络断开了，生成没能完成。等网络恢复后再试。",
                locale: locale
            )
        case .runFailedGeneric:
            return L10n.string(
                "生成失败，请稍后再试。",
                locale: locale
            )
        }
    }

    /// 是否瞬断类（可自动重试一次）：只有 transient-
    /// Network——其余失败（鉴权/状态码/解码）重试无益
    public var isTransient: Bool {
        if case .transientNetwork = self { return true }
        return false
    }

    /// 是否「对象不存在」（§223 删除全域收口）：接
    /// 口回 404——点开本地残留行导入会话时撞上它，
    /// 含义是会话已在服务端消失（他处已删），不是
    /// 服务器出错；呈现层据此走清本地残留＋人话提
    /// 示，不许把状态码原文甩给用户
    public var isSessionNotFound: Bool {
        if case .unexpectedStatus(_, let status) = self {
            return status == 404
        }
        return false
    }

    /// URLError → 失败分型（0.20.0）：分型表收进 Core
    /// 纯函数单测把守，客户端 transport 层只许调它、
    /// 不许再自拼映射（旧映射把 .networkConnectionLost
    /// 与 .notConnectedToInternet 都塞进 unreachable
    /// 「网络不可用＋查地址」一档，即 23:35 词与事实
    /// 打架的出处）。
    /// - 瞬断档（transientNetwork）：超时、连接丢失、
    ///   系统报无网、连不上主机、蜂窝受限——路径抖动
    ///   优先归因（顶栏另有桥轮询的在线信号可互证，
    ///   此档文案不提地址对用户更诚实）；
    /// - 地址档（unreachable）：只有主机名解析失败
    ///   （找不到主机/DNS）才配让用户查地址；
    /// - 其余网络错误归 unreachable「网络错误」。
    public static func fromURLError(
        _ error: URLError, locale: Locale = AppLocale.uiLocale
    ) -> HermesError {
        switch error.code {
        case .timedOut, .networkConnectionLost,
             .notConnectedToInternet, .cannotConnectToHost,
             .dataNotAllowed, .internationalRoamingOff:
            return .transientNetwork
        case .cannotFindHost, .dnsLookupFailed:
            return .unreachable(L10n.string("无法建立连接", locale: locale))
        default:
            return .unreachable(L10n.string("网络错误", locale: locale))
        }
    }
}
