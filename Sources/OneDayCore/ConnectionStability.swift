import Foundation

/// 连接稳固纯策略（0.36.20，§86）：治审计 R1/R2 的两
/// 件判定收进 Core 单测把守——在线判定迟滞（连失阈值
/// 才翻、任一成功即清零）与重试退避（AWS 全抖动）。
/// App 层只执行本处的数，不许另立口径。

/// 在线判定迟滞（§86.2）：单一信号永不单独翻脸。
/// - 探活连续失败满 failureThreshold 次才定版离线；
///   阈值前的失败只累加计数、isUp 保持上一结论（呈
///   现层据此在静默期维持原状态词、不出断开文案）
/// - 任一次成功（探活或真实业务）立即清零并回写在线
/// 阈值取 3 的理由：探活节律 30s 一轮、轮内另有快速
/// 重探（见 OverviewBridgeStore），单次抖动（服务器
/// 负载尖峰/旁路由节点切换/TLS 建连失败）只吃 1 次计
/// 数、永不达阈；真断时快速重探在数秒内连失 3 次即
/// 定版，不必等三轮 30s。
public struct ConnectionLiveness: Equatable, Sendable {
    /// 连续失败翻转阈值
    public static let failureThreshold = 3

    /// 当前连续失败计数（成功即清零）
    public private(set) var consecutiveFailures = 0
    /// 最近定版结论：nil＝尚无任何结论（冷启未探到）
    public private(set) var isUp: Bool?

    public init() {}

    /// 记一次失败，返回最新定版结论：未达阈值时保持
    /// 上一结论（可能仍为 true 或 nil），达阈值翻 false
    @discardableResult
    public mutating func recordFailure() -> Bool? {
        consecutiveFailures += 1
        if consecutiveFailures >= Self.failureThreshold {
            isUp = false
        }
        return isUp
    }

    /// 记一次成功：计数清零、立即回写在线（业务成功
    /// 与探活成功同权——治审计 R4「双通道互不作证」）
    @discardableResult
    public mutating func recordSuccess() -> Bool? {
        consecutiveFailures = 0
        isUp = true
        return isUp
    }

    /// 静默期标志：已有失败在累积但尚未定版离线——呈
    /// 现层在此期间不出任何断开文案（§86.5 三档之一档）
    public var isSuspect: Bool {
        consecutiveFailures > 0 && isUp != false
    }
}

/// 退避重试口径（§86.2/§86.3）：全抖动（AWS
/// Architecture Blog《Exponential Backoff and Jitter》
/// 推荐式）sleep = U(0, min(cap, base × 2^(n-1)))，
/// 抖动单位由调用方注入（App 传随机数、单测传定值），
/// 保证判定可钉测。尝试上限与提交步同量级（首发＋2
/// 次重试），只许一层退避、不叠乘。
public enum RetryBackoff {
    /// 总尝试上限（含首发）：与提交步 submitRun 的
    /// 「同 key 重试至多 2 次」同量级
    public static let maxAttempts = 3

    /// 第 failure 次失败后的等待秒数（failure 从 1
    /// 起）：指数帽随失败次数翻倍、封顶 cap，再乘抖
    /// 动单位（0…1）。failure＜1 返回 0（不等待）
    public static func delay(
        afterFailure failure: Int,
        base: Double = 1.2, cap: Double = 5.0,
        jitterUnit: Double
    ) -> Double {
        guard failure >= 1 else { return 0 }
        let temp = min(cap, base * pow(2.0, Double(failure - 1)))
        return temp * min(max(jitterUnit, 0), 1)
    }

    /// 第 attempts 次尝试已用尽后是否还许再试（attempts
    /// 为已尝试次数，含首发）
    public static func shouldRetry(afterAttempts attempts: Int) -> Bool {
        attempts >= 1 && attempts < maxAttempts
    }
}
