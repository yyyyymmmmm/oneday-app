import Foundation

/// 数字入场账：只记已落定值，决策本身不写账；未完成的
/// 插值不冒充终值。后端可注入独立 suite，默认落 UserDefaults。
/// 内部以锁同步，可任意线程调用；UserDefaults 本身线程安全。
public final class RollingNumberGate: @unchecked Sendable {
    public enum Decision: Equatable, Sendable {
        case `static`(Double)
        case roll(from: Double, to: Double)
    }

    public static let shared = RollingNumberGate()
    private let lock = NSLock()
    private var settledValues: [String: Double] = [:]
    private let defaults: UserDefaults
    private let storagePrefix = "rollingNumber.settled."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func decision(key: String, value: Double) -> Decision {
        lock.lock()
        var previous = settledValues[key]
        lock.unlock()
        if previous == nil {
            let stored = (defaults.object(forKey: storagePrefix + key) as? NSNumber)?.doubleValue
            lock.lock()
            previous = settledValues[key] ?? stored
            if let previous { settledValues[key] = previous }
            lock.unlock()
        }
        if let previous {
            if previous == value { return .static(value) }
        }
        return .roll(from: previous ?? 0, to: value)
    }

    public func settle(key: String, value: Double) {
        lock.lock()
        settledValues[key] = value
        lock.unlock()
        defaults.set(value, forKey: storagePrefix + key)
    }
}
