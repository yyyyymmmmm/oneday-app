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

    // MARK: - 批二·授权状态机（系统授权铁律）

    /// 授权门全档钉：可用三档直达、只有未决定才发那
    /// 一次请求、已拒绝/受限/只写一律降级——引擎的
    /// 请求函数只认这张表，不许各自发挥
    func testPermissionGateDecisions() {
        XCTAssertEqual(
            DevicePermissionGate.decision(for: .granted), .proceed
        )
        XCTAssertEqual(
            DevicePermissionGate.decision(for: .limited), .proceed
        )
        XCTAssertEqual(
            DevicePermissionGate.decision(for: .notApplicable),
            .proceed
        )
        XCTAssertEqual(
            DevicePermissionGate.decision(for: .notDetermined),
            .requestOnce
        )
        XCTAssertEqual(
            DevicePermissionGate.decision(for: .denied), .degrade
        )
        XCTAssertEqual(
            DevicePermissionGate.decision(for: .restricted),
            .degrade
        )
        XCTAssertEqual(
            DevicePermissionGate.decision(for: .writeOnly),
            .degrade
        )
    }

    // MARK: - 批二·闹钟参数

    func testAlarmSetArgsForms() throws {
        let fixed = try AlarmSetArgs.parse([
            "title": .string("起床"),
            "at": .string("2026-11-16T07:30:00+08:00"),
            "idempotencyKey": .string("al-1"),
        ])
        XCTAssertNotNil(fixed.at)
        XCTAssertNil(fixed.afterSeconds)
        XCTAssertTrue(fixed.humanSummary.contains("起床"))
        let countdown = try AlarmSetArgs.parse([
            "title": .string("泡面"),
            "afterSeconds": .number(600),
            "idempotencyKey": .string("al-2"),
        ])
        XCTAssertNil(countdown.at)
        XCTAssertEqual(countdown.afterSeconds, 600)
        XCTAssertTrue(
            countdown.humanSummary.contains("10 分钟后")
        )
    }

    /// 时刻与倒计时同给/同缺必拒（口径歧义不许下
    /// 发）；倒计时越界、缺标题、缺幂等键同拒
    func testAlarmSetArgsRejectsConflicts() {
        XCTAssertThrowsError(try AlarmSetArgs.parse([
            "title": .string("x"),
            "at": .string("2026-11-16T07:30:00+08:00"),
            "afterSeconds": .number(600),
            "idempotencyKey": .string("al-3"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        XCTAssertThrowsError(try AlarmSetArgs.parse([
            "title": .string("x"),
            "idempotencyKey": .string("al-4"),
        ]), "两者同缺必拒")
        XCTAssertThrowsError(try AlarmSetArgs.parse([
            "title": .string("x"),
            "afterSeconds": .number(4),
            "idempotencyKey": .string("al-5"),
        ]), "倒计时低于下限必拒")
        XCTAssertThrowsError(try AlarmSetArgs.parse([
            "title": .string("x"),
            "afterSeconds": .number(90_000),
            "idempotencyKey": .string("al-6"),
        ]), "倒计时高于上限必拒")
        XCTAssertThrowsError(try AlarmSetArgs.parse([
            "at": .string("2026-11-16T07:30:00+08:00"),
            "idempotencyKey": .string("al-7"),
        ]), "缺标题必拒")
        XCTAssertThrowsError(try AlarmSetArgs.parse([
            "title": .string("x"),
            "at": .string("2026-11-16T07:30:00+08:00"),
        ]), "缺幂等键必拒")
    }

    func testAlarmCancelArgsValidation() throws {
        let id = UUID().uuidString
        let args = try AlarmCancelArgs.parse([
            "alarmId": .string(id),
            "idempotencyKey": .string("ac-1"),
        ])
        XCTAssertEqual(args.alarmID, id)
        XCTAssertTrue(
            args.humanSummary(title: "起床").contains("起床")
        )
        XCTAssertTrue(
            args.humanSummary(title: nil).contains("取消闹钟")
        )
        XCTAssertThrowsError(try AlarmCancelArgs.parse([
            "alarmId": .string("not-a-uuid"),
            "idempotencyKey": .string("ac-2"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    // MARK: - 批二·通知参数

    func testNotifyPostArgsValidation() throws {
        let now = try NotifyPostArgs.parse([
            "title": .string("提醒"),
            "body": .string("该喝水了"),
            "idempotencyKey": .string("np-1"),
        ])
        XCTAssertEqual(now.delaySeconds, 0)
        XCTAssertTrue(now.humanSummary.contains("立即送达"))
        let later = try NotifyPostArgs.parse([
            "title": .string("提醒"),
            "body": .string("该出门了"),
            "delaySeconds": .number(1800),
            "idempotencyKey": .string("np-2"),
        ])
        XCTAssertEqual(later.delaySeconds, 1800)
        XCTAssertTrue(later.humanSummary.contains("30 分钟后"))
        XCTAssertThrowsError(try NotifyPostArgs.parse([
            "title": .string("x"), "body": .string("y"),
            "delaySeconds": .number(-5),
            "idempotencyKey": .string("np-3"),
        ]), "负延迟必拒")
        XCTAssertThrowsError(try NotifyPostArgs.parse([
            "title": .string("x"), "body": .string("y"),
            "delaySeconds": .number(700_000),
            "idempotencyKey": .string("np-4"),
        ]), "延迟超 7 天必拒")
        XCTAssertThrowsError(try NotifyPostArgs.parse([
            "title": .string("x"),
            "idempotencyKey": .string("np-5"),
        ]), "缺正文必拒")
    }

    // MARK: - 批二·拉起白名单

    func testOpenTargetArgsValidation() throws {
        let args = try OpenTargetArgs.parse([
            "target": .string("settings.wifi"),
            "idempotencyKey": .string("ot-1"),
        ])
        XCTAssertEqual(args.target.id, "settings.wifi")
        XCTAssertTrue(args.humanSummary.contains("Wi-Fi"))
        XCTAssertThrowsError(try OpenTargetArgs.parse([
            "target": .string("https://example.com"),
            "idempotencyKey": .string("ot-2"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "任意 URL 在解析层就拒、不下发执行层"
            )
        }
        XCTAssertNil(OpenTargetCatalog.target("settings.nope"))
    }

    /// 白名单目录不变量：id 唯一；地址只许四类已审
    /// 计形态（系统设置根页/自家设置页哨兵/登记应
    /// 用的公开 scheme），http(s) 任意地址永不入册；
    /// 每条目标三语名可取
    func testOpenTargetCatalogSafety() {
        let ids = OpenTargetCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let allowedPrefixes = [
            "App-prefs:", "weixin://", "alipay://",
            "iosamap://", "maps://",
        ]
        for target in OpenTargetCatalog.all {
            if target.urlString != OpenTarget.appSettingsSentinel {
                XCTAssertTrue(
                    allowedPrefixes.contains {
                        target.urlString.hasPrefix($0)
                    },
                    target.id
                )
            }
            XCTAssertFalse(
                target.urlString.hasPrefix("http"), target.id
            )
            XCTAssertFalse(
                target.name(
                    locale: Locale(identifier: "zh-Hans")
                ).isEmpty,
                target.id
            )
        }
    }

    // MARK: - 批二·时长人话

    func testDeviceDurationText() {
        XCTAssertEqual(deviceDurationText(45), "45 秒后")
        XCTAssertEqual(deviceDurationText(600), "10 分钟后")
        XCTAssertEqual(deviceDurationText(90), "1 分 30 秒后")
        XCTAssertEqual(deviceDurationText(5400), "1 小时 30 分后")
        XCTAssertEqual(deviceDurationText(7200), "2 小时后")
    }

    // MARK: - 批三·在场交互参数

    /// 拍照/扫描是落文件的写动作：幂等键必填，缺键
    /// 在解析层就拒（不许把取景框弹出去才发现没法
    /// 防重）
    func testCameraAndScanArgsRequireKey() throws {
        let capture = try CameraCaptureArgs.parse([
            "idempotencyKey": .string("cap-1"),
        ])
        XCTAssertEqual(capture.idempotencyKey, "cap-1")
        XCTAssertTrue(capture.humanSummary.contains("拍照"))
        XCTAssertThrowsError(try CameraCaptureArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        let scan = try VisionDocumentScanArgs.parse([
            "idempotencyKey": .string("scan-1"),
        ])
        XCTAssertEqual(scan.idempotencyKey, "scan-1")
        XCTAssertThrowsError(
            try VisionDocumentScanArgs.parse([:])
        ) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    /// 识别两件的路径与 files_read 同一套规范化：
    /// 相对路径收敛、越界在解析层拒
    func testVisionArgsPaths() throws {
        let ocr = try VisionOCRArgs.parse([
            "path": .string("captures/photo-1.jpg"),
        ])
        XCTAssertEqual(ocr.path, "captures/photo-1.jpg")
        let code = try VisionScanCodeArgs.parse([
            "path": .string("./captures/../captures/a.png"),
        ])
        XCTAssertEqual(code.path, "captures/a.png")
        XCTAssertThrowsError(try VisionOCRArgs.parse([
            "path": .string("../secret.jpg"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "越出 OneDay 文件夹的路径在解析层就拒"
            )
        }
        XCTAssertThrowsError(try VisionScanCodeArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    /// 翻译参数：原文/源语言必填、目标可缺省；超长
    /// 与非法语言代码在解析层拒
    func testTranslateArgsValidation() throws {
        let args = try TranslateTextArgs.parse([
            "text": .string("Hello"),
            "source": .string("en"),
        ])
        XCTAssertNil(args.target)
        let targeted = try TranslateTextArgs.parse([
            "text": .string("你好"),
            "source": .string("zh-Hans"),
            "target": .string("ja"),
        ])
        XCTAssertEqual(targeted.target, "ja")
        XCTAssertThrowsError(try TranslateTextArgs.parse([
            "text": .string("Hello"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "无头会话必须先有源语言，不设缺省兜底"
            )
        }
        XCTAssertThrowsError(try TranslateTextArgs.parse([
            "text": .string("Hello"),
            "source": .string("en/us"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        XCTAssertThrowsError(try TranslateTextArgs.parse([
            "text": .string(
                String(repeating: "a", count: 4001)
            ),
            "source": .string("en"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    /// 端上模型参数：问题必填且有字数收敛；指令可
    /// 缺省、超长拒
    func testOnDeviceModelArgsValidation() throws {
        let args = try OnDeviceModelArgs.parse([
            "prompt": .string("把这段话缩成一句"),
        ])
        XCTAssertNil(args.instructions)
        let withInstructions = try OnDeviceModelArgs.parse([
            "prompt": .string("总结一下"),
            "instructions": .string("只用中文回答"),
        ])
        XCTAssertEqual(withInstructions.instructions, "只用中文回答")
        XCTAssertThrowsError(try OnDeviceModelArgs.parse([
            "prompt": .string(
                String(repeating: "问", count: 3001)
            ),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        XCTAssertThrowsError(try OnDeviceModelArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    /// 本人确认参数：理由必填（要原样显示在系统验
    /// 证框里、不许空着验）、有字数收敛；且它按定
    /// 义不带幂等键（每次必真问一次）
    func testBiometricArgsValidation() throws {
        let args = try BiometricAuthArgs.parse([
            "reason": .string("批准这笔付款前确认是本人"),
        ])
        XCTAssertEqual(args.reason, "批准这笔付款前确认是本人")
        XCTAssertTrue(args.humanSummary.contains("本人确认"))
        XCTAssertThrowsError(try BiometricAuthArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        XCTAssertThrowsError(try BiometricAuthArgs.parse([
            "reason": .string(
                String(repeating: "验", count: 121)
            ),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    // MARK: - 批四·日常面参数

    /// 定位参数：地点检索条数收敛；地址坐标换算恰
    /// 给其一（同给/同缺/坐标半对/越界都在解析层拒）
    func testLocationArgsValidation() throws {
        let search = try LocationSearchPlacesArgs.parse([
            "query": .string("药店"),
            "limit": .number(99),
        ])
        XCTAssertEqual(search.limit, 20, "条数收敛到上限 20")
        let defaults = try LocationSearchPlacesArgs.parse([
            "query": .string("药店"),
        ])
        XCTAssertEqual(defaults.limit, 10)
        XCTAssertThrowsError(try LocationSearchPlacesArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        let forward = try LocationGeocodeArgs.parse([
            "address": .string("西安市高陵区"),
        ])
        XCTAssertEqual(forward.address, "西安市高陵区")
        XCTAssertNil(forward.latitude)
        let reverse = try LocationGeocodeArgs.parse([
            "latitude": .number(34.5),
            "longitude": .number(109.0),
        ])
        XCTAssertEqual(reverse.latitude, 34.5)
        XCTAssertThrowsError(try LocationGeocodeArgs.parse([
            "address": .string("西安"),
            "latitude": .number(34.5),
            "longitude": .number(109.0),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "地址与坐标同给必有歧义，解析层拒"
            )
        }
        XCTAssertThrowsError(try LocationGeocodeArgs.parse([
            "latitude": .number(34.5),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "坐标必须成对给"
            )
        }
        XCTAssertThrowsError(try LocationGeocodeArgs.parse([
            "latitude": .number(91),
            "longitude": .number(109.0),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        XCTAssertThrowsError(try LocationGeocodeArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    /// 媒体参数：类别是封闭枚举、条数收敛；建歌单
    /// 必带键；播放动作是封闭枚举且必带键（切歌重
    /// 发会按两次，防重不是可选的）
    func testMediaArgsValidation() throws {
        let search = try MediaLibrarySearchArgs.parse([
            "query": .string("周杰伦"),
        ])
        XCTAssertEqual(search.kind, .any)
        XCTAssertEqual(search.limit, 20)
        let songs = try MediaLibrarySearchArgs.parse([
            "query": .string("晴天"),
            "kind": .string("song"),
            "limit": .number(500),
        ])
        XCTAssertEqual(songs.kind, .song)
        XCTAssertEqual(songs.limit, 50, "条数收敛到上限 50")
        XCTAssertThrowsError(try MediaLibrarySearchArgs.parse([
            "query": .string("晴天"),
            "kind": .string("video"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "类别表外值在解析层拒"
            )
        }
        let create = try MediaPlaylistCreateArgs.parse([
            "name": .string("跑步歌单"),
            "idempotencyKey": .string("pl-1"),
        ])
        XCTAssertEqual(create.name, "跑步歌单")
        XCTAssertThrowsError(try MediaPlaylistCreateArgs.parse([
            "name": .string("跑步歌单"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "建歌单是写工具，缺幂等键在解析层拒"
            )
        }
        let control = try MediaPlaybackControlArgs.parse([
            "action": .string("next"),
            "idempotencyKey": .string("pb-1"),
        ])
        XCTAssertEqual(control.action, .next)
        XCTAssertNil(control.query)
        let play = try MediaPlaybackControlArgs.parse([
            "action": .string("play"),
            "query": .string("晴天"),
            "idempotencyKey": .string("pb-2"),
        ])
        XCTAssertEqual(play.query, "晴天")
        XCTAssertThrowsError(try MediaPlaybackControlArgs.parse([
            "action": .string("shuffle"),
            "idempotencyKey": .string("pb-3"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "播放动作表外值在解析层拒"
            )
        }
        XCTAssertThrowsError(try MediaPlaybackControlArgs.parse([
            "action": .string("pause"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }

    /// 撰写参数：号码形态校验（字母拒）；收件人必
    /// 须是字符串数组且至少一个；邮箱粗验含 @；分
    /// 享文字与文件至少给一样、文件路径走沙盒规范
    /// 化（越界在解析层拒）
    func testComposeArgsValidation() throws {
        let call = try CallStartArgs.parse([
            "number": .string("+86 137-7289-5146"),
        ])
        XCTAssertEqual(call.number, "+86 137-7289-5146")
        XCTAssertThrowsError(try CallStartArgs.parse([
            "number": .string("call-me-now"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "号码里混字母在解析层拒"
            )
        }
        let sms = try ComposeSMSArgs.parse([
            "recipients": .array([.string("13772895146")]),
            "body": .string("开会改到下午三点"),
        ])
        XCTAssertEqual(sms.recipients, ["13772895146"])
        XCTAssertThrowsError(try ComposeSMSArgs.parse([
            "recipients": .array([]),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        XCTAssertThrowsError(try ComposeSMSArgs.parse([
            "recipients": .string("13772895146"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "收件人必须是数组，单个字符串不收"
            )
        }
        let mail = try ComposeEmailArgs.parse([
            "to": .array([.string("a@example.com")]),
            "subject": .string("你好"),
        ])
        XCTAssertEqual(mail.recipients, ["a@example.com"])
        XCTAssertThrowsError(try ComposeEmailArgs.parse([
            "to": .array([.string("not-an-email")]),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        let shareText = try ShareSheetArgs.parse([
            "text": .string("一段要分享的文字"),
        ])
        XCTAssertEqual(shareText.text, "一段要分享的文字")
        XCTAssertNil(shareText.path)
        let shareFile = try ShareSheetArgs.parse([
            "path": .string("captures/photo-1.jpg"),
        ])
        XCTAssertEqual(shareFile.path, "captures/photo-1.jpg")
        XCTAssertThrowsError(try ShareSheetArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "文字与文件同缺无从分享"
            )
        }
        XCTAssertThrowsError(try ShareSheetArgs.parse([
            "path": .string("../secret.txt"),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "越出 OneDay 文件夹的路径在解析层就拒"
            )
        }
    }

    /// 快捷指令与文件呈现参数：指令名必填且有字数
    /// 收敛、输入可缺省；预览/打印路径与 files_read
    /// 同一套规范化
    func testShortcutAndFilePresenceArgs() throws {
        let run = try ShortcutRunArgs.parse([
            "name": .string("睡前播客"),
        ])
        XCTAssertEqual(run.name, "睡前播客")
        XCTAssertNil(run.input)
        XCTAssertThrowsError(try ShortcutRunArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments",
                "只能按名运行，没名字在解析层拒"
            )
        }
        XCTAssertThrowsError(try ShortcutRunArgs.parse([
            "name": .string(
                String(repeating: "令", count: 101)
            ),
        ])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
        let preview = try FilePreviewArgs.parse([
            "path": .string("./docs/../report.md"),
        ])
        XCTAssertEqual(preview.path, "report.md")
        XCTAssertThrowsError(try FilePrintArgs.parse([:])) { error in
            XCTAssertEqual(
                (error as? DeviceToolError)?.code,
                "invalid_arguments"
            )
        }
    }
}
