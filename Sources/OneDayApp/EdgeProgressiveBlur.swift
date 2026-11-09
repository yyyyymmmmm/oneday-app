import SwiftUI
import UIKit

/// 渐进模糊层（0.4.4，例外 E11，DESIGN-V4 §29；
/// 用户 2026-11-09 11:31 真机验收 0.4.3 后批准
/// 调研 §4.3 第一条豁免）：UIVisualEffectView 真
/// 模糊＋CAGradientLayer alpha mask——模糊的半
/// 径恒定（公开 API 无 variable blur，调研 §2.1）、
/// 不透明度沿带长衰减，内容滚近屏幕上下缘时先化
/// 开再消失。系统 .scrollEdgeEffectStyle(.soft)
/// 的作用区只等于已注册 bar 的高度、上限 subtle
/// （§28.6）；本层把化开区放大到带长量级（聊天顶
/// 176／抽屉顶 150 固定；两条底带 0.4.5 起动态带长
/// ——聊天底＝56＋发送区实测高（带底收在发送区底
/// 缘）、抽屉底＝124＋底条下边距段（带底达屏边），
/// 见 chatBottom/drawerBottom 的 (bandHeight:) 版）。
///
/// 用法纪律：只作已注册 safeAreaBar 内容的 back-
/// ground 溢出绘制——不参与布局（bar 尺寸/发送舱
/// 自量高链零影响）、不接命中（SwiftUI 侧 allows-
/// HitTesting(false)＋UIKit 侧 interaction 关）、
/// bar 本体在层上保持锐利；底带挂发送区 back-
/// ground 即随安全区（键盘）同通道升降，不与发
/// 送舱打架（§29 键盘复核）。私有 variableBlur
/// 滤镜线不碰（调研 §4.3-3，除非用户亲点）。
struct EdgeProgressiveBlur: UIViewRepresentable {
    /// mask 停点（带顶→带底：位置 0–1、该处模糊
    /// 不透明度 0–1），调用点按各自几何给定
    var stops: [GradientStop]

    struct GradientStop {
        let location: Double
        let alpha: Double
    }

    func makeUIView(context: Context) -> MaskedBlurView {
        MaskedBlurView(stops: stops)
    }

    func updateUIView(_ uiView: MaskedBlurView, context: Context) {}
}

extension EdgeProgressiveBlur {
    /// 聊天顶带（带长 176pt：上探状态区 60＋顶栏
    /// 本体＋向内容延出约 45）：自带顶满模糊、过
    /// 顶栏下缘后衰减到无
    static let chatTop: [GradientStop] = [
        GradientStop(location: 0, alpha: 1),
        GradientStop(location: 0.58, alpha: 1),
        GradientStop(location: 0.82, alpha: 0.45),
        GradientStop(location: 1, alpha: 0),
    ]

    /// 聊天底带（0.4.5 改动态带长，§30）：带长由调用
    /// 点给（56pt 渐入段＋发送区实测高），带底恰收在
    /// 发送区底缘——0.4.4 的固定 216pt 带向下延出约
    /// 96pt「与坞衔接」被用户 11:47 点名收掉（坞下方
    /// 显成独立一坨）。停点按绝对锚换算：自带顶 0、
    /// 30pt 处半、58pt 处满、其后恒满——与 0.4.4 定版
    /// （216 带上 0.14/0.27 恰为 30/58pt）逐点同形，
    /// 坞上方渐入段分毫不变
    static func chatBottom(bandHeight: Double) -> [GradientStop] {
        let h = max(bandHeight, 60)
        return [
            GradientStop(location: 0, alpha: 0),
            GradientStop(location: 30 / h, alpha: 0.5),
            GradientStop(location: 58 / h, alpha: 1),
            GradientStop(location: 1, alpha: 1),
        ]
    }

    /// 抽屉顶带（带长 150pt：上探状态区 56＋名字
    /// 区＋向名单延出约 35）：形态同聊天顶带
    static let drawerTop: [GradientStop] = [
        GradientStop(location: 0, alpha: 1),
        GradientStop(location: 0.60, alpha: 1),
        GradientStop(location: 0.85, alpha: 0.45),
        GradientStop(location: 1, alpha: 0),
    ]

    /// 抽屉底带（0.4.5 改动态带长，§30）：带长由调用
    /// 点给（0.4.4 的 124pt 本体＋底条下边距段——
    /// 0.4.5 名单穿安全区直达屏底、带底须跟到屏边，
    /// 见 DrawerView）。停点按绝对锚换算：自带顶 0、
    /// 43pt 处半、68pt 处满、其后恒满——带顶起 68pt
    /// 的化开形态与 0.4.4 定版（124 带上 0.35/0.55
    /// 恰为 43/68pt）逐点同形
    static func drawerBottom(bandHeight: Double) -> [GradientStop] {
        let h = max(bandHeight, 72)
        return [
            GradientStop(location: 0, alpha: 0),
            GradientStop(location: 43 / h, alpha: 0.5),
            GradientStop(location: 68 / h, alpha: 1),
            GradientStop(location: 1, alpha: 1),
        ]
    }
}

/// UIVisualEffectView＋渐变 mask 的 UIKit 本体
/// （调研 §2.3 的公开近似路线落点）：mask 挂在
/// effect view 的 layer 上、模糊结果的 alpha 随
/// mask 衰减；材质走 .systemMaterial（明暗自适
/// 应，与页面系统材质同族）
final class MaskedBlurView: UIVisualEffectView {
    private let gradientMask = CAGradientLayer()

    init(stops: [EdgeProgressiveBlur.GradientStop]) {
        super.init(effect: UIBlurEffect(style: .systemMaterial))
        gradientMask.colors = stops.map {
            UIColor.black.withAlphaComponent(CGFloat($0.alpha)).cgColor
        }
        gradientMask.locations = stops.map { NSNumber(value: $0.location) }
        gradientMask.startPoint = CGPoint(x: 0.5, y: 0)
        gradientMask.endPoint = CGPoint(x: 0.5, y: 1)
        layer.mask = gradientMask
        // UIKit 侧再断一层命中，防 effect view 本体
        // 吞掉滚动/点按（SwiftUI 侧另有 allowsHit-
        // Testing(false)）
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientMask.frame = bounds
    }
}
