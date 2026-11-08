import Foundation

/// 发送舱高度口径（DESIGN-V4 §11）：「实测文本高 → 应得高度」
/// 的纯逻辑，高度回归的单测把守层。ComposerTextView 负责量
/// （UITextView 以提议宽度量当前文本，含拼音 marked 段），
/// 本处负责算：封顶、内滚判据、多行形状判据、胶囊总高——
/// 三处（量高封顶／形状判据／测试）共用同一口径，不许各写
/// 一份数字。
public enum ComposerLayout {
    /// 正文行高（.body 字体口径，与 ComposerTextView 量高一致）
    public static let lineHeight: CGFloat = 22.5
    /// 多行上限：实测高超过封顶后文本视图内滚
    public static let maxLines = 6
    /// 文本封顶高（6 行）
    public static var maxTextHeight: CGFloat {
        lineHeight * CGFloat(maxLines)
    }
    /// 多行判据阈值：实测高跨过 1.5 行即视为多行形态
    public static var multilineThreshold: CGFloat {
        lineHeight * 1.5
    }
    /// 舱内纵向边距合计：文本视图纵向 padding 16（8×2）＋
    /// 内容行纵向 padding 16（8×2），与 ChatView.composerRow
    /// 的两层 spacingS 边距对应
    public static let verticalInsets: CGFloat = 32

    /// 空文本也按一行计：量高下限为一行
    public static func effectiveTextHeight(measured: CGFloat) -> CGFloat {
        max(measured, lineHeight)
    }

    /// 封顶后的文本高（高度权威的返回值口径）
    public static func cappedTextHeight(measured: CGFloat) -> CGFloat {
        min(effectiveTextHeight(measured: measured), maxTextHeight)
    }

    /// 实测高过封顶才内滚
    public static func shouldScroll(measured: CGFloat) -> Bool {
        measured > maxTextHeight
    }

    /// 多行形态判据（玻璃形状 Capsule ↔ 固定圆角矩形）
    public static func isMultiline(measured: CGFloat) -> Bool {
        effectiveTextHeight(measured: measured) > multilineThreshold
    }

    /// 胶囊总高＝封顶文本高＋舱内纵向边距。
    /// 单行规格：22.5＋32＝54.5，落在 54±4 内
    public static func capsuleHeight(measured: CGFloat) -> CGFloat {
        cappedTextHeight(measured: measured) + verticalInsets
    }

    /// 行数→文本高（规格推导与测试用）；行数下限 1
    public static func textHeight(forLineCount lines: Int) -> CGFloat {
        lineHeight * CGFloat(max(lines, 1))
    }
}
