import Foundation

/// 分区折叠与服务商可见性治理（§158，用户 2026-11-11
/// 21:13 三项指令＋21:15 追问升级）：抽屉分区与模型
/// 分组共用一套折叠口径；回执内置行（用户从未配置
/// 过的服务商）默认收进折叠区；内置行与网关行可经
/// 管理动作「隐藏」——隐藏＝本机名单过滤（UserDefaults
/// 落盘），服务端 config 一字不动、随时可恢复。本
/// 文件只收纯口径：折叠判定、存储编解码、分组分拣、
/// 隐藏过滤，呈现层（App）只消费结论不私算。

// MARK: - 折叠状态（按区持久化）

/// 折叠状态账：分区键 → 是否折叠。持久化形态＝
/// JSON {键: true/false}（UserDefaults 一键）；解码
/// 失败/缺键一律回落调用方给的默认，不因脏数据崩。
public enum SectionCollapseState {

    /// 判定：账里有值用账里的，没有用 defaultCollapsed
    public static func isCollapsed(
        key: String, in store: [String: Bool],
        defaultCollapsed: Bool
    ) -> Bool {
        store[key] ?? defaultCollapsed
    }

    /// 切换：返回新账（不可变风格，与本仓落盘账同式）
    public static func toggled(
        key: String, in store: [String: Bool],
        defaultCollapsed: Bool
    ) -> [String: Bool] {
        var next = store
        next[key] = !isCollapsed(
            key: key, in: store, defaultCollapsed: defaultCollapsed
        )
        return next
    }

    public static func encode(_ store: [String: Bool]) -> Data? {
        try? JSONEncoder().encode(store)
    }

    public static func decode(_ data: Data?) -> [String: Bool] {
        guard let data,
              let decoded = try? JSONDecoder().decode(
                  [String: Bool].self, from: data
              )
        else { return [:] }
        return decoded
    }
}

/// 折叠状态的存储键（单一出处，照 LanguageStorageKeys
/// 先例）：App 层 @AppStorage 与读写口都引此
public enum SectionCollapseStorageKeys {
    /// 抽屉分区的折叠账（键＝DrawerSectionKey 原值）
    public static let drawerSections = "drawerSectionCollapse"
    /// 模型分区的折叠账（键＝模型分组标题）
    public static let modelSections = "modelSectionCollapse"
    /// 已隐藏服务商名单（JSON 数组，存组键）
    public static let hiddenProviders = "hiddenProviderGroups"
}

/// 抽屉分区键（本包三区）：分区头折叠键的唯一拼装口，
/// 不许呈现层散写字面量
public enum DrawerSectionKey {
    public static let navigation = "drawer.nav"
    public static let channels = "drawer.channels"
    public static let sideChats = "drawer.side"

    /// 搜索态名单不是第四个区——它与旁聊区同键（搜
    /// 索时强制展开由呈现层处理，账不另立）
    public static func key(forSearching searching: Bool) -> String {
        sideChats
    }
}

// MARK: - 服务商分组判定与隐藏

/// 模型分组的来源判定（§158 第 3 条收口）：
/// - 主列：网关组＋注册表具名组（用户自加/已配置）
/// - 内置行：/api/model/options 回执里注册表外的行
///   ——Hermes 程序自带的目录行（如 nous、deepseek
///   官方行），用户从未在 App 里配过。「已配置」判
///   定只认两个可用信号：①该行是回执 is_current 行
///   （服务端默认正走它＝在用）；②行 slug 与注册表
///   条目归一化后同名（那它已在具名组里、不会走到
///   本判定）。查无信号一律保守归内置行（未配置），
///   判错的代价只是多收进折叠区、展开仍可选，不丢
///   任何模型。
public enum ProviderGroupVisibility {

    /// 回执内置行（未配置）的折叠区标题（用户可见
    /// 串，三语经 xcstrings 同键）
    public static let builtinBucketTitle = "未配置的服务商"

    /// 一组是不是回执内置行：ChatModelGroups.build
    /// 的拼装口径里，内置行组恒 providerField == nil
    /// 且标题不是网关组标题；具名组恒带 custom:<名>、
    /// 网关组恒带裸 custom。判定只认这组结构信号，
    /// 不另查名单——拼装口与判定口同源，不会漂移。
    public static func isBuiltinGroup(_ group: ChatModelGroup) -> Bool {
        group.title != ChatModelGroups.gatewayGroupTitle
            && group.choices.allSatisfy { $0.providerField == nil }
    }

    /// 组里是否含当前默认模型（isDefault 标记行）：
    /// 含默认的内置行组＝服务端默认正走它，按「当
    /// 前在用」升回主列并默认展开（任务单第 2 条默
    /// 认态口径），不许被折叠区吞掉默认的可见性
    public static func containsDefault(_ group: ChatModelGroup) -> Bool {
        group.choices.contains { $0.isDefault }
    }

    /// 分组分拣（选择器/设置面共用）：主列保原序，
    /// 内置行析出成一份（保原序）；含默认的内置组
    /// 留主列不析出
    public static func partition(
        _ groups: [ChatModelGroup]
    ) -> (main: [ChatModelGroup], builtin: [ChatModelGroup]) {
        var main: [ChatModelGroup] = []
        var builtin: [ChatModelGroup] = []
        for group in groups {
            if isBuiltinGroup(group), !containsDefault(group) {
                builtin.append(group)
            } else {
                main.append(group)
            }
        }
        return (main, builtin)
    }

    /// 内置行收纳组：多家内置行并成一组呈现（标题
    /// ＝builtinBucketTitle），组内每行副行带自家服
    /// 务商名（呈现层拼），模型本体不改一字
    public static func bucketGroup(
        _ builtin: [ChatModelGroup]
    ) -> ChatModelGroup? {
        guard !builtin.isEmpty else { return nil }
        return ChatModelGroup(
            title: builtinBucketTitle,
            choices: builtin.flatMap(\.choices)
        )
    }

    // MARK: 隐藏名单（21:15 追问升级：能去掉，不只是收起）

    /// 组键：隐藏名单与恢复入口的唯一标识——网关组
    /// 恒 "gateway"；内置行按行归一化 slug（与呈现标
    /// 题同源小写口径）；具名组不入隐藏面（删除走设
    /// 置页既有删除服务商，本包不复刻）
    public static func groupKey(for group: ChatModelGroup) -> String? {
        if group.title == ChatModelGroups.gatewayGroupTitle {
            return "gateway"
        }
        guard isBuiltinGroup(group) else { return nil }
        return "builtin:"
            + MainModelAssignment.slug(forProviderName: group.title)
    }

    /// 隐藏过滤（选择器的唯一过滤口）：hidden 里的
    /// 组整组撤出；含默认的组恒不撤（执行模型的呈现
    /// 锚不许消失——隐藏当前默认组在管理动作层已先
    /// 经确认且默认会改走网关，过滤口再加这道结构
    /// 闸双保险）。返回留下的组（保序）
    public static func visibleGroups(
        _ groups: [ChatModelGroup], hidden: Set<String>
    ) -> [ChatModelGroup] {
        groups.filter { group in
            guard let key = groupKey(for: group),
                  hidden.contains(key) else { return true }
            return containsDefault(group)
        }
    }

    /// 隐藏名单编解码（JSON 数组；脏数据回空集）
    public static func encodeHidden(_ hidden: Set<String>) -> Data? {
        try? JSONEncoder().encode(hidden.sorted())
    }

    public static func decodeHidden(_ data: Data?) -> Set<String> {
        guard let data,
              let decoded = try? JSONDecoder().decode(
                  [String].self, from: data
              )
        else { return [] }
        return Set(decoded)
    }

    /// 恢复入口的名单行：把当前回执里「已隐藏且真实
    /// 存在」的组列出来（标题保回执原名，键保组键），
    /// 回执里已不存在的隐藏键不列（服务端升级改名后
    /// 旧键自然失效，不拿幽灵行占位）
    public static func hiddenEntries(
        in groups: [ChatModelGroup], hidden: Set<String>
    ) -> [(key: String, title: String)] {
        groups.compactMap { group in
            guard let key = groupKey(for: group),
                  hidden.contains(key) else { return nil }
            return (key: key, title: group.title)
        }
    }

    /// 折叠默认态（任务单第 2 条）：主列组默认展开；
    /// 内置行收纳组默认收起。用户手动改过的以持久
    /// 账为准（呈现层先查账、缺键才问本函数）
    public static func defaultCollapsed(isBuiltinBucket: Bool) -> Bool {
        isBuiltinBucket
    }
}
