import Foundation

/// 本机连接器（0.34.0 批一，设计档 device-connectors-
/// design-20261110.md 定版）：手机自家的五件数据源——
/// 日历/提醒/通讯录/健康/家庭（蓝牙已决不做、不列）。
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

    /// 上报给桥 permissions 字典的值。桥以精确等于
    /// "granted" 放行调用；limited 的子集在 App 内由
    /// 系统框架天然收敛（只搜得到被勾选的联系人），
    /// 故报 granted 放行、另以 contactsScope 注解标明
    /// 子集（见 DeviceRegistration），不许因桥口径把
    /// 已授权子集误报成 permission_denied
    public var bridgeValue: String {
        switch self {
        case .granted, .limited: return "granted"
        case .notDetermined: return "notDetermined"
        case .writeOnly: return "writeOnly"
        case .denied: return "denied"
        case .restricted: return "restricted"
        }
    }

    /// 状态人话（目录行与详情页共用一处）
    public var label: String {
        switch self {
        case .notDetermined: return "未授权"
        case .granted: return "已授权"
        case .limited: return "已授权 · 部分联系人"
        case .writeOnly: return "仅写入权限"
        case .denied: return "被拒"
        case .restricted: return "受限制"
        }
    }

    /// 权限是否足以执行该件工具（读或写）
    public var isUsable: Bool {
        switch self {
        case .granted, .limited: return true
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
    /// 口径脚注（详情页尾）：这件的数据边界一句人话
    public let footnote: String

    public var id: String { sourceID.rawValue }

    /// 本版是否已接线（批二两件为 false）
    public var isWired: Bool { batch == 1 }

    public init(
        sourceID: DeviceSourceID, name: String, blurb: String,
        tileSymbol: String, tileColorHex: UInt32, batch: Int,
        agentNote: String, footnote: String
    ) {
        self.sourceID = sourceID
        self.name = name
        self.blurb = blurb
        self.tileSymbol = tileSymbol
        self.tileColorHex = tileColorHex
        self.batch = batch
        self.agentNote = agentNote
        self.footnote = footnote
    }
}

public enum DeviceSourceDirectory {
    /// 名册全集（呈现序：日历→提醒→通讯录→健康→家
    /// 庭；蓝牙已决不做、永不入册）
    public static let roster: [DeviceSourceDescriptor] = [
        DeviceSourceDescriptor(
            sourceID: .calendar,
            name: "日历",
            blurb: "日程安排 · 被问到时现读现回，也可按确认新建和修改",
            tileSymbol: "calendar", tileColorHex: 0xD64541, batch: 1,
            agentNote: "智能体可调用：查询最长 14 天窗口内的日程，或按你在对话里的确认新建/修改日程（删除不做）",
            footnote: "日程只在被调用的那一刻现读现回，服务器不保存日程内容；关掉调用开关后，智能体连问的机会都没有。"
        ),
        DeviceSourceDescriptor(
            sourceID: .reminders,
            name: "提醒事项",
            blurb: "待办提醒 · 现读未完成项，可按确认新建与勾完成",
            tileSymbol: "list.bullet", tileColorHex: 0xE8892B, batch: 1,
            agentNote: "智能体可调用：读取未完成提醒，或按你在对话里的确认新建提醒、勾完成（删除不做）",
            footnote: "只回未完成项，不回已完成历史；提醒内容只过境不落服务器。"
        ),
        DeviceSourceDescriptor(
            sourceID: .contacts,
            name: "通讯录",
            blurb: "联系人 · 只按关键词现查现回，不整体读取、不写入",
            tileSymbol: "person.crop.circle", tileColorHex: 0x66727E,
            batch: 1,
            agentNote: "智能体可调用：只按姓名关键词现查，命中条目才回；不提供整体读取，也不能新建或修改联系人",
            footnote: "搜索在手机上完成，只有命中条目过境，通讯录全量从不离开手机。"
        ),
        DeviceSourceDescriptor(
            sourceID: .health,
            name: "健康",
            blurb: "步数/睡眠/心率等每日摘要 · 待签名权益到位后开通",
            tileSymbol: "heart.fill", tileColorHex: 0xE5484D, batch: 2,
            agentNote: "待开通：开通后智能体只能读每日摘要（步数/睡眠/静息心率/锻炼分钟），原始样本永不出手机",
            footnote: "健康需要系统签名权益，当前安装方式下尚未开通；这里不会显示任何健康数据。"
        ),
        DeviceSourceDescriptor(
            sourceID: .home,
            name: "家庭",
            blurb: "家庭配件当前状态 · 待签名权益到位后开通",
            tileSymbol: "house.fill", tileColorHex: 0xE8A33D, batch: 2,
            agentNote: "待开通：开通后智能体只能现查配件当前状态，不提供任何控制（开灯/开锁等一律不做）",
            footnote: "家庭需要系统签名权益，当前安装方式下尚未开通；这里不会显示任何配件状态。"
        ),
    ]

    public static func descriptor(
        _ id: DeviceSourceID
    ) -> DeviceSourceDescriptor {
        // 名册恒含五件全集，查不到即编程错误——以首
        // 条兜底而非崩溃（呈现层宁可显错条不许闪退）
        roster.first { $0.sourceID == id } ?? roster[0]
    }
}

// MARK: - 工具名册（与 device-bridge TOOLS 逐字对齐）

/// 工具定义：name 与桥 TOOLS 表逐字一致；source 是
/// 门控该工具的权限件（device_status 由桥本地应答、
/// 无 source）。isWrite 的四件必带 idempotencyKey。
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
        DeviceToolSpec(name: "health_daily_summary", source: .health, isWrite: false),
        DeviceToolSpec(name: "home_status", source: .home, isWrite: false),
    ]

    public static func spec(_ name: String) -> DeviceToolSpec? {
        all.first { $0.name == name }
    }

    /// 本版 App 真能执行的工具（批一三件的七个；
    /// device_status 桥本地应答、不经手机，不在此列；
    /// 健康/家庭的工具定义先行、App 未接线，不上报）
    public static let appExecutable: [DeviceToolSpec] = all.filter {
        guard let source = $0.source else { return false }
        return DeviceSourceDirectory.descriptor(source).isWired
    }
}

// MARK: - 注册载荷（双层开关语义的落点）

public enum DeviceRegistration {
    /// 组装 POST /device/session 的 permissions 与
    /// tools：permissions 报五件系统权限原态（桥据此
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
    /// 目录行状态字（单一映射）：授权态＋调用开关态
    /// ＋一句本地读数（有才拼，取不到不编）。批二两
    /// 件恒「待签名权益」——行在、状态如实、不点入
    /// 假页面。metric 例：「今天 3 个日程」
    public static func line(
        descriptor: DeviceSourceDescriptor,
        permission: DevicePermissionState,
        agentCallEnabled: Bool,
        metric: String?
    ) -> String {
        guard descriptor.isWired else { return "待签名权益" }
        switch permission {
        case .notDetermined:
            return "未授权"
        case .denied, .restricted:
            return "被拒"
        case .writeOnly:
            return "仅写入权限 · 不能读取"
        case .granted, .limited:
            var parts = [permission.label]
            parts.append(agentCallEnabled ? "可调用" : "调用已关")
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
        statusLines: [DeviceSourceID: String], query: String
    ) -> [DeviceSourceDescriptor] {
        DeviceSourceDirectory.roster.filter { descriptor in
            matches(
                descriptor,
                statusLine: statusLines[descriptor.sourceID] ?? "",
                query: query
            )
        }
    }
}
