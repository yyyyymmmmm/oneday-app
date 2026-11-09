import Foundation

/// 审批桥钥匙的设置状态（纯判定，设置页与单测共用）。
///
/// 语义只有一条：Keychain 里有非空值＝已设置。空串与纯
/// 空白一律按未设置——桥客户端拿到空钥匙与没钥匙无异，
/// 不许让「存了个空串」冒充已设置。实际读写在 App 层走
/// KeychainStore＋CredentialKey.writeGateKey，与枢纽页
/// WriteGateClient 的读取处同一键（§31 代码层自证）。
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
