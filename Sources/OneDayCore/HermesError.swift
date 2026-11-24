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
    /// 确定未发出（§414 增补，断网发送态规格 5.2）：
    /// 设备侧确定事实——无网络接口/蜂窝数据被禁，
    /// 请求根本不可能出设备（URLError.notConnected-
    /// ToInternet/.dataNotAllowed）。与 transientNet-
    /// work 的「可能已达服务端、回执丢失」真未知是
    /// 两回事：不许同桶按结果未知处理（对账 600 秒
    /// 假生成即此误伤）。发送提交段对此分型不判未
    /// 知、不进对账，直接折回待发巷等网络恢复续发
    case notSentOffline
    /// 第一步 /health 非 200
    case healthCheckFailed(status: Int)
    /// 第二步登录被拒：密码不对（401/403）
    case loginRejected
    /// 第二步登录被限速（429）：伴生登录桥与面板登录
    /// 同一限速池，试太多次要等几分钟（§244）
    case loginRateLimited
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
    /// 朗读 provider 未开通（H2-a，台账 159）：speak
    /// 400 的 detail 明示「No TTS provider availa-
    /// ble」——与裸状态码分开：客户端据此把朗读可
    /// 用性精修为「未开通」并收起入口，文案不许把
    /// 「还没开通」说成「朗读失败」
    case speechProviderUnavailable
    /// 认领码无效（配对一期，网关 401 enrollment_
    /// code_invalid）：码不对、已被认领过、或出码太
    /// 久已被清——服务端同码回应，客户端不许替用户
    /// 猜是哪一种
    case enrollmentCodeInvalid
    /// 认领码过期（配对一期，网关 410 enrollment_
    /// code_expired）：码还在但过了 5 分钟有效期，
    /// 与「无效」分开说文案
    case enrollmentCodeExpired
    /// 认领被锁定（配对一期，网关 429 enrollment_
    /// locked）：错码试太多次，服务端锁 10 分钟
    case enrollmentLocked
    /// 出码超限（配对一期，网关 429 enrollment_too_
    /// many_pending）：未被认领的码已达上限（3 个）
    case enrollmentTooManyPending
    /// 推送登记端点未开通（总表 138，DESIGN §397）：网关
    /// 404——部署包批 4b 的登记端点还没装机；与一般 404
    /// 分开，登记状态机据此记 serverNotReady 如实呈现
    case pushEndpointNotReady
    /// 反应目标行已不在（台账 187，网关 404 message_
    /// not_found）：会话谱系里已无此行（多为该消息已
    /// 被删/会话已重建）——与裸 404 分开：客户端据此
    /// 回滚乐观镜像并给人话，不许把状态码甩给用户
    case reactionTargetGone
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
        case .notSentOffline:
            return L10n.string(
                "设备现在没有网络，这条还没发出去。网络恢复后会自动发送。",
                locale: locale
            )
        case .healthCheckFailed:
            return L10n.string(
                "服务器健康检查没通过，可能不是 Hermes 服务，或版本太旧。",
                locale: locale
            )
        case .loginRejected:
            return L10n.string("登录被拒：密码不对（和伴生面板、网页端同一把）。", locale: locale)
        case .loginRateLimited:
            return L10n.string("登录试太多次了，请几分钟后再试。", locale: locale)
        case .loginFailed:
            return L10n.string(
                "登录失败，请稍后再试。", locale: locale
            )
        case .apiKeyRejected:
            return L10n.string(
                "API 密钥被拒：检查密钥是否填对、是否已被撤销。", locale: locale
            )
        case .unexpectedStatus:
            return L10n.string(
                "服务器没能处理这个请求，请稍后再试。",
                locale: locale
            )
        case .sessionBusy:
            return L10n.string(
                "这条会话还在运行中，等它跑完再删。", locale: locale
            )
        case .serverError:
            return L10n.string(
                "服务器没能处理这个请求，请稍后再试。",
                locale: locale
            )
        case .decodingFailed:
            return L10n.string(
                "服务器的返回看不懂，可能是服务端版本与 App 不匹配。",
                locale: locale
            )
        case .speechProviderUnavailable:
            return L10n.string(
                "这台服务器还没开通朗读。", locale: locale
            )
        case .enrollmentCodeInvalid:
            return L10n.string(
                "这个认领码不对，或者已经被用过了。在出码的那台设备上重新生成一个，再扫一次。",
                locale: locale
            )
        case .enrollmentCodeExpired:
            return L10n.string(
                "这个认领码过期了，只管用 5 分钟。在出码的那台设备上重新生成一个，再扫一次。",
                locale: locale
            )
        case .enrollmentLocked:
            return L10n.string(
                "认领试错太多次，这台服务器先锁一会儿。过几分钟再试。",
                locale: locale
            )
        case .enrollmentTooManyPending:
            return L10n.string(
                "等着被认领的码已经满了。等几分钟让旧码过期，或者先用掉一个再生成。",
                locale: locale
            )
        case .pushEndpointNotReady:
            return L10n.string(
                "这台服务器还没开通推送登记。",
                locale: locale
            )
        case .reactionTargetGone:
            return L10n.string(
                "这条消息已不在了，反应没有生效。",
                locale: locale
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

    /// 是否朗读未开通（H2-a）：可用性精修的真值信号
    public var isSpeechProviderUnavailable: Bool {
        if case .speechProviderUnavailable = self { return true }
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
    /// - 未发出档（notSentOffline，§414 增补）：系统
    ///   报无网、蜂窝数据被禁——设备侧确定事实，请
    ///   求不可能出设备，与真未知分开（见 case 注）；
    /// - 瞬断档（transientNetwork）：超时、连接丢失、
    ///   连不上主机、漫游关——请求可能已达服务端、
    ///   回执丢失的真未知，路径抖动优先归因（顶栏
    ///   另有桥轮询的在线信号可互证，此档文案不提
    ///   地址对用户更诚实）；
    /// - 地址档（unreachable）：只有主机名解析失败
    ///   （找不到主机/DNS）才配让用户查地址；
    /// - 其余网络错误归 unreachable「网络错误」。
    public static func fromURLError(
        _ error: URLError, locale: Locale = AppLocale.uiLocale
    ) -> HermesError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return .notSentOffline
        case .timedOut, .networkConnectionLost,
             .cannotConnectToHost, .internationalRoamingOff:
            return .transientNetwork
        case .cannotFindHost, .dnsLookupFailed:
            return .unreachable(L10n.string("无法建立连接", locale: locale))
        default:
            return .unreachable(L10n.string("网络错误", locale: locale))
        }
    }
}

/// 错误大类（G-03，DESIGN §389）：错误横幅的人话主
/// 文案按类取底表——网络/鉴权/服务端/未知四类。分
/// 类只认错误本体形态，不读文案字符串（防文案改字
/// 漂移分类）。
public enum HermesErrorCategory: String, CaseIterable, Sendable {
    case network
    case authentication
    case server
    case unknown

    /// 四类底表（横幅主文案的最后兜底：错误本体没
    /// 有更具体的人话时按类取此句；具体人话在
    /// HermesError.userMessage，两者不许互相冒充）
    public func headline(locale: Locale) -> String {
        switch self {
        case .network:
            return L10n.string(
                "网络好像不太稳，这一步没能完成。等网络恢复后再试一次。",
                locale: locale
            )
        case .authentication:
            return L10n.string(
                "登录状态失效了，重新登录后再试。",
                locale: locale
            )
        case .server:
            return L10n.string(
                "服务器那边出了点问题，这一步没能完成，请稍后再试。",
                locale: locale
            )
        case .unknown:
            return L10n.string(
                "这一步没能完成，请稍后再试。",
                locale: locale
            )
        }
    }
}

extension HermesError {
    /// 本错误归入的横幅大类（§389 映射表）：
    /// - network：连不上/瞬断/run 网络中断——路径抖
    ///   动优先归因，不许甩锅地址；
    /// - authentication：登录/密钥/会话/认领码家族
    ///   ——用户的下一步是重新登录或重新出码；
    /// - server：服务端明确回错或其能力信号（健康
    ///   检查/状态码/解码/欠费/超时/未开通等）；
    /// - unknown：客户端校验与判不出的一律落此，
    ///   不许冒充已分类。
    public var category: HermesErrorCategory {
        switch self {
        case .unreachable, .transientNetwork, .notSentOffline,
             .runNetworkInterrupted:
            return .network
        case .loginRejected, .loginRateLimited, .loginFailed,
             .apiKeyRejected, .sessionExpired,
             .enrollmentCodeInvalid, .enrollmentCodeExpired,
             .enrollmentLocked, .enrollmentTooManyPending:
            return .authentication
        case .healthCheckFailed, .unexpectedStatus, .serverError,
             .decodingFailed, .sessionBusy,
             .speechProviderUnavailable, .reactionTargetGone,
             .modelNotUpstream,
             .runBillingExhausted, .runServiceUnavailable,
             .runTimedOut, .pushEndpointNotReady:
            return .server
        case .invalidServerAddress, .cancelled, .demoLimitReached,
             .runFailedGeneric:
            return .unknown
        }
    }

    /// 诊断详情（G-03）：状态码/接口名/错误码只许
    /// 进这里——错误横幅的「详情」展开与诊断日志共
    /// 用，用户主文案（userMessage）永不带这些。无
    /// 技术细节可给的错误返回 nil（横幅不显详情钮）
    public var diagnosticDetail: String? {
        switch self {
        case .healthCheckFailed(let status):
            return "健康检查 · HTTP \(status)"
        case .loginFailed(let status):
            return "登录 · HTTP \(status)"
        case .unexpectedStatus(let endpoint, let status):
            return "\(endpoint) · HTTP \(status)"
        case .serverError(let endpoint, let status, let code):
            return "\(endpoint) · HTTP \(status) · \(code)"
        case .decodingFailed(let endpoint):
            return "\(endpoint) · 响应解码失败"
        case .unreachable(let detail):
            return detail
        default:
            return nil
        }
    }

    /// 是否分页契约被拒（台账 117，§389）：/messages
    /// 分页被服务端以 400 invalid_pagination 拒——
    /// 历史拉取链据此降级无参全量拉取。结构化码在
    /// 场时只认码本体；裸 unexpectedStatus 无码可
    /// 验，在分页调用点语境下 400 只此一种成因，按
    /// 状态码认。
    public var isPaginationRejected: Bool {
        switch self {
        case .serverError(_, let status, let code):
            return status == 400 && code == "invalid_pagination"
        case .unexpectedStatus(_, let status):
            return status == 400
        default:
            return false
        }
    }
}
