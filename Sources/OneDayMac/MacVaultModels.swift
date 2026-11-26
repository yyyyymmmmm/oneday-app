import Foundation

/// 凭据库 DTO（棒 2，对位 #71/#20）：与 iOS 端
/// VaultModels 逐字段同形——服务端 /v1/vault 契约
/// 单源，Mac 只另写一份解码模型（iOS 那份在 App 目
/// 标内、Mac 不可达），字段与口径不许漂移。
/// 红线：条目回包只有元数据（field_names 列字段名、
/// has_secret 标有无值），值永不回客户端——创建/
/// 替换/兑现时由用户在端上输入、直送服务端，不落
/// 盘、不进日志。

struct MacVaultEntry: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let service: String
    let domains: [String]
    let username: String?
    let fieldNames: [String]
    let updatedAt: Double
    let version: Int
    let hasSecret: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, service, domains, username, version
        case fieldNames = "field_names"
        case updatedAt = "updated_at"
        case hasSecret = "has_secret"
    }

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt) }
}

struct MacVaultEntryListResponse: Decodable, Sendable {
    let data: [MacVaultEntry]
}

struct MacVaultWriteRequest: Encodable, Sendable {
    let name: String
    let service: String
    let domains: [String]
    let values: [String: String]
    let username: String?
}

struct MacVaultWriteResponse: Decodable, Sendable {
    let id: String
    let version: Int
    let updatedAt: Double
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, version, status
        case updatedAt = "updated_at"
    }
}

struct MacVaultRevokeResponse: Decodable, Sendable {
    let status: String
}

/// 凭据请求（智能体经工具发起、等用户兑现/拒绝）
struct MacVaultRequest: Decodable, Sendable, Identifiable {
    let requestID: String
    let service: String
    let domain: String
    let reason: String
    let fields: [String]
    let status: String
    let expiresAt: Double

    var id: String { requestID }

    var expiresDate: Date { Date(timeIntervalSince1970: expiresAt) }

    var isPending: Bool { status == "pending" }

    enum CodingKeys: String, CodingKey {
        case service, domain, reason, fields, status
        case requestID = "request_id"
        case expiresAt = "expires_at"
    }
}

struct MacVaultRequestListResponse: Decodable, Sendable {
    let data: [MacVaultRequest]
}

struct MacVaultRequestStatus: Decodable, Sendable {
    let requestID: String
    let status: String
    let expiresAt: Double

    enum CodingKeys: String, CodingKey {
        case status
        case requestID = "request_id"
        case expiresAt = "expires_at"
    }
}

struct MacVaultFulfillRequest: Encodable, Sendable {
    /// "fulfill" / "reject"（与 iOS 卡同一契约值）
    let decision: String
    let values: [String: String]?
    let username: String?
}

struct MacVaultFulfillResponse: Decodable, Sendable {
    let status: String
    let credentialRef: String?

    enum CodingKeys: String, CodingKey {
        case status
        case credentialRef = "credential_ref"
    }
}

/// 请求字段的人话名（与 iOS 凭据请求卡同一译表）
enum MacVaultFieldCopy {
    static func displayName(_ field: String) -> String {
        switch field {
        case "username": return "用户名"
        case "password": return "密码"
        case "token": return "令牌"
        case "api_key": return "API Key"
        case "secret": return "Secret"
        case "otp": return "OTP"
        default: return field
        }
    }

    /// 敏感字段走安全输入框（密码类不回显）
    static func isSecret(_ field: String) -> Bool {
        switch field {
        case "password", "token", "api_key", "secret", "otp":
            return true
        default:
            return false
        }
    }
}
