import XCTest
@testable import OneDayCore

/// 本机连接器批一闸（0.34.0）：①名册五件完整（蓝牙
/// 永不入册）、批一/批二分界 ②工具名册与桥 TOOLS 逐
/// 字对齐、App 可执行集恰七个 ③权限桥口径映射
/// （limited 报 granted＋scope 注解）④注册载荷双层
/// 开关语义（权限报原态、tools 只列可用且开关开）
/// ⑤目录行状态文案单一映射 ⑥搜索纯函数。
final class DeviceSourcesTests: XCTestCase {

    // MARK: - 名册

    func testRosterIntegrity() {
        let roster = DeviceSourceDirectory.roster
        XCTAssertEqual(roster.count, 5)
        XCTAssertEqual(
            roster.map(\.sourceID),
            [.calendar, .reminders, .contacts, .health, .home],
            "名册序＝目录呈现序"
        )
        XCTAssertEqual(Set(roster.map(\.id)).count, roster.count)
        for entry in roster {
            XCTAssertFalse(entry.name.isEmpty, entry.id)
            XCTAssertFalse(entry.blurb.isEmpty, entry.id)
            XCTAssertFalse(entry.tileSymbol.isEmpty, entry.id)
            XCTAssertFalse(entry.agentNote.isEmpty, entry.id)
            // 0.36.3：一行能力短文案齐备且真是一行
            // （详情页开关副文用；不成段、不带句号尾）
            XCTAssertFalse(entry.capabilityLine.isEmpty, entry.id)
            XCTAssertFalse(entry.capabilityLine.contains("\n"), entry.id)
            XCTAssertLessThanOrEqual(
                entry.capabilityLine.count, 24, entry.id
            )
            XCTAssertFalse(entry.footnote.isEmpty, entry.id)
        }
        for id in DeviceSourceID.allCases {
            XCTAssertEqual(DeviceSourceDirectory.descriptor(id).sourceID, id)
        }
    }

    /// 蓝牙已决不做：名册与 rawValue 里永不出现它
    func testBluetoothNeverListed() {
        XCTAssertNil(DeviceSourceID(rawValue: "bluetooth"))
        XCTAssertFalse(
            DeviceSourceDirectory.roster.contains {
                $0.name.contains("蓝牙")
            }
        )
    }

    /// 批次分界：日历/提醒/通讯录批一已接线，健康/
    /// 家庭批二待权益（isWired 为假）
    func testBatchSplit() {
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.calendar).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.reminders).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.contacts).isWired)
        XCTAssertFalse(DeviceSourceDirectory.descriptor(.health).isWired)
        XCTAssertFalse(DeviceSourceDirectory.descriptor(.home).isWired)
    }

    // MARK: - 工具名册

    /// 与 device-bridge TOOLS 表逐字对齐（十件全集）
    func testToolRegistryMatchesBridge() {
        XCTAssertEqual(
            DeviceToolRegistry.all.map(\.name),
            [
                "device_status", "calendar_list_events",
                "calendar_create_event", "calendar_update_event",
                "reminders_list", "reminders_create",
                "reminders_complete", "contacts_search",
                "health_daily_summary", "home_status",
            ]
        )
        XCTAssertEqual(
            Set(DeviceToolRegistry.all.filter(\.isWrite).map(\.name)),
            [
                "calendar_create_event", "calendar_update_event",
                "reminders_create", "reminders_complete",
            ],
            "写工具恰四件（无 delete，设计档红线）"
        )
        XCTAssertFalse(
            DeviceToolRegistry.all.contains { $0.name.contains("delete") }
        )
    }

    /// App 可执行集：批一三件的七个；device_status 桥
    /// 本地应答不经手机；健康/家庭未接线不上报
    func testAppExecutableSet() {
        XCTAssertEqual(
            Set(DeviceToolRegistry.appExecutable.map(\.name)),
            [
                "calendar_list_events", "calendar_create_event",
                "calendar_update_event", "reminders_list",
                "reminders_create", "reminders_complete",
                "contacts_search",
            ]
        )
    }

    // MARK: - 权限映射

    func testPermissionBridgeValues() {
        XCTAssertEqual(DevicePermissionState.granted.bridgeValue, "granted")
        XCTAssertEqual(
            DevicePermissionState.limited.bridgeValue, "granted",
            "limited 子集由系统框架天然收敛，报 granted 放行、scope 另注"
        )
        XCTAssertEqual(DevicePermissionState.denied.bridgeValue, "denied")
        XCTAssertEqual(
            DevicePermissionState.notDetermined.bridgeValue, "notDetermined"
        )
        XCTAssertEqual(DevicePermissionState.writeOnly.bridgeValue, "writeOnly")
        XCTAssertTrue(DevicePermissionState.granted.isUsable)
        XCTAssertTrue(DevicePermissionState.limited.isUsable)
        XCTAssertFalse(DevicePermissionState.writeOnly.isUsable)
        XCTAssertFalse(DevicePermissionState.denied.isUsable)
    }

    // MARK: - 注册载荷

    func testRegistrationAllGrantedAllOn() {
        let payload = DeviceRegistration.payload(
            permissions: [
                .calendar: .granted, .reminders: .granted,
                .contacts: .granted,
            ],
            agentCallEnabled: [
                .calendar: true, .reminders: true, .contacts: true,
            ]
        )
        XCTAssertEqual(payload.permissions["calendar"], "granted")
        XCTAssertEqual(payload.permissions["reminders"], "granted")
        XCTAssertEqual(payload.permissions["contacts"], "granted")
        XCTAssertEqual(
            payload.permissions["health"], "notDetermined",
            "批二两件未接线，权限报未申请原态"
        )
        XCTAssertNil(payload.permissions["contactsScope"])
        XCTAssertEqual(
            Set(payload.tools),
            Set(DeviceToolRegistry.appExecutable.map(\.name))
        )
    }

    func testRegistrationSwitchOffDropsToolsOnly() {
        let payload = DeviceRegistration.payload(
            permissions: [.calendar: .granted],
            agentCallEnabled: [.calendar: false]
        )
        XCTAssertEqual(
            payload.permissions["calendar"], "granted",
            "系统权限照实报，开关只影响 tools"
        )
        XCTAssertTrue(
            payload.tools.allSatisfy { !$0.hasPrefix("calendar_") },
            "开关关掉的件，工具不列（桥回 tool_unavailable）"
        )
    }

    func testRegistrationDeniedDropsTools() {
        let payload = DeviceRegistration.payload(
            permissions: [.reminders: .denied],
            agentCallEnabled: [.reminders: true]
        )
        XCTAssertEqual(payload.permissions["reminders"], "denied")
        XCTAssertTrue(payload.tools.allSatisfy { !$0.hasPrefix("reminders_") })
    }

    func testRegistrationContactsLimitedAnnotated() {
        let payload = DeviceRegistration.payload(
            permissions: [.contacts: .limited],
            agentCallEnabled: [.contacts: true]
        )
        XCTAssertEqual(payload.permissions["contacts"], "granted")
        XCTAssertEqual(
            payload.permissions["contactsScope"], "limited",
            "受限授权必须有注解，智能体在 device_status 可见"
        )
        XCTAssertTrue(payload.tools.contains("contacts_search"))
    }

    /// 健康即使假设已授权＋开关开，批二未接线也绝不
    /// 上报工具（不许菜单上有、手机做不到）
    func testRegistrationBatch2NeverOffered() {
        let payload = DeviceRegistration.payload(
            permissions: [.health: .granted, .home: .granted],
            agentCallEnabled: [.health: true, .home: true]
        )
        XCTAssertFalse(payload.tools.contains("health_daily_summary"))
        XCTAssertFalse(payload.tools.contains("home_status"))
    }

    // MARK: - 目录行状态文案

    func testRowStatusLines() {
        let calendar = DeviceSourceDirectory.descriptor(.calendar)
        let health = DeviceSourceDirectory.descriptor(.health)
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: health, permission: .notDetermined,
                agentCallEnabled: false, metric: nil
            ),
            "待签名权益"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .notDetermined,
                agentCallEnabled: false, metric: nil
            ),
            "未授权"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .denied,
                agentCallEnabled: true, metric: nil
            ),
            "被拒"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .granted,
                agentCallEnabled: true, metric: "今天 3 个日程"
            ),
            "已授权 · 可调用 · 今天 3 个日程"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .granted,
                agentCallEnabled: false, metric: nil
            ),
            "已授权 · 调用已关"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .writeOnly,
                agentCallEnabled: true, metric: nil
            ),
            "仅写入权限 · 不能读取"
        )
        let contacts = DeviceSourceDirectory.descriptor(.contacts)
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: contacts, permission: .limited,
                agentCallEnabled: true, metric: nil
            ),
            "已授权 · 部分联系人 · 可调用"
        )
    }

    // MARK: - 搜索

    func testSearchFiltered() {
        let lines: [DeviceSourceID: String] = [
            .calendar: "已授权 · 可调用", .reminders: "未授权",
            .contacts: "被拒", .health: "待签名权益",
            .home: "待签名权益",
        ]
        XCTAssertEqual(
            DeviceRowStatus.filtered(statusLines: lines, query: "").count, 5
        )
        XCTAssertEqual(
            DeviceRowStatus.filtered(
                statusLines: lines, query: "日历"
            ).map(\.sourceID),
            [.calendar]
        )
        XCTAssertEqual(
            DeviceRowStatus.filtered(
                statusLines: lines, query: "被拒"
            ).map(\.sourceID),
            [.contacts],
            "状态词可搜"
        )
        XCTAssertEqual(
            DeviceRowStatus.filtered(
                statusLines: lines, query: "待签名权益"
            ).map(\.sourceID),
            [.health, .home]
        )
    }
}
