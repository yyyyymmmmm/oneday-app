import XCTest
@testable import OneDayCore

/// §244 对话内授权流的 Core 纯逻辑闸：①ask/notice
/// 载荷解析（残缺载荷不许成卡）②卡过期口径（非终
/// 态 24h、终态不翻）③注册附加面（agentCall 全件
/// 映射＋能力声明）④resume 回执分型（404/409 不当
/// 业务失败）⑤结果摘要（humanSummary 优先、不编话）
final class DevicePermissionFlowTests: XCTestCase {

    // MARK: - ask 解析

    func testAskParseValid() {
        let ask = PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
            "resumeToken": .string("park-0123abcd"),
        ])
        XCTAssertEqual(ask?.source, .contacts)
        XCTAssertEqual(ask?.tool, "contacts_search")
        XCTAssertEqual(ask?.resumeToken, "park-0123abcd")
    }

    func testAskParseRejectsBrokenPayloads() {
        XCTAssertNil(PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
        ]), "缺 token 不成卡")
        XCTAssertNil(PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
            "resumeToken": .string(""),
        ]), "空 token 不成卡")
        XCTAssertNil(PermissionAskRequest.parse(arguments: [
            "source": .string("no_such_source"),
            "tool": .string("contacts_search"),
            "resumeToken": .string("park-0123abcd"),
        ]), "未知数据源不成卡")
    }

    // MARK: - notice 解析与落卡相位

    func testNoticeParseLayersAndPhases() {
        let denied = PermissionNotice.parse(arguments: [
            "source": .string("calendar"),
            "tool": .string("calendar_list_events"),
            "resumeToken": .string("park-aaaa"),
            "blockerLayer": .string("permission"),
            "state": .string("denied"),
            "parkKind": .string("live"),
        ])
        XCTAssertEqual(denied?.layer, .permission)
        XCTAssertEqual(denied?.state, .denied)
        XCTAssertEqual(denied?.initialPhase, .blocked)
        XCTAssertEqual(denied?.isSyncQuery, false)

        let switchOff = PermissionNotice.parse(arguments: [
            "source": .string("clipboard"),
            "tool": .string("clipboard_get"),
            "resumeToken": .string("park-bbbb"),
            "blockerLayer": .string("agentSwitch"),
            "state": .string("granted"),
            "parkKind": .string("live"),
        ])
        XCTAssertEqual(switchOff?.initialPhase, .switchOff)

        let sync = PermissionNotice.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_count"),
            "resumeToken": .string("park-ccCC"),
            "blockerLayer": .string("permission"),
            "state": .string("revoked"),
            "parkKind": .string("sync"),
        ])
        XCTAssertEqual(sync?.isSyncQuery, true)
        // revoked 不是 App 侧状态枚举：解析为 nil 不拦卡
        XCTAssertNil(sync?.state)
        XCTAssertEqual(sync?.initialPhase, .blocked)
    }

    func testNoticeParseRejectsMissingLayer() {
        XCTAssertNil(PermissionNotice.parse(arguments: [
            "source": .string("calendar"),
            "tool": .string("calendar_list_events"),
            "resumeToken": .string("park-aaaa"),
        ]))
    }

    // MARK: - 卡过期口径

    func testCardExpiry() {
        let card = PermissionCard(
            id: "park-1", source: .contacts, tool: "contacts_count",
            layer: .permission, isSyncQuery: true, phase: .blocked,
            createdAt: 1_000
        )
        XCTAssertEqual(card.expiresAt, 1_000 + 24 * 3600)
        XCTAssertFalse(card.isExpired(at: 1_000 + 23 * 3600))
        XCTAssertTrue(card.isExpired(at: 1_000 + 25 * 3600))

        var done = card
        done.phase = .done
        XCTAssertFalse(
            done.isExpired(at: 1_000 + 48 * 3600),
            "终态卡不翻过期"
        )
    }

    // MARK: - §261 ② 过期口径单源（桥 park 时刻起算）

    func testCardDatesPreferBridgeParkTimes() {
        let ask = PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
            "resumeToken": .string("park-0123abcd"),
            "parkedAt": .number(2_000),
            "expiresAt": .number(2_000 + 24 * 3600),
        ])
        let dates = ask?.cardDates(now: 9_999)
        XCTAssertEqual(dates?.createdAt, 2_000, "起算点＝桥 park 时刻，不用本地收信时刻")
        XCTAssertEqual(dates?.expiresAt, 2_000 + 24 * 3600)

        let legacy = PermissionAskRequest.parse(arguments: [
            "source": .string("contacts"),
            "tool": .string("contacts_search"),
            "resumeToken": .string("park-0123abcd"),
        ])
        let fallback = legacy?.cardDates(now: 9_999)
        XCTAssertEqual(fallback?.createdAt, 9_999, "旧桥无时间字段才本地兜底")
        XCTAssertEqual(fallback?.expiresAt, 9_999 + 24 * 3600)
    }

    func testNoticeDatesPreferBridgeParkTimes() {
        let notice = PermissionNotice.parse(arguments: [
            "source": .string("calendar"),
            "tool": .string("calendar_list_events"),
            "resumeToken": .string("park-aaaa"),
            "blockerLayer": .string("permission"),
            "parkedAt": .number(3_000),
            "expiresAt": .number(3_600),
        ])
        let dates = notice?.cardDates(now: 8_888)
        XCTAssertEqual(dates?.createdAt, 3_000)
        XCTAssertEqual(dates?.expiresAt, 3_600)
    }

    func testCardExplicitExpiresAtAndLegacyDecode() throws {
        let card = PermissionCard(
            id: "park-2", source: .calendar,
            tool: "calendar_list_events", layer: .permission,
            isSyncQuery: false, phase: .blocked,
            createdAt: 1_000, expiresAt: 5_000
        )
        XCTAssertEqual(card.expiresAt, 5_000, "桥给的过期时刻直接落卡")
        XCTAssertFalse(card.askUnanswered)

        // 旧持久化（无 askUnanswered 键）必须解得回来，
        // 不许把在途卡整表丢掉
        let legacyJSON = """
        [{"id":"park-3","source":"contacts","tool":"contacts_count",\
        "layer":"permission","isSyncQuery":true,"phase":"blocked",\
        "createdAt":1000,"expiresAt":87400,"resultSummary":null,\
        "failureNote":null}]
        """
        let decoded = try JSONDecoder().decode(
            [PermissionCard].self, from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(decoded.first?.id, "park-3")
        XCTAssertEqual(decoded.first?.askUnanswered, false)
        XCTAssertEqual(decoded.first?.expiresAt, 87_400)
    }

    // MARK: - §261 ①③ 桥侧读面解析与对账裁定

    func testParkStateParse() {
        let gone = PermissionParkState.parse(body: .object([
            "ok": .bool(true), "exists": .bool(false),
        ]))
        XCTAssertEqual(gone?.exists, false, "桥明确说没了是有效答复")

        let alive = PermissionParkState.parse(body: .object([
            "ok": .bool(true), "exists": .bool(true),
            "park": .object([
                "source": .string("contacts"),
                "tool": .string("contacts_search"),
                "blockerLayer": .string("permission"),
                "kind": .string("sync"),
                "createdAt": .number(2_000),
                "expiresAt": .number(88_400),
                "askOutcome": .string("unanswered"),
            ]),
        ]))
        XCTAssertEqual(alive?.exists, true)
        XCTAssertEqual(alive?.source, .contacts)
        XCTAssertEqual(alive?.isSyncQuery, true)
        XCTAssertEqual(alive?.expiresAt, 88_400)
        XCTAssertEqual(alive?.askOutcome, .unanswered)

        XCTAssertNil(
            PermissionParkState.parse(body: .object(["ok": .bool(true)])),
            "缺 exists 的回执不可信，回 nil 走本地兜底"
        )
        XCTAssertNil(PermissionParkState.parse(body: nil))
    }

    func testParkReconcileDecisions() {
        let now: TimeInterval = 10_000
        func card(_ phase: PermissionCardPhase) -> PermissionCard {
            PermissionCard(
                id: "park-9", source: .contacts,
                tool: "contacts_search", layer: .permission,
                isSyncQuery: false, phase: phase, createdAt: 1_000
            )
        }
        let gone = PermissionParkState(
            exists: false, source: nil, tool: nil, layer: nil,
            isSyncQuery: false, createdAt: nil, expiresAt: nil,
            askOutcome: nil
        )
        let alive = PermissionParkState(
            exists: true, source: .contacts, tool: "contacts_search",
            layer: .permission, isSyncQuery: false,
            createdAt: 2_000, expiresAt: 88_400, askOutcome: nil
        )
        let stale = PermissionParkState(
            exists: true, source: .contacts, tool: "contacts_search",
            layer: .permission, isSyncQuery: false,
            createdAt: 100, expiresAt: 9_999, askOutcome: nil
        )
        XCTAssertEqual(
            PermissionParkReconciler.decision(
                card: card(.blocked), park: gone, now: now
            ), .expire, "桥说 park 没了 → 本地卡翻过期"
        )
        XCTAssertEqual(
            PermissionParkReconciler.decision(
                card: card(.blocked), park: stale, now: now
            ), .expire, "桥的过期时刻已过 → 翻过期"
        )
        XCTAssertEqual(
            PermissionParkReconciler.decision(
                card: card(.blocked), park: alive, now: now
            ), .adopt(park: alive), "park 还在 → 采纳桥口径"
        )
        XCTAssertEqual(
            PermissionParkReconciler.decision(
                card: card(.done), park: gone, now: now
            ), .keep, "终态卡是本地既成事实，不对账翻案"
        )
        XCTAssertEqual(
            PermissionParkReconciler.decision(
                card: card(.resuming), park: gone, now: now
            ), .keep, "续办在途消费 park 是时序、不是真相"
        )
        XCTAssertEqual(
            PermissionParkReconciler.decision(
                card: card(.asking), park: gone, now: now
            ), .keep, "ask 在途同理"
        )
    }

    // MARK: - 注册附加面

    func testRegistrationExtras() {
        let map = DeviceRegistrationExtras.agentCallMap(
            agentCallEnabled: [.contacts: true, .calendar: false]
        )
        XCTAssertEqual(map.count, DeviceSourceID.allCases.count)
        XCTAssertEqual(map["contacts"], true)
        XCTAssertEqual(map["calendar"], false)
        XCTAssertEqual(
            map["health"], false, "未给的件默认关（与既有口径同）"
        )
        XCTAssertEqual(
            DeviceRegistrationExtras.capabilities,
            ["permission_ask_v1"]
        )
    }

    // MARK: - resume 回执分型

    func testResumeOutcomeTyping() {
        XCTAssertEqual(
            PermissionResumeOutcome.from(httpStatus: 404, body: nil),
            .tokenGone
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(httpStatus: 409, body: nil),
            .offline
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(
                httpStatus: 200,
                body: .object([
                    "ok": .bool(true),
                    "result": .object(["total": .number(7)]),
                ])
            ),
            .succeeded(result: .object(["total": .number(7)]))
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(
                httpStatus: 200,
                body: .object([
                    "ok": .bool(false),
                    "error": .string("sync_copy_empty"),
                    "message": .string("副本里还没有数据。"),
                ])
            ),
            .failed(code: "sync_copy_empty", message: "副本里还没有数据。")
        )
        XCTAssertEqual(
            PermissionResumeOutcome.from(httpStatus: 200, body: nil),
            .failed(code: "bad_response", message: nil)
        )
    }

    // MARK: - 结果摘要

    func testResultSummaryPrefersHumanSummary() {
        XCTAssertEqual(
            PermissionResultSummary.line(for: .object([
                "humanSummary": .string("通讯录里共 7 人。"),
            ])),
            "通讯录里共 7 人。"
        )
        XCTAssertEqual(
            PermissionResultSummary.line(for: .object([:])),
            "已办完。"
        )
        XCTAssertEqual(PermissionResultSummary.line(for: nil), "已办完。")
    }
}
