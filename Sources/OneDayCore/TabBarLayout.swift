import Foundation

/// 自绘底栏几何定版（0.3.8，fixlist 第 2 条用户裁决：替换
/// 原生 TabView 呈现层、IA 四格与数据逻辑不动）。
///
/// 定数依据：0.3.7 卡 19 纠正 3 在原生 TabView 下无代码落
/// 点（选中垫为系统几何、约栏宽 1/4）；自绘后垫宽由构造
/// 决定——垫＝字形紧致宽＋两侧各 13pt，22pt 字形的垫宽
/// 约 52–58pt（栏宽 393 时约 13–15%，对照 Muse 选中垫
/// 贴合字形的观感）。栏体悬浮大胶囊：横边距 16、底边距
/// ＝安全区内 8pt、栏高 58。手势口径：栏体只承载四格点
/// 按，不挂拖拽手势，与页面滚动/抽屉拖拽不冲突；Reduce
/// Motion 时切换动画由 MotionTokens.resolved 出口降级；
/// 无障碍：每格 Button 带文字标签（VoiceOver 读格名）。
public enum TabBarLayout {
    /// 栏体高度（不含外边距）
    public static let barHeight: CGFloat = 58
    /// 栏体相对屏幕的横边距
    public static let horizontalMargin: CGFloat = 16
    /// 栏体底边距（安全区内侧起算）
    public static let bottomMargin: CGFloat = 8
    /// 字形尺寸（与 §22.5 尺寸带 20...22 对齐）
    public static let glyphSize: CGFloat = 22
    /// 选中垫高
    public static let padHeight: CGFloat = 40
    /// 选中垫横向内衬（字形紧致宽两侧各一份）
    public static let padHorizontalInset: CGFloat = 13

    /// 选中垫宽＝字形点宽＋两侧内衬（字形点宽由渲染层按
    /// 符号实测传入；纯逻辑在此，单测钉常数口径）
    public static func padWidth(glyphWidth: CGFloat) -> CGFloat {
        glyphWidth + padHorizontalInset * 2
    }

    /// 栏体占位总高（聊天页/列表页底部留白口径：栏高＋
    /// 底边距＋呼吸 10；安全区由调用处另加）
    public static var zoneHeight: CGFloat {
        barHeight + bottomMargin + 10
    }
}
