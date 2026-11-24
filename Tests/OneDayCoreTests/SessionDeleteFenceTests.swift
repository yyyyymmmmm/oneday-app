import OneDayCore
import XCTest

/// 删除 409 热修钉测（报告 §2/§3）：JSON 形状取自
/// 2026-11-13 对生产 Hermes v0.23.0 的实测回包——
/// 详情 GET 的 archived/pinned 是数字 0/1（sqlite
/// 原样）、快照端点四件套、拒删回包的 detail 码。
/// 修前此文件第一条即红：合成解码对 Bool? 遇数字
/// 抛错、整行解不出（真机 409 的根）。
final class SessionDeleteFenceTests: XCTestCase {
    private let decoder = JSONDecoder()

    // MARK: - ServerSession 生产形状解码

    /// 生产详情回包形状（用户实删失败那条会话的同
    /// 形回包，值脱敏）：数字形 archived/pinned ＋
    /// 围栏 1/1 ＋ 详情独有未知键（hidden/system_
    /// prompt）必须整行解得出且各值正确
    func testServerSessionDecodesProductionIntBoolShape() throws {
        let json = """
        {"id": "oneday-side-00000000-1111-2222-3333-444444444444",
         "source": "oneday-side", "session_key": null,
         "display_name": "Question mark inquiry",
         "title": "Question mark inquiry", "title_source": "llm",
         "archived": 0, "pinned": 0, "hidden": 0,
         "system_prompt": "…", "model": "claude-sonnet-4-6",
         "profile": "default", "started_at": 1763000000.5,
         "ended_at": null, "end_reason": null,
         "message_count": 2, "tool_call_count": 0,
         "input_tokens": 1200, "output_tokens": 300,
         "runtime_revision": 1, "runtime_generation": 1}
        """
        let row = try decoder.decode(ServerSession.self, from: Data(json.utf8))
        XCTAssertEqual(row.isArchived, false)
        XCTAssertEqual(row.isPinned, false)
        XCTAssertEqual(row.runtimeRevision, 1)
        XCTAssertEqual(row.runtimeGeneration, 1)
        XCTAssertEqual(row.serverTitle, "Question mark inquiry")
        XCTAssertEqual(row.title, "Question mark inquiry")
    }

    /// 数字 1 也要解成 true（归档行同形）
    func testServerSessionDecodesIntOneAsTrue() throws {
        let json = """
        {"id": "s-arch", "archived": 1, "pinned": 1,
         "runtime_revision": 3, "runtime_generation": 2}
        """
        let row = try decoder.decode(ServerSession.self, from: Data(json.utf8))
        XCTAssertEqual(row.isArchived, true)
        XCTAssertEqual(row.isPinned, true)
        XCTAssertEqual(row.runtimeRevision, 3)
    }

    /// Bool 形状（旧夹具/其他端点）不得回归
    func testServerSessionDecodesBoolShape() throws {
        let json = """
        {"id": "s-bool", "archived": true, "pinned": false}
        """
        let row = try decoder.decode(ServerSession.self, from: Data(json.utf8))
        XCTAssertEqual(row.isArchived, true)
        XCTAssertEqual(row.isPinned, false)
    }

    /// 旧服务端无 runtime 字段：围栏值 nil 如实呈现
    /// （调用方据此报错，不许编造、不许裸发）
    func testServerSessionMissingRuntimeFieldsDecodeNil() throws {
        let json = #"{"id": "s-old", "archived": 0}"#
        let row = try decoder.decode(ServerSession.self, from: Data(json.utf8))
        XCTAssertNil(row.runtimeRevision)
        XCTAssertNil(row.runtimeGeneration)
    }

    // MARK: - mutation-snapshot 解码

    /// 生产快照回包形状（实测：只有身份四件）
    func testMutationSnapshotDecodesProductionShape() throws {
        let json = """
        {"session_id": "oneday-side-00000000-1111-2222-3333-444444444444",
         "exists": true, "runtime_revision": 0, "runtime_generation": 0}
        """
        let snap = try decoder.decode(
            SessionMutationSnapshot.self, from: Data(json.utf8)
        )
        XCTAssertEqual(snap.exists, true)
        XCTAssertEqual(snap.runtimeRevision, 0)
        XCTAssertEqual(snap.runtimeGeneration, 0)
    }

    func testMutationSnapshotDecodesNotExistsShape() throws {
        let json = """
        {"session_id": "gone", "exists": false,
         "runtime_revision": null, "runtime_generation": null}
        """
        let snap = try decoder.decode(
            SessionMutationSnapshot.self, from: Data(json.utf8)
        )
        XCTAssertEqual(snap.exists, false)
        XCTAssertNil(snap.runtimeRevision)
    }

    // MARK: - 服务端错误码解析

    func testServerErrorCodeParsesBareCode() {
        let body = Data(#"{"detail":"revision_conflict"}"#.utf8)
        XCTAssertEqual(HermesServerErrorCode.parse(body), "revision_conflict")
    }

    /// 带冒号长句的码取冒号前本体
    func testServerErrorCodeParsesPrefixedCode() {
        let body = Data(
            #"{"detail":"client_upgrade_required: this app is out of sync with the session runtime contract"}"#.utf8
        )
        XCTAssertEqual(
            HermesServerErrorCode.parse(body), "client_upgrade_required"
        )
    }

    func testServerErrorCodeParsesBusyAndInvalidParams() {
        XCTAssertEqual(
            HermesServerErrorCode.parse(Data(#"{"detail":"session_busy"}"#.utf8)),
            "session_busy"
        )
        XCTAssertEqual(
            HermesServerErrorCode.parse(Data(#"{"detail":"invalid_params"}"#.utf8)),
            "invalid_params"
        )
    }

    /// 非码形状（自然语言句子/非 JSON/缺 detail）回 nil
    func testServerErrorCodeRejectsNonCodeShapes() {
        XCTAssertNil(
            HermesServerErrorCode.parse(Data(#"{"detail":"Session not found"}"#.utf8))
        )
        XCTAssertNil(HermesServerErrorCode.parse(Data("not json".utf8)))
        XCTAssertNil(HermesServerErrorCode.parse(Data(#"{"ok":true}"#.utf8)))
        XCTAssertNil(HermesServerErrorCode.parse(Data()))
    }

    // MARK: - 删除收口分流矩阵

    func testDeleteDirectiveMatrix() {
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 200, serverCode: nil), .done
        )
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 204, serverCode: nil), .done
        )
        // 404＝已不在：幂等口径视为达成，不许报错吓人
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 404, serverCode: nil), .done
        )
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 409, serverCode: "revision_conflict"),
            .retryWithFreshIdentity
        )
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 409, serverCode: "session_busy"),
            .retryAfterBusy
        )
        // 身份齐发仍被拒＝客户端/版本问题：不许盲重试
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 409, serverCode: "client_upgrade_required"),
            .fail
        )
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 409, serverCode: nil), .fail
        )
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 400, serverCode: "invalid_params"),
            .fail
        )
        XCTAssertEqual(
            SessionDeleteDirective.directive(status: 500, serverCode: nil), .fail
        )
    }

    // MARK: - busy 人话

    func testSessionBusyMessageIsHumanReadable() {
        let message = HermesError.sessionBusy.userMessage(
            locale: Locale(identifier: "zh-Hans")
        )
        XCTAssertTrue(message.contains("运行中"))
        XCTAssertFalse(message.contains("409"))
    }
}
