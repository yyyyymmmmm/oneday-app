import Foundation

/// 发送舱高度口径（DESIGN-V4 §11 定案、§12.3 改基数）：
/// 「实测文本高 → 应得高度」的纯逻辑，高度回归的单测把守
/// 层。ComposerTextView 负责量（UITextView 以提议宽度量
/// 当前文本，含拼音 marked 段），本处负责算：封顶、内滚
/// 判据、多行形状判据、胶囊总高——三处（量高封顶／形状
/// 判据／测试）共用同一口径，不许各写一份数字。
///
/// 0.2.8 基数改版（用户真机同机量测对齐 Muse）：单行
/// 总高由 54.5 改 46（Muse 约 45、OneDay 旧值约 60）。
/// 构成：正文行高 22.5 → 20（字体改固定 16pt 系统字体，
/// 与 ComposerTextView 同口径）；文本纵向边距合计
/// 16 → 10；两键直径 36 → 30。胶囊高取「文本侧」与
/// 「键侧」较高者＋行纵向边距：单行时两侧同为 30，总高
/// 30＋16＝46；多行起文本侧接管、随行递增。
public enum ComposerLayout {
    /// 正文行高（16pt 系统字体口径，与 ComposerTextView
    /// 的量高一致）
    public static let lineHeight: CGFloat = 20
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
    /// 文本视图纵向 padding 合计（5×2，ChatView.composerRow
    /// 施加于 ComposerTextView）
    public static let textVerticalInsets: CGFloat = 10
    /// 内容行纵向 padding 合计（spacingS 8×2，composerRow
    /// 本体的纵向边距）
    public static let rowVerticalInsets: CGFloat = 16
    /// 两键（＋／发送／停止／麦克风）直径：胶囊高的下限
    /// 锚——单行时文本侧与键侧同高，键再大胶囊必超规格
    public static let buttonHeight: CGFloat = 30

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

    /// 胶囊总高＝max(封顶文本高＋文本纵向边距, 键直径)
    /// ＋行纵向边距。单行规格：max(20＋10, 30)＋16＝46，
    /// 落在目标带 45–46 内（0.2.8 改版，54.5 旧规格作废）
    public static func capsuleHeight(measured: CGFloat) -> CGFloat {
        max(
            cappedTextHeight(measured: measured) + textVerticalInsets,
            buttonHeight
        ) + rowVerticalInsets
    }

    /// 行数→文本高（规格推导与测试用）；行数下限 1
    public static func textHeight(forLineCount lines: Int) -> CGFloat {
        lineHeight * CGFloat(max(lines, 1))
    }
}
