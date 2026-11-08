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
/// 0.2.9 行高校准（DESIGN-V4 §13.2）：CI 帧量测实证
/// 16pt 系统字体真实行高约 19.17（2 行 38.33、4 行
/// 76.67），旧常数 20 系近似——4 行累计漂移 3.3、封顶
/// 偏高 5。lineHeight 改实测值，封顶随之 120 → 115.02、
/// 胶囊上限 146 → 141.02；单行规格不变（键侧 30 主导，
/// 仍 46）。
public enum ComposerLayout {
    /// 正文行高：16pt 系统字体实测行高（CI 帧量测，
    /// §13.2），与 ComposerTextView 的量高一致
    public static let lineHeight: CGFloat = 19.17
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

    /// 横向 chrome 合计（容器宽 → 文本视图宽的扣减，
    /// 单行形态，0.2.9 宽度同源审计，DESIGN-V4 §13）：
    /// inputBar 横向边距 12×2＝24＋composerRow 横向边
    /// 距 8×2＝16＋两键直径 30×2＝60＋HStack 间距 8×2
    /// ＝16＋字段横向边距 8×2＝16，合计 132。逐项对应
    /// ChatView 的 padding/frame 定义（spacingSM 12、
    /// spacingS 8、buttonHeight 30）——改那边的几何必
    /// 同步改这里，量测宽与布局宽共用这一份扣减表
    public static let horizontalChrome: CGFloat = 132

    /// inputBar 横向边距合计（12×2，含在 horizontalChrome
    /// 的 132 内）：布局层（ComposerBarLayout）拿到的是
    /// 行宽（容器宽−24），换算回容器宽时用它
    public static let inputBarChrome: CGFloat = 24

    /// 横向 chrome 合计·多行形态（0.3.3 上文下钮，§18）：
    /// 按钮行沉底后文字区全宽——inputBar 24＋row 横向
    /// 边距 16＋字段横向边距 16＝56（无两键与行内间距）
    public static let horizontalChromeMultiline: CGFloat = 56

    /// 多行形态下文字区与按钮行之间的间距（0.3.3）
    public static let buttonRowSpacing: CGFloat = 4

    /// 文本视图宽（量测与布局同源的那个宽度；单行形态）
    public static func textWidth(forContainerWidth width: CGFloat) -> CGFloat {
        max(width - horizontalChrome, 0)
    }

    /// 文本视图宽（按形态）：单行＝两键夹住的窄宽、多行
    /// ＝全宽。形态判据恒以窄宽量测为准（见 capsuleHeight
    /// 注），两宽分工不许混用
    public static func textWidth(
        forContainerWidth width: CGFloat, multiline: Bool
    ) -> CGFloat {
        max(
            width - (multiline
                ? horizontalChromeMultiline : horizontalChrome),
            0
        )
    }

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

    /// 胶囊总高（0.3.3 上文下钮结构，DESIGN-V4 §18）：
    /// 形态判据恒以窄宽实测为准（isMultiline(narrow)）——
    /// 与全宽行数无关，避免形态在临界文本上反复横跳。
    /// - 单行：沿 0.2.8 定版公式＝max(窄宽文本高＋文本
    ///   纵向边距, 键直径)＋行纵向边距（单行 46 不变）
    /// - 多行：全宽文本高（封顶）＋文本纵向边距＋按钮行
    ///   距＋键直径（按钮行）＋行纵向边距——文字在上全
    ///   宽生长、按钮钉在底部行（学 Muse/ChatGPT 与
    ///   Exyte/Stream Composer 的成熟结构）
    public static func capsuleHeight(
        narrowMeasured: CGFloat, fullMeasured: CGFloat
    ) -> CGFloat {
        if isMultiline(measured: narrowMeasured) {
            return cappedTextHeight(measured: fullMeasured)
                + textVerticalInsets + buttonRowSpacing
                + buttonHeight + rowVerticalInsets
        }
        return max(
            cappedTextHeight(measured: narrowMeasured) + textVerticalInsets,
            buttonHeight
        ) + rowVerticalInsets
    }

    /// 行数→文本高（规格推导与测试用）；行数下限 1
    public static func textHeight(forLineCount lines: Int) -> CGFloat {
        lineHeight * CGFloat(max(lines, 1))
    }
}
