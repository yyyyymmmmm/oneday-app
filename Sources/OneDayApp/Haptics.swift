#if canImport(UIKit)
import UIKit
#endif

/// 触觉反馈（0.36.2 按《动效宪法》表 D 重建，体验
/// 三件规格 §2）：事件分化是目标——同事件同 pattern
/// 全 App 一致，用户靠一致性学会这套词。
/// - 任务成功（发送/保存/连接/复制/采纳/批准/
///   目标达成）＝ notification .success
/// - 操作失败/报错＝ notification .error（0.36.2
///   归位：旧口径拿 .warning 冒充失败，自本版改判）
/// - 需注意未失败（结果未确认、驳回类决定）＝
///   notification .warning，只给本义
/// - 离散值变化（分段切换）＝ selection（经
///   .sensoryFeedback 落点，不走本枚举）
/// - 删除确认落锤＝ impact .heavy；删除成功后不再
///   叠 success——同一因果链只震一次
/// 防腻清单（明示防回潮）：普通点按、行点击、tab
/// 切换、页面进出、滚动、键盘、抽屉开合、翻页、
/// 下拉刷新、系统开关/Picker 一律无触感。
/// 历史口径：0.3.2「只挂结果」纪律（DESIGN-V4
/// §17）已被宪法表 D 取代；0.2.2 的 impact 点曾随
/// 之撤销，本版按表 D 定点重建（仅删除落锤一处
/// impact、无手势吸附面故 light 暂无落点）。
/// 复制点的触感在 CopyButton 内以 SwiftUI
/// .sensoryFeedback(.success) 施加（设计层组件够
/// 不着本文件），语义同属本表。
enum Haptics {
    /// 任务成功（通知型反馈）
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// 需注意未失败（通知型反馈）：只给本义——
    /// 结果未确认、需用户注意但动作本身没失败
    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// 操作失败/报错（通知型反馈，0.36.2 新增归位）
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }

    /// 离散值变化（选择型反馈，0.36.2 新增）：即用
    /// 即建与现行写法一致；视图层优先用
    /// .sensoryFeedback(.selection, trigger:) 声明式
    /// 落点，本函数留给命令式路径
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// 物理落锤（影响型反馈，0.36.2 新增）：当前
    /// 唯一落点＝删除确认 .heavy
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}
