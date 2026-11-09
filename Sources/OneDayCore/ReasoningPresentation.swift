import Foundation

/// 思考（reasoning）折叠单元的呈现判定（0.5.1，
/// DESIGN-V4 §32；B 案拆解清单 4.5 照改）：标题文案与
/// 展开口径收进纯函数单测把守，视图（ReasoningBlock）
/// 只消费结论。
///
/// 形态口径（对照 Fullmoon／Enchanted 两家成型单元）：
/// 流式期展开显示思考原文＋实时计时；落盘后默认折叠，
/// 标题给「已思考 · 约 Xs」，点按才展开。秒数来自流内
/// 实测（首个思考增量→首个正文增量或流结束），无数据
/// （历史导入等）只显「已思考」不编数。
public enum ReasoningPresentation {
    /// 正文是否可见：流式期恒展开；落盘后由用户展开态决定
    public static func showsText(
        isStreaming: Bool, expanded: Bool
    ) -> Bool {
        isStreaming || expanded
    }

    /// 折叠头标题。流式期 elapsed 为已思考秒数（现算，
    /// 可为 nil）；落盘后 seconds 为落盘实测值（可为 nil）
    public static func header(
        isStreaming: Bool,
        seconds: Double?,
        elapsed: TimeInterval?
    ) -> String {
        if isStreaming {
            guard let elapsed, elapsed >= 1 else { return "思考中" }
            return "思考中 · \(Int(elapsed)) 秒"
        }
        guard let seconds else { return "已思考" }
        if seconds < 1 { return "已思考 · 不到 1 秒" }
        return "已思考 · 约 \(Int(seconds.rounded())) 秒"
    }
}
