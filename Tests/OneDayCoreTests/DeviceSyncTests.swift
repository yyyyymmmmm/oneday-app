import XCTest
@testable import OneDayCore

/// 同步制闸（0.36.14）：①数据集名册与桥逐字对齐、
/// 映射与节流 ②通讯录指纹稳定且对变化敏感 ③五件
/// 记录 JSON 键名与伴生 _materialize 契约逐字对齐
/// （漂移即红）④日历窗口/提醒聚合/步数日计划的纯
/// 算术 ⑤前台计划器与批次切分 ⑥状态回执两种形状
/// 解码 ⑦呈现文案（新鲜度与状态段，与桥 freshness
/// 同措辞）
final class DeviceSyncTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        utc.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute
        ))!
    }

    // MARK: - 数据集名册

    func testDatasetRosterMatchesBridge() {
        XCTAssertEqual(
            DeviceSyncDataset.allCases.map(\.bridgeName),
            ["contacts", "calendar", "reminders", "photos", "motion"],
            "与伴生 DATASETS 逐字一致、序一致"
        )
        XCTAssertEqual(
            DeviceSyncDataset.allCases.map(\.label),
            ["通讯录", "日历", "提醒事项", "照片", "步数"]
        )
        for dataset in DeviceSyncDataset.allCases {
            XCTAssertEqual(
                DeviceSyncDataset.fromSource(dataset.sourceID), dataset
            )
        }
        XCTAssertNil(DeviceSyncDataset.fromSource(.health))
        XCTAssertNil(DeviceSyncDataset.fromSource(.home))
    }

    func testDatasetThrottle() {
        XCTAssertEqual(DeviceSyncDataset.contacts.throttleSeconds, 900)
        XCTAssertEqual(DeviceSyncDataset.calendar.throttleSeconds, 900)
        XCTAssertEqual(DeviceSyncDataset.reminders.throttleSeconds, 900)
        XCTAssertEqual(DeviceSyncDataset.photos.throttleSeconds, 900)
        XCTAssertEqual(DeviceSyncDataset.motion.throttleSeconds, 3600)
    }

    // MARK: - 通讯录指纹

    private func sampleRecord(
        phones: [SyncLabeledValue]? = nil,
        emails: [SyncLabeledValue]? = nil
    ) -> SyncContactRecord {
        SyncContactRecord(
            id: "c1", displayName: "张三", familyName: "张",
            givenName: "三", organization: "知和数智",
            phones: phones ?? [
                SyncLabeledValue(label: "手机", value: "138 0000 0000"),
                SyncLabeledValue(label: "工作", value: "029-88888888"),
            ],
            emails: emails ?? [
                SyncLabeledValue(label: "个人", value: "A@Example.com"),
            ],
            groups: ["家人"]
        )
    }

    func testFingerprintStableAndOrderInsensitive() {
        let a = sampleRecord()
        let b = sampleRecord(
            phones: [
                SyncLabeledValue(label: "工作", value: "029-88888888"),
                SyncLabeledValue(label: "手机", value: "138 0000 0000"),
            ],
            emails: [
                SyncLabeledValue(label: "个人", value: "a@example.com"),
            ]
        )
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(a.fingerprint.count, 64, "SHA-256 hex")
        XCTAssertEqual(a.manifestEntry.id, "c1")
        XCTAssertEqual(a.manifestEntry.fingerprint, a.fingerprint)
    }

    func testFingerprintSensitiveToChanges() {
        let base = sampleRecord()
        let changedPhone = sampleRecord(phones: [
            SyncLabeledValue(label: "手机", value: "139 0000 0000"),
            SyncLabeledValue(label: "工作", value: "029-88888888"),
        ])
        XCTAssertNotEqual(base.fingerprint, changedPhone.fingerprint)
        let changedLabel = sampleRecord(phones: [
            SyncLabeledValue(label: "住宅", value: "138 0000 0000"),
            SyncLabeledValue(label: "工作", value: "029-88888888"),
        ])
        XCTAssertNotEqual(
            base.fingerprint, changedLabel.fingerprint,
            "只改标签也算有变（宁可多传不许漏变）"
        )
    }

    // MARK: - 记录 JSON 契约

    func testContactRecordJSONContract() {
        let json = sampleRecord().json
        XCTAssertEqual(
            Set(json.keys),
            [
                "id", "displayName", "familyName", "givenName",
                "organization", "phones", "emails", "groups",
                "fingerprint",
            ]
        )
        guard case .array(let phones)? = json["phones"],
              case .object(let first)? = phones.first else {
            return XCTFail("phones 形状不对")
        }
        XCTAssertEqual(Set(first.keys), ["label", "value"])
        // 最小化红线：备注/地址/生日/头像键永不出现
        for banned in ["notes", "address", "birthday", "image"] {
            XCTAssertNil(json[banned], banned)
        }
        let bare = SyncContactRecord(
            id: "c2", displayName: "李四", familyName: nil,
            givenName: nil, organization: nil,
            phones: [], emails: [], groups: []
        )
        XCTAssertNil(bare.json["familyName"])
        XCTAssertNil(bare.json["organization"])
    }

    func testCalendarRecordJSONContract() {
        let record = SyncCalendarRecord(
            occurrenceId: "ev1|2026-11-11T02:00:00.000Z",
            eventId: "ev1", title: "周会",
            start: date(2026, 11, 11, 2, 0),
            end: date(2026, 11, 11, 3, 0),
            allDay: false, calendarName: "工作", location: "会议室"
        )
        XCTAssertEqual(
            Set(record.json.keys),
            [
                "occurrenceId", "eventId", "title", "start",
                "end", "allDay", "calendarName", "location",
            ]
        )
        XCTAssertEqual(
            record.json["start"],
            .string(DeviceISO8601.format(record.start))
        )
        let noLocation = SyncCalendarRecord(
            occurrenceId: "e|t", eventId: "e", title: "t",
            start: date(2026, 1, 1), end: date(2026, 1, 1, 1),
            allDay: true, calendarName: "个人", location: nil
        )
        XCTAssertNil(noLocation.json["location"])
    }

    func testReminderRecordAndAggregates() {
        let record = SyncReminderRecord(
            id: "r1", title: "买菜", due: nil,
            priority: 0, listName: "生活"
        )
        XCTAssertEqual(
            Set(record.json.keys), ["id", "title", "priority", "listName"],
            "无到期时 due 键不出现（伴生存 NULL）"
        )
        let now = date(2026, 11, 10, 12, 0)
        let inputs = [
            // 今天完成 → 计今日已完成
            SyncReminderInput(
                due: nil, isCompleted: true,
                completionDate: date(2026, 11, 10, 9, 0)
            ),
            // 昨天完成 → 不计
            SyncReminderInput(
                due: nil, isCompleted: true,
                completionDate: date(2026, 11, 9, 9, 0)
            ),
            // 未完成、昨天到期 → 已过期
            SyncReminderInput(
                due: date(2026, 11, 9, 18, 0),
                isCompleted: false, completionDate: nil
            ),
            // 未完成、今天到期 → 不算过期（今天零点口径）
            SyncReminderInput(
                due: date(2026, 11, 10, 8, 0),
                isCompleted: false, completionDate: nil
            ),
            // 未完成、无到期 → 都不计
            SyncReminderInput(
                due: nil, isCompleted: false, completionDate: nil
            ),
        ]
        let aggregates = SyncReminderAggregates.compute(
            inputs, now: now, calendar: utc
        )
        XCTAssertEqual(aggregates.todayCompleted, 1)
        XCTAssertEqual(aggregates.overdueCount, 1)
        XCTAssertEqual(
            aggregates.json,
            ["todayCompleted": .number(1), "overdueCount": .number(1)]
        )
    }

    func testPhotoRecordJSONContract() {
        let record = SyncPhotoRecord(
            assetId: "A1", createdAt: date(2026, 10, 1, 8, 30),
            mediaType: "photo", subtype: "screenshot",
            width: 1179, height: 2556, durationSec: nil,
            isFavorite: true, albumName: nil, hasLocation: false
        )
        XCTAssertEqual(
            Set(record.json.keys),
            [
                "assetId", "createdAt", "mediaType", "subtype",
                "width", "height", "isFavorite", "hasLocation",
            ],
            "albumName/durationSec 为空不出现；坐标键永不出现"
        )
        XCTAssertNil(record.json["location"])
        XCTAssertNil(record.json["latitude"])
    }

    func testMotionRecordJSONContract() {
        let record = SyncMotionDayRecord(
            date: "2026-11-10", steps: 8432,
            distanceM: 5120.5, flights: 6
        )
        XCTAssertEqual(record.json["source"], .string("手机计步"))
        XCTAssertEqual(record.json["steps"], .number(8432))
        let bare = SyncMotionDayRecord(
            date: "2026-11-09", steps: 0,
            distanceM: nil, flights: nil
        )
        XCTAssertNil(bare.json["distanceM"])
        XCTAssertNil(bare.json["flights"])
    }

    // MARK: - 窗口与日计划

    func testCalendarWindow() {
        let now = date(2026, 11, 10, 15, 30)
        let bounds = SyncCalendarWindow.bounds(now: now, calendar: utc)
        XCTAssertEqual(bounds.start, date(2026, 10, 11))
        XCTAssertEqual(
            bounds.end, date(2027, 2, 9),
            "终点＝+90 天（2月8日）的次日零点，整天覆盖"
        )
    }

    func testMotionDayRanges() {
        let now = date(2026, 11, 10, 15, 30)
        let ranges = SyncMotionPlan.dayRanges(
            now: now, calendar: utc
        )
        XCTAssertEqual(ranges.count, 7)
        XCTAssertEqual(ranges.first?.day, "2026-11-04")
        XCTAssertEqual(ranges.last?.day, "2026-11-10")
        XCTAssertEqual(ranges.last?.start, date(2026, 11, 10))
        for index in 1..<ranges.count {
            XCTAssertEqual(
                ranges[index].start, ranges[index - 1].end,
                "逐日区间首尾相接、不重不漏"
            )
        }
    }

    // MARK: - 计划器与批次

    func testPlannerDecisions() {
        let now = date(2026, 11, 10, 12, 0)
        XCTAssertEqual(
            DeviceSyncPlanner.foregroundDecision(
                dataset: .contacts, permissionUsable: false,
                syncEnabled: true, lastSuccessAt: nil,
                pendingWrite: false, now: now
            ),
            .blockedPermission
        )
        XCTAssertEqual(
            DeviceSyncPlanner.foregroundDecision(
                dataset: .contacts, permissionUsable: true,
                syncEnabled: false, lastSuccessAt: nil,
                pendingWrite: false, now: now
            ),
            .blockedSwitchOff
        )
        XCTAssertEqual(
            DeviceSyncPlanner.foregroundDecision(
                dataset: .contacts, permissionUsable: true,
                syncEnabled: true, lastSuccessAt: nil,
                pendingWrite: false, now: now
            ),
            .sync, "从未同步过恒到期"
        )
        XCTAssertEqual(
            DeviceSyncPlanner.foregroundDecision(
                dataset: .contacts, permissionUsable: true,
                syncEnabled: true,
                lastSuccessAt: date(2026, 11, 10, 11, 50),
                pendingWrite: false, now: now
            ),
            .skipThrottled, "10 分钟前同步过、15 分钟内跳过"
        )
        XCTAssertEqual(
            DeviceSyncPlanner.foregroundDecision(
                dataset: .contacts, permissionUsable: true,
                syncEnabled: true,
                lastSuccessAt: date(2026, 11, 10, 11, 50),
                pendingWrite: true, now: now
            ),
            .sync, "有未同步写入标记无视节流"
        )
        XCTAssertEqual(
            DeviceSyncPlanner.foregroundDecision(
                dataset: .motion, permissionUsable: true,
                syncEnabled: true,
                lastSuccessAt: date(2026, 11, 10, 11, 30),
                pendingWrite: false, now: now
            ),
            .skipThrottled, "步数节流 1 小时：30 分钟前跳过"
        )
        XCTAssertEqual(
            DeviceSyncPlanner.foregroundDecision(
                dataset: .motion, permissionUsable: true,
                syncEnabled: true,
                lastSuccessAt: date(2026, 11, 10, 10, 59),
                pendingWrite: false, now: now
            ),
            .sync, "步数满 1 小时到期"
        )
    }

    func testBatchPlanRanges() {
        XCTAssertEqual(SyncBatchPlan.ranges(total: 0), [0..<0])
        XCTAssertEqual(SyncBatchPlan.ranges(total: 1), [0..<1])
        XCTAssertEqual(SyncBatchPlan.ranges(total: 500), [0..<500])
        XCTAssertEqual(
            SyncBatchPlan.ranges(total: 501), [0..<500, 500..<501]
        )
        XCTAssertEqual(
            SyncBatchPlan.ranges(total: 1200),
            [0..<500, 500..<1000, 1000..<1200]
        )
    }

    // MARK: - 状态回执解码

    func testStatusDecodeSyncedShape() {
        let body = """
        {"datasets": {
          "contacts": {
            "dataset": "contacts", "label": "通讯录",
            "synced": true,
            "synced_at": "2026-11-10T09:41:00.500000+08:00",
            "freshness": "数据截至今天 09:41，约 20 分钟前同步",
            "expired": false, "item_count": 156,
            "auth_range": "full", "permission_state": "granted",
            "pending_write": true, "syncing": false,
            "last_error": null
          },
          "calendar": {
            "dataset": "calendar", "label": "日历",
            "synced": true,
            "synced_at": "2026-11-10T09:40:00+08:00",
            "freshness": "x", "expired": true, "item_count": 42,
            "auth_range": "full", "permission_state": "granted",
            "pending_write": false, "syncing": false,
            "last_error": null,
            "coverage": {
              "start": "2026-10-11T00:00:00+08:00",
              "end": "2027-02-08T00:00:00+08:00"
            }
          },
          "reminders": {
            "dataset": "reminders", "label": "提醒事项",
            "synced": true,
            "synced_at": "2026-11-10T09:40:00+08:00",
            "freshness": "x", "expired": false, "item_count": 7,
            "auth_range": "full", "permission_state": "revoked",
            "pending_write": false, "syncing": false,
            "last_error": null,
            "aggregates": {"today_completed": 3, "overdue_at_sync": 2}
          },
          "photos": {
            "dataset": "photos", "label": "照片",
            "synced": false, "item_count": 0,
            "permission_state": null, "pending_write": false
          },
          "motion": {
            "dataset": "motion", "label": "步数",
            "synced": false, "item_count": 0,
            "permission_state": null, "pending_write": false
          }
        }}
        """
        let decoded = DeviceSyncStatusResponse.decode(Data(body.utf8))
        XCTAssertEqual(decoded.count, 5)
        let contacts = decoded[.contacts]
        XCTAssertEqual(contacts?.itemCount, 156)
        XCTAssertEqual(contacts?.pendingWrite, true)
        XCTAssertNotNil(contacts?.syncedAt)
        XCTAssertEqual(contacts?.freshness, "数据截至今天 09:41，约 20 分钟前同步")
        XCTAssertEqual(decoded[.calendar]?.expired, true)
        XCTAssertEqual(
            decoded[.calendar]?.coverageStart, "2026-10-11T00:00:00+08:00"
        )
        XCTAssertEqual(decoded[.reminders]?.reminderTodayCompleted, 3)
        XCTAssertEqual(decoded[.reminders]?.reminderOverdueAtSync, 2)
        XCTAssertEqual(decoded[.reminders]?.isRevoked, true)
        XCTAssertEqual(decoded[.photos]?.synced, false)
        XCTAssertNil(decoded[.photos]?.syncedAt)
    }

    func testStatusDecodeGarbageIsEmpty() {
        XCTAssertTrue(
            DeviceSyncStatusResponse.decode(Data("nope".utf8)).isEmpty
        )
        XCTAssertTrue(
            DeviceSyncStatusResponse.decode(Data("{}".utf8)).isEmpty
        )
    }

    // MARK: - 呈现文案

    func testDayLabelAndFreshness() {
        let now = date(2026, 11, 10, 12, 0)
        XCTAssertEqual(
            DeviceSyncPresentation.dayLabel(
                date(2026, 11, 10, 9, 41), now: now, calendar: utc
            ),
            "今天 09:41"
        )
        XCTAssertEqual(
            DeviceSyncPresentation.dayLabel(
                date(2026, 11, 9, 23, 10), now: now, calendar: utc
            ),
            "昨晚 23:10"
        )
        XCTAssertEqual(
            DeviceSyncPresentation.dayLabel(
                date(2026, 11, 9, 10, 0), now: now, calendar: utc
            ),
            "昨天 10:00"
        )
        XCTAssertEqual(
            DeviceSyncPresentation.freshnessLine(
                syncedAt: date(2026, 11, 10, 11, 59),
                now: now, pendingWrite: false, calendar: utc
            ),
            "数据截至今天 11:59，刚刚同步"
        )
        XCTAssertEqual(
            DeviceSyncPresentation.freshnessLine(
                syncedAt: date(2026, 11, 10, 11, 40),
                now: now, pendingWrite: false, calendar: utc
            ),
            "数据截至今天 11:40，约 20 分钟前同步"
        )
        XCTAssertEqual(
            DeviceSyncPresentation.freshnessLine(
                syncedAt: date(2026, 11, 8, 12, 0),
                now: now, pendingWrite: false, calendar: utc
            ),
            "数据截至11月8日 12:00，已过期"
        )
        XCTAssertTrue(
            DeviceSyncPresentation.freshnessLine(
                syncedAt: date(2026, 11, 10, 11, 40),
                now: now, pendingWrite: true, calendar: utc
            ).hasSuffix("；刚写入的一条可能还没反映在副本里")
        )
    }

    func testSegmentLines() {
        let now = date(2026, 11, 10, 12, 0)
        XCTAssertEqual(
            DeviceSyncPresentation.segment(
                dataset: .contacts, status: nil,
                syncEnabled: false, now: now, calendar: utc
            ),
            "同步未开"
        )
        XCTAssertEqual(
            DeviceSyncPresentation.segment(
                dataset: .contacts, status: nil,
                syncEnabled: true, now: now, calendar: utc
            ),
            "同步已开 · 还没有同步"
        )
        let status = DeviceSyncDatasetStatus(
            dataset: .contacts, synced: true,
            syncedAt: date(2026, 11, 10, 9, 41),
            freshness: nil, expired: false, itemCount: 156,
            authRange: "full", permissionState: "granted",
            pendingWrite: false, syncing: false, lastError: nil,
            coverageStart: nil, coverageEnd: nil,
            reminderTodayCompleted: nil, reminderOverdueAtSync: nil
        )
        XCTAssertEqual(
            DeviceSyncPresentation.segment(
                dataset: .contacts, status: status,
                syncEnabled: true, now: now, calendar: utc
            ),
            "已同步 156 人 · 今天 09:41"
        )
        XCTAssertEqual(
            DeviceSyncPresentation.rangeLine(status), "全部"
        )
    }

    // MARK: - 一开关映射（0.36.16）

    func testOneSwitchAgentCanQueryTruthTable() {
        // 开＝权限可用才可查；关＝一律不可用
        XCTAssertTrue(DeviceSyncControl.agentCanQuery(
            permission: .granted, syncEnabled: true
        ))
        XCTAssertTrue(DeviceSyncControl.agentCanQuery(
            permission: .limited, syncEnabled: true
        ))
        XCTAssertFalse(DeviceSyncControl.agentCanQuery(
            permission: .granted, syncEnabled: false
        ))
        XCTAssertFalse(DeviceSyncControl.agentCanQuery(
            permission: .denied, syncEnabled: true
        ))
        XCTAssertFalse(DeviceSyncControl.agentCanQuery(
            permission: .notDetermined, syncEnabled: true
        ))
        XCTAssertFalse(DeviceSyncControl.agentCanQuery(
            permission: .writeOnly, syncEnabled: true
        ))
        XCTAssertFalse(DeviceSyncControl.agentCanQuery(
            permission: .restricted, syncEnabled: true
        ))
    }

    func testEnableActionMapping() {
        XCTAssertEqual(
            DeviceSyncControl.enableAction(for: .granted), .enable
        )
        XCTAssertEqual(
            DeviceSyncControl.enableAction(for: .limited), .enable
        )
        XCTAssertEqual(
            DeviceSyncControl.enableAction(for: .notDetermined),
            .requestPermission
        )
        XCTAssertEqual(
            DeviceSyncControl.enableAction(for: .denied),
            .openSettings
        )
        XCTAssertEqual(
            DeviceSyncControl.enableAction(for: .restricted),
            .openSettings
        )
        XCTAssertEqual(
            DeviceSyncControl.enableAction(for: .writeOnly),
            .openSettings
        )
    }

    func testPermissionStatusText() {
        XCTAssertEqual(
            DeviceSyncControl.permissionStatusText(.granted), "已授权"
        )
        XCTAssertEqual(
            DeviceSyncControl.permissionStatusText(.limited),
            "已授权 · 部分"
        )
        XCTAssertEqual(
            DeviceSyncControl.permissionStatusText(.notDetermined),
            "未授权"
        )
        XCTAssertEqual(
            DeviceSyncControl.permissionStatusText(.denied),
            "未授权 · 去设置"
        )
        XCTAssertEqual(
            DeviceSyncControl.permissionStatusText(.writeOnly),
            "仅写入 · 去设置"
        )
        XCTAssertEqual(
            DeviceSyncControl.permissionStatusText(.restricted),
            "受限制"
        )
    }

    func testEnableSequenceOrder() {
        // P-10 解耦序：先落日志 → 关说明 → 翻状态 → 起引擎
        XCTAssertEqual(
            DeviceSyncControl.enableSequence,
            [.logEnabling, .dismissIntro, .flipSwitchOn, .startSync]
        )
    }

    // MARK: - 同步日志（0.36.16）

    func testSyncLogLineConstruction() {
        let at = date(2026, 11, 10, 23, 20)
        func line(
            _ kind: DeviceSyncLogEntry.Kind, added: Int? = nil,
            total: Int? = nil, reason: String? = nil
        ) -> String {
            DeviceSyncLogPresentation.line(
                for: DeviceSyncLogEntry(
                    at: at, kind: kind, added: added,
                    total: total, reason: reason
                ),
                dataset: .contacts
            )
        }
        XCTAssertEqual(line(.enabling), "正在开启同步")
        XCTAssertEqual(line(.enabled), "同步已开启")
        XCTAssertEqual(
            line(.disabled), "同步已关闭，智能体用不了这一件了"
        )
        XCTAssertEqual(line(.syncStarted), "开始同步")
        XCTAssertEqual(
            line(.syncCompleted, added: 3, total: 156),
            "同步完成：新增 3 人，共 156 人"
        )
        XCTAssertEqual(
            line(.syncFailed, reason: "还没连上服务器，同步不了"),
            "同步没成：还没连上服务器，同步不了"
        )
        XCTAssertEqual(
            line(.permissionRevoked),
            "系统权限被关掉了：已停供，智能体查不到这一件了"
        )
        XCTAssertEqual(line(.permissionRestored), "系统权限恢复了")
        XCTAssertEqual(line(.copyDeleted), "服务器上的副本已删除")
    }

    func testSyncLogBookCapAndOrder() {
        var entries: [DeviceSyncLogEntry] = []
        for index in 0..<55 {
            entries = DeviceSyncLogBook.appending(
                entries,
                DeviceSyncLogEntry(
                    at: Date(timeIntervalSince1970: Double(index)),
                    kind: .syncStarted
                )
            )
        }
        XCTAssertEqual(entries.count, DeviceSyncLogBook.cap)
        // 新在上：第 55 条（下标 54）在首，第 6 条在尾
        XCTAssertEqual(
            entries.first?.at, Date(timeIntervalSince1970: 54)
        )
        XCTAssertEqual(
            entries.last?.at, Date(timeIntervalSince1970: 5)
        )
    }

    func testSyncLogAddedCount() {
        XCTAssertEqual(
            DeviceSyncLogBook.addedCount(
                previousTotal: nil, newTotal: 156
            ), 156, "没有旧账：全量即新增"
        )
        XCTAssertEqual(
            DeviceSyncLogBook.addedCount(
                previousTotal: 150, newTotal: 156
            ), 6
        )
        XCTAssertEqual(
            DeviceSyncLogBook.addedCount(
                previousTotal: 160, newTotal: 156
            ), 0, "变少报 0、不报负数"
        )
    }

    func testSyncLogEntryCodableRoundTrip() throws {
        let entry = DeviceSyncLogEntry(
            at: date(2026, 11, 10, 23, 20), kind: .syncCompleted,
            added: 3, total: 156
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(
            DeviceSyncLogEntry.self, from: data
        )
        XCTAssertEqual(decoded, entry)
    }
}
