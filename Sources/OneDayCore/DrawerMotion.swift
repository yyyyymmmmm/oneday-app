import Foundation

/// 抽屉动效纯逻辑（0.7.1，chrome 裁决档 §3.5 S1–S8 的
/// 可测部分；档＝oneday-design-review/chrome-research-
/// 20261109.md，用户 2026-11-09 16:15 批准全案）：
/// 壳层只持一个 drawerOffset，本枚举管它的全部派生与
/// 判定——方向锁定（S2）、跟手位移换算（S2）、松手吸附
/// （S6）、圆角/阴影的白名单值（S3/§3.4）。弹簧本体在
/// OneDayDesign.MotionTokens.drawerSpring（S7）；挂载
/// 时机（S5）与呈现层接管（S7）在壳层 DrawerShell。
/// 0.17.0：抽屉改覆盖形态（调研报告 Q1/Q4 定案——被
/// 整体变换的页卡承载 TabView 是底栏下沉的病根），页
/// 卡退役，cornerRadius/shadowOpacity 自此无呈现层调
/// 用、保留作数据与回归钉；新增 scrimOpacity 承担覆
/// 盖形态的蒙层派生。位移三件（锁定/跟手/吸附）不变。
public enum DrawerMotion {
    /// S2 方向锁定：累计横向位移达到此值前手势不接管、
    /// 不写任何位移状态（纵滚零干扰）
    public static let directionLockDistance: CGFloat = 10
    /// S2 方向锁定：横纵比门槛（|dx| ≥ 1.5×|dy| 才算横拖）
    public static let directionLockRatio: CGFloat = 1.5
    /// S6 fling 直通：松手速度朝目标向超此值不看位置
    /// 直接吸附（pt/s）
    public static let flingVelocity: CGFloat = 800
    /// S6 预测位移吸附阈值：动量投影相对手势起点的偏
    /// 移过 travel 的三成即吸附到对岸（现行阈值沿用，
    /// 已合 momentum 语义——裁决档 §3.5 S6）
    public static let settleFraction: CGFloat = 0.3
    /// S3 圆角一步到位阈值：progress 过此值圆角直接到
    /// 定值、拖动期不插值（逐帧改裁切半径＝整卡离屏
    /// 重合成，是 0.6.1 拖动卡顿主因之一，§1.5-2）
    public static let cornerStepProgress: CGFloat = 0.02
    /// 页卡圆角定值（§30 录屏量测形态，0.7.1 起冻结
    /// 不再随 progress 插值）
    public static let cardCornerRadius: CGFloat = 28
    /// §3.4 页卡柔影定值（灰柱处方：0.6.1 的 radius 24
    /// /x −10 在平色抽屉面上摊成约 48pt 灰柱；改窄而
    /// 贴缘，总宽收至约 20pt）
    public static let shadowRadius: CGFloat = 10
    public static let shadowX: CGFloat = -4
    /// 柔影峰值 alpha（progress=1 时）；拖动期 radius
    /// 与 x 冻结、只有 opacity 随 progress 变（S3）
    public static let shadowMaxOpacity: Double = 0.12
    /// 蒙层峰值 alpha（0.17.0 覆盖式抽屉）：页卡退役
    /// 后内容层静止不动，抽屉与内容的分离感改由滑入
    /// 抽屉下方的整屏蒙层承担（调研报告 Q4 结构 A）
    public static let scrimMaxOpacity: Double = 0.32

    /// S2 方向锁定判定：累计位移达标且横向主导才接管
    public static func isDirectionLocked(dx: CGFloat, dy: CGFloat) -> Bool {
        let ax = abs(dx)
        return ax >= directionLockDistance
            && ax >= directionLockRatio * abs(dy)
    }

    /// S1 派生语义：offset 过半记为开（供语义对账与命
    /// 中层开关；位移计算不读它——0.6.1 的 bool＋delta
    /// 双状态自此退役）
    public static func isOpen(offset: CGFloat, travel: CGFloat) -> Bool {
        travel > 0 && offset > travel / 2
    }

    /// S1 派生进度：钳制 0…1（橡皮筋越界段不放大进
    /// 度，缩放/阴影不被越界量带偏）
    public static func progress(offset: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(offset / travel, 0), 1)
    }

    /// S2 跟手位移：接管后写入值扣除锁定段（消除旧实
    /// 现「含判定段全量写入」的起步跳，§1.5-5）；界内
    /// 1:1，越界段走 DrawerGeometry 橡皮筋（c＝0.55，
    /// §3.5 S2 维持不动）
    /// - startOffset: 接管瞬间的呈现位移
    /// - translation: 手势当前全量横向位移（自手势起点）
    /// - lockTranslation: 接管瞬间的手势横向位移（锁定段）
    public static func followedOffset(
        startOffset: CGFloat,
        translation: CGFloat,
        lockTranslation: CGFloat,
        travel: CGFloat
    ) -> CGFloat {
        let target = startOffset + (translation - lockTranslation)
        if target > travel {
            return travel + DrawerGeometry.rubberBand(
                overshoot: target - travel, containerWidth: travel
            )
        }
        if target < 0 {
            return -DrawerGeometry.rubberBand(
                overshoot: -target, containerWidth: travel
            )
        }
        return target
    }

    /// S6 松手吸附：fling 直通优先；否则以动量预测增
    /// 量外推——相对手势接管起点的总偏移过 30% travel
    /// 吸附到对岸（开向/合向同阈，沿现行口径）
    /// - currentOffset: 松手瞬间位移
    /// - startOffset: 本次手势接管时的位移（定开/合向）
    /// - predictedExtra: predictedEndTranslation − translation（动量外推增量）
    /// - velocityX: 松手速度（pt/s，右为正）
    public static func settleOpens(
        currentOffset: CGFloat,
        startOffset: CGFloat,
        predictedExtra: CGFloat,
        velocityX: CGFloat,
        travel: CGFloat
    ) -> Bool {
        guard travel > 0 else { return false }
        if velocityX > flingVelocity { return true }
        if velocityX < -flingVelocity { return false }
        let relative = (currentOffset - startOffset) + predictedExtra
        if startOffset < travel / 2 {
            return relative > travel * settleFraction
        }
        return relative > -travel * settleFraction
    }

    /// S3 圆角：progress 过阈一步到定值（拖动期冻结）
    public static func cornerRadius(progress: CGFloat) -> CGFloat {
        progress > cornerStepProgress ? cardCornerRadius : 0
    }

    /// S3/§3.4 阴影不透明度：白名单内唯一随 progress
    /// 变的阴影属性
    public static func shadowOpacity(progress: CGFloat) -> Double {
        shadowMaxOpacity * Double(min(max(progress, 0), 1))
    }

    /// 蒙层不透明度（0.17.0）：随 progress 线性、两端
    /// 钳制——橡皮筋越界段不放大蒙层（与 progress 的
    /// 钳制口径一致，越界只动抽屉本体）
    public static func scrimOpacity(progress: CGFloat) -> Double {
        scrimMaxOpacity * Double(min(max(progress, 0), 1))
    }
}
