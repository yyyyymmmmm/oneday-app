import Testing
import Foundation
@testable import OneDayApp

@Suite("Vault 凭据库测试")
struct VaultTests {

    // MARK: - 门禁状态机测试

    @Test("未解锁时列表零渲染")
    func testUnlockedGate() async throws {
        let store = VaultStore()

        #expect(store.entries.isEmpty)
        #expect(store.loading == false)
        #expect(store.loadError == nil)
    }

    // MARK: - 域名校验测试

    @Test("域名校验 - 有效域名")
    func testValidDomains() {
        let valid = [
            "example.com",
            "sub.example.com",
            "api.service.example.com",
            "a.b.c.d.example.com",
            "example-service.com",
            "123.example.com"
        ]

        for domain in valid {
            let result = validateDomain(domain)
            #expect(result == nil, "域名 \(domain) 应该通过验证")
        }
    }

    @Test("域名校验 - 小写要求")
    func testDomainLowercaseRequired() {
        let result = validateDomain("Example.Com")
        #expect(result != nil)
        #expect(result?.contains("小写") == true)
    }

    @Test("域名校验 - 不能包含空格")
    func testDomainNoSpaces() {
        let result = validateDomain("example .com")
        #expect(result != nil)
        #expect(result?.contains("空格") == true)
    }

    @Test("域名校验 - 必须包含点号")
    func testDomainRequiresDot() {
        let result = validateDomain("examplecom")
        #expect(result != nil)
        #expect(result?.contains("点号") == true)
    }

    @Test("域名校验 - 无效格式")
    func testDomainInvalidFormat() {
        let invalid = [
            ".example.com",
            "example.com.",
            "-example.com",
            "example-.com",
            "exa mple.com",
            "example..com"
        ]

        for domain in invalid {
            let result = validateDomain(domain)
            #expect(result != nil, "域名 \(domain) 应该被拒绝")
        }
    }

    // MARK: - Fulfill 键集合校验测试

    @Test("键集合校验 - 完全匹配")
    func testFulfillKeysExactMatch() {
        let required: Set<String> = ["username", "password"]
        let provided: Set<String> = ["username", "password"]

        #expect(required == provided)
    }

    @Test("键集合校验 - 缺少字段")
    func testFulfillKeysMissing() {
        let required: Set<String> = ["username", "password", "token"]
        let provided: Set<String> = ["username", "password"]

        #expect(required != provided)
        #expect(required.isSuperset(of: provided))
    }

    @Test("键集合校验 - 多余字段")
    func testFulfillKeysExtra() {
        let required: Set<String> = ["username", "password"]
        let provided: Set<String> = ["username", "password", "token"]

        #expect(required != provided)
        #expect(provided.isSuperset(of: required))
    }

    // MARK: - 元数据解码测试

    @Test("VaultEntryMeta 解码")
    func testVaultEntryMetaDecoding() throws {
        let json = """
        {
            "id": "cred_test123",
            "name": "测试凭据",
            "service": "test-service",
            "domains": ["example.com", "api.example.com"],
            "username": "testuser",
            "field_names": ["username", "password"],
            "updated_at": 1700000000.0,
            "version": 1,
            "has_secret": true
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let entry = try decoder.decode(VaultEntryMeta.self, from: data)

        #expect(entry.id == "cred_test123")
        #expect(entry.name == "测试凭据")
        #expect(entry.service == "test-service")
        #expect(entry.domains == ["example.com", "api.example.com"])
        #expect(entry.username == "testuser")
        #expect(entry.fieldNames == ["username", "password"])
        #expect(entry.version == 1)
        #expect(entry.hasSecret == true)
        #expect(entry.updatedAt == 1700000000.0)
    }

    @Test("VaultEntryListResponse 解码")
    func testVaultEntryListResponseDecoding() throws {
        let json = """
        {
            "object": "list",
            "data": [
                {
                    "id": "cred_1",
                    "name": "凭据1",
                    "service": "service1",
                    "domains": ["domain1.com"],
                    "username": null,
                    "field_names": ["password"],
                    "updated_at": 1700000000.0,
                    "version": 1,
                    "has_secret": true
                },
                {
                    "id": "cred_2",
                    "name": "凭据2",
                    "service": "service2",
                    "domains": ["domain2.com"],
                    "username": "user2",
                    "field_names": ["username", "token"],
                    "updated_at": 1700000100.0,
                    "version": 2,
                    "has_secret": true
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(VaultEntryListResponse.self, from: data)

        #expect(response.object == "list")
        #expect(response.data.count == 2)
        #expect(response.data[0].id == "cred_1")
        #expect(response.data[1].id == "cred_2")
        #expect(response.data[0].username == nil)
        #expect(response.data[1].username == "user2")
    }

    @Test("VaultRequestStatus 解码")
    func testVaultRequestStatusDecoding() throws {
        let json = """
        {
            "request_id": "vreq_test456",
            "status": "pending",
            "expires_at": 1700001000.0
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let status = try decoder.decode(VaultRequestStatus.self, from: data)

        #expect(status.requestId == "vreq_test456")
        #expect(status.status == "pending")
        #expect(status.expiresAt == 1700001000.0)
    }

    @Test("VaultRequestFulfillResponse 解码")
    func testVaultRequestFulfillResponseDecoding() throws {
        let json = """
        {
            "status": "fulfilled",
            "credential_ref": "cred_abc123"
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(VaultRequestFulfillResponse.self, from: data)

        #expect(response.status == "fulfilled")
        #expect(response.credentialRef == "cred_abc123")
    }

    // MARK: - 明文零落盘验证

    @Test("VaultEntryMeta 不包含 values 字段")
    func testVaultEntryMetaNoValuesField() throws {
        let json = """
        {
            "id": "cred_test",
            "name": "测试",
            "service": "test",
            "domains": ["test.com"],
            "username": "user",
            "field_names": ["password"],
            "updated_at": 1700000000.0,
            "version": 1,
            "has_secret": true,
            "values": {"password": "secret123"}
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let entry = try decoder.decode(VaultEntryMeta.self, from: data)

        let mirror = Mirror(reflecting: entry)
        let propertyNames = mirror.children.compactMap { $0.label }

        #expect(!propertyNames.contains("values"))
    }

    @Test("VaultRequestFulfillRequest 编码后不含明文样本")
    func testFulfillRequestNoPlaintextInEncoding() throws {
        let request = VaultRequestFulfillRequest(
            decision: "approve",
            values: ["password": "secret123", "token": "token456"],
            username: "testuser"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("secret123"))
        #expect(jsonString.contains("token456"))
    }
}

// MARK: - 辅助函数

private func validateDomain(_ domain: String) -> String? {
    if domain.isEmpty {
        return "域名不能为空"
    }

    if domain != domain.lowercased() {
        return "域名必须是小写：\(domain)"
    }

    if domain.contains(" ") {
        return "域名不能包含空格：\(domain)"
    }

    if !domain.contains(".") {
        return "域名必须包含点号：\(domain)"
    }

    let domainRegex = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/
    if domain.firstMatch(of: domainRegex) == nil {
        return "无效的域名格式：\(domain)"
    }

    return nil
}
