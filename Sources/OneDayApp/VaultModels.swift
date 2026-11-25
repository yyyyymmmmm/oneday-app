import Foundation

// MARK: - Vault Entry Metadata

struct VaultEntryMeta: Decodable, Sendable, Identifiable {
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
        case id
        case name
        case service
        case domains
        case username
        case fieldNames = "field_names"
        case updatedAt = "updated_at"
        case version
        case hasSecret = "has_secret"
    }

    var updatedAtDate: Date {
        Date(timeIntervalSince1970: updatedAt)
    }
}

struct VaultEntryListResponse: Decodable, Sendable {
    let object: String
    let data: [VaultEntryMeta]
}

// MARK: - Vault Entry Write Models

struct VaultEntryCreateRequest: Encodable, Sendable {
    let name: String
    let service: String
    let domains: [String]
    let values: [String: String]
    let username: String?
}

struct VaultEntryReplaceRequest: Encodable, Sendable {
    let name: String
    let service: String
    let domains: [String]
    let values: [String: String]
    let username: String?
}

struct VaultEntryWriteResponse: Decodable, Sendable {
    let id: String
    let version: Int
    let updatedAt: Double
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case version
        case updatedAt = "updated_at"
        case status
    }
}

struct VaultEntryRevokeResponse: Decodable, Sendable {
    let status: String
}

// MARK: - Vault Request Models

struct VaultRequestStatus: Decodable, Sendable {
    let requestId: String
    let status: String
    let expiresAt: Double

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case status
        case expiresAt = "expires_at"
    }

    var expiresAtDate: Date {
        Date(timeIntervalSince1970: expiresAt)
    }
}

struct VaultRequestFulfillRequest: Encodable, Sendable {
    let decision: String
    let values: [String: String]?
    let username: String?
}

struct VaultRequestFulfillResponse: Decodable, Sendable {
    let status: String
    let credentialRef: String?

    enum CodingKeys: String, CodingKey {
        case status
        case credentialRef = "credential_ref"
    }
}
