import XCTest
@testable import OneDayCore

/// 线程真步契约钉测（274）：threadId 反算与服务端
/// activity_feed 的 classify_item＋thread_key 同规、
/// 线程详情回执按 _ledger_thread_detail 实形解码、
/// 步名解析链（语义步→自带名→形态名→规则名）与
/// 相位/步长派生全为确定性断言。服务端未上线
/// 2.25.0 契约字段时（detailSummary/stepsHuman 全
/// 缺）的回落行为同在本文件钉死
final class LedgerThreadStepsTests: XCTestCase {

    private var zh: Locale { Locale(identifier: "zh-Hans") }

    private func decode<T: Decodable>(
        _ type: T.Type, _ json: String
    ) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func makeItem(
        id: String, kind: LedgerKind,
        sessionId: String? = nil, runId: String? = nil,
        link: LedgerLink? = nil
    ) -> LedgerItem {
        LedgerItem(
            id: id, kind: kind, source: .app,
            title: "标题", titleSource: "user_excerpt",
            status: .completed, startedAt: 100, endedAt: 200,
            lastEvidenceAt: nil, origin: "reported",
            link: link, counts: [:], failReason: nil,
            evidenceLagging: false, lastSeq: 1,
            sessionId: sessionId, runId: runId,
            correctedBy: nil, history: []
        )
    }

    // MARK: - threadId 反算（服务端同规）

    func testThreadIDRunPrefersRunId() {
        let item = makeItem(
            id: "run:abc", kind: .run,
            sessionId: "sess-1", runId: "r-9"
        )
        XCTAssertEqual(
            LedgerThreading.threadID(for: item), "thread:run:r-9"
        )
    }

    func testThreadIDRunFallsToIdSuffix() {
        let item = makeItem(
            id: "run:abc", kind: .run, sessionId: "sess-1"
        )
        XCTAssertEqual(
            LedgerThreading.threadID(for: item), "thread:run:abc"
        )
    }

    func testThreadIDTurnRecordUsesRunId() {
        // 2.23.0 回合记录：id 是 turn:<sid>:run:<runId>，
        // 不带 run: 前缀，thread_key 走 runId 字段
        let item = makeItem(
            id: "turn:sess-1:run:r-2", kind: .run,
            sessionId: "sess-1", runId: "r-2"
        )
        XCTAssertEqual(
            LedgerThreading.threadID(for: item), "thread:run:r-2"
        )
    }

    func testThreadIDRunWithoutUserSessionIsNil() {
        XCTAssertNil(LedgerThreading.threadID(for: makeItem(
            id: "run:abc", kind: .run
        )))
        XCTAssertNil(LedgerThreading.threadID(for: makeItem(
            id: "run:abc", kind: .run, sessionId: "run_46c0"
        )))
    }

    func testThreadIDApprovalUsesSessionAnchor() {
        let item = makeItem(
            id: "appr:p-1", kind: .approval, sessionId: "sess-1"
        )
        XCTAssertEqual(
            LedgerThreading.threadID(for: item),
            "thread:appr:sess-1"
        )
        XCTAssertNil(LedgerThreading.threadID(for: makeItem(
            id: "appr:p-1", kind: .approval
        )))
    }

    func testThreadIDKanbanPrefersLinkTarget() {
        let linked = makeItem(
            id: "task:t-1", kind: .kanban,
            link: LedgerLink(kind: "kanban", targetId: "board-7")
        )
        XCTAssertEqual(
            LedgerThreading.threadID(for: linked),
            "thread:kanban:board-7"
        )
        let bare = makeItem(id: "task:t-2", kind: .kanban)
        XCTAssertEqual(
            LedgerThreading.threadID(for: bare),
            "thread:kanban:t-2"
        )
    }

    func testThreadIDExcludedKindsAreNil() {
        for kind: LedgerKind in [.job, .device, .monitor] {
            XCTAssertNil(
                LedgerThreading.threadID(for: makeItem(
                    id: "x:1", kind: kind, sessionId: "sess-1"
                )),
                "\(kind) 不组线程"
            )
        }
    }

    // MARK: - 回执解码（_ledger_thread_detail 实形）

    private var threadJSON: String {
        """
        {
          "threadId": "thread:run:r-1",
          "prototype": "run",
          "title": "检查服务器状态",
          "status": "completed",
          "inProgress": false,
          "startedAt": 1764000000,
          "endedAt": 1764000300,
          "itemIds": ["run:r-1"],
          "itemCount": 1,
          "steps": [
            {"tool": "terminal", "preview": "git fetch gh",
             "ok": true},
            {"tool": "web_search", "preview": "天气 API",
             "ok": false},
            {"action": "∅ → running", "at": 1764000000,
             "by": "gateway"},
            {"action": "running → completed", "at": 1764000300,
             "by": "gateway"},
            {"summary": "共 60 步，仅显示前 50 步"}
          ],
          "stepsTotal": 5,
          "items": [
            {"id": "run:r-1", "kind": "run",
             "status": "completed", "startedAt": 1764000000,
             "sessionId": "sess-1", "runId": "r-1",
             "detailSummary": "先拉了远端核对分支，随后搜索天气接口。",
             "stepsHuman": [
               {"humanTitle": "拉取远端更新",
                "humanNote": "核对分支与日志"},
               {"humanTitle": "联网搜索天气接口"}
             ]}
          ]
        }
        """
    }

    func testThreadDetailDecodesServerShape() throws {
        let detail = try decode(
            LedgerThreadDetail.self, threadJSON
        )
        XCTAssertEqual(detail.threadId, "thread:run:r-1")
        XCTAssertFalse(detail.inProgress)
        XCTAssertEqual(detail.steps.count, 5)
        XCTAssertEqual(detail.stepsTotal, 5)
        XCTAssertEqual(detail.steps[0].tool, "terminal")
        XCTAssertEqual(detail.steps[0].ok, true)
        XCTAssertEqual(detail.steps[1].ok, false)
        XCTAssertEqual(
            detail.steps[2].action, "∅ → running"
        )
        XCTAssertEqual(detail.steps[2].at, 1764000000)
        XCTAssertEqual(
            detail.steps[4].summary, "共 60 步，仅显示前 50 步"
        )
        XCTAssertEqual(detail.items.count, 1)
        XCTAssertEqual(
            detail.items[0].detailSummary,
            "先拉了远端核对分支，随后搜索天气接口。"
        )
        XCTAssertEqual(detail.items[0].stepsHuman.count, 2)
    }

    func testHumanStepsResolveFromMembers() throws {
        let detail = try decode(
            LedgerThreadDetail.self, threadJSON
        )
        let humans = LedgerThreading.humanSteps(for: detail)
        XCTAssertEqual(humans.count, 2)
        XCTAssertEqual(humans[0].humanTitle, "拉取远端更新")
        XCTAssertEqual(humans[0].humanNote, "核对分支与日志")
        XCTAssertEqual(humans[1].humanTitle, "联网搜索天气接口")
        XCTAssertNil(humans[1].humanNote)
    }

    func testDetailSummaryResolvesFromMember() throws {
        let detail = try decode(
            LedgerThreadDetail.self, threadJSON
        )
        XCTAssertEqual(
            LedgerThreading.detailSummary(
                for: detail, itemID: "run:r-1"
            ),
            "先拉了远端核对分支，随后搜索天气接口。"
        )
    }

    func testThreadLevelFieldsWinWhenPresent() throws {
        // 契约字段挂线程级时：语义步整段优先于成员拼
        // 接、总结段成员缺失时回线程级
        let json = """
        {
          "threadId": "thread:run:r-2",
          "inProgress": true,
          "steps": [{"tool": "terminal", "ok": true}],
          "stepsTotal": 1,
          "stepsHuman": [{"humanTitle": "线程级步名"}],
          "detailSummary": "线程级总结段。",
          "items": [
            {"id": "run:r-2", "kind": "run",
             "status": "running", "startedAt": 1764000000,
             "stepsHuman": [{"humanTitle": "成员步名"}]}
          ]
        }
        """
        let detail = try decode(LedgerThreadDetail.self, json)
        XCTAssertEqual(
            LedgerThreading.humanSteps(for: detail).first?
                .humanTitle,
            "线程级步名"
        )
        XCTAssertEqual(
            LedgerThreading.detailSummary(
                for: detail, itemID: "run:r-2"
            ),
            "线程级总结段。"
        )
    }

    // MARK: - 步名解析链与相位

    func testRowsPreferHumanTitlesAndNotes() throws {
        let detail = try decode(
            LedgerThreadDetail.self, threadJSON
        )
        let rows = LedgerBoard.threadStepRows(
            steps: detail.steps,
            humanSteps: LedgerThreading.humanSteps(for: detail),
            inProgress: false, threadStatus: "completed",
            endedAt: detail.endedAt, serverNow: 1764000400,
            locale: zh
        )
        XCTAssertEqual(rows.count, 5)
        // ① 语义步 humanTitle 第一优先、humanNote 作注记
        XCTAssertEqual(rows[0].title, "拉取远端更新")
        XCTAssertEqual(rows[0].note, "核对分支与日志")
        XCTAssertEqual(rows[0].preview, "git fetch gh")
        XCTAssertEqual(rows[0].phase, .done)
        // 语义步盖过规则名（web_search 本会派生联网搜索）
        XCTAssertEqual(rows[1].title, "联网搜索天气接口")
        XCTAssertEqual(rows[1].phase, .failed)
        // ③ 变迁步：落点状态人话＋相邻步间隔步长
        XCTAssertEqual(rows[2].title, "进行中")
        XCTAssertEqual(rows[2].at, 1764000000)
        XCTAssertEqual(rows[2].duration, 300)
        XCTAssertEqual(rows[2].actorWord, "网关")
        // 终态落点是时间点：不给步长
        XCTAssertEqual(rows[3].title, "已完成")
        XCTAssertNil(rows[3].duration)
        // 截断尾行原样成行
        XCTAssertEqual(rows[4].title, "共 60 步，仅显示前 50 步")
        XCTAssertEqual(rows[4].phase, .done)
    }

    func testRowsFallBackToRuleNamesWithoutHumanSteps() {
        // 2.25.0 未上线（无任何语义步）时的回落：工具
        // 名走聊天工具卡同一张词面表
        let steps = [
            LedgerThreadStep(
                tool: "terminal", preview: "ls", ok: true,
                action: nil, object: nil, result: nil,
                at: nil, by: nil, note: nil, summary: nil,
                ownTitle: nil, failReason: nil
            ),
            LedgerThreadStep(
                tool: "web_search", preview: "西安天气",
                ok: true, action: nil, object: nil,
                result: nil, at: nil, by: nil, note: nil,
                summary: nil, ownTitle: nil, failReason: nil
            ),
            LedgerThreadStep(
                tool: "read_file", preview: "/opt/data/x.md",
                ok: nil, action: nil, object: nil,
                result: nil, at: nil, by: nil, note: nil,
                summary: nil, ownTitle: nil, failReason: nil
            ),
        ]
        let rows = LedgerBoard.threadStepRows(
            steps: steps, humanSteps: [],
            inProgress: true, threadStatus: "running",
            endedAt: nil, serverNow: 1764000400, locale: zh
        )
        XCTAssertEqual(rows[0].title, "运行命令")
        XCTAssertEqual(rows[0].phase, .done)
        XCTAssertEqual(rows[1].title, "联网搜索")
        XCTAssertEqual(rows[2].title, "读取文件")
        // 进行中线程末个未回结果步＝当前步
        XCTAssertEqual(rows[2].phase, .current)
        // 运行步端点无时刻：at/duration 全 nil 不冒充
        XCTAssertNil(rows[0].at)
        XCTAssertNil(rows[0].duration)
    }

    func testRowsApprovalShapeUsesActionObjectResult() {
        let steps = [
            LedgerThreadStep(
                tool: nil, preview: nil, ok: nil,
                action: "写入", object: "长期记忆",
                result: "已批准", at: nil, by: nil,
                note: nil, summary: nil, ownTitle: nil,
                failReason: nil
            ),
        ]
        let rows = LedgerBoard.threadStepRows(
            steps: steps, humanSteps: [],
            inProgress: false, threadStatus: "completed",
            endedAt: nil, serverNow: 0, locale: zh
        )
        XCTAssertEqual(rows[0].title, "写入 长期记忆")
        XCTAssertEqual(rows[0].note, "已批准")
        XCTAssertEqual(rows[0].phase, .done)
    }

    func testRowsEmptyStepsStayEmpty() {
        XCTAssertTrue(
            LedgerBoard.threadStepRows(
                steps: [], humanSteps: [],
                inProgress: false, threadStatus: nil,
                endedAt: nil, serverNow: 0, locale: zh
            ).isEmpty
        )
    }

    // MARK: - 条目契约字段解码

    func testItemDecodesContractFields() throws {
        let json = """
        {"id": "run:r-1", "kind": "run",
         "status": "completed", "startedAt": 1764000000,
         "detailSummary": "总结段。",
         "stepsHuman": [{"humanTitle": "第一步",
                         "humanNote": "注记"}]}
        """
        let item = try decode(LedgerItem.self, json)
        XCTAssertEqual(item.detailSummary, "总结段。")
        XCTAssertEqual(item.stepsHuman.count, 1)
        XCTAssertEqual(item.stepsHuman[0].humanTitle, "第一步")
        XCTAssertEqual(item.stepsHuman[0].humanNote, "注记")
    }

    func testItemWithoutContractFieldsDefaults() throws {
        // 旧服务端条目：两字段全缺不许炸解码
        let json = """
        {"id": "run:r-1", "kind": "run",
         "status": "completed", "startedAt": 1764000000}
        """
        let item = try decode(LedgerItem.self, json)
        XCTAssertNil(item.detailSummary)
        XCTAssertTrue(item.stepsHuman.isEmpty)
    }
}
