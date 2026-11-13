import Foundation

/// 按线程分格的暂存格（基础止血包 P4）：待发附件这
/// 类「属于某个会话、还没消费」的临时物，一格一线
/// 程、互不可见——切线程时把当前格存回、目标格取
/// 出，从构造上断绝串带到别的会话呈现/发送。纯内存
/// 语义：进程被杀即全灭（附件本体的持久化是发送队
/// 列包的正解，不在本件）。
public struct ThreadBoundStash<Value> {
    private var storage: [UUID: Value] = [:]

    public init() {}

    /// 存入某线程的格（同格覆盖）
    public mutating func store(_ value: Value, for threadID: UUID) {
        storage[threadID] = value
    }

    /// 取出并清格（取出后归调用方持有，格内不再留份）
    public mutating func take(for threadID: UUID) -> Value? {
        storage.removeValue(forKey: threadID)
    }

    /// 只看不清格
    public func peek(for threadID: UUID) -> Value? {
        storage[threadID]
    }

    /// 丢弃某线程的格（线程被删时连带清，不留死键）
    public mutating func remove(for threadID: UUID) {
        storage[threadID] = nil
    }

    public var isEmpty: Bool { storage.isEmpty }
}
