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
/// 思考呈现相位（0.20.0，用户 2026-11-09 23:36 硬规
/// 格）：默认展开态只许在「纯思考期」——正文一旦起
/// 流（contentStarted）或本轮结束（finished，含历史
/// 载入的一切落盘条目）一律默认收起，用户点按的覆
/// 盖态优先于相位默认（覆盖存视图侧、Core 只裁默认）
public enum ReasoningPhase: Sendable {
    /// 流式中且尚无正文/工具产出
    case streaming
    /// 流式中但正文（或工具卡）已开始产出
    case contentStarted
    /// 本轮结束／落盘条目（含历史载入）
    case finished
}

public enum ReasoningPresentation {
    /// 相位默认展开态：只有纯思考期默认展开；
    /// contentStarted 与 finished（含全部历史条目）
    /// 默认收起——0.20.0 钉死，单测把守（用户截图：
    /// 旧会话一打开满屏思考原文即此条要防的形态）
    public static func defaultExpanded(phase: ReasoningPhase) -> Bool {
        phase == .streaming
    }

    /// 思考正文区高度上限（pt）：主流聊天 App 的思考
    /// 区量级不超过视高约三分之一——iPhone 视高约
    /// 730–870pt，三分之一约 243–290，取 240 保守落
    /// 在带内；区内独立滚动跟随最新一行，思考再长也
    /// 不许把答案与输入舱顶出屏外（0.20.0 硬规格 1/2）
    public static let maxBodyHeight: Double = 240

    /// 正文是否可见：流式期恒展开；落盘后由用户展开态决定
    /// （0.20.0 起视图层改走 defaultExpanded(phase:)＋
    /// 用户覆盖，本函数保留作旧口径档案与单测锚点）
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
