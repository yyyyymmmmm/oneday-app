import Foundation

/// run 生成失败的分型（基础止血包 P5）：服务端终态
/// 回执里的 output/error 是原文字符串——旧链在落定
/// 失败分支把它直通 errorMessage 上屏，用户对着英
/// 文技术文本，且 2026-11-12 有错误回显敏感内容的
/// 先例。本分类器把原文收成 HermesError 五档人话，
/// 界面只许呈现分型结果；原文仅由调用方写诊断日志，
/// 永不直达界面。
///
/// 分型纪律：签名表刻意收窄——只有业内通行、形态
/// 稳定的信号（HTTP 402/5xx 状态码、insufficient/
/// balance/quota、timeout、网络断开词族）才认，判
/// 不出的一律落 .runFailedGeneric，不许靠扩表「猜
/// 满天飞」。状态码按数字边界匹配（防 15000 这类
/// 数字串误伤）；裸 connection 不认（太宽，会吞服
/// 务端连接池类错误）。判定顺序有意义：欠费（402
/// 最具体）→ 超时 → 网络 → 服务端 → 兜底。
public enum RunFailureClassifier {

    /// 终态回执（状态 output＋error 两字段）→ 人话档
    public static func classify(
        errorText: String?, outputText: String?
    ) -> HermesError {
        let haystack = [errorText, outputText]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        guard !haystack.isEmpty else { return .runFailedGeneric }
        if containsCode(haystack, "402")
            || matches(haystack, billingSignatures) {
            return .runBillingExhausted
        }
        if matches(haystack, timeoutSignatures) {
            return .runTimedOut
        }
        if matches(haystack, networkSignatures) {
            return .runNetworkInterrupted
        }
        if containsAnyCode(haystack, ["500", "502", "503", "504"])
            || matches(haystack, serviceSignatures) {
            return .runServiceUnavailable
        }
        return .runFailedGeneric
    }

    private static func matches(
        _ haystack: String, _ signatures: [String]
    ) -> Bool {
        signatures.contains { haystack.contains($0) }
    }

    /// 状态码字面须独立成词：前后不得再贴数字
    private static func containsCode(
        _ haystack: String, _ code: String
    ) -> Bool {
        haystack.range(
            of: "(?<!\\d)\(code)(?!\\d)",
            options: .regularExpression
        ) != nil
    }

    private static func containsAnyCode(
        _ haystack: String, _ codes: [String]
    ) -> Bool {
        codes.contains { containsCode(haystack, $0) }
    }

    /// 欠费档词族：额度/余额（中英）
    private static let billingSignatures = [
        "payment required", "insufficient",
        "balance", "quota", "out of credit", "billing",
        "余额不足", "余额", "欠费", "额度不足", "额度已用完",
    ]

    /// 超时档
    private static let timeoutSignatures = [
        "timed out", "timeout", "超时",
    ]

    /// 网络档：只认成词的断开表述
    private static let networkSignatures = [
        "network connection", "connection lost",
        "connection reset", "not connected",
        "网络连接", "网络断开", "网络中断",
    ]

    /// 服务端档词族：服务不可用/过载
    private static let serviceSignatures = [
        "internal server error", "bad gateway",
        "service unavailable", "server error", "overloaded",
        "服务器错误", "服务暂时不可用", "服务不可用",
    ]
}
