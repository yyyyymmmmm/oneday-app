import Foundation
import Security

/// 凭据键名（与 iOS 端 CredentialKey 同名同义）：连接
/// 成功后写入、启动时读回，键名集中在此一处，不许散落
enum MacCredentialKey {
    static let baseURL = "server.baseURL"
    static let password = "auth.password"
    static let apiKey = "api.key"

    static let all = [baseURL, password, apiKey]
}

/// Keychain 薄封装（kSecClassGenericPassword）：与 iOS
/// 端 KeychainStore 同一 service（site.didichou.oneday）
/// 与同一账户口径——服务器地址、面板密码、API 密钥只
/// 许存这里，不进 UserDefaults／文件（凭据纪律同 iOS）
enum MacKeychain {
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
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAllCredentials() {
        for account in MacCredentialKey.all {
            delete(account: account)
        }
    }
}
