import OneDayCore
import XCTest

/// 0.27.0 串话热修的纯判定闸：合并桶识别与解绑
/// 计划、删除归档闸、种子转录过滤、建会话/import
/// 请求体形态、当前线程显式解析。网络与服务端行
/// 为不在此验（生产联调证据在 DESIGN-V4 §54）。
final class SessionLinkHotfixTests: XCTestCase {

    // MARK: - 合并桶

    func testMergeBucketsAreRecognized() {
        XCTAssertTrue(SideChatLink.isMergeBucket("api-592647b9ae21ec54"))
        XCTAssertTrue(SideChatLink.isMergeBucket("api-e8c923beeaebed9c"))
        XCTAssertFalse(SideChatLink.isMergeBucket("api-0000000000000000"))
        XCTAssertFalse(SideChatLink.isMergeBucket("oneday-side-x"))
        XCTAssertFalse(SideChatLink.isMergeBucket(nil))
        XCTAssertFalse(SideChatLink.isMergeBucket(""))
    }

    func testBucketBoundThreadMustRelink() {
        // 绑合并桶＝按未链接处理：种子位无论真假都
        // 先解绑重链——桶里混着主线历史，会话模式直
        // 发等于继续往桶里写
        for bucket in SideChatLink.mergeBucketSessionIDs {
            XCTAssertEqual(
                SideChatLink.sendPlan(
                    serverSessionID: bucket, serverSeeded: true
                ),
                .linkAndSeed
            )
            XCTAssertEqual(
                SideChatLink.sendPlan(
                    serverSessionID: bucket, serverSeeded: false
                ),
                .linkAndSeed
            )
        }
    }

    func testMergeBucketWarningNamesMainlineStakes() {
        // 二次确认文案必须写明牵连主线（信息给足是
        // 这道闸的全部意义）
        XCTAssertTrue(SideChatLink.mergeBucketWarning.contains("主线"))
        XCTAssertTrue(SideChatLink.mergeBucketWarning.contains("归档"))
        XCTAssertTrue(SideChatLink.mergeBucketWarning.contains("删除"))
    }

    // MARK: - 删除归档闸

    func testArchiveOnDeleteOnlyForOwnSessions() {
        XCTAssertTrue(
            SideChatLink.mayArchiveOnDelete(sessionID: "oneday-side-x")
        )
        XCTAssertTrue(
            SideChatLink.mayArchiveOnDelete(sessionID: "oneday-main-x")
        )
        // 合并桶：归档它等于连带归档主线服务端历史
        XCTAssertFalse(
            SideChatLink.mayArchiveOnDelete(
                sessionID: "api-592647b9ae21ec54"
            )
        )
        XCTAssertFalse(
            SideChatLink.mayArchiveOnDelete(
                sessionID: "api-e8c923beeaebed9c"
            )
        )
        // 他方/导入会话与空绑定：只删本地、零动作
        XCTAssertFalse(
            SideChatLink.mayArchiveOnDelete(sessionID: "sess-foreign-1")
        )
        XCTAssertFalse(SideChatLink.mayArchiveOnDelete(sessionID: nil))
        XCTAssertFalse(SideChatLink.mayArchiveOnDelete(sessionID: ""))
    }

    // MARK: - 种子转录

    func testSeedTranscriptFiltersAndKeepsOrder() {
        let entries = [
            SeedEntry(role: "user", content: "第一问"),
            SeedEntry(role: "tool", content: "工具卡不进种子"),
            SeedEntry(role: "assistant", content: "第一答"),
            SeedEntry(role: "user", content: "   "),
            SeedEntry(role: "assistant", content: ""),
            SeedEntry(role: "system", content: "系统条不进种子"),
            SeedEntry(role: "user", content: "第二问"),
        ]
        let seed = SideChatLink.seedTranscript(from: entries)
        XCTAssertEqual(
            seed.map(\.content), ["第一问", "第一答", "第二问"]
        )
        XCTAssertEqual(seed.map(\.role), ["user", "assistant", "user"])
    }

    func testSeedTranscriptOfEmptyIsEmpty() {
        XCTAssertTrue(SideChatLink.seedTranscript(from: []).isEmpty)
    }

    // MARK: - 建会话请求形态（网关面契约）

    func testCreateSessionBodyMainShape() {
        XCTAssertEqual(
            SideChatLink.createSessionBody(id: "oneday-main-x", title: "主线"),
            ["id": .string("oneday-main-x"), "title": .string("主线")]
        )
        XCTAssertEqual(
            SideChatLink.createSessionBody(id: nil, title: nil),
            [:]
        )
    }

    func testLinkedCreateSessionBodyLocksModelWithoutTitle() {
        let body = SideChatLink.linkedCreateSessionBody(
            id: "oneday-side-x", model: "deepseek-flash"
        )
        XCTAssertEqual(
            body,
            [
                "id": .string("oneday-side-x"),
                "model": .string("deepseek-flash"),
                "require_model_lock": .bool(true),
            ]
        )
        // 标题不带：服务端两段式标题须由内容自生
        XCTAssertNil(body["title"])
    }

    // MARK: - import 请求形态（Dashboard 种子契约）

    func testImportSessionBodyCarriesLockAndMessages() {
        let messages = [
            SeedEntry(role: "user", content: "问", timestamp: 100),
            SeedEntry(role: "assistant", content: "答"),
        ]
        let body = SideChatLink.importSessionBody(
            id: "oneday-side-x", title: nil, model: "deepseek-flash",
            messages: messages, lockUpdatedAt: 200
        )
        XCTAssertEqual(body["id"], .string("oneday-side-x"))
        XCTAssertEqual(body["source"], .string("api_server"))
        XCTAssertNil(body["title"])
        XCTAssertEqual(body["model"], .string("deepseek-flash"))
        guard case .object(let lock) = body["model_config"],
              case .object(let browserLock) = lock["browser_model_lock"]
        else {
            return XCTFail("model_config.browser_model_lock 缺失")
        }
        XCTAssertEqual(browserLock["model"], .string("deepseek-flash"))
        XCTAssertEqual(browserLock["confirmed"], .bool(true))
        XCTAssertEqual(browserLock["updated_at"], .number(200))
        guard case .array(let items) = body["messages"], items.count == 2
        else {
            return XCTFail("messages 形态不对")
        }
        guard case .object(let first) = items[0] else {
            return XCTFail("message 须为对象")
        }
        XCTAssertEqual(first["role"], .string("user"))
        XCTAssertEqual(first["content"], .string("问"))
        XCTAssertEqual(first["timestamp"], .number(100))
        guard case .object(let second) = items[1] else {
            return XCTFail("message 须为对象")
        }
        // 无时间戳的条目不带该键（服务端落当前时刻）
        XCTAssertNil(second["timestamp"])
    }

    func testImportSessionBodyMainShapeHasTitleNoLock() {
        let body = SideChatLink.importSessionBody(
            id: "oneday-main-x", title: "主线", model: nil,
            messages: [SeedEntry(role: "user", content: "问")],
            lockUpdatedAt: 0
        )
        XCTAssertEqual(body["title"], .string("主线"))
        XCTAssertNil(body["model"])
        XCTAssertNil(body["model_config"])
    }

    func testImportRequestBodyCarriesFencing() {
        let session = SideChatLink.importSessionBody(
            id: "oneday-side-x", title: nil, model: nil,
            messages: [], lockUpdatedAt: 0
        )
        let body = SideChatLink.importRequestBody(
            requestID: "req-1", expectedRevision: 0, sessions: [session]
        )
        XCTAssertEqual(body["request_id"], .string("req-1"))
        XCTAssertEqual(body["expected_revision"], .number(0))
        guard case .array(let sessions) = body["sessions"],
              sessions.count == 1 else {
            return XCTFail("sessions 形态不对")
        }
    }

    func testBrowserModelLockConfigShape() {
        let config = SideChatLink.browserModelLockConfig(
            model: "deepseek-v4-pro", updatedAt: 42
        )
        guard case .object(let outer) = config,
              case .object(let lock) = outer["browser_model_lock"]
        else {
            return XCTFail("锁配置形态不对")
        }
        XCTAssertEqual(lock["provider"], .string(""))
        XCTAssertEqual(lock["model"], .string("deepseek-v4-pro"))
        XCTAssertEqual(lock["confirmed"], .bool(true))
        XCTAssertEqual(lock["route_source"], .string(""))
    }

    // MARK: - 当前线程显式解析

    func testResolveMatchesExactly() {
        let ids = [1, 2, 3]
        XCTAssertEqual(
            CurrentThreadResolution.resolve(currentID: 2, existingIDs: ids),
            2
        )
    }

    func testResolveMismatchReturnsNilNotFallback() {
        // 旧口径在此回落最近线程——新口径必须返 nil
        let ids = [1, 2, 3]
        XCTAssertNil(
            CurrentThreadResolution.resolve(currentID: 99, existingIDs: ids)
        )
        XCTAssertNil(
            CurrentThreadResolution.resolve(
                currentID: nil, existingIDs: ids
            )
        )
    }

    func testEnsureDecisionThreeWays() {
        let ids = [1, 2, 3]
        XCTAssertEqual(
            CurrentThreadResolution.ensureDecision(
                currentID: 1, existingIDs: ids
            ),
            .useExisting
        )
        XCTAssertEqual(
            CurrentThreadResolution.ensureDecision(
                currentID: nil, existingIDs: ids
            ),
            .createFresh
        )
        XCTAssertEqual(
            CurrentThreadResolution.ensureDecision(
                currentID: 99, existingIDs: ids
            ),
            .mismatch
        )
    }
}
