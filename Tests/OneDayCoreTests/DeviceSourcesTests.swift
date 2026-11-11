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
        XCTAssertEqual(roster.count, 22)
        XCTAssertEqual(
            roster.map(\.sourceID),
            [
                .calendar, .reminders, .contacts, .photos,
                .motion, .clipboard, .files, .alarm,
                .notifications, .opener, .camera, .vision,
                .translate, .ondevice, .biometric,
                .location, .media, .compose, .shortcuts,
                .deviceinfo, .health, .home,
            ],
            "名册序＝目录呈现序（0.36.14 加照片/步数，扩容批一加剪贴板/文件，扩容批二加闹钟/通知/打开目标，扩容批三加相机/识别/翻译/端上智能/本人确认，扩容批四加定位/媒体库/拨号与撰写/快捷指令/设备信息）"
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
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.alarm, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.notifications, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.opener, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.camera, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.vision, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.translate, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.ondevice, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.biometric, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.location, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.media, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.compose, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.shortcuts, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertTrue(DeviceSourceDirectory.descriptor(.deviceinfo, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertFalse(DeviceSourceDirectory.descriptor(.health, locale: Locale(identifier: "zh-Hans")).isWired)
        XCTAssertFalse(DeviceSourceDirectory.descriptor(.home, locale: Locale(identifier: "zh-Hans")).isWired)
    }

    // MARK: - 工具名册

    /// 与 device-bridge TOOLS 表逐字对齐（四十二件
    /// 全集；扩容批一/批二/批三/批四的三十二件待桥
    /// 侧 TOOLS 表补齐后才真正双向对齐——App 侧先
    /// 行定义、桥未上线时调用在桥侧就不存在，App
    /// 侧门控见注册载荷钉测）
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
                "file_preview", "file_print",
                "alarm_set", "alarm_list", "alarm_cancel",
                "notify_post", "open_target",
                "camera_capture", "vision_ocr",
                "vision_scan_code", "vision_document_scan",
                "translate_text", "ondevice_model_run",
                "auth_biometric",
                "location_current", "location_search_places",
                "location_geocode",
                "media_library_search", "media_playlists",
                "media_playlist_create", "media_playback_control",
                "call_start", "compose_sms", "compose_email",
                "share_sheet", "shortcut_run", "device_info",
                "health_daily_summary", "home_status",
            ]
        )
        XCTAssertEqual(
            Set(DeviceToolRegistry.all.filter(\.isWrite).map(\.name)),
            [
                "calendar_create_event", "calendar_update_event",
                "reminders_create", "reminders_complete",
                "clipboard_set", "files_write",
                "alarm_set", "alarm_cancel",
                "notify_post", "open_target",
                "camera_capture", "vision_document_scan",
                "media_playlist_create", "media_playback_control",
            ],
            "写工具恰十四件（无 delete；alarm_cancel 是取消自设闹钟的配对动作、不是删用户数据，见 §113.6；auth_biometric 不入写集——它不改状态、回放旧确认会把在场门放掉，见 §114；批四的撰写/分享/快捷指令/预览/打印六件同理不入写集——只把系统面交到用户手上、不自己改变状态，见 §115）"
        )
        XCTAssertFalse(
            DeviceToolRegistry.all.contains { $0.name.contains("delete") }
        )
    }

    /// App 可执行集：已接线数据源的三十九个；
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
                "file_preview", "file_print",
                "alarm_set", "alarm_list", "alarm_cancel",
                "notify_post", "open_target",
                "camera_capture", "vision_ocr",
                "vision_scan_code", "vision_document_scan",
                "translate_text", "ondevice_model_run",
                "auth_biometric",
                "location_current", "location_search_places",
                "location_geocode",
                "media_library_search", "media_playlists",
                "media_playlist_create", "media_playback_control",
                "call_start", "compose_sms", "compose_email",
                "share_sheet", "shortcut_run", "device_info",
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
                .alarm: .granted, .notifications: .granted,
                .opener: .notApplicable,
                .camera: .granted, .vision: .notApplicable,
                .translate: .notApplicable,
                .ondevice: .notApplicable,
                .biometric: .notApplicable,
                .location: .granted, .media: .granted,
                .compose: .notApplicable,
                .shortcuts: .notApplicable,
                .deviceinfo: .notApplicable,
            ],
            agentCallEnabled: [
                .calendar: true, .reminders: true, .contacts: true,
                .clipboard: true, .files: true,
                .alarm: true, .notifications: true, .opener: true,
                .camera: true, .vision: true, .translate: true,
                .ondevice: true, .biometric: true,
                .location: true, .media: true, .compose: true,
                .shortcuts: true, .deviceinfo: true,
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
            payload.permissions["alarm"], "granted",
            "闹钟是真权限键：报系统原态，桥可据此先行拦权限错误"
        )
        XCTAssertEqual(
            payload.permissions["notifications"], "granted",
            "通知同为真权限键，与 clipboard/files 的恒通口径不同、不许混"
        )
        XCTAssertEqual(
            payload.permissions["opener"], "granted",
            "打开目标无系统权限，同 notApplicable 放行口径"
        )
        XCTAssertEqual(
            payload.permissions["camera"], "granted",
            "相机是真权限键：报系统原态，桥可据此先行拦权限错误"
        )
        XCTAssertEqual(
            payload.permissions["vision"], "granted",
            "识别无系统权限，同 notApplicable 放行口径"
        )
        XCTAssertEqual(
            payload.permissions["translate"], "granted",
            "翻译无系统权限，同 notApplicable 放行口径"
        )
        XCTAssertEqual(
            payload.permissions["ondevice"], "granted",
            "端上智能无系统权限，同 notApplicable 放行口径（机型可用性门在 App 层组装 tools 时另行摘除）"
        )
        XCTAssertEqual(
            payload.permissions["biometric"], "granted",
            "本人确认无系统权限开关，同 notApplicable 放行口径（同意在每次调用时由系统当面给出）"
        )
        XCTAssertEqual(
            payload.permissions["location"], "granted",
            "定位是真权限键：报系统原态，桥可据此先行拦权限错误"
        )
        XCTAssertEqual(
            payload.permissions["media"], "granted",
            "媒体库是真权限键：报系统原态，与定位同档"
        )
        XCTAssertEqual(
            payload.permissions["compose"], "granted",
            "拨号与撰写无系统权限，同 notApplicable 放行口径（发出权在系统撰写面当场把关）"
        )
        XCTAssertEqual(
            payload.permissions["shortcuts"], "granted",
            "快捷指令无系统权限，同 notApplicable 放行口径"
        )
        XCTAssertEqual(
            payload.permissions["deviceinfo"], "granted",
            "设备信息无系统权限，同 notApplicable 放行口径"
        )
        XCTAssertEqual(
            payload.permissions["health"], "notDetermined",
            "健康/家庭未接线，权限报未申请原态"
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
            DeviceRowStatus.filtered(statusLines: lines, query: "", locale: Locale(identifier: "zh-Hans")).count, 22
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
        XCTAssertNil(DeviceSyncDataset.fromSource(.alarm))
        XCTAssertNil(DeviceSyncDataset.fromSource(.notifications))
        XCTAssertNil(DeviceSyncDataset.fromSource(.opener))
        XCTAssertNil(DeviceSyncDataset.fromSource(.camera))
        XCTAssertNil(DeviceSyncDataset.fromSource(.vision))
        XCTAssertNil(DeviceSyncDataset.fromSource(.translate))
        XCTAssertNil(DeviceSyncDataset.fromSource(.ondevice))
        XCTAssertNil(DeviceSyncDataset.fromSource(.biometric))
        XCTAssertNil(DeviceSyncDataset.fromSource(.location))
        XCTAssertNil(DeviceSyncDataset.fromSource(.media))
        XCTAssertNil(DeviceSyncDataset.fromSource(.compose))
        XCTAssertNil(DeviceSyncDataset.fromSource(.shortcuts))
        XCTAssertNil(DeviceSyncDataset.fromSource(.deviceinfo))
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

    // MARK: - 动作型三件（设备扩容批二）

    /// 真权限两件的门控：权限不可用→工具不列、权限
    /// 原样上报（桥据此先行回 permission_denied，与
    /// clipboard/files 的 granted 恒通口径本质不同）；
    /// 打开目标无系统权限、只认调用开关
    func testRegistrationActionGating() {
        let alarmOK = DeviceRegistration.payload(
            permissions: [.alarm: .granted],
            agentCallEnabled: [.alarm: true]
        )
        XCTAssertEqual(alarmOK.permissions["alarm"], "granted")
        XCTAssertTrue(alarmOK.tools.contains("alarm_set"))
        XCTAssertTrue(alarmOK.tools.contains("alarm_list"))
        XCTAssertTrue(alarmOK.tools.contains("alarm_cancel"))
        let alarmDenied = DeviceRegistration.payload(
            permissions: [.alarm: .denied],
            agentCallEnabled: [.alarm: true]
        )
        XCTAssertEqual(
            alarmDenied.permissions["alarm"], "denied",
            "真权限键报原态，不许学无权限件报 granted"
        )
        XCTAssertTrue(alarmDenied.tools.allSatisfy {
            !$0.hasPrefix("alarm_")
        })
        let notifyUndecided = DeviceRegistration.payload(
            permissions: [.notifications: .notDetermined],
            agentCallEnabled: [.notifications: true]
        )
        XCTAssertFalse(notifyUndecided.tools.contains("notify_post"))
        let openerOn = DeviceRegistration.payload(
            permissions: [.opener: .notApplicable],
            agentCallEnabled: [.opener: true]
        )
        XCTAssertTrue(openerOn.tools.contains("open_target"))
        let openerOff = DeviceRegistration.payload(
            permissions: [.opener: .notApplicable],
            agentCallEnabled: [.opener: false]
        )
        XCTAssertFalse(openerOff.tools.contains("open_target"))
    }

    /// 文案诚实钉（批二）：闹钟必须写明穿透静音与
    /// 专注（这是 AlarmKit 与普通通知的本质区别）；
    /// 通知必须写明 64 条待发上限；打开目标必须写
    /// 明白名单封闭——三件的承诺边界都写在明处
    func testActionSourceCopyHonesty() {
        let alarm = DeviceSourceDirectory.descriptor(.alarm, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(alarm.agentNote.contains("专注"))
        XCTAssertTrue(alarm.blurb.contains("全屏"))
        let notifications = DeviceSourceDirectory.descriptor(.notifications, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(notifications.agentNote.contains("64"))
        let opener = DeviceSourceDirectory.descriptor(.opener, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(opener.agentNote.contains("白名单"))
        XCTAssertTrue(opener.footnote.contains("白名单"))
    }

    // MARK: - 在场交互五件（设备扩容批三）

    /// 门控分档：相机是真权限键（被拒→两件工具都
    /// 不列、权限报原态，桥可先行回 permission_
    /// denied；文档扫描同归相机门下）；识别/翻译/
    /// 端上智能/本人确认无系统权限、只认调用开关
    /// （关→不列、开→全列）
    func testRegistrationPresenceGating() {
        let cameraDenied = DeviceRegistration.payload(
            permissions: [.camera: .denied],
            agentCallEnabled: [.camera: true]
        )
        XCTAssertEqual(
            cameraDenied.permissions["camera"], "denied",
            "相机真权限键报原态，不许学无权限件报 granted"
        )
        XCTAssertFalse(cameraDenied.tools.contains("camera_capture"))
        XCTAssertFalse(
            cameraDenied.tools.contains("vision_document_scan"),
            "文档扫描归相机门：相机被拒它也不可用"
        )
        let cameraOK = DeviceRegistration.payload(
            permissions: [.camera: .granted],
            agentCallEnabled: [.camera: true]
        )
        XCTAssertTrue(cameraOK.tools.contains("camera_capture"))
        XCTAssertTrue(cameraOK.tools.contains("vision_document_scan"))
        let cameraOff = DeviceRegistration.payload(
            permissions: [.camera: .granted],
            agentCallEnabled: [.camera: false]
        )
        XCTAssertFalse(cameraOff.tools.contains("camera_capture"))
        let presenceOff = DeviceRegistration.payload(
            permissions: [
                .vision: .notApplicable, .translate: .notApplicable,
                .ondevice: .notApplicable, .biometric: .notApplicable,
            ],
            agentCallEnabled: [
                .vision: false, .translate: false,
                .ondevice: false, .biometric: false,
            ]
        )
        for name in [
            "vision_ocr", "vision_scan_code", "translate_text",
            "ondevice_model_run", "auth_biometric",
        ] {
            XCTAssertFalse(presenceOff.tools.contains(name), name)
        }
        let presenceOn = DeviceRegistration.payload(
            permissions: [
                .vision: .notApplicable, .translate: .notApplicable,
                .ondevice: .notApplicable, .biometric: .notApplicable,
            ],
            agentCallEnabled: [
                .vision: true, .translate: true,
                .ondevice: true, .biometric: true,
            ]
        )
        XCTAssertEqual(
            Set(presenceOn.tools),
            [
                "vision_ocr", "vision_scan_code", "translate_text",
                "ondevice_model_run", "auth_biometric",
            ]
        )
    }

    /// 文案诚实钉（批三）：相机必须写明当面操作（智
    /// 能体只能发起不能代拍）；端上智能必须写明机
    /// 型门；本人确认必须写明读不到生物数据；翻
    /// 译必须写明语言包边界——四件的承诺边界都写
    /// 在明处
    func testPresenceSourceCopyHonesty() {
        let camera = DeviceSourceDirectory.descriptor(.camera, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(camera.agentNote.contains("当面"))
        XCTAssertTrue(camera.footnote.contains("相册"))
        let vision = DeviceSourceDirectory.descriptor(.vision, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(vision.agentNote.contains("没有系统权限"))
        XCTAssertTrue(vision.footnote.contains("不上传"))
        let translate = DeviceSourceDirectory.descriptor(.translate, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(translate.agentNote.contains("语言包"))
        let ondevice = DeviceSourceDirectory.descriptor(.ondevice, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(ondevice.agentNote.contains("机型"))
        XCTAssertTrue(ondevice.capabilityLine.contains("机型"))
        let biometric = DeviceSourceDirectory.descriptor(.biometric, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(biometric.agentNote.contains("读不到"))
        XCTAssertTrue(biometric.footnote.contains("不出系统"))
    }

    // MARK: - 日常面五件（设备扩容批四）

    /// 门控分档：定位/媒体库是真权限键（被拒/未决
    /// 定→工具不列、权限报原态，桥可先行回
    /// permission_denied）；拨号与撰写/快捷指令/设
    /// 备信息无系统权限、只认调用开关（关→不列、
    /// 开→全列）；文件预览/打印随文件源的开关走
    func testRegistrationEverydayGating() {
        let locationDenied = DeviceRegistration.payload(
            permissions: [.location: .denied],
            agentCallEnabled: [.location: true]
        )
        XCTAssertEqual(
            locationDenied.permissions["location"], "denied",
            "定位真权限键报原态，不许学无权限件报 granted"
        )
        XCTAssertTrue(locationDenied.tools.allSatisfy {
            !$0.hasPrefix("location_")
        })
        let mediaUndecided = DeviceRegistration.payload(
            permissions: [.media: .notDetermined],
            agentCallEnabled: [.media: true]
        )
        XCTAssertEqual(
            mediaUndecided.permissions["media"], "notDetermined"
        )
        XCTAssertTrue(mediaUndecided.tools.allSatisfy {
            !$0.hasPrefix("media_")
        })
        let everydayOff = DeviceRegistration.payload(
            permissions: [
                .compose: .notApplicable,
                .shortcuts: .notApplicable,
                .deviceinfo: .notApplicable,
            ],
            agentCallEnabled: [
                .compose: false, .shortcuts: false,
                .deviceinfo: false,
            ]
        )
        for name in [
            "call_start", "compose_sms", "compose_email",
            "share_sheet", "shortcut_run", "device_info",
        ] {
            XCTAssertFalse(everydayOff.tools.contains(name), name)
        }
        let everydayOn = DeviceRegistration.payload(
            permissions: [
                .compose: .notApplicable,
                .shortcuts: .notApplicable,
                .deviceinfo: .notApplicable,
            ],
            agentCallEnabled: [
                .compose: true, .shortcuts: true,
                .deviceinfo: true,
            ]
        )
        XCTAssertEqual(
            Set(everydayOn.tools),
            [
                "call_start", "compose_sms", "compose_email",
                "share_sheet", "shortcut_run", "device_info",
            ]
        )
        let filesOff = DeviceRegistration.payload(
            permissions: [.files: .notApplicable],
            agentCallEnabled: [.files: false]
        )
        XCTAssertFalse(filesOff.tools.contains("file_preview"))
        XCTAssertFalse(filesOff.tools.contains("file_print"))
        let filesOn = DeviceRegistration.payload(
            permissions: [.files: .notApplicable],
            agentCallEnabled: [.files: true]
        )
        XCTAssertTrue(filesOn.tools.contains("file_preview"))
        XCTAssertTrue(filesOn.tools.contains("file_print"))
    }

    /// 文案诚实钉（批四）：定位必须写明现读现回与
    /// 没有后台定位；媒体库必须写明读不到其他 App
    /// 在放什么；撰写必须写明不能代发；快捷指令必
    /// 须写明只能按名运行、无回执只报已发起；设备
    /// 信息必须写明不编数——五件的承诺边界都写在
    /// 明处
    func testEverydaySourceCopyHonesty() {
        let location = DeviceSourceDirectory.descriptor(.location, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(location.agentNote.contains("现读现回"))
        XCTAssertTrue(location.footnote.contains("后台"))
        let media = DeviceSourceDirectory.descriptor(.media, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(media.agentNote.contains("读不到其他 App"))
        XCTAssertTrue(media.footnote.contains("不出手机"))
        let compose = DeviceSourceDirectory.descriptor(.compose, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(compose.agentNote.contains("不能代发"))
        XCTAssertTrue(compose.footnote.contains("取消"))
        let shortcuts = DeviceSourceDirectory.descriptor(.shortcuts, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(shortcuts.agentNote.contains("已发起"))
        XCTAssertTrue(shortcuts.footnote.contains("不能枚举"))
        let deviceinfo = DeviceSourceDirectory.descriptor(.deviceinfo, locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(deviceinfo.agentNote.contains("现读现回"))
        XCTAssertTrue(deviceinfo.footnote.contains("不编数"))
    }
}
