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
///   任何位移，纵滚完整归列表；0.36.21（§88）生死判
///   据改问速度，真机仍全灭；0.36.23（§90）外部调研
///   裁决：三轮死因不在判据量纲、在装载层级＋零编排
///   （生产实现无一把竞争 pan 装滚动视图祖先层且不
///   做失败要求编排），生死判据回归位移纯比值（见
///   shouldBeginPan 注），编排改由桥侧 require(to-
///   Fail:) 明文声明；位移口径的 engages 留作带锁
///   定距离的语义参照、不喂 shouldBegin
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

    /// 方向生死判据（0.36.20 §85 立、0.36.21 §88 曾改
    /// 速度域、0.36.23 §90 回归位移纯比值）：UIKit 手
    /// 势桥在 `gestureRecognizerShouldBegin` 阶段问本
    /// 函数决定平移识别器生死。**入参是位移，且只问
    /// 方向比值、不带任何量级/距离分量**——should-
    /// Begin 是离开 .possible 的一次性闸门（苹果 Ev-
    /// ent Handling Guide 原文），被咨询时累计位移只
    /// 有首次移动的数 pt，任何量级门在数学上过不去：
    /// 0.36.20 首版带 10pt 锁定距离的位移判据恒拒、
    /// 右滑全灭，即死于此。纯比值与量级无关，数 pt
    /// 的首次移动即可定案——此形态与 SwipeCellKit
    /// 现行 master 的 shouldBegin 逐字同型（transla-
    /// tion 纯比值、无量级门）。
    ///
    /// 速度域判据（0.36.21）退役理由（§90 调研裁
    /// 决）：其立论「SwipeCellKit 已改 velocity 判
    /// shouldBegin」经逐行核查不成立——velocity＋角
    /// 度门只见于 2020 年 PR #381 的 patch、合入状态
    /// 未证实，现行 master 仍是位移比值版；且三轮真
    /// 机死状（识别器从未启动）随判据量纲更换而不
    /// 变，定案死因在装载层级＋失败要求零编排，不在
    /// 量纲，本轮由桥侧 require(toFail:) 补上编排。
    ///
    /// 判据：右向（dx＞0）且 |dx| ≥ 主导比值 × |dy|
    /// ——比值引 DrawerMotion.directionLockRatio 与
    /// 抽屉 S2 同源单值，不在本处另写数字（上游
    /// SwipeCellKit 的 1.0 松口径不采：与本仓 S2 单
    /// 源冲突，且斜向慢滑不误触的复验口径要更严的
    /// 门）。与 engages 的差别只在量级门：engages 带
    /// 10pt 锁定距离、是「接管跟手」的语义判据；
    /// 本函数无量级门、是「一次性闸门」的生死判据，
    /// 两者服务的回调不同，不许混用。纵向主导/左
    /// 向/静止必拒＝识别器在识别层当场 Failed，桥侧
    /// 失败要求随即放行滚动 pan、本次触摸零写入；
    /// 横向主导必允，begin 后滚动 pan 按失败要求语
    /// 义已被置 Failed，本段触摸内绝不滚动（不设同
    /// 时识别、不动 isScrollEnabled）
    public static func shouldBeginPan(
        dx: CGFloat, dy: CGFloat
    ) -> Bool {
        dx > 0
            && abs(dx)
                >= DrawerMotion.directionLockRatio * abs(dy)
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
