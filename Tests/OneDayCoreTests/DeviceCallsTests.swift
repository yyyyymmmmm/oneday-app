import XCTest
@testable import OneDayCore

/// 设备调用纯逻辑闸（0.34.0 批一）：①ISO 时刻解析/
/// 格式化 ②日历窗口 14 天收敛 ③逐工具参数解析（必
/// 填/幂等键/limit 收敛）④会话状态机全生命周期（含
/// 409 重注册）⑤写键账本 24 小时窗口 ⑥错误码映射
/// ⑦调用元数据文案。
final class DeviceCallsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_763_000_000)

    // MARK: - ISO 8601

    func testISOParseAndFormat() {
        let parsed = DeviceISO8601.parse("2026-11-10T08:30:00+08:00")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(
            DeviceISO8601.parse("2026-11-10T00:30:00.500Z"),
            Date(timeIntervalSince1970: 1_794_270_600.5)
        )
        XCTAssertNil(DeviceISO8601.parse("下周三"))
        XCTAssertNil(DeviceISO8601.parse(""))
        if let date = parsed {
            XCTAssertEqual(
                DeviceISO8601.parse(DeviceISO8601.format(date)), date,
                "格式化→再解析须无损往返"
            )
        }
    }

    // MARK: - 日历窗口

    func testCalendarWindowNormal() throws {
        let window = try CalendarListWindow.parse([
            "start": .string("2026-11-10T00:00:00Z"),
            "end": .string("2026-11-12T00:00:00Z"),
        ])
        XCTAssertFalse(window.wasClamped)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 2 * 86400)
    }

    func testCalendarWindowClampedTo14Days() throws {
        let window = try CalendarListWindow.parse([
            "start": .string("2026-11-10T00:00:00Z"),
            "end": .string("2026-12-31T00:00:00Z"),
        ])
        XCTAssertTrue(window.wasClamped)
        XCTAssertEqual(
            window.end.timeIntervalSince(window.start),
            CalendarListWindow.maxWindowSeconds,
            "超 14 天的窗口在 App 侧收敛，不拖全量历史"
        )
    }

    func testCalendarWindowRejectsBadInput() {
        XCTAssertThrowsError(try CalendarListWindow.parse([
            "start": .string("2026-11-10T00:00:00Z"),
            "end": .string("2026-11-09T00:00:00Z"),
        ])) { error in
            XCTAssertEqual((error as? DeviceToolError)?.code, "invalid_arguments")
        }
        XCTAssertThrowsError(try CalendarListWindow.parse([:])) { error in
            XCTAssertEqual((error as? DeviceToolError)?.code, "invalid_arguments")
        }
    }

    // MARK: - 参数解析

    func testCalendarCreateArgs() throws {
        let args = try CalendarCreateArgs.parse([
            "title": .string("婚礼"),
            "start": .string("2026-11-16T13:00:00+08:00"),
            "end": .string("2026-11-16T15:00:00+08:00"),
            "allDay": .bool(false),
            "location": .string("西故现村"),
            "idempotencyKey": .string("key-1"),
        ])
        XCTAssertEqual(args.title, "婚礼")
        XCTAssertEqual(args.idempotencyKey, "key-1")
        XCTAssertEqual(args.location, "西故现村")
        XCTAssertNil(args.calendarName)
    }

    func testWriteArgsRequireIdempotencyKey() {
        XCTAssertThrowsError(try CalendarCreateArgs.parse([
            "title": .string("x"),
            "start": .string("2026-11-16T13:00:00Z"),
            "end": .string("2026-11-16T15:00:00Z"),
        ])) { error in
            XCTAssertEqual((error as? DeviceToolError)?.code, "invalid_arguments")
            XCTAssertTrue(
                (error as? DeviceToolError)?.message.contains("幂等键") ?? false
            )
        }
        XCTAssertThrowsError(try ReminderCompleteArgs.parse([
            "reminderId": .string("r1"),
        ]))
    }

    func testCalendarUpdateArgsPartial() throws {
        let args = try CalendarUpdateArgs.parse([
            "eventId": .string("e1"),
            "title": .string("改名"),
            "idempotencyKey": .string("key-2"),
        ])
        XCTAssertEqual(args.title, "改名")
        XCTAssertNil(args.start)
        XCTAssertNil(args.location)
    }

    func testReminderCreateArgsOptionalDue() throws {
        let args = try ReminderCreateArgs.parse([
            "title": .string("买喜糖"),
            "idempotencyKey": .string("key-3"),
        ])
        XCTAssertNil(args.due)
        let withDue = try ReminderCreateArgs.parse([
            "title": .string("买喜糖"),
            "due": .string("2026-11-12T09:00:00+08:00"),
            "listName": .string("生活"),
            "idempotencyKey": .string("key-4"),
        ])
        XCTAssertNotNil(withDue.due)
        XCTAssertEqual(withDue.listName, "生活")
    }

    func testContactsSearchLimitClamp() throws {
        XCTAssertEqual(
            try ContactsSearchArgs.parse(["query": .string("秦")]).limit, 20
        )
        XCTAssertEqual(
            try ContactsSearchArgs.parse([
                "query": .string("秦"), "limit": .number(0),
            ]).limit, 1
        )
        XCTAssertEqual(
            try ContactsSearchArgs.parse([
                "query": .string("秦"), "limit": .number(999),
            ]).limit, 50
        )
        XCTAssertThrowsError(try ContactsSearchArgs.parse([:]))
    }

    // MARK: - 会话状态机

    func testSessionLifecycle() {
        var machine = DeviceSessionMachine()
        XCTAssertEqual(machine.phase, .offline)
        XCTAssertEqual(machine.handle(.startRequested), .register)
        XCTAssertEqual(machine.phase, .registering)
        XCTAssertEqual(machine.handle(.registered(sessionID: "s1")), .poll)
        XCTAssertEqual(machine.phase, .active(sessionID: "s1"))
        XCTAssertEqual(machine.handle(.pollReturnedEmpty), .poll)
        XCTAssertEqual(machine.handle(.pollReturnedCall(callID: "c1")), .none)
        XCTAssertEqual(
            machine.phase, .executing(sessionID: "s1", callID: "c1")
        )
        XCTAssertEqual(machine.handle(.respondFinished), .poll)
        XCTAssertEqual(machine.phase, .active(sessionID: "s1"))
        XCTAssertEqual(machine.handle(.disconnectRequested), .disconnect)
        XCTAssertEqual(machine.phase, .offline)
        XCTAssertFalse(machine.isOnline)
    }

    func testSessionUnknownTriggersReregister() {
        var machine = DeviceSessionMachine()
        machine.handle(.startRequested)
        machine.handle(.registered(sessionID: "s1"))
        XCTAssertEqual(machine.handle(.pollUnknownSession), .register)
        XCTAssertEqual(machine.phase, .registering)
        XCTAssertNil(machine.sessionID)
        machine.handle(.registered(sessionID: "s2"))
        machine.handle(.pollReturnedCall(callID: "c9"))
        XCTAssertEqual(machine.handle(.pollUnknownSession), .register)
        XCTAssertEqual(machine.handle(.registrationFailed), .none)
        XCTAssertEqual(machine.phase, .offline)
    }

    func testSessionNoiseEventsIgnored() {
        var machine = DeviceSessionMachine()
        XCTAssertEqual(machine.handle(.pollReturnedEmpty), .none)
        XCTAssertEqual(machine.handle(.disconnectRequested), .none)
        machine.handle(.startRequested)
        XCTAssertEqual(
            machine.handle(.startRequested), .none,
            "注册中重复 start 是时序噪声，不重复发注册"
        )
        XCTAssertEqual(machine.phase, .registering)
    }

    // MARK: - 写键账本

    func testWriteKeyLedgerWindow() {
        var records: [WriteKeyRecord] = []
        records = WriteKeyLedger.recording(
            records, key: "k1", tool: "reminders_create",
            objectID: "r1", now: t0
        )
        XCTAssertEqual(
            WriteKeyLedger.lookup(records, key: "k1", now: t0.addingTimeInterval(3600))?.objectID,
            "r1"
        )
        XCTAssertNil(
            WriteKeyLedger.lookup(
                records, key: "k1",
                now: t0.addingTimeInterval(WriteKeyLedger.windowSeconds + 1)
            ),
            "24 小时窗口外视为未执行"
        )
        XCTAssertNil(WriteKeyLedger.lookup(records, key: "other", now: t0))
    }

    func testWriteKeyLedgerRecordingPrunesAndReplaces() {
        var records = WriteKeyLedger.recording(
            [], key: "old", tool: "reminders_create",
            objectID: "x", now: t0
        )
        records = WriteKeyLedger.recording(
            records, key: "new", tool: "reminders_create",
            objectID: "y", now: t0.addingTimeInterval(25 * 3600)
        )
        XCTAssertEqual(records.map(\.key), ["new"], "过期记录记账时清掉")
        records = WriteKeyLedger.recording(
            records, key: "new", tool: "reminders_create",
            objectID: "y2", now: t0.addingTimeInterval(26 * 3600)
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.objectID, "y2", "同 key 覆盖旧记录")
    }

    // MARK: - 错误码与元数据文案

    func testErrorCodes() {
        XCTAssertEqual(DeviceToolError.permissionDenied("x").code, "permission_denied")
        XCTAssertEqual(DeviceToolError.toolUnavailable("x").code, "tool_unavailable")
        XCTAssertEqual(DeviceToolError.invalidArguments("x").code, "invalid_arguments")
        XCTAssertEqual(DeviceToolError.updateNotAllowed("x").code, "update_not_allowed")
        XCTAssertEqual(DeviceToolError.failed("x").code, "device_error")
    }

    func testCallLogSummary() {
        let ok = DeviceCallLogEntry(
            tool: "reminders_list", source: .reminders, at: 0,
            succeeded: true, errorCode: nil
        )
        XCTAssertEqual(ok.summaryLine, "最近调用：成功")
        let bad = DeviceCallLogEntry(
            tool: "calendar_list_events", source: .calendar, at: 0,
            succeeded: false, errorCode: "permission_denied"
        )
        XCTAssertEqual(bad.summaryLine, "最近调用：失败（permission_denied）")
    }

    // MARK: - 剪贴板与文件参数（设备扩容批一）

    func testClipboardSetArgs() throws {
        let args = try ClipboardSetArgs.parse([
            "text": .string("开场词"),
            "idempotencyKey": .string("cb-1"),
        ])
        XCTAssertEqual(args.text, "开场词")
        XCTAssertEqual(args.idempotencyKey, "cb-1")
        // 空串合法（把剪贴板设为空）——与「没给参
        // 数」是两回事，不许混
        let cleared = try ClipboardSetArgs.parse([
            "text": .string(""),
            "idempotencyKey": .string("cb-2"),
        ])
        XCTAssertEqual(cleared.text, "")
        XCTAssertThrowsError(try ClipboardSetArgs.parse([
            "idempotencyKey": .string("cb-3"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        XCTAssertThrowsError(try ClipboardSetArgs.parse([
            "text": .string("x"),
        ])) { error in
            XCTAssertTrue(
                (error as? DeviceToolError)?.message
                    .contains("幂等键") ?? false,
                "写工具缺幂等键必须报错（双层去重纪律）"
            )
        }
    }

    /// 路径规范化防越界组：合法形态收敛、越界形态
    /// 一律拒——这是文件工具的安全边界，逐条钉死
    func testSandboxPathNormalize() throws {
        XCTAssertEqual(try SandboxPath.normalize(""), "")
        XCTAssertEqual(try SandboxPath.normalize("a/b.txt"), "a/b.txt")
        XCTAssertEqual(try SandboxPath.normalize("a//b/./c"), "a/b/c")
        XCTAssertEqual(try SandboxPath.normalize("a/../b"), "b")
        XCTAssertEqual(try SandboxPath.normalize("."), "")
        XCTAssertEqual(try SandboxPath.normalize("a/"), "a")
        for bad in ["/etc/passwd", "..", "../x", "a/../../x", "/"] {
            XCTAssertThrowsError(
                try SandboxPath.normalize(bad), bad
            ) { error in
                XCTAssertEqual(
                    (error as? DeviceToolError)?.code,
                    "invalid_arguments"
                )
            }
        }
        XCTAssertThrowsError(try SandboxPath.normalize("a\0b"))
        // 文件路径不许是根目录本身
        XCTAssertThrowsError(try SandboxPath.normalizeFilePath(""))
        XCTAssertThrowsError(try SandboxPath.normalizeFilePath("."))
        XCTAssertEqual(
            try SandboxPath.normalizeFilePath("a.txt"), "a.txt"
        )
    }

    func testFilesListArgs() throws {
        XCTAssertEqual(try FilesListArgs.parse([:]).path, "")
        XCTAssertEqual(
            try FilesListArgs.parse([
                "path": .string("notes/2026"),
            ]).path,
            "notes/2026"
        )
        XCTAssertThrowsError(try FilesListArgs.parse([
            "path": .string("../outside"),
        ]))
    }

    func testFilesReadArgs() throws {
        XCTAssertEqual(
            try FilesReadArgs.parse([
                "path": .string("a.txt"),
            ]).path,
            "a.txt"
        )
        XCTAssertThrowsError(try FilesReadArgs.parse([:]))
        XCTAssertThrowsError(try FilesReadArgs.parse([
            "path": .string("/abs.txt"),
        ]))
    }

    func testFilesWriteArgs() throws {
        let args = try FilesWriteArgs.parse([
            "path": .string("notes/a.txt"),
            "content": .string("正文"),
            "idempotencyKey": .string("fw-1"),
        ])
        XCTAssertEqual(args.path, "notes/a.txt")
        XCTAssertEqual(args.content, "正文")
        // 路径在解析层先规范化：不越界的 .. 回退收敛
        let folded = try FilesWriteArgs.parse([
            "path": .string("notes/../a.txt"),
            "content": .string(""),
            "idempotencyKey": .string("fw-2"),
        ])
        XCTAssertEqual(folded.path, "a.txt")
        XCTAssertThrowsError(try FilesWriteArgs.parse([
            "path": .string("a.txt"), "content": .string("x"),
        ]), "缺幂等键必报错")
        XCTAssertThrowsError(try FilesWriteArgs.parse([
            "path": .string("a.txt"),
            "idempotencyKey": .string("fw-3"),
        ]), "缺内容必报错")
        let oversized = String(
            repeating: "x",
            count: SandboxPath.maxContentBytes + 1
        )
        XCTAssertThrowsError(try FilesWriteArgs.parse([
            "path": .string("a.txt"),
            "content": .string(oversized),
            "idempotencyKey": .string("fw-4"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }
}
