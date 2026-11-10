import Foundation

/// 退役桥钥的 Keychain 残项清单（0.33.1，用户 16:08
/// 定版：用户只持一把 Hermes 登录密钥、桥间分权纯服
/// 务器内部）。0.32.1 的五分项钥（bridge.key.<scope>）
/// 自此退役：App 启动时按本清单把这组键从 Keychain
/// 删净——只删本 App 自己写过的这组键，登录凭据
/// （api.key／auth.*／server.baseURL）与旧共用钥
/// writegate.key 都不在清单内、绝不误删。
public enum RetiredBridgeKeyAccounts {
    /// 退役分项钥的 Keychain account 全名（顺序即
    /// 0.32.1 的 scope 序：overview/oneday/writegate/
    /// box/device）
    public static let accounts: [String] = [
        "bridge.key.overview",
        "bridge.key.oneday",
        "bridge.key.writegate",
        "bridge.key.box",
        "bridge.key.device",
    ]

    /// 从现存 account 集里挑出要清的退役键：只回清单
    /// 内且确实存在的，按清单 canonical 顺序返回
    public static func accountsToPurge(
        existingAccounts: [String]
    ) -> [String] {
        let existing = Set(existingAccounts)
        return accounts.filter { existing.contains($0) }
    }
}
