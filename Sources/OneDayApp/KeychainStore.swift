import Foundation
import OneDayCore
import Security

/// 凭据键名：连接页写入、AppState 读取，键名集中在此一处。
enum CredentialKey {
    static let baseURL = "server.baseURL"
    static let username = "auth.username"
    static let password = "auth.password"
    static let apiKey = "api.key"
    /// write-gate 桥单独钥匙（桥方案 §2.2：不复用聊天
    /// 钥匙，审批权可独立轮换）。不并入 all（断开连接不清
    /// 它，生命周期独立）。发放通道＝0.5.0 起设置页「审批
    /// 桥钥匙」粘贴一次写入本键（WriteGateKeySettings-
    /// View），WriteGateClient 只读；读不到即审核段落
    /// 「通道未接通」诚实态
    static let writeGateKey = "writegate.key"

    /// 桥分项钥（0.32.1，审计 F03/R8）：五桥按 scope
    /// 各自一把，键名 bridge.key.<scope>。writeGateKey
    /// 自此降为【过渡回退】来源（见 BridgeKeyStore），
    /// 服务器轮换完成后的下一版连键带回退一并删除
    static func bridgeKey(_ scope: BridgeKeyScope) -> String {
        "bridge.key.\(scope.rawValue)"
    }

    static let all = [baseURL, username, password, apiKey]
}

/// 分桥钥匙读取（0.32.1，F03/R8）：各桥客户端只经此
/// 读自己 scope 的钥。优先分项钥；分项未配置时临时
/// 回退旧共用钥 writeGateKey——【仅过渡期】：服务器
/// 五桥轮换完成前，现装版本靠回退照常工作；轮换后
/// 旧钥在各桥 env 退役、回退值会被桥拒绝而自然失
/// 效。回退在轮换完成后下一版删除。注意：设置页的
/// 逐项状态只认分项本体（scopedValue），不许拿回退
/// 的可用冒充已分权。
enum BridgeKeyStore {
    /// 客户端实际取钥：分项优先、旧钥过渡回退
    static func read(_ scope: BridgeKeyScope) -> String? {
        if let scoped = scopedValue(scope) {
            return scoped
        }
        return WriteGateKeyStatus.sanitizedForStorage(
            KeychainStore.read(account: CredentialKey.writeGateKey)
        )
    }

    /// 分项本体（设置页逐项状态专用，不含回退）
    static func scopedValue(_ scope: BridgeKeyScope) -> String? {
        WriteGateKeyStatus.sanitizedForStorage(
            KeychainStore.read(account: CredentialKey.bridgeKey(scope))
        )
    }
}

/// Keychain 薄封装（kSecClassGenericPassword）。
/// 服务器地址、面板账号密码、API 密钥只许存这里，不进
/// UserDefaults / SwiftData / 文件（沿礼记凭据纪律）。
enum KeychainStore {
    private static let service = "site.didichou.oneday"

    static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearAll() {
        for account in CredentialKey.all {
            delete(account: account)
        }
    }
}
