import Foundation
import Security

/// 凭据键名：连接页写入、AppState 读取，键名集中在此一处。
enum CredentialKey {
    static let baseURL = "server.baseURL"
    static let username = "auth.username"
    static let password = "auth.password"
    static let apiKey = "api.key"
    /// write-gate 桥单独钥匙（桥方案 §2.2：不复用聊天
    /// 钥匙，审批权可独立轮换）。暂不并入 all：钥匙的
    /// 发放/清除生命周期在合并联调时与桥侧一并定（本
    /// 线只读取；读不到即审核段落「通道未接通」诚实态）
    static let writeGateKey = "writegate.key"

    static let all = [baseURL, username, password, apiKey]
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
