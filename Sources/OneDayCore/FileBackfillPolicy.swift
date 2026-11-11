import Foundation

/// 大小回读重试口径（§127 对齐包，D1）：文件卡可见
/// 时即回读，但首试常撞上通道未就绪（冷启动刚进列
/// 表、后台刚恢复）——旧形态失败即静默放弃、要等
/// 打开页再试才补上，卡面长期缺大小。本表钉重试形
/// 状：最多 3 试、间隔递增、失败后同目录冷却（多张
/// 同目录卡不许轮番轰目录列表）。判定纯函数，宿主
/// （FileMetadataStore.ensureSize）按表执行。
public enum FileBackfillPolicy {
    /// 单张卡一次可见周期内的最多回读次数（含首试）
    public static let maxAttempts = 3

    /// 同目录回读失败后的冷却秒数：冷却内再来的回
    /// 读请求直接回失败、不发网络（通道未就绪时几
    /// 十张卡同屏，逐卡单发是无谓轰击）
    public static let failureCooldown: TimeInterval = 5

    /// 第 attempt 次失败后、再试前的等待秒数（1 起
    /// 数）；用尽次数回 nil（不再等、保持只显类型）
    public static func delay(afterFailedAttempt attempt: Int) -> TimeInterval? {
        switch attempt {
        case 1: return 1.5
        case 2: return 4
        default: return nil
        }
    }

    /// 是否还在冷却内（lastFailure 为 nil＝没失败过）
    public static func isCoolingDown(
        lastFailureAt: Date?, now: Date
    ) -> Bool {
        guard let lastFailureAt else { return false }
        return now.timeIntervalSince(lastFailureAt) < failureCooldown
    }
}
