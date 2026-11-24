import Foundation

/// 发送失败成因分类＋文案单表（发送失败机制包，
/// DESIGN 审查 2026-11-24 第四节语义 3/5）。
///
/// 病根（原机制为何能让 bug 存在）：失败落点只写
/// 一个 .failed 状态、成因随 HermesError 在各出口
/// 自行散落——自动重试政策只看状态不看成因，5xx/
/// 凭据/模型拒与网络抖动同等待遇全进自动重试名
/// 单；呈现层没有成因可读，只能一句「服务器没能
/// 处理」包打天下。本文件把成因收成一处：失败落
/// 点必写 kind 进发件箱重试账（OutboxRetryRecord.
/// lastFailureKind），政策准入、呈现投影、文案取
/// 词全从 kind 一处出，不许再有第二本账。
///
/// 准入口径（对位 TG：失败即稳定终态、只等手点；
/// 自动续发只认传输层与服务端明示的等待）：
/// - 可自动：未出门（离线未发出）、传输中断、连
///   不上主机——请求没被服务端明确处置过，重投
///   无副作用语义；
/// - 等待门：限流——不算失败、不落 failed，按服
///   务端 Retry-After 等待后自动续（提交段内处
///   置，不进本表判定）；
/// - 钉死等手点：一切明确拒绝（5xx/4xx 业务拒绝/
///   队列满/凭据/欠费/模型拒）、准备段失败、一切
///   运行面失败（生成失败永不自动重发——重发即
///   重跑生成，成本与副作用由用户决定）、判不出
///   的未知成因（保守钉死）。
public enum SendFailureKind: String, Codable, CaseIterable,
    Equatable, Sendable {
    // MARK: 提交面
    /// 设备确定无网、请求没出设备（notSentOffline）
    case offlineNotSent
    /// 传输中断/超时：请求可能已达、回执丢失
    case transportInterrupted
    /// 连不上主机（DNS/拒绝连接）：地址或服务在否
    /// 未定，有界重试无害、文案保留查地址指引
    case hostUnreachable
    /// 限流（429）：等待门，不算失败
    case rateLimited
    /// 队列满（409 queue_full）
    case queueFull
    /// 凭据/会话失效（401/403/会话过期）
    case authRejected
    /// 欠费（402）
    case billingRejected
    /// 模型被拒/不在上游
    case modelRejected
    /// 服务端 5xx 明确拒绝
    case serverRejected
    /// 其余 4xx 业务明确拒绝（含 session_busy）
    case businessRejected
    /// 准备段失败（上传/链接，离线停泊不走此路）
    case prepareFailed
    // MARK: 运行面（生成失败：run 已落定失败）
    case runBilling
    case runTimeout
    case runNetwork
    case runService
    case runGeneric
    /// run 结果丢失终局（对账跨访问累计耗尽，语义 7）
    case runResultLost
    /// 判不出成因：保守钉死
    case unknown

    /// 是否准入自动重试（政策单源读此位）
    public var allowsAutoRetry: Bool {
        switch self {
        case .offlineNotSent, .transportInterrupted,
             .hostUnreachable:
            return true
        case .rateLimited, .queueFull, .authRejected,
             .billingRejected, .modelRejected,
             .serverRejected, .businessRejected,
             .prepareFailed,
             .runBilling, .runTimeout, .runNetwork,
             .runService, .runGeneric, .runResultLost,
             .unknown:
            return false
        }
    }

    /// 是否限流等待门（不算失败、不落失败面）
    public var isWaitGate: Bool { self == .rateLimited }

    /// 是否全局状况（呈现投影单源读此位：全局面才
    /// 出横幅；单条失败只行内叹号＋小提示）：凭据
    /// 失效与服务不可用（5xx）影响整面发送
    public var presentsGlobally: Bool {
        switch self {
        case .authRejected, .serverRejected:
            return true
        default:
            return false
        }
    }

    /// 是否运行面成因（生成侧失败，与提交面分面
    /// 分句：用户须分清「没发出去」与「发了没跑成」）
    public var isRunFace: Bool {
        switch self {
        case .runBilling, .runTimeout, .runNetwork,
             .runService, .runGeneric, .runResultLost:
            return true
        default:
            return false
        }
    }

    /// 提交面成因分类（HermesError → kind）：状态码
    /// 与结构化码优先，判不出落 .unknown 钉死
    public static func classify(
        submit error: HermesError
    ) -> SendFailureKind {
        switch error {
        case .notSentOffline:
            return .offlineNotSent
        case .transientNetwork:
            return .transportInterrupted
        case .unreachable:
            return .hostUnreachable
        case .rateLimited:
            return .rateLimited
        case .apiKeyRejected, .loginRejected, .sessionExpired:
            return .authRejected
        case .modelNotUpstream:
            return .modelRejected
        case .sessionBusy:
            return .businessRejected
        case .unexpectedStatus(_, let status):
            return classify(status: status, code: nil)
        case .serverError(_, let status, let code):
            return classify(status: status, code: code)
        case .runBillingExhausted, .runTimedOut,
             .runNetworkInterrupted, .runServiceUnavailable,
             .runFailedGeneric:
            return classify(run: error)
        default:
            return .unknown
        }
    }

    /// 运行面成因分类（run 终态分型后的 HermesError
    /// 五档 → kind）：非 run 档回提交面口径兜底
    public static func classify(
        run error: HermesError
    ) -> SendFailureKind {
        switch error {
        case .runBillingExhausted:
            return .runBilling
        case .runTimedOut:
            return .runTimeout
        case .runNetworkInterrupted:
            return .runNetwork
        case .runServiceUnavailable:
            return .runService
        case .runFailedGeneric:
            return .runGeneric
        default:
            return classify(submit: error)
        }
    }

    private static func classify(
        status: Int, code: String?
    ) -> SendFailureKind {
        if code == "queue_full" { return .queueFull }
        switch status {
        case 401, 403:
            return .authRejected
        case 402:
            return .billingRejected
        case 409:
            return .queueFull
        case 429:
            return .rateLimited
        case 500...599:
            return .serverRejected
        case 400...499:
            return .businessRejected
        default:
            return .unknown
        }
    }
}

/// 失败文案单表（面×成因 → 人话）：发送链的失败
/// 呈现只许从本表取词，不许调用点自拼整句（横扫
/// P2/P5 关账点）。run 面五句与 HermesError 的
/// run* 档现行人话逐字同源（那五档本就是分型后
/// 的人话层，两处同句不许漂移——钉测对账）。
public enum SendFailureCopy {
    public static func message(
        kind: SendFailureKind
    ) -> String {
        message(kind: kind, locale: AppLocale.uiLocale)
    }

    public static func message(
        kind: SendFailureKind, locale: Locale
    ) -> String {
        switch kind {
        case .offlineNotSent:
            return L10n.string(
                "设备现在没有网络，这条还没发出去。网络恢复后会自动发送。",
                locale: locale
            )
        case .transportInterrupted:
            return L10n.string(
                "网络好像断了一下，这条没发出去。网络恢复后会自动再试，也可以点这条消息旁的感叹号重新发送。",
                locale: locale
            )
        case .hostUnreachable:
            return L10n.string(
                "连不上服务器，这条没发出去。检查地址是否正确、服务器是否在线。",
                locale: locale
            )
        case .rateLimited:
            return L10n.string(
                "发送太频繁了，服务器让稍等一下，会自动继续。",
                locale: locale
            )
        case .queueFull:
            return L10n.string(
                "这条会话的排队已满，这条还没发出去。等前面的处理完，再点这条消息旁的感叹号重新发送。",
                locale: locale
            )
        case .authRejected:
            return L10n.string(
                "登录状态失效了，这条没发出去。重新登录后再试。",
                locale: locale
            )
        case .billingRejected:
            return L10n.string(
                "账户余额或额度不足，这条没发出去。处理好后再试。",
                locale: locale
            )
        case .modelRejected:
            return L10n.string(
                "这个模型被服务端拒绝了，这条没发出去。换个模型再试。",
                locale: locale
            )
        case .serverRejected:
            return L10n.string(
                "服务器内部错误，这条没发出去，请稍后再试。",
                locale: locale
            )
        case .businessRejected:
            return L10n.string(
                "服务器拒绝了这条请求，这条还没发出去。改一下内容再试，或稍后再试。",
                locale: locale
            )
        case .prepareFailed:
            return L10n.string(
                "这条的准备步骤没完成，还没发出去。处理后点这条消息旁的感叹号重新发送。",
                locale: locale
            )
        case .runBilling:
            return L10n.string(
                "生成失败：账户余额或额度不足，处理好后再试。",
                locale: locale
            )
        case .runTimeout:
            return L10n.string(
                "生成超时了，稍后再试一次。",
                locale: locale
            )
        case .runNetwork:
            return L10n.string(
                "网络断开了，生成没能完成。等网络恢复后再试。",
                locale: locale
            )
        case .runService:
            return L10n.string(
                "生成失败：服务器那边出了点问题，稍后再试。",
                locale: locale
            )
        case .runGeneric:
            return L10n.string(
                "生成失败，请稍后再试。",
                locale: locale
            )
        case .runResultLost:
            return L10n.string(
                "这条的生成结果没能找回——服务器上已经查不到这一轮。可以点这条消息旁的感叹号重新发送。",
                locale: locale
            )
        case .unknown:
            return L10n.string(
                "这条没能完成，请稍后再试。",
                locale: locale
            )
        }
    }

    /// 拼接收尾归一（横扫 P2-1/P2-2 关账）：「头＋
    /// 自由文案＋尾」拼接点全走本函数——被拼文案
    /// 自带的尾标点先剥净，再由本函数统一补一个
    /// 句号，杜绝「请稍后再试。。链接恢复后…」式
    /// 双句号叠字。自由文案为空时只拼头尾
    public static func joiningReason(
        head: String, reason: String, tail: String
    ) -> String {
        var core = reason.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        while let last = core.last,
              "。．.！!？?".contains(last) {
            core.removeLast()
        }
        core = core.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !core.isEmpty else { return head + tail }
        return head + core + "。" + tail
    }
}
