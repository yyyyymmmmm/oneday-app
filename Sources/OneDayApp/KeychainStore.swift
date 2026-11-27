import Foundation
import OneDayCore
import Security

/// 凭据键名：连接页写入、AppState 读取，键名集中在此一处。
enum CredentialKey {
    static let baseURL = "server.baseURL"
    /// §244 退役：面板密码无账号概念，登录链不再读写本
    /// 键；键名留档＋留在 all 里（断开连接时随三件套一
    /// 并清掉存量值），成功登录时也顺手删
    static let username = "auth.username"
    static let password = "auth.password"
    static let apiKey = "api.key"
    /// #1 短时票据对（JSON 编码的 ShortLivedTokenPair）：
    /// 含 24h access_token 与 30d 滑动 refresh_token，随
    /// 断开连接一并清除（纳入 all）
    static let shortLivedTokenPair = "auth.shortLivedTokenPair"
    /// 旧桥共用钥的发放键（0.5.0–0.32.1 历史）：设置页
    /// 「桥钥匙」曾写入本键、桥客户端曾以它作 Bearer。
    /// 0.33.1 起无人读写（桥请求改用 api.key、入口在服
    /// 务器内部换钥，见 BridgeCredential）；键名保留作档
    /// 案，存量值不删（回滚 0.32.1 时仍可用），不并入
    /// all（断开连接不清它，生命周期独立）
    static let writeGateKey = "writegate.key"

    static let all = [baseURL, username, password, apiKey, shortLivedTokenPair]
}

/// 身份键名（根治版包 1，DESIGN §330）：主线钦定身
/// 份键（主线线程/服务端会话 id＋链接确认位）自
/// UserDefaults 迁 Keychain 与凭据同级，键名集中在
/// 此一处（SessionLedger 经 IdentityValueStore 读写）。
/// 不并入 CredentialKey.all：断开连接不清身份——重
/// 连同一台服务器还要认得出主线；旧 UserDefaults 键
/// （sideChats.main*）留作一版双轨镜像保回滚（与归
/// 档列同口径，停写归下一大版本）。
enum IdentityKey {
    static let mainThreadID = "identity.mainThreadID"
    static let mainServerSessionID = "identity.mainServerSessionID"
    static let mainServerConfirmed = "identity.mainServerConfirmed"
    static let mainServerSeeded = "identity.mainServerSeeded"
}

/// 桥客户端统一取钥（0.33.1，用户 16:08 定版）：用户
/// 只持一把 Hermes 登录密钥——桥请求直接以聊天同一
/// 份 api.key 作 Bearer，nginx 入口校验通过后在服务
/// 器内部换成各桥自己的服务钥（分权是服务器内部的
/// 事、用户无感、不再懂五把钥）。0.32.1 的 BridgeKey-
/// Store 五分项读取与旧共用钥回退自此整件退役。
enum BridgeCredential {
    static func read() -> String? {
        WriteGateKeyStatus.sanitizedForStorage(
            KeychainStore.read(account: CredentialKey.apiKey)
        )
    }
}

/// 退役桥钥残项清理（0.33.1）：启动时把 0.32.1 写进
/// Keychain 的五条 bridge.key.* 删净。删除面由
/// OneDayCore.RetiredBridgeKeyAccounts 钉死——只删本
/// App 自己写过的这组键，登录凭据与 writegate.key
/// 存量一概不动。幂等：键已不在时 SecItemDelete 无害。
enum RetiredBridgeKeyCleanup {
    static func purge() {
        for account in RetiredBridgeKeyAccounts.accounts {
            KeychainStore.delete(account: account)
        }
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

    static func saveShortLivedTokenPair(_ pair: ShortLivedTokenPair) {
        guard let data = try? JSONEncoder().encode(pair),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        save(text, account: CredentialKey.shortLivedTokenPair)
    }

    static func readShortLivedTokenPair() -> ShortLivedTokenPair? {
        guard let text = read(account: CredentialKey.shortLivedTokenPair),
              let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ShortLivedTokenPair.self, from: data)
    }

    static func deleteShortLivedTokenPair() {
        delete(account: CredentialKey.shortLivedTokenPair)
    }
}
