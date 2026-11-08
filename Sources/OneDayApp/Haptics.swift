#if canImport(UIKit)
import UIKit
#endif

/// 轻触觉反馈（0.2.2 动效专项）：克制使用，只落在关键动作点——
/// 发送消息、抽屉吸附开合、删除确认、网关重启确认。不给普通
/// 点按与滚动加震动（登记见 docs/DESIGN-V3-NOTES.md §7）。
enum Haptics {
    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}
