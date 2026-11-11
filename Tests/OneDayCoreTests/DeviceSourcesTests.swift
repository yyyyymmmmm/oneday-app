import XCTest
@testable import OneDayCore

/// 本机连接器批一闸（0.34.0）：①名册完整（蓝牙
/// 永不入册）、批一/批二分界 ②工具名册与桥 TOOLS 逐
/// 字对齐、App 可执行集恰七个 ③权限桥口径映射
/// （limited 报 granted＋scope 注解）④注册载荷双层
/// 开关语义（权限报原态、tools 只列可用且开关开）
/// ⑤目录行状态文案单一映射 ⑥搜索纯函数。
final class DeviceSourcesTests: XCTestCase {

    // MARK: - 名册

    func testRosterIntegrity() {
        let roster = DeviceSourceDirectory.roster(locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(roster.count, 9)
        XCTAssertEqual(
            roster.map(\.sourceID),
            [
                .calendar, .reminders, .contacts, .photos,
                .motion, .clipboard, .files, .health, .home,
            ],
            "名册序＝目录呈现序（0.36.14 加照片/步数，扩容批一加剪贴板/文件）"
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
            XCTAssertEqual(DeviceSourceDirectory.descriptor(id, locale: Locale(identifier: "zh-Hans")).sourceID, id)
        }
    }

    /// 蓝牙已决不做：名册与 rawValue 里永不出现它
    func testBluetoothNeverListed() {
        XCTAssertNil(DeviceSourceID(rawValue: "bluetooth"))
        XCTAssertFalse(
            DeviceSourceDirectory.roster(locale: Locale(identifier: "zh-Hans")).contains {
                $0.name.contains("蓝牙")
            }
        )
    }

    /// 批次分界：日历/提醒/通讯录批一已接线，照片/
    /// 步数 0.36.14 同步制接线（通道只有同步副本），
    /// 健康/家庭批二待权益（isWired 为假）
    func testBatchSplit() {
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.calendar, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.reminders, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.contacts, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.photos, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.motion, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.clipboard, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.files, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertFalse(DeviceSourceDirectory.descriptor(.health, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertFalse(DeviceSourceDirectory.descriptor(.home, locale: Locale(identifier: "zh-Hans")).isWired)
    }

    // MARK: - 工具名册

    /// 与 device-bridge TOOLS 表逐字对齐（十五件全
    /// 集；扩容批一的五件待桥侧 TOOLS 表补齐后才真
    /// 正双向对齐——App 侧先行定义、桥未上线时调用
    /// 在桥侧就不存在，App 侧门控见注册载荷钉测）
    func testToolRegistryMatchesBridge() {
        XCTAssertEqual(
            DeviceToolRegistry.all.map(\.name),
            [
                "device_status", "calendar_list_events",
                "calendar_create_event", "calendar_update_event",
                "reminders_list", "reminders_create",
                "reminders_complete", "contacts_search",
                "clipboard_get", "clipboard_set",
                "files_list", "files_read", "files_write",
                "health_daily_summary", "home_status",
            ]
        )
        XCTAssertEqual(
            Set(DeviceToolRegistry.all.filter(\.isWrite).map(\.name)),
            [
                "calendar_create_event", "calendar_update_event",
                "reminders_create", "reminders_complete",
                "clipboard_set", "files_write",
            ],
            "写工具恰六件（无 delete，设计档红线）"
        )
        XCTAssertFalse(
            DeviceToolRegistry.all.contains { $0.name.contains("delete") }
        )
    }

    /// App 可执行集：已接线数据源的十二个；
    /// device_status 桥本地应答不经手机；健康/家庭
    /// 未接线不上报
    func testAppExecutableSet() {
        XCTAssertEqual(
            Set(DeviceToolRegistry.appExecutable.map(\.name)),
            [
                "calendar_list_events", "calendar_create_event",
                "calendar_update_event", "reminders_list",
                "reminders_create", "reminders_complete",
                "contacts_search",
                "clipboard_get", "clipboard_set",
                "files_list", "files_read", "files_write",
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
                .clipboard: .notApplicable, .files: .notApplicable,
            ],
            agentCallEnabled: [
                .calendar: true, .reminders: true, .contacts: true,
                .clipboard: true, .files: true,
            ]
        )
        XCTAssertEqual(payload.permissions["calendar"], "granted")
        XCTAssertEqual(payload.permissions["reminders"], "granted")
        XCTAssertEqual(payload.permissions["contacts"], "granted")
        XCTAssertEqual(
            payload.permissions["clipboard"], "granted",
            "无系统权限两件：桥侧放行口径报 granted（呈现层另用专名，不冒充已授权）"
        )
        XCTAssertEqual(payload.permissions["files"], "granted")
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
        let calendar = DeviceSourceDirectory.descriptor(.calendar, locale: Locale(identifier: "zh-Hans"))
        let health = DeviceSourceDirectory.descriptor(.health, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: health, permission: .notDetermined,
                agentCallEnabled: false, sessionOnline: false,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "待签名权益"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .notDetermined,
                agentCallEnabled: false, sessionOnline: true,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "未授权"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .denied,
                agentCallEnabled: true, sessionOnline: true,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "被拒"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .granted,
                agentCallEnabled: true, sessionOnline: true,
                metric: "今天 3 个日程"
            , locale: Locale(identifier: "zh-Hans")),
            "已授权 · 可调用 · 今天 3 个日程"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .granted,
                agentCallEnabled: false, sessionOnline: true,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "已授权 · 调用已关"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .writeOnly,
                agentCallEnabled: true, sessionOnline: true,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "仅写入权限 · 不能读取"
        )
        let contacts = DeviceSourceDirectory.descriptor(.contacts, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: contacts, permission: .limited,
                agentCallEnabled: true, sessionOnline: true,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "已授权 · 部分联系人 · 可调用"
        )
    }

    /// 0.36.10（判词 4）：开关开但设备会话离线——不许
    /// 再拼「可调用」，如实降为「会话未连接」；开关关
    /// 时仍以「调用已关」为准（与在线与否无关）
    func testRowStatusLineSessionOffline() {
        let calendar = DeviceSourceDirectory.descriptor(.calendar, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .granted,
                agentCallEnabled: true, sessionOnline: false,
                metric: "今天 3 个日程"
            , locale: Locale(identifier: "zh-Hans")),
            "已授权 · 会话未连接 · 今天 3 个日程"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: calendar, permission: .granted,
                agentCallEnabled: false, sessionOnline: false,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "已授权 · 调用已关"
        )
        let contacts = DeviceSourceDirectory.descriptor(.contacts, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: contacts, permission: .limited,
                agentCallEnabled: true, sessionOnline: false,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "已授权 · 部分联系人 · 会话未连接"
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
            DeviceRowStatus.filtered(statusLines: lines, query: "", locale: Locale(identifier: "zh-Hans")).count, 9
        )
        XCTAssertEqual(
            DeviceRowStatus.filtered(
                statusLines: lines, query: "日历"
            , locale: Locale(identifier: "zh-Hans")).map(\.sourceID),
            [.calendar]
        )
        XCTAssertEqual(
            DeviceRowStatus.filtered(
                statusLines: lines, query: "被拒"
            , locale: Locale(identifier: "zh-Hans")).map(\.sourceID),
            [.contacts],
            "状态词可搜"
        )
        XCTAssertEqual(
            DeviceRowStatus.filtered(
                statusLines: lines, query: "待签名权益"
            , locale: Locale(identifier: "zh-Hans")).map(\.sourceID),
            [.health, .home]
        )
    }

    // MARK: - 无系统权限两件（设备扩容批一）

    /// notApplicable 语义钉：桥口径放行（granted）、
    /// 可用性为真，但呈现专名是「无需系统权限」——
    /// 绝不许与「已授权」混同（不画假的系统权限）
    func testNotApplicablePermissionSemantics() {
        let state = DevicePermissionState.notApplicable
        XCTAssertEqual(state.bridgeValue, "granted")
        XCTAssertTrue(state.isUsable)
        XCTAssertEqual(
            state.label(locale: Locale(identifier: "zh-Hans")),
            "无需系统权限"
        )
        XCTAssertNotEqual(
            state.label(locale: Locale(identifier: "zh-Hans")),
            DevicePermissionState.granted.label(
                locale: Locale(identifier: "zh-Hans")
            )
        )
    }

    /// 一开关门控：无系统权限两件的工具只由「允许
    /// 智能体调用」开关决定列不列——关→不列（桥回
    /// tool_unavailable；桥端 TOOLS 未上线时同理，
    /// 工具压根不在注册清单里）；开→全列
    func testRegistrationNotApplicableGating() {
        let off = DeviceRegistration.payload(
            permissions: [
                .clipboard: .notApplicable, .files: .notApplicable,
            ],
            agentCallEnabled: [.clipboard: false, .files: false]
        )
        XCTAssertTrue(off.tools.allSatisfy {
            !$0.hasPrefix("clipboard_") && !$0.hasPrefix("files_")
        })
        let on = DeviceRegistration.payload(
            permissions: [
                .clipboard: .notApplicable, .files: .notApplicable,
            ],
            agentCallEnabled: [.clipboard: true, .files: true]
        )
        XCTAssertEqual(
            Set(on.tools),
            [
                "clipboard_get", "clipboard_set",
                "files_list", "files_read", "files_write",
            ]
        )
    }

    /// 目录行：无系统权限两件的状态字以专名打头、
    /// 后接调用态（不许出现「已授权」）
    func testRowStatusNotApplicable() {
        let clipboard = DeviceSourceDirectory.descriptor(.clipboard, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: clipboard, permission: .notApplicable,
                agentCallEnabled: true, sessionOnline: true,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "无需系统权限 · 可调用"
        )
        XCTAssertEqual(
            DeviceRowStatus.line(
                descriptor: clipboard, permission: .notApplicable,
                agentCallEnabled: false, sessionOnline: true,
                metric: nil
            , locale: Locale(identifier: "zh-Hans")),
            "无需系统权限 · 调用已关"
        )
    }

    /// 剪贴板/文件不是同步数据集：同步制五件之外，
    /// fromSource 恒回 nil（不许混进副本通道）
    func testNewSourcesAreNotSyncDatasets() {
        XCTAssertNil(DeviceSyncDataset.fromSource(.clipboard))
        XCTAssertNil(DeviceSyncDataset.fromSource(.files))
    }

    /// 文案诚实钉：剪贴板说明必须如实写明读取会触
    /// 发系统粘贴提示（不许假装无感）；文件说明必
    /// 须写明只限自家文件夹与大小上限
    func testNewSourceCopyHonesty() {
        let clipboard = DeviceSourceDirectory.descriptor(.clipboard, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(clipboard.blurb.contains("粘贴提示"))
        XCTAssertTrue(clipboard.agentNote.contains("没有系统权限"))
        let files = DeviceSourceDirectory.descriptor(.files, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(files.agentNote.contains("文件夹之外"))
        XCTAssertTrue(files.footnote.contains("256 KB"))
    }
}
