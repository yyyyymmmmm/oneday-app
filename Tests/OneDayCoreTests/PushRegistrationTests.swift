import OneDayCore
import XCTest

/// 推送登记契约钉测（总表 138，DESIGN §397）：令牌编
/// 码、环境解析、登记契约字面、失败分型、就绪派生与
/// 点按路由——全部纯逻辑，对批 4b §4.1/§4.2 草案契约
/// 与 §397 状态口径，不许凭图臆测
final class PushRegistrationTests: XCTestCase {

    // MARK: 令牌编码

    func testTokenHexEncodeDecode() {
        let data = Data([0x00, 0x01, 0xab, 0xff, 0x10])
        XCTAssertEqual(PushTokenHex.encode(data), "0001abff10")
        XCTAssertEqual(
            PushTokenHex.decode("0001abff10"), data
        )
    }

    func testTokenHexDecodeRejectsInvalid() {
        XCTAssertNil(PushTokenHex.decode(""))
        XCTAssertNil(PushTokenHex.decode("abc"))
        XCTAssertNil(PushTokenHex.decode("zz"))
        XCTAssertNil(PushTokenHex.decode("0g"))
    }

    // MARK: 环境解析

    private func provisionData(
        apsEnvironment: String?
    ) throws -> Data {
        var entitlements: [String: Any] = [
            "application-identifier":
                "TEAMID.site.didichou.oneday",
        ]
        if let apsEnvironment {
            entitlements["aps-environment"] = apsEnvironment
        }
        let plist: [String: Any] = [
            "Entitlements": entitlements, "Name": "fixture",
        ]
        let xml = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        var data = Data([0x30, 0x82, 0x1c])
        data.append(xml)
        data.append(Data([0x00, 0xff, 0x10]))
        return data
    }

    func testProvisionParsesDevelopmentAsSandbox() throws {
        let data = try provisionData(
            apsEnvironment: "development"
        )
        XCTAssertEqual(
            PushProvisionReader.apsEnvironment(
                fromProvisionData: data
            ),
            .sandbox
        )
    }

    func testProvisionParsesProduction() throws {
        let data = try provisionData(
            apsEnvironment: "production"
        )
        XCTAssertEqual(
            PushProvisionReader.apsEnvironment(
                fromProvisionData: data
            ),
            .production
        )
    }

    func testProvisionMissingKeyOrGarbageReturnsNil() throws {
        let noKey = try provisionData(apsEnvironment: nil)
        XCTAssertNil(
            PushProvisionReader.apsEnvironment(
                fromProvisionData: noKey
            )
        )
        XCTAssertNil(
            PushProvisionReader.apsEnvironment(
                fromProvisionData: Data([0x01, 0x02, 0x03])
            )
        )
        let unknown = try provisionData(
            apsEnvironment: "something-else"
        )
        XCTAssertNil(
            PushProvisionReader.apsEnvironment(
                fromProvisionData: unknown
            )
        )
    }

    // MARK: 登记契约字面（批 4b §4.1 草案）

    func testRegistrationBodyEncoding() throws {
        let body = PushTokenRegistrationBody(
            deviceToken: "deadbeef",
            environment: .sandbox,
            bundleID: "site.didichou.oneday",
            appVersion: "0.50.98"
        )
        let data = try JSONEncoder().encode(body)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertEqual(object.count, 4)
        XCTAssertEqual(
            object["device_token"] as? String, "deadbeef"
        )
        XCTAssertEqual(
            object["environment"] as? String, "sandbox"
        )
        XCTAssertEqual(
            object["bundle_id"] as? String,
            "site.didichou.oneday"
        )
        XCTAssertEqual(
            object["app_version"] as? String, "0.50.98"
        )
    }

    func testRegisteredResponseDecoding() throws {
        let yes = try JSONDecoder().decode(
            PushTokenRegisteredResponse.self,
            from: Data(#"{"registered":true}"#.utf8)
        )
        XCTAssertTrue(yes.registered)
        let no = try JSONDecoder().decode(
            PushTokenRegisteredResponse.self,
            from: Data(#"{"registered":false}"#.utf8)
        )
        XCTAssertFalse(no.registered)
    }

    func testSnapshotCodableRoundTrip() throws {
        let snap = PushRegistrationSnapshot(
            tokenHex: "cafe",
            environment: .production,
            appVersion: "0.50.98",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(
            PushRegistrationSnapshot.self, from: data
        )
        XCTAssertEqual(decoded, snap)
    }

    // MARK: 失败分型

    func testClassifierEntitlementVsSystem() {
        XCTAssertEqual(
            PushFailureClassifier.classify(
                systemErrorDescription:
                    "no valid 'aps-environment' entitlement string found for application"
            ),
            .noEntitlement
        )
        XCTAssertEqual(
            PushFailureClassifier.classify(
                systemErrorDescription:
                    "The operation couldn't be completed."
            ),
            .system
        )
    }

    // MARK: 就绪派生

    func testReadinessGrantedRegistered() {
        let snap = PushRegistrationSnapshot(
            tokenHex: "cafe", environment: .production,
            appVersion: "0.50.98", updatedAt: Date()
        )
        let report = PushReadiness.report(
            permission: .granted, phase: .registered,
            snapshot: snap
        )
        XCTAssertEqual(report.rows.count, 3)
        XCTAssertEqual(report.rows[0].tone, .ok)
        XCTAssertEqual(report.rows[1].tone, .ok)
        XCTAssertTrue(
            report.rows[1].statusText.contains("生产环境")
        )
        XCTAssertEqual(report.rows[2].tone, .info)
        XCTAssertTrue(report.summary.contains("就绪大半"))
    }

    func testReadinessNotDeterminedGatesRegistration() {
        let report = PushReadiness.report(
            permission: .notDetermined, phase: .idle,
            snapshot: nil
        )
        XCTAssertEqual(report.rows[0].tone, .pending)
        XCTAssertTrue(
            report.rows[1].statusText.contains("等通知授权后启动")
        )
        XCTAssertTrue(report.summary.contains("长轮询"))
    }

    func testReadinessDeniedBlocked() {
        let report = PushReadiness.report(
            permission: .denied, phase: .idle, snapshot: nil
        )
        XCTAssertEqual(report.rows[0].tone, .blocked)
    }

    func testReadinessServerNotReady() {
        let report = PushReadiness.report(
            permission: .granted,
            phase: .failed(.serverNotReady),
            snapshot: nil
        )
        XCTAssertEqual(report.rows[1].tone, .blocked)
        XCTAssertEqual(
            report.rows[1].statusText,
            PushRegistrationFailure.serverNotReady.label
        )
        XCTAssertEqual(report.rows[2].tone, .blocked)
        XCTAssertTrue(
            report.rows[2].statusText.contains("批 4b")
        )
    }

    func testReadinessUploadPending() {
        let report = PushReadiness.report(
            permission: .granted, phase: .uploadPending,
            snapshot: nil
        )
        XCTAssertEqual(report.rows[1].tone, .pending)
        XCTAssertEqual(report.rows[2].tone, .info)
    }

    // MARK: 点按路由（批 4b §4.2 payload 契约）

    func testRouteApproval() {
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(
                userInfo: ["kind": "approval", "request_id": "r1"]
            ),
            .approval(requestID: "r1")
        )
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(
                userInfo: ["kind": "approval"]
            ),
            .approval(requestID: nil)
        )
    }

    func testRouteRun() {
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(
                userInfo: ["kind": "run", "session_id": "s1"]
            ),
            .session(sessionID: "s1")
        )
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(
                userInfo: ["kind": "run"]
            ),
            .none
        )
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(
                userInfo: ["kind": "run", "session_id": ""]
            ),
            .none
        )
    }

    func testRouteNoneForLocalAndUnknown() {
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(userInfo: [:]),
            .none
        )
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(
                userInfo: ["kind": "other", "session_id": "s1"]
            ),
            .none
        )
        // 本地通知（notify_post 形态：无 kind 键）
        XCTAssertEqual(
            PushNotificationRouteResolver.resolve(
                userInfo: ["title": "提醒", "body": "正文"]
            ),
            .none
        )
    }
}
