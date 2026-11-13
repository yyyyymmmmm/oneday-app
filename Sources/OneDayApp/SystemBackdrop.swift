import UIKit

/// 系统材质底衬（§198，2026-11-13，用户 11:24 拍板）：
/// 聊天页三处浮层背后垫一层**均匀**系统磨砂——顶带
/// （顶簇区，挂 TopBarGuideHostController 层级内）、输
/// 入框周边（挂 ComposerGuideHostController 层级内）、
/// 底部坞（挂 UITabBar 本体）。病象：内容上滚滑进状
/// 态栏带与时间/电量叠字、顶簇玻璃透字重影、汉堡钮
/// 压列表序号——根子是浮层背后没有底衬、内容以原锐
/// 度从玻璃与空隙间透出。
///
/// ## 选型（iOS 26 现行口径，出处）
/// - 材质档：`UIBlurEffect(style: .systemChrome-
///   Material)`——系统材质族（UIBlurEffect 系统材质
///   族）的 chrome 档，苹果文档原文「A blur matching
///   the system chrome」；UIBarAppearance（导航栏/
///   工具栏外观）的 backgroundEffect 通行取值即此档，
///   本就是给栏位类 chrome 区的系统材质。三处共用
///   同一档、同一定义点（本文件），不许各处自选。
/// - 明暗自适应：取系统自适应变体（非 Light/Dark
///   定版），深色模式随系统切档（§198 自查帧验）。
/// - 与 Liquid Glass 的分工：HIG《Materials》（2025
///   -09 更新口径）——Liquid Glass 是系统自身功能层
///   （标签栏等系统件）的材质，标准材质（UIBlur-
///   Effect 族）用于内容层与结构区分；顶簇/输入舱
///   是自托管浮层、不是系统栏件，故用标准材质垫底，
///   胶囊本体仍走 §179 玻璃定式、互不改形。
/// - 与 §173 的硬区分：§173 渐进溶化（边缘按距离渐
///   变淡出）已被用户亲删、整包作废；本件是**均匀**
///   材质——整带同值、不渐变、不淡出，任何形态的
///   渐变/溶化不许复活。列表顶缘 .soft／底缘
///   .hidden 的滚动边缘口径（§170/§185）是另一机
///   制、本包一字不动。
///
/// ## 挂载纪律（换代施工图定版）
/// 底衬只许挂进宿主控制器自己的视图层级与坞本体
/// ——原生列表换代（路线三）时宿主整体搬家、底衬随
/// 搬不丢；不许挂 ChatView 的 overlay/栈结构（会
/// 被收编推翻）。底衬一律不接命中（纯视觉层），浮
/// 层的透传判定仍由各宿主的实测帧闸门说了算。
enum SystemBackdrop {
    /// 三处底衬共用的唯一材质档（单点定义，测试钉此值）
    static let style: UIBlurEffect.Style =
        .systemChromeMaterial

    /// 三处底衬共用的唯一材质定义
    static var effect: UIBlurEffect {
        UIBlurEffect(style: style)
    }

    /// 宿主层级内底衬的标准形态：材质视图＋不接命中
    @MainActor
    static func makeView() -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect)
        view.isUserInteractionEnabled = false
        return view
    }
}

/// 坞底衬本体（独立类名：装配幂等按类型识别，不靠
/// tag/关联对象）
final class SystemDockBackdropView: UIVisualEffectView {}

/// 底部坞底衬装配（§198）：把系统材质垫进 UITabBar
/// 本体层级的最底层，覆盖坞 bounds 全幅——浮动玻璃
/// 坞盘之外的坞区（左右与下方）自此同为均匀磨砂，
/// 内容滑到坞后不以原锐度透出。装配点在 Composer-
/// GuideHostController 的坞锚解析（它本就逐次定位
/// 坞本体）：坞实例被换/系统重排子视图后，下个离散
/// 事件（显形/收键盘/入窗）即由 ensure 幂等校正。
enum SystemDockBackdrop {
    /// 幂等装配：已装→校正回最底层＋帧随坞 bounds；
    /// 未装→新建插入坞层级底层，帧以 autoresizing
    /// 跟随坞 bounds 变化
    @discardableResult
    @MainActor
    static func ensureInstalled(
        in tabBar: UITabBar
    ) -> SystemDockBackdropView {
        if let existing = tabBar.subviews.first(
            where: { $0 is SystemDockBackdropView }
        ) as? SystemDockBackdropView {
            tabBar.sendSubviewToBack(existing)
            if existing.frame != tabBar.bounds {
                existing.frame = tabBar.bounds
            }
            return existing
        }
        let backdrop = SystemDockBackdropView(
            effect: SystemBackdrop.effect
        )
        backdrop.isUserInteractionEnabled = false
        backdrop.frame = tabBar.bounds
        backdrop.autoresizingMask = [
            .flexibleWidth, .flexibleHeight,
        ]
        tabBar.insertSubview(backdrop, at: 0)
        return backdrop
    }
}
