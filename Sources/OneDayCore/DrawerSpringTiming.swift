import Foundation

/// 抽屉弹簧定版（§313 换代立单源；§322 速度重定
/// 版）：本枚举是全仓唯一弹簧事实源——response/ζ
/// 只在此处定版，UIKit 刚度/阻尼由此派生（单位质
/// 量：ω＝2π/response、k＝ω²、c＝2ζω；回算 ζ＝
/// c/(2√k)、response＝2π/√k 恒等，单测钉死）。
/// SwiftUI 侧 MotionTokens.drawerSpring 是同值镜
/// 像（新壳层无 SwiftUI 消费方、只供令牌册完整
/// 性），两处字面值由单测逐项对钉——不再有第三
/// 处弹簧参数。
///
/// 定版值（§351 换代）：response 0.27／ζ 0.90
/// ——出处＝2026-11-22 用户新递 Muse 真机视频
/// （720×1566@30fps）开态接缝前锋逐帧轨迹最小
/// 二乘拟合（原始最优 response 0.229/ζ 0.865；
/// 候选带内取 0.27/0.90：对 Muse 轨迹 RMSE
/// 0.037、优于 §322 档 0.077 一倍；永久落定
/// 0.24s 对 Muse 开合总时长约 0.27–0.3s；过冲
/// 0.15% 近无回摆——§322 档 0.63% 过冲＋落定后
/// 残留微动正是用户视频里「停后尾巴」的同构性
/// 状）。§322 档（response 0.35／ζ 0.85）出处
/// ＝2026-11-17 Muse 录屏实测拟合（drawer-
/// ghosting-diagnosis-20261117.md §5：纯弹簧关段
/// 位移 400→209→81→24→3→0px、过冲 +4–5px≈
/// 0.8% 行程、松手落定尾 0.20–0.27s；报告区间
/// response 0.35–0.45／ζ 0.85–0.95 内逐点核算
/// 两项可观测量，本点最贴合：模型过冲 0.63%、
/// 全程 v0＝0 永久落定（≤2px）≈0.41s 对 Muse
/// 打开全程实测 0.43–0.47s、余量 200px 落定
/// ≈0.25s 对其实测尾段；同模型回算旧档全程落
/// 定 1.50s、与 .65 录屏实测互证）。欠阻尼、带
/// 微过冲——与 Muse 性状同构。旧值 response
/// 1.4／ζ 1.2（第 78 条 D3「Muse 录屏点按开实
/// 测」口径）经同录屏对照证伪（落定慢约 6 倍、
/// 性状亦异）**作废**；再旧值 0.34/ζ 0.86
/// （0.7.1 S7 跟手位移档）早已作废。
public enum DrawerSpringTiming {
    /// 弹簧定版 response（秒；与 MotionTokens.
    /// drawerSpring 镜像同值，单测对钉）
    public static let response: CGFloat = 0.27
    /// 弹簧定版阻尼比 ζ（欠阻尼、微过冲；与
    /// MotionTokens.drawerSpring 镜像同值，单测对钉）
    public static let dampingFraction: CGFloat = 0.90
    /// 松手吸附的动量投影时长（§322 随弹簧重算）：
    /// UIKit 手势无 SwiftUI 的 predictedEndTrans-
    /// lation，以「速度 × 本时长」近似其外推增量
    /// 后仍走 DrawerMotion.settleOpens 同一判定
    /// （判定口径不分家）。取值口径＝与弹簧动量
    /// 吸收率 ζω 反比缩放：旧档 0.22 对应旧弹簧
    /// ζω≈5.39，新弹簧 ζω≈15.26，0.22×5.39/
    /// 15.26≈0.078 → 取 0.08。保持旧值会把中速
    /// 甩动的投影行程高估约 2.8 倍、吸附判定系统
    /// 性偏开。§351 随新弹簧同口径再缩放：新弹簧
    /// ζω≈20.94，0.22×5.39/20.94≈0.057 → 取 0.06
    public static let settleProjectionInterval: CGFloat = 0.06

    /// 弹簧刚度 k（质量恒 1）
    public static var stiffness: CGFloat {
        let omega = 2 * CGFloat.pi / response
        return omega * omega
    }

    /// 弹簧阻尼 c（质量恒 1）
    public static var damping: CGFloat {
        let omega = 2 * CGFloat.pi / response
        return 2 * dampingFraction * omega
    }
}
