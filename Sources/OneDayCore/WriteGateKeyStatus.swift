import Foundation

/// 凭据值的设置状态（纯判定，单测共用）。
///
/// 语义只有一条：Keychain 里有非空值＝已设置。空串与纯
/// 空白一律按未设置——客户端拿到空钥匙与没钥匙无异，
/// 不许让「存了个空串」冒充已设置。0.33.1 后本枚举的
/// 桥钥匙状态用途已退役（桥钥匙整节删除），仅余
/// sanitizedForStorage 清洗函数供 BridgeCredential
/// 统一取钥复用（清洗口径不变，故整件保留）。
public enum WriteGateKeyStatus: Equatable, Sendable {
    case notSet
    case set

    /// 由 Keychain 回读的原始值派生状态（nil/空/纯空白
    /// 均为未设置）。
    public static func resolve(storedValue: String?) -> WriteGateKeyStatus {
        sanitizedForStorage(storedValue) == nil ? .notSet : .set
    }

    /// 入库前清洗：去首尾空白（含换行，粘贴常带）；清洗
    /// 后为空返回 nil，调用方据此拒绝保存。
    public static func sanitizedForStorage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
