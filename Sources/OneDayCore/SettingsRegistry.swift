import Foundation

// MARK: - 设置注册表（AI 自主设置权一期·App 半边，DESIGN §437）

/// 注册表记录（施工图 §435 §2.1 的 App 侧子集）：全
/// App 设置的单一真源在服务端，本模型是下发形态——
/// 一条记录＝一个设置条目：基础型（bool/enum/string/
/// number/text）由 App 通用渲染器直出；复杂面只登记
/// 入口（destination 锚回内置目录条目 id，点入仍走
/// 原生页）。一期只读：无任何写端点，值只来自记录回
/// 读（value ?? default），不碰任何现行存储——本期只
/// 换「界面从哪来」，不换「值存哪」。

/// 注册表值类型（§2.1 五型；secret-ref 只存引用、
/// App 不见明文，不进渲染面，故不在本枚举内）
public enum SettingsRegistryValueType: String, Sendable {
    case bool
    case enumeration = "enum"
    case string
    case number
    case text
}

/// 注册表标量值（JSON 原生三型宽容解码：bool 先于
/// number 试解，防 0/1 与 true/false 串味）
public enum SettingsRegistryValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

extension SettingsRegistryValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "注册表值只许 bool/number/string"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

public struct SettingsRegistryRecord: Equatable, Sendable, Identifiable {
    /// 全局唯一键（如 chat.reactions.ai_self）
    public let key: String
    /// 值类型；未知型/缺失为 nil——目的地登记记录不
    /// 需要类型，值记录无有效类型即无效（合并引擎丢弃）
    public let type: SettingsRegistryValueType?
    /// 行题（源串，App 侧经本地化取词，与目录同口径）
    public let title: String
    public let summary: String?
    /// SF 符号名（App 层呈现，可空＝通用符号兜底）
    public let icon: String?
    /// 归属面＝SettingsGroupID 的 rawValue
    public let surface: String
    /// 组内分段＝SettingsSegmentID 的 rawValue（只服
    /// 务与工作区组的值行用）
    public let segment: String?
    /// 面内排序（同值按 下发序稳定排序）
    public let sort: Int
    /// 目的地登记：锚回内置目录条目 id（如 "models"）；
    /// 非 nil 即入口记录，type/值字段不参与渲染
    public let destination: String?
    /// enum 型的候选集
    public let options: [String]?
    /// 默认值（wire 键名 default）
    public let defaultValue: SettingsRegistryValue?
    /// 服务端回读的当前值
    public let value: SettingsRegistryValue?
    /// 依赖能力键（可空）：本期 App 侧不逐条判活——
    /// 整表下发与否由服务端探针把门（探针死不下发渲
    /// 染标记，§435 §2.5），App 只存字段备二期
    public let capability: String?
    /// 条目来源（server／app_local，只读镜像标记）
    public let source: String?

    public var id: String { key }

    public init(
        key: String,
        type: SettingsRegistryValueType? = nil,
        title: String,
        summary: String? = nil,
        icon: String? = nil,
        surface: String,
        segment: String? = nil,
        sort: Int = 0,
        destination: String? = nil,
        options: [String]? = nil,
        defaultValue: SettingsRegistryValue? = nil,
        value: SettingsRegistryValue? = nil,
        capability: String? = nil,
        source: String? = nil
    ) {
        self.key = key
        self.type = type
        self.title = title
        self.summary = summary
        self.icon = icon
        self.surface = surface
        self.segment = segment
        self.sort = sort
        self.destination = destination
        self.options = options
        self.defaultValue = defaultValue
        self.value = value
        self.capability = capability
        self.source = source
    }

    /// 生效值：回读值优先、无值回落注册表默认值
    /// （§2.1——注册表无值时回落 default，行为与现行一致）
    public var effectiveValue: SettingsRegistryValue? {
        value ?? defaultValue
    }
}

extension SettingsRegistryRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case key, type, title, summary, icon, surface, segment, sort
        case destination, options, capability, source, value
        case defaultValue = "default"
    }

    /// 宽容解码：单条字段缺失不炸整表——key/surface
    /// 缺失以空串落位、由合并引擎按无效记录丢弃（整
    /// 表结构损坏才走解码失败→回落内置目录）
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(
            String.self, forKey: .key
        ) ?? ""
        type = try container.decodeIfPresent(
            String.self, forKey: .type
        ).flatMap(SettingsRegistryValueType.init(rawValue:))
        title = try container.decodeIfPresent(
            String.self, forKey: .title
        ) ?? ""
        summary = try container.decodeIfPresent(
            String.self, forKey: .summary
        )
        icon = try container.decodeIfPresent(
            String.self, forKey: .icon
        )
        surface = try container.decodeIfPresent(
            String.self, forKey: .surface
        ) ?? ""
        segment = try container.decodeIfPresent(
            String.self, forKey: .segment
        )
        sort = try container.decodeIfPresent(
            Int.self, forKey: .sort
        ) ?? 0
        destination = try container.decodeIfPresent(
            String.self, forKey: .destination
        )
        options = try container.decodeIfPresent(
            [String].self, forKey: .options
        )
        defaultValue = try container.decodeIfPresent(
            SettingsRegistryValue.self, forKey: .defaultValue
        )
        value = try container.decodeIfPresent(
            SettingsRegistryValue.self, forKey: .value
        )
        capability = try container.decodeIfPresent(
            String.self, forKey: .capability
        )
        source = try container.decodeIfPresent(
            String.self, forKey: .source
        )
    }
}

/// GET /v1/settings/registry 回文（§435 §5 一期端点）
public struct SettingsRegistryResponse: Equatable, Sendable {
    public let version: Int
    public let records: [SettingsRegistryRecord]

    public init(version: Int, records: [SettingsRegistryRecord]) {
        self.version = version
        self.records = records
    }
}

public extension SettingsRegistryResponse {
    /// 按全局键直查记录（§450，设置 IA 先行包 R4）：
    /// config-backed 记录（如两条写入审批）的 sur-
    /// face 是服务端面名口径、不经合并引擎的组面分
    /// 发，消费方（审批规则页）按 key 取行呈现——缺
    /// 记录返回 nil，消费方据此整行不出、不造假行
    func record(forKey key: String) -> SettingsRegistryRecord? {
        records.first { $0.key == key }
    }
}

extension SettingsRegistryResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case version, records
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(
            Int.self, forKey: .version
        ) ?? 0
        records = try container.decodeIfPresent(
            [SettingsRegistryRecord].self, forKey: .records
        ) ?? []
    }
}

// MARK: - 有效行模型（内置目录 × 注册表的合并产物）

/// 设置根页/搜索的一行：目的地行＝现行目录条目（渲
/// 染与点达全走既有路径，行为不变）；值行＝注册表
/// 基础型条目——§496 起合并引擎不再产出值行（不进
/// 浏览组/搜索，只许专属面按 key 直查），枚举与通用
/// 渲染器保留备专属面消费
public enum SettingsRowModel: Equatable, Sendable, Identifiable {
    case destination(SettingsCatalogEntry)
    case value(SettingsRegistryRecord)

    public var id: String {
        switch self {
        case .destination(let entry): return "destination:\(entry.id)"
        case .value(let record): return "value:\(record.key)"
        }
    }

    /// 目的地行拆包（消费方分流与测试对账共用）
    public var destinationEntry: SettingsCatalogEntry? {
        if case .destination(let entry) = self { return entry }
        return nil
    }
}

/// 值行的渲染模型：控件型与展示值自记录派生（生效
/// 值口径见 effectiveValue），五型各一控件——bool 开
/// 关、enum 选择器、string 文本框、number 数值框、
/// text 文本块；无有效类型按文本框兜底（合并引擎已
/// 拦无类型值记录，本兜底只防直造记录）
public struct SettingsRegistryRowModel: Equatable, Sendable {
    public enum ControlKind: Equatable, Sendable {
        case toggle
        case picker
        case textField
        case numberField
        case textBlock
    }

    public let kind: ControlKind
    public let boolValue: Bool
    public let stringValue: String
    public let numberValue: Double
    public let options: [String]

    public init(record: SettingsRegistryRecord) {
        let effective = record.effectiveValue
        switch record.type {
        case .bool:
            kind = .toggle
            boolValue = effective?.boolValue ?? false
            stringValue = ""
            numberValue = 0
            options = []
        case .enumeration:
            kind = .picker
            options = record.options ?? []
            stringValue = effective?.stringValue ?? options.first ?? ""
            boolValue = false
            numberValue = 0
        case .number:
            kind = .numberField
            numberValue = effective?.numberValue ?? 0
            stringValue = ""
            boolValue = false
            options = []
        case .text:
            kind = .textBlock
            stringValue = effective?.stringValue ?? ""
            boolValue = false
            numberValue = 0
            options = []
        case .string, nil:
            kind = .textField
            stringValue = effective?.stringValue ?? ""
            boolValue = false
            numberValue = 0
            options = []
        }
    }
}

// MARK: - 合并引擎（SettingsCatalog 的可下发形态）

public extension SettingsCatalog {

    /// 某组的有效记录（注册表驱动的原料判定）：sur-
    /// face 命中本组，且——目的地记录能按 id 锚回本
    /// 组内置条目、值记录自带有效类型与题——按 (sort,
    /// 下发序) 稳定排序；目的地按条目 id 去重、值按
    /// key 去重（先到先得）。锚不回/跨组/无材料的记
    /// 录一律丢弃：注册表不许凭空造页（僵尸禁令）
    private static func validRecords(
        in group: SettingsGroupID,
        registry: SettingsRegistryResponse
    ) -> [SettingsRegistryRecord] {
        var seenDestinations = Set<String>()
        var seenKeys = Set<String>()
        var picked: [(index: Int, record: SettingsRegistryRecord)] = []
        for (index, record) in registry.records.enumerated() {
            guard record.surface == group.rawValue else { continue }
            if let destinationID = record.destination {
                guard let entry = entries.first(where: {
                    $0.id == destinationID
                }), entry.group == group,
                    seenDestinations.insert(destinationID).inserted
                else { continue }
                picked.append((index, record))
            } else {
                guard record.type != nil,
                      !record.key.isEmpty,
                      !record.title.isEmpty,
                      seenKeys.insert(record.key).inserted
                else { continue }
                picked.append((index, record))
            }
        }
        return picked
            .sorted {
                ($0.record.sort, $0.index) < ($1.record.sort, $1.index)
            }
            .map(\.record)
    }

    /// 有效浏览行（§437 合并规则）：registry 为 nil
    /// （能力位不亮/断服/拉取失败）或本组无有效记录
    /// →纯内置行（逐面回落，与现行逐字一致）；有有
    /// 效记录→记录序成行（目的地记录锚回内置条目、
    /// 值记录走通用渲染），未被任何记录引用的内置浏
    /// 览条目按原序附后——注册表只许重排与增行，不
    /// 许静默删行（部分种子优雅降级）。浏览态尊重内
    /// 置条目的 showsInBrowse：搜索专行不因注册表登
    /// 记被提进浏览
    static func effectiveBrowseRows(
        in group: SettingsGroupID,
        registry: SettingsRegistryResponse?
    ) -> [SettingsRowModel] {
        let builtin = browseEntries(in: group)
        guard let registry else {
            return builtin.map(SettingsRowModel.destination)
        }
        let records = validRecords(in: group, registry: registry)
        guard !records.isEmpty else {
            return builtin.map(SettingsRowModel.destination)
        }
        var referenced = Set<String>()
        var rows: [SettingsRowModel] = []
        for record in records {
            if let destinationID = record.destination,
               let entry = entries.first(where: {
                   $0.id == destinationID
               }) {
                guard entry.showsInBrowse else { continue }
                referenced.insert(entry.id)
                rows.append(.destination(entry))
            }
            // §496 加门：值记录（destination == nil）
            // 不进任何浏览组——只许专属面按 key 直查
            // 消费（record(forKey:)）；根页浏览行自此
            // 全为目录目的地行（堵 118 盲区：值行曾绕
            // 过目录混排进根页、实际可见比目录多 3 行）
        }
        for entry in builtin where !referenced.contains(entry.id) {
            rows.append(.destination(entry))
        }
        return rows
    }

    /// 有效分段（服务与工作区组）：registry 为 nil 时
    /// 与 browseSegments 逐字一致（同一份内置产物包
    /// 装）；有注册表时按有效行归桶——目的地行用条目
    /// 自带段（无段条目与现行口径同不进分段浏览）、
    /// 值行用记录段（缺省归维护段＝末段）
    static func effectiveBrowseSegments(
        in group: SettingsGroupID,
        registry: SettingsRegistryResponse?
    ) -> [(segment: SettingsSegmentID, rows: [SettingsRowModel])] {
        guard let registry else {
            return browseSegments(in: group).map {
                (
                    segment: $0.segment,
                    rows: $0.entries.map(SettingsRowModel.destination)
                )
            }
        }
        let rows = effectiveBrowseRows(in: group, registry: registry)
        return SettingsSegmentID.allCases.compactMap { segment in
            let items = rows.filter { row in
                switch row {
                case .destination(let entry):
                    return entry.segment == segment
                case .value(let record):
                    let recordSegment = record.segment.flatMap(
                        SettingsSegmentID.init(rawValue:)
                    ) ?? .maintenance
                    return recordSegment == segment
                }
            }
            return items.isEmpty ? nil : (segment: segment, rows: items)
        }
    }

    /// 有效搜索：registry 为 nil 时与 search 逐字一致
    /// （同一份内置产物包装）；有注册表时目的地集合
    /// 仍是全量内置条目（永不删行——搜索可达面不因
    /// 注册表缩水）；§496 起值行不并入搜索（加门，
    /// 只许专属面按 key 直查消费）
    static func effectiveSearch(
        _ query: String,
        registry: SettingsRegistryResponse?
    ) -> [SettingsRowModel] {
        guard let registry else {
            return search(query).map(SettingsRowModel.destination)
        }
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        // §496 加门：值记录不进搜索面（与浏览组同口
        // 径），搜索命中自此只有目录条目
        guard !needle.isEmpty else {
            return entries.map(SettingsRowModel.destination)
        }
        let entryTitleHits = entries.filter {
            $0.title.lowercased().contains(needle)
        }
        let entryOtherHits = entries.filter { entry in
            !entry.title.lowercased().contains(needle)
                && (entry.summary.lowercased().contains(needle)
                    || entry.keywords.contains {
                        $0.lowercased().contains(needle)
                    })
        }
        return entryTitleHits.map(SettingsRowModel.destination)
            + entryOtherHits.map(SettingsRowModel.destination)
    }
}
