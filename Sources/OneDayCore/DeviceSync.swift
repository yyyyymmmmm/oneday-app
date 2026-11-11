import CryptoKit
import Foundation

/// 本地数据同步制（0.36.14，规格 device-sync-design-
/// 20261110.md 定版）：记录型五件（通讯录/日历/提醒/
/// 照片/步数）把最小化副本同步到用户自己的伴生服务，
/// 智能体查库回答。本文件只放纯逻辑：数据集名册（与
/// 伴生 device_sync.DATASETS 逐字对齐）、通讯录清单
/// 指纹、五件记录的 JSON 契约形状（键名与伴生
/// _materialize 逐字对齐、钉测防漂移）、日历窗口、
/// 提醒聚合、节流/前台计划、批次切分、状态回执解码
/// 与呈现文案。框架读取（Contacts/EventKit/PhotoKit/
/// CoreMotion）与网络在 App 层。
///
/// 红线口径：新鲜度必须明示——副本答案永远带同步时
/// 刻；权限撤销＝完全停供（2026-11-10 21:58 拍板，
/// 桥侧 REVOKED_SERVES_COPY=False 定死，App 侧只如
/// 实上报与呈现）；照片只同步元数据索引，不含原图
/// 与坐标（同日拍板：授权了就给全量索引）。

// MARK: - 数据集名册

public enum DeviceSyncDataset: String, CaseIterable, Identifiable, Sendable, Codable {
    case contacts
    case calendar
    case reminders
    case photos
    case motion

    public var id: String { rawValue }

    /// 桥 dataset 名（与 DATASETS 逐字一致）
    public var bridgeName: String { rawValue }

    /// 对应的连接器数据源（五件都是已接线数据源）
    public var sourceID: DeviceSourceID {
        switch self {
        case .contacts: return .contacts
        case .calendar: return .calendar
        case .reminders: return .reminders
        case .photos: return .photos
        case .motion: return .motion
        }
    }

    public static func fromSource(
        _ source: DeviceSourceID
    ) -> DeviceSyncDataset? {
        switch source {
        case .contacts: return .contacts
        case .calendar: return .calendar
        case .reminders: return .reminders
        case .photos: return .photos
        case .motion: return .motion
        case .health, .home, .clipboard, .files,
             .alarm, .notifications, .opener: return nil
        }
    }

    /// 数据集名（与伴生 DATASET_LABEL 同字）
    public var label: String { label(locale: AppLocale.uiLocale) }

    /// 数据集名的目录取词形（0.42.1 国际化长尾
    /// 包）：本名只作呈现（删除确认文案与行标题，
    /// 已核无与服务端串比对的用法——线上键是枚
    /// 举 rawValue）；「与伴生同字」是命名约定、
    /// 非协议匹配
    public func label(locale: Locale) -> String {
        switch self {
        case .contacts: return L10n.string("通讯录", locale: locale)
        case .calendar: return L10n.string("日历", locale: locale)
        case .reminders: return L10n.string("提醒事项", locale: locale)
        case .photos: return L10n.string("照片", locale: locale)
        case .motion: return L10n.string("步数", locale: locale)
        }
    }

    /// 条数单位（状态呈现用）
    public var countUnit: String { countUnit(locale: AppLocale.uiLocale) }

    /// 条数单位的目录取词形（0.42.0：单位词随界面
    /// 语言；呈现函数把自己的 locale 透传到这里）
    public func countUnit(locale: Locale) -> String {
        switch self {
        case .contacts: return L10n.string("人", locale: locale)
        case .calendar: return L10n.string("条", locale: locale)
        case .reminders: return L10n.string("项", locale: locale)
        case .photos: return L10n.string("项", locale: locale)
        case .motion: return L10n.string("天", locale: locale)
        }
    }

    /// 前台增量节流下限（规格 §3.2）：记录型 15 分
    /// 钟、步数 1 小时（日聚合变化慢）
    public var throttleSeconds: TimeInterval {
        switch self {
        case .motion: return 3600
        case .contacts, .calendar, .reminders, .photos:
            return 15 * 60
        }
    }
}

// MARK: - 通讯录指纹与清单（规格 §3.3 清单比对）

/// 联系人关键字段指纹：姓名/公司/电话/邮箱规整后排
/// 序拼接再 SHA-256。同输入必同输出（跨启动稳定）；
/// 任一关键字段变了指纹必变。标签随值一并入纹——
/// 只改标签也算有变，宁可多传一条不许漏变。
public enum ContactFingerprint {
    public static func make(
        displayName: String, familyName: String?,
        givenName: String?, organization: String?,
        phones: [SyncLabeledValue], emails: [SyncLabeledValue]
    ) -> String {
        func trimmed(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let phonePart = phones
            .map { "\(trimmed($0.label))=\(trimmed($0.value))" }
            .sorted()
            .joined(separator: ",")
        let emailPart = emails
            .map { "\(trimmed($0.label))=\(trimmed($0.value).lowercased())" }
            .sorted()
            .joined(separator: ",")
        let canonical = [
            trimmed(displayName), trimmed(familyName),
            trimmed(givenName), trimmed(organization),
            phonePart, emailPart,
        ].joined(separator: "\u{1E}")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// 带标签的值（电话/邮箱）：键名 label/value 与伴
/// 生查库侧消费口径逐字一致
public struct SyncLabeledValue: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var json: [String: JSONValue] {
        ["label": .string(label), "value": .string(value)]
    }
}

/// 清单条目（送 /device/sync/manifest 比对的轻量行）
public struct ContactManifestEntry: Equatable, Sendable {
    public let id: String
    public let fingerprint: String

    public init(id: String, fingerprint: String) {
        self.id = id
        self.fingerprint = fingerprint
    }

    public var json: [String: JSONValue] {
        ["id": .string(id), "fingerprint": .string(fingerprint)]
    }
}

/// 通讯录同步记录（字段最小化，规格 §2.2：备注/地
/// 址/生日/头像永不进副本）
public struct SyncContactRecord: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let familyName: String?
    public let givenName: String?
    public let organization: String?
    public let phones: [SyncLabeledValue]
    public let emails: [SyncLabeledValue]
    public let groups: [String]

    public init(
        id: String, displayName: String, familyName: String?,
        givenName: String?, organization: String?,
        phones: [SyncLabeledValue], emails: [SyncLabeledValue],
        groups: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.familyName = familyName
        self.givenName = givenName
        self.organization = organization
        self.phones = phones
        self.emails = emails
        self.groups = groups
    }

    public var fingerprint: String {
        ContactFingerprint.make(
            displayName: displayName, familyName: familyName,
            givenName: givenName, organization: organization,
            phones: phones, emails: emails
        )
    }

    public var manifestEntry: ContactManifestEntry {
        ContactManifestEntry(id: id, fingerprint: fingerprint)
    }

    public var json: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "displayName": .string(displayName),
            "phones": .array(phones.map { .object($0.json) }),
            "emails": .array(emails.map { .object($0.json) }),
            "groups": .array(groups.map { .string($0) }),
            "fingerprint": .string(fingerprint),
        ]
        if let familyName { object["familyName"] = .string(familyName) }
        if let givenName { object["givenName"] = .string(givenName) }
        if let organization { object["organization"] = .string(organization) }
        return object
    }
}

// MARK: - 日历窗口与记录（规格 §3.4 滚动窗口整换）

public enum SyncCalendarWindow {
    /// 窗口＝[今天 −30 天，今天 +90 天]（按本地日历
    /// 的整天计：起点为 −30 天的零点，终点为 +90 天
    /// 的次日零点、不含）
    public static func bounds(
        now: Date, calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(
            byAdding: .day, value: -30, to: today
        ) ?? today
        let endDay = calendar.date(
            byAdding: .day, value: 90, to: today
        ) ?? today
        let end = calendar.date(
            byAdding: .day, value: 1, to: endDay
        ) ?? endDay
        return (start, end)
    }
}

/// 日历同步记录（一行一个具体场次，重复事件按场次
/// 展开；occurrenceId＝事件标识＋场次开始时刻）
public struct SyncCalendarRecord: Equatable, Sendable {
    public let occurrenceId: String
    public let eventId: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let calendarName: String
    public let location: String?

    public init(
        occurrenceId: String, eventId: String, title: String,
        start: Date, end: Date, allDay: Bool,
        calendarName: String, location: String?
    ) {
        self.occurrenceId = occurrenceId
        self.eventId = eventId
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.calendarName = calendarName
        self.location = location
    }

    public var json: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "occurrenceId": .string(occurrenceId),
            "eventId": .string(eventId),
            "title": .string(title),
            "start": .string(DeviceISO8601.format(start)),
            "end": .string(DeviceISO8601.format(end)),
            "allDay": .bool(allDay),
            "calendarName": .string(calendarName),
        ]
        if let location, !location.isEmpty {
            object["location"] = .string(location)
        }
        return object
    }
}

// MARK: - 提醒记录与聚合（规格 §3.4 未完成全量整换）

public struct SyncReminderRecord: Equatable, Sendable {
    public let id: String
    public let title: String
    public let due: Date?
    public let priority: Int
    public let listName: String

    public init(
        id: String, title: String, due: Date?,
        priority: Int, listName: String
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.priority = priority
        self.listName = listName
    }

    public var json: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "title": .string(title),
            "priority": .number(Double(priority)),
            "listName": .string(listName),
        ]
        if let due {
            object["due"] = .string(DeviceISO8601.format(due))
        }
        return object
    }
}

/// 提醒聚合的输入行（全量提醒的最小投影）
public struct SyncReminderInput: Equatable, Sendable {
    public let due: Date?
    public let isCompleted: Bool
    public let completionDate: Date?

    public init(
        due: Date?, isCompleted: Bool, completionDate: Date?
    ) {
        self.due = due
        self.isCompleted = isCompleted
        self.completionDate = completionDate
    }
}

/// 提醒聚合（随完成确认一并送出，伴生存元信息）：
/// 今日已完成数＋同步时刻的已过期未完成数。过期口
/// 径与伴生计数同款：未完成且到期早于今天零点
public struct SyncReminderAggregates: Equatable, Sendable {
    public let todayCompleted: Int
    public let overdueCount: Int

    public static func compute(
        _ inputs: [SyncReminderInput], now: Date,
        calendar: Calendar = .current
    ) -> SyncReminderAggregates {
        let dayStart = calendar.startOfDay(for: now)
        var todayCompleted = 0
        var overdue = 0
        for input in inputs {
            if input.isCompleted {
                if let done = input.completionDate, done >= dayStart {
                    todayCompleted += 1
                }
            } else if let due = input.due, due < dayStart {
                overdue += 1
            }
        }
        return SyncReminderAggregates(
            todayCompleted: todayCompleted, overdueCount: overdue
        )
    }

    public var json: [String: JSONValue] {
        [
            "todayCompleted": .number(Double(todayCompleted)),
            "overdueCount": .number(Double(overdueCount)),
        ]
    }
}

// MARK: - 照片索引记录（规格 §2.2 全量元数据索引）

/// 照片同步记录（一行一个资产的元数据；原图、缩略
/// 图与经纬度永不进副本——hasLocation 只记有/无）
public struct SyncPhotoRecord: Equatable, Sendable {
    public let assetId: String
    public let createdAt: Date
    /// "photo" / "video"（伴生按月统计以 video 分桶，
    /// 其余计照片）
    public let mediaType: String
    /// 如 "screenshot" / "livePhoto"，无则 nil
    public let subtype: String?
    public let width: Int
    public let height: Int
    public let durationSec: Double?
    public let isFavorite: Bool
    public let albumName: String?
    public let hasLocation: Bool

    public init(
        assetId: String, createdAt: Date, mediaType: String,
        subtype: String?, width: Int, height: Int,
        durationSec: Double?, isFavorite: Bool,
        albumName: String?, hasLocation: Bool
    ) {
        self.assetId = assetId
        self.createdAt = createdAt
        self.mediaType = mediaType
        self.subtype = subtype
        self.width = width
        self.height = height
        self.durationSec = durationSec
        self.isFavorite = isFavorite
        self.albumName = albumName
        self.hasLocation = hasLocation
    }

    public var json: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "assetId": .string(assetId),
            "createdAt": .string(DeviceISO8601.format(createdAt)),
            "mediaType": .string(mediaType),
            "width": .number(Double(width)),
            "height": .number(Double(height)),
            "isFavorite": .bool(isFavorite),
            "hasLocation": .bool(hasLocation),
        ]
        if let subtype { object["subtype"] = .string(subtype) }
        if let durationSec {
            object["durationSec"] = .number(durationSec)
        }
        if let albumName { object["albumName"] = .string(albumName) }
        return object
    }
}

// MARK: - 步数日聚合记录（规格 §3.4 按日合并）

public struct SyncMotionDayRecord: Equatable, Sendable {
    /// 本地日期 "yyyy-MM-dd"
    public let date: String
    public let steps: Int
    public let distanceM: Double?
    public let flights: Int?

    public init(
        date: String, steps: Int,
        distanceM: Double?, flights: Int?
    ) {
        self.date = date
        self.steps = steps
        self.distanceM = distanceM
        self.flights = flights
    }

    public var json: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "date": .string(date),
            "steps": .number(Double(steps)),
            "source": .string("手机计步"),
        ]
        if let distanceM { object["distanceM"] = .number(distanceM) }
        if let flights { object["flights"] = .number(Double(flights)) }
        return object
    }
}

/// 步数同步计划：最近 N 天（含今天）的逐日区间，
/// 按日期升序（旧→今）。手机计步自身只留最近约
/// 7 天，副本靠历次合并攒长历史
public enum SyncMotionPlan {
    public static let dayCount = 7

    public static func dayRanges(
        now: Date, days: Int = dayCount,
        calendar: Calendar = .current
    ) -> [(day: String, start: Date, end: Date)] {
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var ranges: [(day: String, start: Date, end: Date)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let start = calendar.date(
                byAdding: .day, value: -offset, to: today
            ), let end = calendar.date(
                byAdding: .day, value: 1, to: start
            ) else { continue }
            ranges.append((
                day: formatter.string(from: start),
                start: start, end: end
            ))
        }
        return ranges
    }
}

// MARK: - 自动同步计划与节流（规格 §3.2，0.36.18 改自动制）

public enum SyncForegroundDecision: Equatable, Sendable {
    case sync
    case skipThrottled
    case blockedPermission
}

/// 自动同步决策（纯函数，0.36.18）：同步的唯一门
/// 是系统权限——授权即自动同步，0.36.16 的同步开
/// 关退出判定（blockedSwitchOff 随之退役）。节流
/// 按数据集下限；有未同步写入标记、或收到系统变
/// 更记号（changePending）时无视节流立即对账；
/// 从未同步过（lastSuccessAt 为 nil）恒到期
public enum DeviceSyncPlanner {
    public static func foregroundDecision(
        dataset: DeviceSyncDataset,
        permissionUsable: Bool,
        lastSuccessAt: Date?, pendingWrite: Bool,
        changePending: Bool = false, now: Date
    ) -> SyncForegroundDecision {
        guard permissionUsable else { return .blockedPermission }
        if pendingWrite || changePending { return .sync }
        guard let lastSuccessAt else { return .sync }
        return now.timeIntervalSince(lastSuccessAt)
            >= dataset.throttleSeconds
            ? .sync : .skipThrottled
    }
}

// MARK: - 批次切分（规格 §3.1 每批 ≤500 条）

public enum SyncBatchPlan {
    public static let batchSize = 500

    /// 把 total 条切成逐批区间；total 为 0 时回一
    /// 个空区间——完成确认需要至少一次批次登记，
    /// 空批次正是「本轮无变化」的登记方式
    public static func ranges(total: Int) -> [Range<Int>] {
        guard total > 0 else { return [0..<0] }
        var out: [Range<Int>] = []
        var start = 0
        while start < total {
            let end = min(start + batchSize, total)
            out.append(start..<end)
            start = end
        }
        return out
    }
}

// MARK: - 状态回执（GET /device/sync/status 解码）

/// 一个数据集在伴生侧的同步状态（状态面只出状态、
/// 永不出记录内容）。两种形状都要吃：已同步（全字
/// 段）与从未同步（只有 dataset/label/synced=false
/// ／条数 0／权限态／未同步写入标记）
public struct DeviceSyncDatasetStatus: Equatable, Sendable {
    public let dataset: DeviceSyncDataset
    public let synced: Bool
    public let syncedAt: Date?
    /// 伴生生成的人话新鲜度（在手时呈现优先用它，
    /// 与工具结果外壳同一份实现侧文案）
    public let freshness: String?
    public let expired: Bool
    public let itemCount: Int
    /// "full" / "limited" / nil（从未同步）
    public let authRange: String?
    /// "granted" / "revoked" / nil
    public let permissionState: String?
    public let pendingWrite: Bool
    public let syncing: Bool
    public let lastError: String?
    public let coverageStart: String?
    public let coverageEnd: String?
    public let reminderTodayCompleted: Int?
    public let reminderOverdueAtSync: Int?

    public var isRevoked: Bool { permissionState == "revoked" }
    public var isLimited: Bool { authRange == "limited" }

    public init(
        dataset: DeviceSyncDataset, synced: Bool,
        syncedAt: Date?, freshness: String?, expired: Bool,
        itemCount: Int, authRange: String?,
        permissionState: String?, pendingWrite: Bool,
        syncing: Bool, lastError: String?,
        coverageStart: String?, coverageEnd: String?,
        reminderTodayCompleted: Int?,
        reminderOverdueAtSync: Int?
    ) {
        self.dataset = dataset
        self.synced = synced
        self.syncedAt = syncedAt
        self.freshness = freshness
        self.expired = expired
        self.itemCount = itemCount
        self.authRange = authRange
        self.permissionState = permissionState
        self.pendingWrite = pendingWrite
        self.syncing = syncing
        self.lastError = lastError
        self.coverageStart = coverageStart
        self.coverageEnd = coverageEnd
        self.reminderTodayCompleted = reminderTodayCompleted
        self.reminderOverdueAtSync = reminderOverdueAtSync
    }
}

public enum DeviceSyncStatusResponse {
    /// 解码状态面回执：结构对不上回空字典（呈现层
    /// 退回本地回执，不猜不编）
    public static func decode(
        _ data: Data
    ) -> [DeviceSyncDataset: DeviceSyncDatasetStatus] {
        guard let root = try? JSONSerialization.jsonObject(
                with: data
              ) as? [String: Any],
              let datasets = root["datasets"] as? [String: Any]
        else { return [:] }
        var out: [DeviceSyncDataset: DeviceSyncDatasetStatus] = [:]
        for dataset in DeviceSyncDataset.allCases {
            guard let raw = datasets[dataset.bridgeName]
                    as? [String: Any] else { continue }
            out[dataset] = parse(dataset: dataset, raw: raw)
        }
        return out
    }

    private static func parse(
        dataset: DeviceSyncDataset, raw: [String: Any]
    ) -> DeviceSyncDatasetStatus {
        let coverage = raw["coverage"] as? [String: Any]
        let aggregates = raw["aggregates"] as? [String: Any]
        return DeviceSyncDatasetStatus(
            dataset: dataset,
            synced: raw["synced"] as? Bool ?? false,
            syncedAt: (raw["synced_at"] as? String)
                .flatMap(DeviceISO8601.parse),
            freshness: raw["freshness"] as? String,
            expired: raw["expired"] as? Bool ?? false,
            itemCount: (raw["item_count"] as? NSNumber)?.intValue ?? 0,
            authRange: raw["auth_range"] as? String,
            permissionState: raw["permission_state"] as? String,
            pendingWrite: raw["pending_write"] as? Bool ?? false,
            syncing: raw["syncing"] as? Bool ?? false,
            lastError: raw["last_error"] as? String,
            coverageStart: coverage?["start"] as? String,
            coverageEnd: coverage?["end"] as? String,
            reminderTodayCompleted:
                (aggregates?["today_completed"] as? NSNumber)?.intValue,
            reminderOverdueAtSync:
                (aggregates?["overdue_at_sync"] as? NSNumber)?.intValue
        )
    }
}

// MARK: - 呈现文案（状态字与新鲜度，规格 §6.2）

public enum DeviceSyncPresentation {
    /// 时刻短标（与伴生 _day_label 同口径）：「今天
    /// 09:41」「昨晚 23:10」「昨天 09:41」「11月
    /// 3日 09:41」
    public static func dayLabel(
        _ date: Date, now: Date, calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        // 0.42.0：相对日词走目录、月日走系统格式器
        // （钉 locale），档位与旧口径不变
        let time = DisplayDate.timeOnly(date, calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) {
            return L10n.format("今天 %@", locale: locale, time)
        }
        if let yesterday = calendar.date(
            byAdding: .day, value: -1, to: now
           ), calendar.isDate(date, inSameDayAs: yesterday) {
            let hour = calendar.component(.hour, from: date)
            return hour >= 18
                ? L10n.format("昨晚 %@", locale: locale, time)
                : L10n.format("昨天 %@", locale: locale, time)
        }
        let monthDay = date.formatted(
            Date.FormatStyle(
                locale: locale, calendar: calendar,
                timeZone: calendar.timeZone
            ).month().day()
        )
        return "\(monthDay) \(time)"
    }

    /// 本地新鲜度句（与伴生 freshness_text 同措辞；
    /// 桥状态在手时优先用桥的那份，本函数是状态取
    /// 不到时的本地兜底——同一件事不许两种说法）
    public static func freshnessLine(
        syncedAt: Date, now: Date, pendingWrite: Bool,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        // 0.42.0：整句模板走目录（键「数据截至%@…」
        // 一组），措辞与伴生 freshness_text 同步本地化
        let label = dayLabel(syncedAt, now: now, calendar: calendar, locale: locale)
        let age = now.timeIntervalSince(syncedAt)
        var text: String
        if age > 24 * 3600 {
            text = L10n.format("数据截至%@，已过期", locale: locale, label)
        } else if age < 90 {
            text = L10n.format("数据截至%@，刚刚同步", locale: locale, label)
        } else if age < 3600 {
            text = L10n.format(
                "数据截至%@，约 %@ 分钟前同步", locale: locale,
                label, String(max(1, Int(age / 60)))
            )
        } else if calendar.isDate(syncedAt, inSameDayAs: now) {
            text = L10n.format(
                "数据截至%@，约 %@ 小时前同步", locale: locale,
                label, String(Int(age / 3600))
            )
        } else {
            text = L10n.format("数据截至%@", locale: locale, label)
        }
        if pendingWrite {
            text += L10n.string("；刚写入的一条可能还没反映在副本里", locale: locale)
        }
        return text
    }

    /// 目录行/总览行的同步段（拼在 DeviceRowStatus
    /// 后面）：只由「权限态＋服务器状态」拼（0.36.18
    /// 起授权即同步、没有独立开关态可报）；服务器
    /// 有副本就如实报副本（权限已关时桥状态带撤销
    /// 记号），没副本才退本地语义，不编条数
    public static func segment(
        dataset: DeviceSyncDataset,
        status: DeviceSyncDatasetStatus?,
        authorized: Bool, now: Date,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        if let status, status.synced, let syncedAt = status.syncedAt {
            var text = L10n.format(
                "已同步 %lld %@", locale: locale,
                status.itemCount, dataset.countUnit(locale: locale)
            ) + " · \(dayLabel(syncedAt, now: now, calendar: calendar, locale: locale))"
            if status.isLimited { text += L10n.string(" · 部分", locale: locale) }
            if status.expired { text += L10n.string(" · 已过期", locale: locale) }
            if status.isRevoked { text += L10n.string(" · 权限已撤销", locale: locale) }
            return text
        }
        return authorized
            ? L10n.string("还没有同步", locale: locale)
            : L10n.string("未授权", locale: locale)
    }

    /// 详情页副题（0.36.18，一句封顶）：副本在哪、
    /// 谁来查、授权后自动同步——三件事一句说清，
    /// 页面不许再出现第二段口径文字（旧的逐件脚注
    /// 段随本版退役）
    public static var detailSubtitle: String {
        detailSubtitle(locale: AppLocale.uiLocale)
    }

    /// 详情页副题的目录取词形（0.42.1 国际化长尾包）
    public static func detailSubtitle(locale: Locale) -> String {
        L10n.string(
            "副本在你自己的服务器上，智能体查副本；开着权限就自动同步",
            locale: locale
        )
    }

    /// 授权范围人话（详情页同步区用）
    public static func rangeLine(
        _ status: DeviceSyncDatasetStatus?,
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        guard let status, status.synced else { return nil }
        return status.isLimited
            ? L10n.string("部分（不是全部）", locale: locale)
            : L10n.string("全部", locale: locale)
    }
}

// MARK: - 权限开关映射（0.36.18，用户 00:03–00:05 三连定版）

/// 拨动权限开关时的处置（用户亲定语义）：开——
/// 未决定时当场发那一次系统授权请求；已决定为不
/// 可用（被拒/受限/仅写入，系统不再弹窗）跳系统
/// 设置本 App 页。关——App 关不掉已授出的系统权
/// 限，一律跳系统设置由用户亲手关，绝不假装已关。
/// 已授权时拨「开」不会发生（开关本就呈开态），
/// .alreadyOn 只作兜底
public enum DeviceSyncPermissionAction: Equatable, Sendable {
    case requestPermission
    case openSettings
    case alreadyOn
}

/// 开权限的动作序（先落账纪律的映射形）：先把
/// 「正在开启」落进同步日志（请求中途被拒/被打
/// 断也留痕），再发那一次系统请求；授权到手，自
/// 动同步随即启动——用户没有第二个开关可点
public enum DeviceSyncPermissionStep: Equatable, Sendable {
    case logEnabling
    case requestPermission
    case startSyncWhenGranted
}

/// 权限开关语义的纯映射（视图与控制器共用一处，
/// 0.36.18）：记录型五件的详情页只剩这一个开关，
/// 它绑的就是系统权限本身——显示永远回读真实状
/// 态，同步与智能体供给都只看这一件事（授权即自
/// 动同步、即可查；权限关＝完全停供，旧规不变）。
/// 0.36.16 的同步开关、首启区、权限状态行与
/// agentCanQuery 双因子判据至此整组退役
public enum DeviceSyncControl {
    public static let permissionEnableSequence:
        [DeviceSyncPermissionStep] = [
            .logEnabling, .requestPermission, .startSyncWhenGranted,
        ]

    /// 开关呈开还是关：只认真实权限状态，不认任
    /// 何本地偏好
    public static func switchIsOn(
        _ permission: DevicePermissionState
    ) -> Bool {
        permission.isUsable
    }

    /// 智能体能不能用这一件：与开关同源——权限
    /// 可用即可查；权限关即完全停供
    public static func agentCanQuery(
        permission: DevicePermissionState
    ) -> Bool {
        permission.isUsable
    }

    /// 用户把开关拨到「开」
    public static func toggleOnAction(
        for permission: DevicePermissionState
    ) -> DeviceSyncPermissionAction {
        switch permission {
        case .granted, .limited: return .alreadyOn
        case .notDetermined: return .requestPermission
        case .writeOnly, .denied, .restricted: return .openSettings
        case .notApplicable:
            // 同步数据集永不取此态（只有剪贴板/文件
            // 两件无系统权限、且不在同步面）；臂仅为
            // 穷尽——无系统门可求，视同已开
            return .alreadyOn
        }
    }

    /// 用户把开关拨到「关」：跳系统设置
    public static func toggleOffAction(
    ) -> DeviceSyncPermissionAction {
        .openSettings
    }
}

// MARK: - 同步日志（0.36.16，用户 23:20 拍板）

/// 同步日志条目（逐数据集一本、本地持久化）：事
/// 件时刻取真实发生时刻，失败不隐藏。kind 决定
/// 呈现行，added/total 只在 syncCompleted 有值，
/// reason 只在 syncFailed 有值
public struct DeviceSyncLogEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case enabling
        case enabled
        case disabled
        case syncStarted
        case syncCompleted
        case syncFailed
        case permissionRevoked
        case permissionRestored
        case copyDeleted
    }

    public let at: Date
    public let kind: Kind
    public let added: Int?
    public let total: Int?
    public let reason: String?

    public init(
        at: Date, kind: Kind, added: Int? = nil,
        total: Int? = nil, reason: String? = nil
    ) {
        self.at = at
        self.kind = kind
        self.added = added
        self.total = total
        self.reason = reason
    }
}

/// 日志本的纯算术：新在上、上限截断、完成条的
/// 「新增」按总量差算（整本重传也只报真实增量，
/// 变少报 0 不报负数）
public enum DeviceSyncLogBook {
    public static let cap = 50

    public static func appending(
        _ entries: [DeviceSyncLogEntry], _ entry: DeviceSyncLogEntry
    ) -> [DeviceSyncLogEntry] {
        Array(([entry] + entries).prefix(cap))
    }

    public static func addedCount(
        previousTotal: Int?, newTotal: Int
    ) -> Int {
        max(0, newTotal - (previousTotal ?? 0))
    }
}

/// 日志行文案（一处真源，视图只渲染）。kind 里的
/// enabled/disabled 是 0.36.16 存量条目（同步开关
/// 时代），新流程不再产生——开关动作改由权限请求
/// 与 permissionRevoked/Restored 记账；回读呈现不
/// 变，存量账不许丢
public enum DeviceSyncLogPresentation {
    /// 行首时间字（0.36.18 日志改版，用户亲定形
    /// 态）：时间打头——「今天 00:01」「昨天
    /// 23:58」「11月3日 09:41」，与状态字同一套
    /// 时刻短标（一处真源，不另起格式）
    public static func timeText(
        for entry: DeviceSyncLogEntry, now: Date,
        calendar: Calendar = .current,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        DeviceSyncPresentation.dayLabel(
            entry.at, now: now, calendar: calendar, locale: locale
        )
    }

    /// 失败行标记（0.36.18）：整本日志只有失败行
    /// 带红点＋红字事由，其余全中性
    public static func isFailure(
        _ entry: DeviceSyncLogEntry
    ) -> Bool {
        entry.kind == .syncFailed
    }

    public static func line(
        for entry: DeviceSyncLogEntry,
        dataset: DeviceSyncDataset,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        // 0.42.0：日志行模板走目录；失败原因等条目
        // 自带文本是记录内容、不译
        switch entry.kind {
        case .enabling:
            return L10n.string("正在开启同步", locale: locale)
        case .enabled:
            return L10n.string("同步已开启", locale: locale)
        case .disabled:
            return L10n.string("同步已关闭，智能体用不了这一件了", locale: locale)
        case .syncStarted:
            return L10n.string("开始同步", locale: locale)
        case .syncCompleted:
            let unit = dataset.countUnit(locale: locale)
            return L10n.format(
                "同步完成：新增 %lld %@，", locale: locale,
                entry.added ?? 0, unit
            ) + L10n.format(
                "共 %lld %@", locale: locale, entry.total ?? 0, unit
            )
        case .syncFailed:
            return L10n.format(
                "同步没成：%@", locale: locale,
                entry.reason ?? L10n.string("原因没记下来", locale: locale)
            )
        case .permissionRevoked:
            return L10n.string("系统权限被关掉了：已停供，智能体查不到这一件了", locale: locale)
        case .permissionRestored:
            return L10n.string("系统权限恢复了", locale: locale)
        case .copyDeleted:
            return L10n.string("服务器上的副本已删除", locale: locale)
        }
    }
}
