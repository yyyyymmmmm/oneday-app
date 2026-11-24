import OneDayCore
import XCTest

/// D3/D2 rewind 契约钉测（DESIGN §352）：请求体编码
/// 形态、快照/回执解码、失败分类矩阵——全部对批 0
/// 真调用实测字面（部署包 1.1.0），不许凭图臆测
final class RewindContractTests: XCTestCase {

    // MARK: - 请求体编码（整数字面钉死）

    func testRewindRequestEncodesTargetAsIntegerLiteral() throws {
        let request = RewindRequest(
            requestID: "req-1", expectedRevision: 45,
            expectedGeneration: 7, targetMessageID: 123
        )
        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)
        // target 必须整数直发：无引号、无 .0 小数尾
        XCTAssertTrue(
            json.contains("\"target_message_id\":123"),
            json
        )
        XCTAssertFalse(json.contains("\"target_message_id\":\""))
        XCTAssertFalse(json.contains("123.0"))
        XCTAssertTrue(
            json.contains("\"expected_revision\":45"), json
        )
        XCTAssertTrue(
            json.contains("\"expected_generation\":7"), json
        )
        XCTAssertTrue(json.contains("\"request_id\":\"req-1\""))
    }

    func testRewindRequestIDsArePerAttemptUnique() {
        // request_id 每试新铸的构造口径：同参数两份请
        // 求只差 requestID 也必须不相等（防误把 run 幂
        // 等键或内容派生值当 request_id 复用）
        let a = RewindRequest(
            requestID: UUID().uuidString, expectedRevision: 1,
            expectedGeneration: 1, targetMessageID: 9
        )
        let b = RewindRequest(
            requestID: UUID().uuidString, expectedRevision: 1,
            expectedGeneration: 1, targetMessageID: 9
        )
        XCTAssertNotEqual(a.requestID, b.requestID)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - 快照/回执解码

    func testMutationSnapshotDecodesRevisionAndGeneration()
        throws {
        // 防 0.50.30 覆辙：围栏双字段必须真解出值、
        // 不许被默认值吞成 nil
        let json = """
        {"session_id":"s1","exists":true,\
        "runtime_revision":45,"runtime_generation":7}
        """
        let snapshot = try JSONDecoder().decode(
            SessionMutationSnapshot.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(snapshot.runtimeRevision, 45)
        XCTAssertEqual(snapshot.runtimeGeneration, 7)
        XCTAssertEqual(snapshot.exists, true)
    }

    func testRewindReceiptDecodesMeasuredShape() throws {
        // 批 0 实测回执形态（rewound_count=5 例）
        let json = """
        {"ok":true,"session_id":"s1","revision":46,\
        "execution_generation":8,"operation":"rewind",\
        "rewound_count":5,"new_head_id":5314,\
        "replacement_message_id":null,\
        "target_message":{"id":5315,"role":"user"}}
        """
        let receipt = try JSONDecoder().decode(
            RewindReceipt.self, from: Data(json.utf8)
        )
        XCTAssertEqual(receipt.ok, true)
        XCTAssertEqual(receipt.sessionID, "s1")
        XCTAssertEqual(receipt.revision, 46)
        XCTAssertEqual(receipt.executionGeneration, 8)
        XCTAssertEqual(receipt.operation, "rewind")
        XCTAssertEqual(receipt.rewoundCount, 5)
        XCTAssertEqual(receipt.newHeadRowID, 5314)
        XCTAssertNil(receipt.replacementMessageRowID)
    }

    // MARK: - 分类矩阵（逐格钉）

    func testDirectiveMatrix() {
        XCTAssertEqual(
            RewindDirective.directive(status: 200, serverCode: nil),
            .done
        )
        XCTAssertEqual(
            RewindDirective.directive(status: 204, serverCode: nil),
            .done
        )
        // 围栏过期（批 0 实测字面）→ 先对账再重试
        XCTAssertEqual(
            RewindDirective.directive(
                status: 409, serverCode: "stale_generation"
            ),
            .reconcileConflict
        )
        XCTAssertEqual(
            RewindDirective.directive(
                status: 409, serverCode: "revision_conflict"
            ),
            .reconcileConflict
        )
        XCTAssertEqual(
            RewindDirective.directive(
                status: 409, serverCode: "session_busy"
            ),
            .retryAfterBusy
        )
        // target 非 user 行（批 0 实测字面）→ 不重试
        XCTAssertEqual(
            RewindDirective.directive(
                status: 400, serverCode: "invalid_params"
            ),
            .failInvalidTarget
        )
        // 端点层拒（缺 generation 的字面）→ fail：客
        // 户端恒带该字段、出现即构造错误，不重试
        XCTAssertEqual(
            RewindDirective.directive(
                status: 400, serverCode: "Invalid rewind payload"
            ),
            .fail
        )
        XCTAssertEqual(
            RewindDirective.directive(
                status: 409, serverCode: "client_upgrade_required"
            ),
            .fail
        )
        XCTAssertEqual(
            RewindDirective.directive(status: 401, serverCode: nil),
            .fail
        )
        XCTAssertEqual(
            RewindDirective.directive(status: 500, serverCode: nil),
            .fail
        )
        // rewind 无 DELETE 式 404=done 语义：会话不在
        // 是失败、不许假装截断成功
        XCTAssertEqual(
            RewindDirective.directive(status: 404, serverCode: nil),
            .fail
        )
    }

    // MARK: - 错误码解析（detail 本体提取）

    func testServerErrorCodeParseFeedsDirective() {
        let body = Data("{\"detail\":\"invalid_params\"}".utf8)
        XCTAssertEqual(
            HermesServerErrorCode.parse(body), "invalid_params"
        )
        XCTAssertEqual(
            RewindDirective.directive(
                status: 400,
                serverCode: HermesServerErrorCode.parse(body)
            ),
            .failInvalidTarget
        )
    }
}
