import AlarmKit
import Contacts
import EventKit
import Foundation
import OneDayCore
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// 系统权限翻译层：EK/CN 的授权状态逐件翻成 Core
/// 的 DevicePermissionState（呈现与注册载荷只认这
/// 一套枚举）。健康/家庭未接线、从未申请，如实
/// 报 notDetermined——不许拿别件的授权冒充。
enum DevicePermissions {
    static func currentStates() -> [DeviceSourceID: DevicePermissionState] {
        [
            .calendar: calendarState(),
            .reminders: remindersState(),
            .contacts: contactsState(),
            // 照片/步数状态函数在 DeviceSyncExecutors
            // （PhotoKit/CoreMotion 翻译层同文件）
            .photos: photosState(),
            .motion: motionState(),
            // 剪贴板/沙盒文件（设备扩容批一）：iOS 没
            // 有这两件的系统权限，如实报 notApplicable
            // ——不许拿 granted 冒充系统已授权；能不能
            // 调用只看「允许智能体调用」开关
            .clipboard: .notApplicable,
            .files: .notApplicable,
            // 闹钟/通知/打开目标（设备扩容批二）：
            // 闹钟走 AlarmKit 同步 authorizationState
            // 现读；通知没有同步读状态的 API，报最近
            // 一次刷新的缓存值（进前台/进页/执行前都
            // 会刷新，执行判门以刷新后的真状态为准）；
            // 打开目标没有系统权限，如实 notApplicable
            .alarm: AlarmEngine.systemState(),
            .notifications: NotificationEngine.cachedState,
            .opener: .notApplicable,
            // 在场交互与端上智能（设备扩容批三）：相机
            // 走 AVCaptureDevice 同步授权状态现读；识
            // 别/翻译是纯端上计算、本人确认的同意在每
            // 次调用时由系统当面给出、端上智能只有机
            // 型可用性门（不进权限档，由注册载荷过滤
            // ＋引擎执行时复查承接）——四件都没有可开
            // 关的系统权限，如实报 notApplicable
            .camera: CameraEngine.systemState(),
            .vision: .notApplicable,
            .translate: .notApplicable,
            .ondevice: .notApplicable,
            .biometric: .notApplicable,
            // 日常面五件（设备扩容批四）：定位走
            // CoreLocation 同步 authorizationStatus
            // 现读、媒体库走 MPMediaLibrary 同步授权
            // 状态现读（两件都是真权限键）；拨号与
            // 撰写/快捷指令/设备信息没有系统权限可
            // 开关，如实报 notApplicable
            .location: LocationEngine.systemState(),
            .media: MediaEngine.systemState(),
            .compose: .notApplicable,
            .shortcuts: .notApplicable,
            .deviceinfo: .notApplicable,
            .health: .notDetermined,
            .home: .notDetermined,
        ]
    }

    static func calendarState() -> DevicePermissionState {
        translate(EKEventStore.authorizationStatus(for: .event))
    }

    static func remindersState() -> DevicePermissionState {
        translate(EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func translate(
        _ status: EKAuthorizationStatus
    ) -> DevicePermissionState {
        switch status {
        case .fullAccess, .authorized: return .granted
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func contactsState() -> DevicePermissionState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: return .granted
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

// MARK: - 呈现层条目（详情页 L1 本地读的形状）

struct DeviceAgendaEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarName: String
    let calendarColorHex: UInt32
    let location: String?
}

struct DeviceReminderItem: Identifiable, Sendable {
    let id: String
    let title: String
    let due: Date?
    let priority: Int
    let notes: String?
    let listName: String
    let isCompleted: Bool

    /// 过期判定（呈现口径）：未完成且到期已过
    var isOverdue: Bool {
        guard !isCompleted, let due else { return false }
        return due < Date()
    }
}

struct DeviceContactItem: Identifiable, Sendable {
    let id: String
    let name: String
    let phones: [String]
    let emails: [String]
    let organization: String?
}

/// 沙盒文件条目（文件详情页本地浏览用）：path 是
/// 相对 Documents 根的规范路径，既是身份也是定位
struct DeviceFileItem: Identifiable, Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let sizeBytes: Int64
    let modifiedAt: Date

    var id: String { path }
}


// MARK: - 设备能力插件协议（#39：按权限域插件化）

protocol DeviceCapabilityPlugin: Sendable {
    static var capabilityDomain: String { get }
}

// MARK: - 工具分发器（执行前复查＋幂等＋回读）

/// 一次桥下发调用的执行：先按注册时口径复查（权限
/// 仍可用、开关仍开——注册后用户可能刚关，执行时以
/// 当下为准），写工具先过 App 侧幂等账本（24 小时
/// 同 key 回原对象、不真写第二次），执行后结果必
/// 含回读字段（在各执行器内完成）。账本只存 key 与
/// 对象 id、落 UserDefaults，不存内容。
final class DeviceToolDispatcher: @unchecked Sendable {
    let events = EventKitEngine()
    let contacts = ContactsEngine()
    let clipboard = ClipboardEngine()
    let files = SandboxFilesEngine()
    let alarms = AlarmEngine()
    let notifications = NotificationEngine()
    let opener = OpenTargetEngine()
    // 批三引擎：相机/识别要共用同一个沙盒文件引擎
    // （产物落盘与识别输入同一条边界），在 init 里
    // 以已建好的 files 注入；翻译/端上模型/本人确
    // 认无状态依赖、直接内联建
    let camera: CameraEngine
    let vision: VisionEngine
    let translate = TranslateEngine()
    let ondevice = OnDeviceModelEngine()
    let biometric = BiometricEngine()
    // 批四引擎：定位/媒体库/撰写/快捷指令/设备信息
    // 无跨引擎状态依赖、直接内联建；文件呈现要共用
    // 同一个沙盒文件引擎，在 init 里注入
    let location = LocationEngine()
    let media = MediaEngine()
    let compose = ComposeEngine()
    let shortcuts = ShortcutEngine()
    let deviceInfo = DeviceInfoEngine()
    let filePresence: FilePresenceEngine

    init() {
        camera = CameraEngine(files: files)
        vision = VisionEngine(files: files)
        filePresence = FilePresenceEngine()
    }

    private static let ledgerKey = "device.writeKeyLedger.v1"

    private func loadLedger() -> [WriteKeyRecord] {
        guard let data = UserDefaults.standard.data(
            forKey: Self.ledgerKey
        ),
        let records = try? JSONDecoder().decode(
            [WriteKeyRecord].self, from: data
        ) else { return [] }
        return records
    }

    private func saveLedger(_ records: [WriteKeyRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.ledgerKey)
        }
    }

    /// 幂等回放结果组装：原对象还在就带回读、不在
    /// 就只回 objectId 并标明对象已不在（如实）
    private func replayResult(
        tool: String, objectID: String?
    ) -> JSONValue {
        var result: [String: JSONValue] = [
            "idempotentReplay": .bool(true),
            "tool": .string(tool),
        ]
        if let objectID {
            result["objectId"] = .string(objectID)
            switch tool {
            case "calendar_create_event", "calendar_update_event":
                if let event = events.eventObjectByID(objectID) {
                    result["event"] = .object(event)
                }
            case "reminders_create", "reminders_complete":
                if let reminder = events.reminderObjectByID(objectID) {
                    result["reminder"] = .object(reminder)
                }
            case "files_write":
                // 回放只带文件元数据（还在不在、多大），
                // 不重读内容——内容不该在回放里再过境
                if let item = files.item(relativePath: objectID) {
                    result["file"] = .object(
                        SandboxFilesEngine.fileObject(item)
                    )
                }
            case "alarm_set":
                // 回放带闹钟当前回读（还在册才有），
                // 不重设第二个闹钟
                if let object = alarms.alarmObject(id: objectID) {
                    result["alarm"] = .object(object)
                }
            case "alarm_cancel":
                // 回放时复核目标确实已不在系统列表
                result["stillAbsent"] = .bool(
                    alarms.alarmObject(id: objectID) == nil
                )
            case "camera_capture":
                // 回放只带已存图片的回读元数据（还在
                // 不在、多大），不重拍第二张——取景框
                // 绝不因重发再弹
                if let item = files.item(relativePath: objectID) {
                    result["file"] = .object(
                        SandboxFilesEngine.fileObject(item)
                    )
                }
            case "vision_document_scan":
                // objectID 是这批页的共同前缀：回放按
                // 前缀找回还在的页并带回元数据
                let pages = camera.scanPages(prefix: objectID)
                result["pageCount"] = .number(
                    Double(pages.count)
                )
                result["pages"] = .array(pages.map {
                    .object(SandboxFilesEngine.fileObject($0))
                })
            case "media_playlist_create":
                // 回放带歌单当前回读（还在才有），不
                // 再建第二个同名歌单
                if let playlist = media.playlistObjectByID(
                    objectID
                ) {
                    result["playlist"] = .object(playlist)
                }
            default:
                break
            }
        }
        return .object(result)
    }

    func execute(
        call: DeviceIncomingCall,
        permissions permissionsSnapshotFallback: [DeviceSourceID: DevicePermissionState],
        agentCallEnabled: [DeviceSourceID: Bool]
    ) async -> (result: JSONValue?, error: DeviceToolError?) {
        guard let spec = DeviceToolRegistry.spec(call.tool) else {
            return (nil, .toolUnavailable("未知工具 \(call.tool)"))
        }
        guard let source = spec.source,
              DeviceSourceDirectory.descriptor(source).isWired else {
            return (nil, .toolUnavailable("工具 \(call.tool) 尚未接线"))
        }
        // 判门逐调现读（§244 G9）：注册快照会旧（用户
        // 在设置里改完权限、快照还没随重注册刷新时最
        // 明显），判门一律以执行这一刻的真状态为准；
        // 入参快照只在现读缺项时兜底。通知无同步读法，
        // 保留既有异步现读覆写
        var permissions = DevicePermissions.currentStates()
        for (key, value) in permissionsSnapshotFallback {
            if permissions[key] == nil { permissions[key] = value }
        }
        if source == .notifications {
            permissions[.notifications] =
                await NotificationEngine.readSystemState()
        }
        // 执行时复查：注册只是快照，当下为准
        let state = permissions[source] ?? .notDetermined
        guard state.isUsable else {
            return (nil, .permissionDenied(
                "\(DeviceSourceDirectory.descriptor(source).name)的系统权限当前是「\(state.label)」，无法执行"
            ))
        }
        guard agentCallEnabled[source] ?? false else {
            return (nil, .toolUnavailable(
                "\(DeviceSourceDirectory.descriptor(source).name)的智能体调用已关闭"
            ))
        }
        do {
            switch call.tool {
            case "calendar_list_events":
                let window = try CalendarListWindow.parse(call.arguments)
                return (events.listEventsResult(window: window), nil)
            case "calendar_create_event":
                let args = try CalendarCreateArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try events.createEvent(args) }
            case "calendar_update_event":
                let args = try CalendarUpdateArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try events.updateEvent(args) }
            case "reminders_list":
                return (await events.listRemindersResult(), nil)
            case "reminders_create":
                let args = try ReminderCreateArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try events.createReminder(args) }
            case "reminders_complete":
                let args = try ReminderCompleteArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) {
                    try events.setReminderCompleted(
                        id: args.reminderID, completed: true
                    )
                }
            case "contacts_search":
                let args = try ContactsSearchArgs.parse(call.arguments)
                return (try contacts.search(args), nil)
            case "clipboard_get":
                return (clipboard.getResult(), nil)
            case "clipboard_set":
                let args = try ClipboardSetArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try clipboard.setClipboard(args) }
            case "files_list":
                let args = try FilesListArgs.parse(call.arguments)
                return (try files.listResult(args), nil)
            case "files_read":
                let args = try FilesReadArgs.parse(call.arguments)
                return (try files.readResult(args), nil)
            case "files_write":
                let args = try FilesWriteArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try files.writeFile(args) }
            case "alarm_set":
                let args = try AlarmSetArgs.parse(call.arguments)
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await alarms.setAlarm(args) }
            case "alarm_list":
                return (alarms.listResult(), nil)
            case "alarm_cancel":
                let args = try AlarmCancelArgs.parse(call.arguments)
                return try writeWithLedger(
                    key: args.idempotencyKey, tool: call.tool
                ) { try alarms.cancelAlarm(args) }
            case "notify_post":
                let args = try NotifyPostArgs.parse(call.arguments)
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await notifications.post(args) }
            case "open_target":
                let args = try OpenTargetArgs.parse(call.arguments)
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await opener.open(args) }
            case "camera_capture":
                let args = try CameraCaptureArgs.parse(call.arguments)
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await camera.capturePhoto(args) }
            case "vision_ocr":
                let args = try VisionOCRArgs.parse(call.arguments)
                return (try await vision.ocrResult(args), nil)
            case "vision_scan_code":
                let args = try VisionScanCodeArgs.parse(call.arguments)
                return (try await vision.scanCodeResult(args), nil)
            case "vision_document_scan":
                let args = try VisionDocumentScanArgs.parse(
                    call.arguments
                )
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await camera.scanDocument(args) }
            case "translate_text":
                let args = try TranslateTextArgs.parse(call.arguments)
                return (try await translate.translate(args), nil)
            case "ondevice_model_run":
                let args = try OnDeviceModelArgs.parse(call.arguments)
                return (try await ondevice.run(args), nil)
            case "auth_biometric":
                // 本人确认不走账本（每次必真问一次，
                // 见 DeviceToolSpec 批三注记）
                let args = try BiometricAuthArgs.parse(call.arguments)
                return (try await biometric.confirm(args), nil)
            case "location_current":
                let args = try LocationCurrentArgs.parse(
                    call.arguments
                )
                return (try await location.currentResult(args), nil)
            case "location_search_places":
                let args = try LocationSearchPlacesArgs.parse(
                    call.arguments
                )
                return (
                    try await location.searchPlacesResult(args),
                    nil
                )
            case "location_geocode":
                let args = try LocationGeocodeArgs.parse(
                    call.arguments
                )
                return (try await location.geocodeResult(args), nil)
            case "media_library_search":
                let args = try MediaLibrarySearchArgs.parse(
                    call.arguments
                )
                return (try media.searchResult(args), nil)
            case "media_playlists":
                let args = try MediaPlaylistsArgs.parse(
                    call.arguments
                )
                return (try media.playlistsResult(args), nil)
            case "media_playlist_create":
                let args = try MediaPlaylistCreateArgs.parse(
                    call.arguments
                )
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await media.createPlaylist(args) }
            case "media_playback_control":
                let args = try MediaPlaybackControlArgs.parse(
                    call.arguments
                )
                return try await writeWithLedgerAsync(
                    key: args.idempotencyKey, tool: call.tool
                ) { try await media.playbackControl(args) }
            case "call_start":
                // 撰写四件不走账本（把面交到用户手上
                // 不是状态写入，见 DeviceToolSpec 批
                // 四注记）
                let args = try CallStartArgs.parse(call.arguments)
                return (try await compose.startCall(args), nil)
            case "compose_sms":
                let args = try ComposeSMSArgs.parse(call.arguments)
                return (try await compose.composeSMS(args), nil)
            case "compose_email":
                let args = try ComposeEmailArgs.parse(
                    call.arguments
                )
                return (try await compose.composeEmail(args), nil)
            case "share_sheet":
                let args = try ShareSheetArgs.parse(call.arguments)
                return (
                    try await compose.share(args, files: files),
                    nil
                )
            case "shortcut_run":
                // 快捷指令不走账本（每次都要真跑一
                // 次，回放旧回执等于骗它跑过了）
                let args = try ShortcutRunArgs.parse(
                    call.arguments
                )
                return (try await shortcuts.run(args), nil)
            case "device_info":
                let args = try DeviceInfoArgs.parse(call.arguments)
                return (await deviceInfo.infoResult(args), nil)
            case "file_preview":
                let args = try FilePreviewArgs.parse(
                    call.arguments
                )
                return (
                    try await filePresence.preview(
                        args, files: files
                    ),
                    nil
                )
            case "file_print":
                let args = try FilePrintArgs.parse(call.arguments)
                return (
                    try await filePresence.print(
                        args, files: files
                    ),
                    nil
                )
            default:
                return (nil, .toolUnavailable("工具 \(call.tool) 尚未接线"))
            }
        } catch let error as DeviceToolError {
            return (nil, error)
        } catch {
            return (nil, .failed(error.localizedDescription))
        }
    }

    /// 写工具统一路径：账本命中→回放；未命中→执行
    /// （执行器内含回读验证）→记账→回结果
    private func writeWithLedger(
        key: String, tool: String,
        perform: () throws -> (objectID: String, result: JSONValue)
    ) throws -> (result: JSONValue?, error: DeviceToolError?) {
        let now = Date()
        let records = loadLedger()
        if let hit = WriteKeyLedger.lookup(records, key: key, now: now) {
            return (replayResult(tool: tool, objectID: hit.objectID), nil)
        }
        let (objectID, result) = try perform()
        saveLedger(WriteKeyLedger.recording(
            records, key: key, tool: tool, objectID: objectID, now: now
        ))
        return (result, nil)
    }

    /// 写工具统一路径的异步形（批二动作型工具用）：
    /// 账本语义与同步形逐字一致——命中回放、未命中
    /// 执行（引擎内含回读验证）后记账
    private func writeWithLedgerAsync(
        key: String, tool: String,
        perform: () async throws
            -> (objectID: String, result: JSONValue)
    ) async throws -> (result: JSONValue?, error: DeviceToolError?) {
        let now = Date()
        let records = loadLedger()
        if let hit = WriteKeyLedger.lookup(
            records, key: key, now: now
        ) {
            return (
                replayResult(tool: tool, objectID: hit.objectID),
                nil
            )
        }
        let (objectID, result) = try await perform()
        saveLedger(WriteKeyLedger.recording(
            records, key: key, tool: tool,
            objectID: objectID, now: now
        ))
        return (result, nil)
    }
}
