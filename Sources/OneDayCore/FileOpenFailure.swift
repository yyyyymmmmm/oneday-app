import Foundation

/// 文件打开失败五分（§121 题二 b，ekko D2/B4 对账）：
/// 旧形态三处取文件失败（聊天文件牌、文件页预览、
/// 文档阅读页）都只给一句 HermesError.userMessage
/// 兜底——「文件下载 返回了状态 404，请稍后再试」
/// 把状态码甩给用户、原因与出路全无。本分类器把
/// 失败按因收成定式文案，落点只消费 message(for:)：
/// - notFound 不存在：服务端 404（Hermes files.py
///   实证「File not found」）；
/// - tooLarge 过大：服务端 413（上限 100MiB）；
/// - serviceUnavailable 服务不可用：5xx／登录态失
///   效／连不上主机；
/// - timeout 超时：网络瞬断档（含 URLError 超时，
///   HermesError.fromURLError 已并入 transient-
///   Network）；
/// - invalidPath 路径无效：服务端 400（非文件）或
///   客户端预检空路径；
/// - forbidden 服务器拒绝：403 敏感路径——五分之外
///   加一档，403 与「路径不对」是两回事不许混；
/// - unsupportedType 没法预览：字节已取到、QL 无资
///   格（canPreviewItem 为假），落下载/分享档；
/// - other 其余：保留旧兜底句，不冒充已分类。
public enum FileOpenFailure: String, CaseIterable, Sendable {
    case notFound
    case tooLarge
    case serviceUnavailable
    case timeout
    case invalidPath
    case forbidden
    case unsupportedType
    case transcodeFailed
    case other

    /// 客户端预检：空路径（或纯空白）不必发请求、
    /// 直接判路径无效——服务端路径由牌/条目数据给
    /// 出，空串只可能是数据损坏
    public static func isInvalidPath(_ path: String) -> Bool {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// HermesError → 失败分型（状态码锚点以 Hermes
    /// web_routers/files.py 实证为准：404 不存在、
    /// 413 过大、400 非文件、403 敏感拒绝）
    public static func classify(
        error: HermesError
    ) -> FileOpenFailure {
        switch error {
        case .unexpectedStatus(_, let status):
            switch status {
            case 404: return .notFound
            case 413: return .tooLarge
            case 400: return .invalidPath
            case 403: return .forbidden
            case 401: return .serviceUnavailable
            case 500...599: return .serviceUnavailable
            default: return .other
            }
        case .transientNetwork:
            return .timeout
        case .unreachable, .healthCheckFailed,
             .sessionExpired, .loginRejected,
             .loginFailed, .apiKeyRejected:
            return .serviceUnavailable
        case .invalidServerAddress, .decodingFailed,
             .modelNotUpstream, .cancelled,
             .demoLimitReached,
             .runBillingExhausted, .runServiceUnavailable,
             .runTimedOut, .runNetworkInterrupted,
             .runFailedGeneric:
            // demoLimitReached（第 4 项空态信号）：文件
            // 读面在演示里是保留面、本分型实际不会收到
            // 它；归 other 兜底，不冒充已分类
            // run 五档（基础止血包 P5）：是落定失败的
            // 呈现值、由分型器合成，从不由文件取回路
            // 抛出；同理归 other，不冒充文件侧已分类
            return .other
        }
    }

    /// 表格转码失败分型（§125）：伴生转码端点 422
    /// （文件损坏/格式读不出）专档 transcodeFailed，
    /// 其余状态码与下载同规走 classify——转码失败不
    /// 许混进「没法预览」，两者出路不同（转码可换下
    /// 载原文件用别的 App 开）
    public static func classifySpreadsheet(
        error: HermesError
    ) -> FileOpenFailure {
        if case .unexpectedStatus(_, let status) = error,
           status == 422 {
            return .transcodeFailed
        }
        return classify(error: error)
    }

    /// 人话文案（目录取词形，与 HermesError 同口径）
    public func message(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch self {
        case .notFound:
            return L10n.string(
                "服务器上没有这个文件，可能已被移动或删除。",
                locale: locale
            )
        case .tooLarge:
            return L10n.string(
                "文件太大了，没法直接打开；可以先下载到本地再看。",
                locale: locale
            )
        case .serviceUnavailable:
            return L10n.string(
                "服务器暂时连不上，稍后再试。", locale: locale
            )
        case .timeout:
            return L10n.string(
                "打开超时，网络可能不稳，稍后再试。",
                locale: locale
            )
        case .invalidPath:
            return L10n.string(
                "这个文件的路径不对，打不开。", locale: locale
            )
        case .forbidden:
            return L10n.string(
                "这个文件不允许在 App 里打开。", locale: locale
            )
        case .unsupportedType:
            return L10n.string(
                "这个类型没法直接预览，可以下载到本地再打开。",
                locale: locale
            )
        case .transcodeFailed:
            return L10n.string(
                "表格转换失败，没能读出内容；可以下载原文件再打开。",
                locale: locale
            )
        case .other:
            return L10n.string(
                "文件打开失败，请稍后再试。", locale: locale
            )
        }
    }
}
