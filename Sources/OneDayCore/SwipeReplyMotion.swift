import Foundation

/// 右滑引用纯逻辑（0.36.19，§84.3）：消息气泡向右滑触
/// 发与长按菜单「回复」完全相同的引用动作，本枚举管
/// 它的全部判定——方向门、跟手位移、触发阈值、箭头显
/// 形进度。呈现层（SwipeReplyModifier）只持拖动状态、
/// 判定全走本处单测把守。
///
/// 手势门控（不与纵向滚动/贴底判定打架的构造）：
/// - 方向门复用抽屉 S2 锁定口径（DrawerMotion.
///   isDirectionLocked：累计 |dx|≥10 且 |dx|≥1.5|dy|），
///   并加右向要求（dx＞0）；0.36.19 首版把方向门放在
///   DragGesture.onChanged 里、真机证明挡不住识别层
///   抢占（纵滚被压死），0.36.20 改由 UIKit 桥在识别
///   器 shouldBegin 阶段问 shouldBeginPan 定生死、
///   begin 前呈现层不写任何位移，纵滚完整归列表
/// - 跟手位移扣除锁定段（接管瞬间 dx），起步无跳；
///   向左回拖钳到 0、向右封顶 maxOffset
/// - 触发只认松手瞬间位移过 triggerOffset，不认速
///   度——慢滑到位也算、快甩没到位不算，判定可预期
public enum SwipeReplyMotion {
    /// 跟手位移封顶：箭头显形区＋气泡让位的最大行程
    public static let maxOffset: CGFloat = 76
    /// 触发阈值：松手瞬间位移达此值即触发引用（同
    /// 时是箭头「已武装」态与显形进度满格的判据）
    public static let triggerOffset: CGFloat = 52

    /// 方向门：右向且横向主导（抽屉 S2 同源口径）
    public static func engages(dx: CGFloat, dy: CGFloat) -> Bool {
        dx > 0 && DrawerMotion.isDirectionLocked(dx: dx, dy: dy)
    }

    /// 方向生死判据（0.36.20，§85）：UIKit 手势桥在
    /// `gestureRecognizerShouldBegin` 阶段问本函数决定
    /// 平移识别器生死——与 engages 同一口径的命名出
    /// 口，不许桥侧另写一份（0.36.19 的教训：方向门
    /// 写在 DragGesture.onChanged 里，识别层已被卷入、
    /// 门只挡位移写入挡不住抢占，纵滚被压死）。纵向
    /// 主导必拒（不 begin、纵滚完整归 ScrollView）、
    /// 横向主导必允、临界比值按 engages 的 1.5 倍口径
    public static func shouldBeginPan(dx: CGFloat, dy: CGFloat) -> Bool {
        engages(dx: dx, dy: dy)
    }

    /// 跟手位移：扣除锁定段后 1:1，两端钳制
    /// - dx: 手势当前全量横向位移（自手势起点）
    /// - lockTranslation: 接管瞬间的手势横向位移
    public static func followedOffset(
        dx: CGFloat, lockTranslation: CGFloat
    ) -> CGFloat {
        min(max(dx - lockTranslation, 0), maxOffset)
    }

    /// 箭头显形进度（0…1）：随位移趋近阈值长满；呈现
    /// 层据此驱动箭头的不透明度与缩放，过阈即满格
    public static func revealProgress(offset: CGFloat) -> Double {
        Double(min(max(offset / triggerOffset, 0), 1))
    }

    /// 松手触发判定：位移过阈才触发
    public static func shouldTrigger(offset: CGFloat) -> Bool {
        offset >= triggerOffset
    }
}
