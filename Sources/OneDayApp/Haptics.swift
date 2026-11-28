#if canImport(UIKit)
import UIKit
#endif

/// 触觉反馈（预热复用池版，遵循《动效宪法》表 D）：
/// - 任务成功（发送/保存/连接/复制/采纳/批准/目标达成）＝ notification .success
/// - 操作失败/报错＝ notification .error
/// - 需注意未失败（结果未确认、驳回类决定）＝ notification .warning
/// - 离散值变化（分段切换）＝ selection
/// - 删除确认落锤＝ impact .heavy；发送/录音/右滑引用/抽屉吸附＝ impact .light
@MainActor
enum Haptics {
    /// 触感总开关持久化键（默认开启，设置·偏好页单一总闸）
    static let enabledStorageKey = "preferences.haptics.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledStorageKey) as? Bool ?? true
    }

    #if canImport(UIKit)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    private static func impactGenerator(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        if let cached = impactGenerators[style] {
            return cached
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        return generator
    }

    /// 预热常用触感引擎，消除首次触发的硬件唤醒延迟
    static func prepare() {
        guard isEnabled else { return }
        notificationGenerator.prepare()
        selectionGenerator.prepare()
        impactGenerator(for: .light).prepare()
    }
    #endif

    /// 触感防抖节流间隔（收敛高频无效震动，保留状态结果与物理越阈）
    private static var lastNotificationAt: TimeInterval = 0
    private static var lastSelectionAt: TimeInterval = 0
    private static var lastLightImpactAt: TimeInterval = 0

    private static func allowTrigger(_ lastAt: inout TimeInterval, cooldown: TimeInterval) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAt >= cooldown else { return false }
        lastAt = now
        return true
    }

    /// 任务成功（通知型反馈）
    static func success() {
        guard isEnabled, allowTrigger(&lastNotificationAt, cooldown: 0.25) else { return }
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #endif
    }

    /// 需注意未失败（通知型反馈）
    static func warning() {
        guard isEnabled, allowTrigger(&lastNotificationAt, cooldown: 0.25) else { return }
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
        #endif
    }

    /// 操作失败/报错（通知型反馈）
    static func error() {
        guard isEnabled, allowTrigger(&lastNotificationAt, cooldown: 0.25) else { return }
        #if canImport(UIKit)
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
        #endif
    }

    /// 离散值变化（选择型反馈，120ms 防抖避免滑动/连点高频震动）
    static func selection() {
        guard isEnabled, allowTrigger(&lastSelectionAt, cooldown: 0.12) else { return }
        #if canImport(UIKit)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }

    /// 轻触（合并接缝修复：v23 调用点按 Haptics.light() 取
    /// 轻击反馈，本体只有 impact(_:) 原语——按 .light 补语义别名）
    static func light() {
        impact(.light)
    }

    /// 物理落锤（影响型反馈；轻触 120ms 防抖，重击删除确认不节流）
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        #if canImport(UIKit)
        if style == .light || style == .soft {
            guard allowTrigger(&lastLightImpactAt, cooldown: 0.12) else { return }
        }
        let generator = impactGenerator(for: style)
        generator.impactOccurred()
        generator.prepare()
        #endif
    }
}
