import Foundation

/// 本机连接器（0.34.0 批一，设计档 device-connectors-
/// design-20261110.md 定版）：手机自家的数据源——
/// 日历/提醒/通讯录/健康/家庭（蓝牙已决不做、不列）；
/// 0.36.14 同步制加照片/步数两件（无现调工具，通道
/// 只有同步副本，见 DeviceSync）。设备扩容批一（预
/// 制）再加剪贴板/文件两件：现调工具、限 App 自有
/// Documents 区；iOS 没有这两件的系统权限，状态恒
/// notApplicable、「允许智能体调用」开关即唯一的门。
/// 机制＝大厂工具调用制：授权与数据都留在手机，智能
/// 体需要时经 device-bridge 发工具调用、App 在线时现
/// 读现回；服务器不存设备数据副本，桥只留会话状态与
/// 调用审计（元数据）。本文件只管静态名册、权限状态
/// 枚举与桥口径映射、注册载荷组装（双层开关语义）、
/// 目录行状态文案与搜索纯函数；框架读取（EventKit/
/// Contacts）在 App 层，翻译成这里的枚举再渲染（与
/// LocalServices 的翻译层先例同构）。
///
/// 双层开关分清：系统权限（iOS 决定 App 能不能读）
/// 与「允许智能体调用」（App 内开关，决定桥能不能把
/// 调用转进来）是两件事——注册载荷里 permissions 报
/// 系统权限原态，tools 只列「权限可用且开关开」的工
/// 具；开关关掉的件，桥侧调用直接回 tool_unavailable，
/// 数据连被问的机会都没有。

/// 数据源标识（名册序即目录呈现序；rawValue 与桥
/// permissions 字典的键逐字一致）
public enum DeviceSourceID: String, CaseIterable, Identifiable, Sendable, Codable {
    case calendar
    case reminders
    case contacts
    /// 照片与步数（0.36.14 同步制）：无现调工具，智能
    /// 体的通道只有同步副本；与健康是两回事（步数走
    /// 手机计步、不碰健康权益）
    case photos
    case motion
    /// 剪贴板与 App 沙盒文件（设备扩容批一）：现调
    /// 工具两组；无系统权限概念，权限状态恒
    /// notApplicable，开关即唯一的门（名册文案说清）
    case clipboard
    case files
    /// 闹钟与本地通知（设备扩容批二，动作型）：有真
    /// 系统权限（AlarmKit / UserNotifications），走
    /// 权限开关终形态、不套批一的 notApplicable 档；
    /// 拉起目标靠白名单封闭，无系统权限（notApplicable）
    case alarm
    case notifications
    case opener
    case health
    case home

    public var id: String { rawValue }

    /// 桥 permissions 字典键（桥按此键查权限档）
    public var bridgeKey: String { rawValue }
}

/// 系统权限状态（App 层把 EK/CN 授权状态翻译成本枚
/// 举；桥只认 granted 一档放行，其余档原样进错误人话）
public enum DevicePermissionState: String, Equatable, Sendable {
    case notDetermined
    case granted
    /// 通讯录 iOS 18+ 受限授权：只给勾选子集（真实状
    /// 态档，呈现必须明说「部分联系人」）
    case limited
    /// 日历只写档（只写不读；本设计不用它做主路，仅如实显）
    case writeOnly
    case denied
    case restricted
    /// 无系统权限概念的数据源（剪贴板/沙盒文件）：
    /// 不是「已授权」——iOS 压根没有这道门，App 内
    /// 「允许智能体调用」开关是唯一的门。桥侧放行口
    /// 径与 granted 同（bridgeValue 报 granted），但
    /// 呈现必须用本档专名，不许冒充系统已授权
    case notApplicable

    /// 上报给桥 permissions 字典的值。桥以精确等于
    /// "granted" 放行调用；limited 的子集在 App 内由
    /// 系统框架天然收敛（只搜得到被勾选的联系人），
    /// 故报 granted 放行、另以 contactsScope 注解标明
    /// 子集（见 DeviceRegistration），不许因桥口径把
    /// 已授权子集误报成 permission_denied
    public var bridgeValue: String {
        switch self {
        case .granted, .limited, .notApplicable: return "granted"
        case .notDetermined: return "notDetermined"
        case .writeOnly: return "writeOnly"
        case .denied: return "denied"
        case .restricted: return "restricted"
        }
    }

    /// 状态人话（目录行与详情页共用一处）
    public var label: String { label(locale: AppLocale.uiLocale) }

    /// 状态人话的目录取词形（0.42.1 国际化长尾包）
    public func label(locale: Locale) -> String {
        switch self {
        case .notDetermined: return L10n.string("未授权", locale: locale)
        case .granted: return L10n.string("已授权", locale: locale)
        case .limited: return L10n.string("已授权 · 部分联系人", locale: locale)
        case .writeOnly: return L10n.string("仅写入权限", locale: locale)
        case .denied: return L10n.string("被拒", locale: locale)
        case .restricted: return L10n.string("受限制", locale: locale)
        case .notApplicable: return L10n.string("无需系统权限", locale: locale)
        }
    }

    /// 权限是否足以执行该件工具（读或写）
    public var isUsable: Bool {
        switch self {
        case .granted, .limited, .notApplicable: return true
        case .notDetermined, .writeOnly, .denied, .restricted:
            return false
        }
    }
}

/// 数据源静态条目（Core 单一真源，视图只渲染）
public struct DeviceSourceDescriptor: Identifiable, Equatable, Sendable {
    public let sourceID: DeviceSourceID
    public let name: String
    /// 一句说明（列表行副题与详情共用）
    public let blurb: String
    /// 瓷砖字形：SF Symbol 名（六件有系统符号可用，
    /// 与云服务字母瓷砖分开——设计档 §6.1 定版）
    public let tileSymbol: String
    public let tileColorHex: UInt32
    /// 施工批次：1＝本版已接线（执行器＋工具），
    /// 2＝待签名权益（健康/家庭，行在但不可点入假页面）
    public let batch: Int
    /// 调用去向口径（详情页状态头用）：这件被智能体
    /// 调用时回什么粒度的数据
    public let agentNote: String
    /// 一行能力短文案（0.36.3）：详情页「允许智能体
    /// 调用」开关的副文——agentNote 的一行版，只说
    /// 能干什么、不成段（详情页语法重做口径）
    public let capabilityLine: String
    /// 口径脚注（详情页尾）：这件的数据边界一句人话
    public let footnote: String

    public var id: String { sourceID.rawValue }

    /// 本版是否已接线（批二两件为 false）
    public var isWired: Bool { batch == 1 }

    public init(
        sourceID: DeviceSourceID, name: String, blurb: String,
        tileSymbol: String, tileColorHex: UInt32, batch: Int,
        agentNote: String, capabilityLine: String, footnote: String
    ) {
        self.sourceID = sourceID
        self.name = name
        self.blurb = blurb
        self.tileSymbol = tileSymbol
        self.tileColorHex = tileColorHex
        self.batch = batch
        self.agentNote = agentNote
        self.capabilityLine = capabilityLine
        self.footnote = footnote
    }
}

public enum DeviceSourceDirectory {
    /// 名册全集（当前界面语言版）
    public static var roster: [DeviceSourceDescriptor] {
        roster(locale: AppLocale.uiLocale)
    }

    /// 名册的目录取词形（0.42.1 国际化长尾包）：
    /// 源表 rosterSource 存简体源串（目录键），按
    /// locale 在构造时解析五件文本字段；sourceID/
    /// 字形/颜色/批次是语言无关口径，原样保留
    public static func roster(
        locale: Locale
    ) -> [DeviceSourceDescriptor] {
        rosterSource.map { entry in
            DeviceSourceDescriptor(
                sourceID: entry.sourceID,
                name: L10n.string(entry.name, locale: locale),
                blurb: L10n.string(entry.blurb, locale: locale),
                tileSymbol: entry.tileSymbol,
                tileColorHex: entry.tileColorHex,
                batch: entry.batch,
                agentNote: L10n.string(entry.agentNote, locale: locale),
                capabilityLine: L10n.string(
                    entry.capabilityLine, locale: locale
                ),
                footnote: L10n.string(entry.footnote, locale: locale)
            )
        }
    }

    /// 名册源表（呈现序：日历→提醒→通讯录→照片→
    /// 步数→剪贴板→文件→健康→家庭；蓝牙已决不做、
    /// 永不入册）；文本字段存简体源串、经 roster
    /// (locale:) 解析后才上屏
    private static let rosterSource: [DeviceSourceDescriptor] = [
        DeviceSourceDescriptor(
            sourceID: .calendar,
            name: "日历",
            blurb: "日程安排 · 现读现回，也可按确认新建/修改；开启同步后可整窗查询",
            tileSymbol: "calendar", tileColorHex: 0xD64541, batch: 1,
            agentNote: "智能体可调用：查询最长 14 天窗口内的日程，或按你在对话里的确认新建/修改日程（删除不做）；开启数据同步后可查过去 30 天到未来 90 天的副本",
            capabilityLine: "查 14 天内日程 · 按确认新建/修改",
            footnote: "被调用时现读现回；你开启「数据同步」后，过去 30 天到未来 90 天的日程清单（不含备注）会存一份在你自己的服务器上供智能体查询，可随时关掉并删除。"
        ),
        DeviceSourceDescriptor(
            sourceID: .reminders,
            name: "提醒事项",
            blurb: "待办提醒 · 现读未完成项，可按确认新建与勾完成",
            tileSymbol: "list.bullet", tileColorHex: 0xE8892B, batch: 1,
            agentNote: "智能体可调用：读取未完成提醒，或按你在对话里的确认新建提醒、勾完成（删除不做）",
            capabilityLine: "读未完成项 · 按确认新建/勾完成",
            footnote: "只回未完成项，不回已完成历史；你开启「数据同步」后，未完成清单会存一份在你自己的服务器上供智能体查询，可随时关掉并删除。"
        ),
        DeviceSourceDescriptor(
            sourceID: .contacts,
            name: "通讯录",
            blurb: "联系人 · 按关键词现查；开启同步后智能体可整本计数与统计，不写入",
            tileSymbol: "person.crop.circle", tileColorHex: 0x66727E,
            batch: 1,
            agentNote: "智能体可调用：按姓名关键词现查；开启数据同步后，还能查同步副本做整本计数、统计与翻页名单；不能新建或修改联系人",
            capabilityLine: "现查＋同步副本整本查 · 不写入",
            footnote: "现查时搜索在手机上完成、只有命中条目过境；你开启「数据同步」后，姓名、电话、邮箱、公司与分组会存一份在你自己的服务器上（备注、地址、生日、头像不同步），可随时关掉并删除。"
        ),
        DeviceSourceDescriptor(
            sourceID: .photos,
            name: "照片",
            blurb: "照片与视频的清单 · 开启同步后智能体可数总数、按月看分布",
            tileSymbol: "photo.fill", tileColorHex: 0xAF52DE,
            batch: 1,
            agentNote: "智能体可调用：读取同步副本里的照片清单统计（总数、按月、收藏与截图数），不取原图",
            capabilityLine: "查副本统计 · 不取原图",
            footnote: "同步只送每项的时间、类型、尺寸这类清单信息，原图与拍摄地点坐标不上传；关掉同步或删掉副本，智能体就查不到。"
        ),
        DeviceSourceDescriptor(
            sourceID: .motion,
            name: "步数",
            blurb: "手机计步的每日步数 · 开启同步后按日攒在你的服务器上",
            tileSymbol: "figure.walk", tileColorHex: 0x30B34D,
            batch: 1,
            agentNote: "智能体可调用：读取同步副本里的每日步数、距离与爬楼（来源是手机计步，不是健康 App）",
            capabilityLine: "查每日步数 · 手机计步",
            footnote: "数据来自手机自身的计步，只同步按日合计；它和「健康」里的日摘要是两条来源，不混在一起。"
        ),
        DeviceSourceDescriptor(
            sourceID: .clipboard,
            name: "剪贴板",
            blurb: "你复制的文字 · 智能体可读也可写；读取时系统会弹出粘贴提示",
            tileSymbol: "doc.on.clipboard", tileColorHex: 0x5856D6,
            batch: 1,
            agentNote: "智能体可调用：读取你当前剪贴板里的文字，或把一段文字放进你的剪贴板。这一件没有系统权限可开可关，详情页里的开关就是唯一的门；每次读取，系统都会弹出提示问你是否允许粘贴（这是苹果的规矩，绕不过去），App 不在前台时也读不到",
            capabilityLine: "读你复制的文字 · 也可写入",
            footnote: "剪贴板内容现读现回、不存副本；读取会触发系统粘贴提示，属正常现象。"
        ),
        DeviceSourceDescriptor(
            sourceID: .files,
            name: "文件",
            blurb: "OneDay 自己文件夹里的文件 · 智能体可列、读、写文本文件",
            tileSymbol: "folder.fill", tileColorHex: 0x0A84FF,
            batch: 1,
            agentNote: "智能体可调用：列出、读取、写入 OneDay 自己文件夹里的文本文件，文件夹之外的任何东西都碰不到。这一件没有系统权限可开可关，详情页里的开关就是唯一的门",
            capabilityLine: "只碰 OneDay 文件夹里的文件",
            footnote: "只限 OneDay 自己文件夹内的文本文件；单次读取/写入上限 256 KB，路径越出这个文件夹一律拒绝。"
        ),
        DeviceSourceDescriptor(
            sourceID: .alarm,
            name: "闹钟",
            blurb: "真闹钟 · 穿透静音与专注，到点全屏响铃",
            tileSymbol: "alarm.fill", tileColorHex: 0xFF9F0A,
            batch: 1,
            agentNote: "智能体可调用：按你在对话里的确认设定真闹钟（定点或倒计时），响铃穿透静音与专注模式；也能查看闹钟列表、取消它设过的闹钟。系统闹钟不带标题，标题由 OneDay 记在这台手机上对账",
            capabilityLine: "按确认设真闹钟 · 可查看/取消",
            footnote: "闹钟由系统托管，App 不在前台也照常响；标题只记在这台手机上，不出手机。"
        ),
        DeviceSourceDescriptor(
            sourceID: .notifications,
            name: "通知",
            blurb: "本地通知 · 到点在锁屏与通知中心提醒你",
            tileSymbol: "bell.fill", tileColorHex: 0xFF3B30,
            batch: 1,
            agentNote: "智能体可调用：按你在对话里的确认给你发一条本地通知（立即或延时）。待发通知最多 64 条，满了先报错、不硬塞",
            capabilityLine: "按确认发本地通知",
            footnote: "通知只发到你这台手机，不经服务器推送；系统通知权限关掉后就发不了。"
        ),
        DeviceSourceDescriptor(
            sourceID: .opener,
            name: "打开目标",
            blurb: "白名单页面与应用 · 只能打开登记过的目标",
            tileSymbol: "arrow.up.forward.app.fill", tileColorHex: 0x5E5CE6,
            batch: 1,
            agentNote: "智能体可调用：把你带到登记过的系统设置页或几个常用应用，只能打开白名单里的目标，任意链接一律不接。这一件没有系统权限可开可关，详情页里的开关就是唯一的门；打开后你会离开 OneDay，这是这个动作本身",
            capabilityLine: "打开白名单里的页面/应用",
            footnote: "只能打开白名单目标；打开即离开 OneDay，设备会话会随之断开，回到 App 后自动恢复。"
        ),
        DeviceSourceDescriptor(
            sourceID: .health,
            name: "健康",
            blurb: "步数/睡眠/心率等每日摘要 · 待签名权益到位后开通",
            tileSymbol: "heart.fill", tileColorHex: 0xE5484D, batch: 2,
            agentNote: "待开通：开通后智能体只能读每日摘要（步数/睡眠/静息心率/锻炼分钟），原始样本永不出手机",
            capabilityLine: "开通后只读每日摘要",
            footnote: "健康需要系统签名权益，当前安装方式下尚未开通；这里不会显示任何健康数据。"
        ),
        DeviceSourceDescriptor(
            sourceID: .home,
            name: "家庭",
            blurb: "家庭配件当前状态 · 待签名权益到位后开通",
            tileSymbol: "house.fill", tileColorHex: 0xE8A33D, batch: 2,
            agentNote: "待开通：开通后智能体只能现查配件当前状态，不提供任何控制（开灯/开锁等一律不做）",
            capabilityLine: "开通后只查状态 · 不做控制",
            footnote: "家庭需要系统签名权益，当前安装方式下尚未开通；这里不会显示任何配件状态。"
        ),
    ]

    public static func descriptor(
        _ id: DeviceSourceID
    ) -> DeviceSourceDescriptor {
        descriptor(id, locale: AppLocale.uiLocale)
    }

    /// 单件取词形（0.42.1 国际化长尾包）
    public static func descriptor(
        _ id: DeviceSourceID, locale: Locale
    ) -> DeviceSourceDescriptor {
        // 名册恒含五件全集，查不到即编程错误——以首
        // 条兜底而非崩溃（呈现层宁可显错条不许闪退）
        let entries = roster(locale: locale)
        return entries.first { $0.sourceID == id } ?? entries[0]
    }
}

// MARK: - 工具名册（与 device-bridge TOOLS 逐字对齐）

/// 工具定义：name 与桥 TOOLS 表逐字一致；source 是
/// 门控该工具的权限件（device_status 由桥本地应答、
/// 无 source）。isWrite 的写动作全必带
/// idempotencyKey（批二起含取消闹钟/发通知/打开
/// 目标：改变系统状态的动作都要能安全重放回执）。
public struct DeviceToolSpec: Equatable, Sendable {
    public let name: String
    public let source: DeviceSourceID?
    public let isWrite: Bool

    public init(name: String, source: DeviceSourceID?, isWrite: Bool) {
        self.name = name
        self.source = source
        self.isWrite = isWrite
    }
}

public enum DeviceToolRegistry {
    public static let all: [DeviceToolSpec] = [
        DeviceToolSpec(name: "device_status", source: nil, isWrite: false),
        DeviceToolSpec(name: "calendar_list_events", source: .calendar, isWrite: false),
        DeviceToolSpec(name: "calendar_create_event", source: .calendar, isWrite: true),
        DeviceToolSpec(name: "calendar_update_event", source: .calendar, isWrite: true),
        DeviceToolSpec(name: "reminders_list", source: .reminders, isWrite: false),
        DeviceToolSpec(name: "reminders_create", source: .reminders, isWrite: true),
        DeviceToolSpec(name: "reminders_complete", source: .reminders, isWrite: true),
        DeviceToolSpec(name: "contacts_search", source: .contacts, isWrite: false),
        DeviceToolSpec(name: "clipboard_get", source: .clipboard, isWrite: false),
        DeviceToolSpec(name: "clipboard_set", source: .clipboard, isWrite: true),
        DeviceToolSpec(name: "files_list", source: .files, isWrite: false),
        DeviceToolSpec(name: "files_read", source: .files, isWrite: false),
        DeviceToolSpec(name: "files_write", source: .files, isWrite: true),
        DeviceToolSpec(name: "alarm_set", source: .alarm, isWrite: true),
        DeviceToolSpec(name: "alarm_list", source: .alarm, isWrite: false),
        DeviceToolSpec(name: "alarm_cancel", source: .alarm, isWrite: true),
        DeviceToolSpec(name: "notify_post", source: .notifications, isWrite: true),
        DeviceToolSpec(name: "open_target", source: .opener, isWrite: true),
        DeviceToolSpec(name: "health_daily_summary", source: .health, isWrite: false),
        DeviceToolSpec(name: "home_status", source: .home, isWrite: false),
    ]

    public static func spec(_ name: String) -> DeviceToolSpec? {
        all.first { $0.name == name }
    }

    /// 本版 App 真能执行的工具（已接线数据源的十七
    /// 个；device_status 桥本地应答、不经手机，不在
    /// 此列；健康/家庭的工具定义先行、App 未接线，
    /// 不上报）
    public static let appExecutable: [DeviceToolSpec] = all.filter {
        guard let source = $0.source else { return false }
        return DeviceSourceDirectory.descriptor(source).isWired
    }
}

// MARK: - 注册载荷（双层开关语义的落点）

public enum DeviceRegistration {
    /// 组装 POST /device/session 的 permissions 与
    /// tools：permissions 报各件系统权限原态（桥据此
    /// 先行拦 permission_denied、不惊动手机）；tools
    /// 只列「批一已接线＋权限可用＋调用开关开」的工
    /// 具——开关关掉的件不列，桥回 tool_unavailable。
    /// 通讯录 limited 另以 contactsScope 注解标明子
    /// 集（桥原样透传进 device_status，智能体可见）
    public static func payload(
        permissions: [DeviceSourceID: DevicePermissionState],
        agentCallEnabled: [DeviceSourceID: Bool]
    ) -> (permissions: [String: String], tools: [String]) {
        var dict: [String: String] = [:]
        for id in DeviceSourceID.allCases {
            let state = permissions[id] ?? .notDetermined
            dict[id.bridgeKey] = state.bridgeValue
            if id == .contacts, state == .limited {
                dict["contactsScope"] = "limited"
            }
        }
        let tools = DeviceToolRegistry.appExecutable.filter { spec in
            guard let source = spec.source else { return false }
            let state = permissions[source] ?? .notDetermined
            return state.isUsable && (agentCallEnabled[source] ?? false)
        }.map(\.name)
        return (dict, tools)
    }
}

// MARK: - 目录行状态文案

public enum DeviceRowStatus {
    /// 目录行状态字（单一映射）：只由本地可验事实拼
    /// 成——系统权限＋调用开关＋设备会话是否在线＋
    /// 一句本地读数（有才拼，取不到不编）。批二两件
    /// 恒「待签名权益」——行在、状态如实、不点入假
    /// 页面。metric 例：「今天 3 个日程」。
    /// 0.36.10（真机判词 4 收口）：旧实现只凭权限＋
    /// 开关就拼「可调用」，把服务端未注册的半截说成
    /// 已通（详情页自家文案与之打架）。服务端注册状
    /// 态 App 验不了、不许写；「可调用」只许在会话
    /// 在线时出现——会话是 App 自家与桥的连接、在线
    /// 与否本地可验；开关开但会话离线如实降为「会话
    /// 未连接」。详情页与总览页共用本映射，不许两套
    /// 口径再打架
    public static func line(
        descriptor: DeviceSourceDescriptor,
        permission: DevicePermissionState,
        agentCallEnabled: Bool,
        sessionOnline: Bool,
        metric: String?,
        syncSegment: String? = nil,
        showsCallState: Bool = true,
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        guard descriptor.isWired else {
            return L10n.string("待签名权益", locale: locale)
        }
        switch permission {
        case .notDetermined:
            return L10n.string("未授权", locale: locale)
        case .denied, .restricted:
            return L10n.string("被拒", locale: locale)
        case .writeOnly:
            return L10n.string("仅写入权限 · 不能读取", locale: locale)
        case .granted, .limited, .notApplicable:
            var parts = [permission.label(locale: locale)]
            // 照片/步数没有现调通道（showsCallState
            // 为假）：不拼「可调用/调用已关」，它们的
            // 通道就是同步副本、由 syncSegment 说清
            if showsCallState {
                if !agentCallEnabled {
                    parts.append(L10n.string("调用已关", locale: locale))
                } else if sessionOnline {
                    parts.append(L10n.string("可调用", locale: locale))
                } else {
                    parts.append(L10n.string("会话未连接", locale: locale))
                }
            }
            if let syncSegment, !syncSegment.isEmpty {
                parts.append(syncSegment)
            }
            if let metric, !metric.isEmpty {
                parts.append(metric)
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: - 搜索（名称＋说明＋状态词，纯函数）

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func matches(
        _ descriptor: DeviceSourceDescriptor,
        statusLine: String, query: String
    ) -> Bool {
        let q = normalized(query)
        if q.isEmpty { return true }
        let fields = [
            descriptor.name, descriptor.blurb,
            descriptor.sourceID.rawValue, statusLine,
        ]
        return fields.contains { normalized($0).contains(q) }
    }

    /// 名册按搜索词过滤（保持名册序）；状态行由调用
    /// 方按当前状态逐件算好传入（映射只此一处）
    public static func filtered(
        statusLines: [DeviceSourceID: String], query: String,
        locale: Locale = AppLocale.uiLocale
    ) -> [DeviceSourceDescriptor] {
        DeviceSourceDirectory.roster(locale: locale).filter { descriptor in
            matches(
                descriptor,
                statusLine: statusLines[descriptor.sourceID] ?? "",
                query: query
            )
        }
    }
}
