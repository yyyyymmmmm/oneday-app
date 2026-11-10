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
///   器 shouldBegin 阶段定生死、begin 前呈现层不写
///   任何位移，纵滚完整归列表；0.36.21（§88）：生死
///   判据改问速度（shouldBegin 时位移未达锁定距离、
///   位移判据恒拒致右滑全灭），位移口径的 engages
///   只留作语义参照、不再喂 shouldBegin
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

    /// 方向生死判据（0.36.20 §85 立、0.36.21 §88 改判
    /// 据域）：UIKit 手势桥在 `gestureRecognizerShould-
    /// Begin` 阶段问本函数决定平移识别器生死。**入参
    /// 是速度（pt/s），不是位移**——0.36.20 首版拿位移
    /// 问生死真机全灭，定案见 §88：shouldBegin 被咨询
    /// 时识别器尚在 .possible、累计位移还没够到 10pt
    /// 锁定距离，位移判据恒为 false、识别器永远 begin
    /// 不了（右滑全无反应；纵滚则因它永不 begin 而完
    /// 好——上一版修过头）。速度在触摸起步即有方向意
    /// 义，生产级 SwipeCellKit 的 shouldBegin 亦由位移
    /// 改判速度（PR #381，角度门）。判据：右向（vx＞0）
    /// 且 |vx| ≥ 主导比值 × |vy|——比值引 DrawerMotion
    /// .directionLockRatio 与抽屉 S2 同源单值，不在本
    /// 处另写数字；速度域没有位移的 10pt 锁定距离
    /// （pt/s 与 pt 不同量纲，硬套距离门正是 0.36.20
    /// 的病根）。纵向主导/左向/静止必拒＝识别器在识
    /// 别层自取消、本次触摸零写入，纵滚完整归列表；
    /// 横向主导必允，begin 后与滚动的排斥由系统默认
    /// 仲裁承担（不设同时识别）
    public static func shouldBeginPan(
        velocityX: CGFloat, velocityY: CGFloat
    ) -> Bool {
        velocityX > 0
            && abs(velocityX)
                >= DrawerMotion.directionLockRatio * abs(velocityY)
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
