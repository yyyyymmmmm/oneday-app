import Foundation

/// 模型设置简化（§119，用户 2026-11-11 12:10 亲定＋
/// 12:15 六点拍板）：设置只留两块——服务商管理＋辅助
/// 模型。本文件是辅助模型面的呈现与读写纯函数层：
/// 槽位注册表（Hermes auxiliary 活槽 19 个，键名依
/// hermes_cli/config_defaults_auxiliary.py 的 _aux 工
/// 厂实查；已死三槽永不呈现）、分配值的读写换算、清
/// 单刷新差异、测连接三态、未配模型判定、预设快照。
/// 文案口径随细节审计 D3-01：用户面一律说「辅助模
/// 型／用途」，不说「槽位」；服务商口径随 D3-16。

// MARK: - 辅助用途注册表（19 活槽）

public enum AuxSlotCatalog {
    public enum Layer: Equatable, Sendable {
        case common
        case more
    }

    public struct Slot: Equatable, Identifiable, Sendable {
        public let key: String
        public let titleKey: String
        public let detailKey: String
        public let layer: Layer
        /// 行内带 enabled 开关（title_generation /
        /// background_review 在 Hermes 配置里自带）
        public let hasEnabledSwitch: Bool
        /// 多模型汇总专用行（显隐条件见 sections）
        public let isMoA: Bool

        public var id: String { key }

        public func title(locale: Locale = AppLocale.uiLocale) -> String {
            L10n.string(titleKey, locale: locale)
        }

        public func detail(locale: Locale = AppLocale.uiLocale) -> String {
            L10n.string(detailKey, locale: locale)
        }
    }

    private static func slot(
        _ key: String, _ title: String, _ detail: String,
        layer: Layer, enabled: Bool = false, moa: Bool = false
    ) -> Slot {
        Slot(
            key: key, titleKey: title, detailKey: detail,
            layer: layer, hasEnabledSwitch: enabled, isMoA: moa
        )
    }

    /// 全部活槽，呈现序：常用 11 在前、更多 8 在后
    /// （分层线依调研报告 §3.2＋§119 任务单调和：
    /// review 放折叠层、mcp 提至常用层）
    public static let all: [Slot] = [
        slot("vision", "看图", "分析图片、看截图时用哪个模型", layer: .common),
        slot("compression", "长对话压缩", "对话太长时，把前面的内容总结变短", layer: .common),
        slot("title_generation", "会话起标题", "第一次对话后，给会话自动起个标题", layer: .common, enabled: true),
        slot("approval", "审批判断", "判断一个操作要不要先问你，适合快而便宜的模型", layer: .common),
        slot("background_review", "后台记忆整理", "每轮对话后整理记忆与技能；跟随主模型会重放整段对话，换小模型更省", layer: .common, enabled: true),
        slot("voice_chat", "语音对话", "语音对话时用哪个模型", layer: .common),
        slot("mcp", "工具调用辅助", "智能体调用工具时，帮忙判断和整理", layer: .common),
        slot("kanban_decomposer", "任务拆解", "把一个大任务拆成能一步步做的小任务", layer: .common),
        slot("triage_specifier", "任务细化", "把一句话需求扩写成完整的任务说明", layer: .common),
        slot("goal_judge", "目标评判", "判断一个目标有没有达成", layer: .common),
        slot("curator", "技能整理", "复盘整理技能库，一次可能跑几分钟", layer: .common),
        slot("review", "审查复核", "让一个独立子任务整段审查结果；它自带调用方式，和其他行只选模型不同", layer: .more),
        slot("memory_query_rewrite", "记忆查找改写", "搜记忆之前，把问句改写得更好查", layer: .more),
        slot("tts_audio_tags", "语音情感标签", "朗读时给文字加上情感与音频标签", layer: .more),
        slot("profile_describer", "智能体简介", "生成智能体的一两句简介时用", layer: .more),
        slot("group_router", "群聊分工", "群聊里判断该由谁来回答", layer: .more),
        slot("monitor", "重要邮件筛选", "从大量邮件里挑重要的，量大，适合小模型", layer: .more),
        slot("moa_reference", "多模型参考", "用多模型汇总时，各家先分别给出意见", layer: .more, moa: true),
        slot("moa_aggregator", "多模型汇总", "用多模型汇总时，把各家意见合成一份回答", layer: .more, moa: true),
    ]

    public static var common: [Slot] { all.filter { $0.layer == .common } }
    public static var more: [Slot] { all.filter { $0.layer == .more } }

    /// 已死三槽：Hermes 写了也忽略，永不呈现
    public static let deadKeys: Set<String> = [
        "web_extract", "session_search", "skills_hub",
    ]

    public static func isDead(_ key: String) -> Bool {
        deadKeys.contains(key)
    }

    public static func slot(forKey key: String) -> Slot? {
        all.first { $0.key == key }
    }

    /// 人话名（注册表外键回落键名本身，不假装认识）
    public static func title(forKey key: String) -> String {
        title(forKey: key, locale: AppLocale.uiLocale)
    }

    public static func title(
        forKey key: String, locale: Locale
    ) -> String {
        slot(forKey: key)?.title(locale: locale) ?? key
    }

    public static func isPrimary(_ key: String) -> Bool {
        slot(forKey: key)?.layer == .common
    }

    /// 分段呈现：MoA 两行仅当任一已被指定为非跟随、
    /// 或当前启用的预设含 MoA 分配时才出现（拍板②）
    public static func sections(
        assignments: [String: AuxAssignment],
        activePresetUsesMoA: Bool
    ) -> (common: [Slot], more: [Slot]) {
        let moaVisible = activePresetUsesMoA
            || (assignments["moa_reference"]?.isFollow == false)
            || (assignments["moa_aggregator"]?.isFollow == false)
        return (
            common: common,
            more: more.filter { !$0.isMoA || moaVisible }
        )
    }

    /// provider 候选（沿旧口径：只许本机实际可用的
    /// ——自动／主端点／用户自加的具名服务商）
    public static func providerChoices(
        namedProviders: [String]
    ) -> [String] {
        ["auto", "main"] + namedProviders
    }
}

// MARK: - 分配值（跟随／指定）

/// 分配指向的服务商：主端点（服务器的主通道，经网
/// 关）、具名服务商、或配置里有但不在册上的原值
public enum AuxProviderRef: Equatable, Sendable {
    case mainEndpoint
    case named(String)
    case other(String)

    /// 写进配置的 provider 值：主端点写 "custom"
    /// （与生产 vision 现行写形一致；读时 "custom"
    /// 与 "main" 都归一为主端点）
    public var storageKey: String {
        switch self {
        case .mainEndpoint: return "custom"
        case .named(let name): return name
        case .other(let raw): return raw
        }
    }

    public func label(locale: Locale = AppLocale.uiLocale) -> String {
        switch self {
        case .mainEndpoint:
            return L10n.string("默认服务商", locale: locale)
        case .named(let name), .other(let name):
            return name
        }
    }
}

/// 一个用途的辅助模型分配
public enum AuxAssignment: Equatable, Sendable {
    /// 跟随主模型（配置写形 provider "auto"＋model ""）
    case follow
    case use(AuxProviderRef, model: String)

    public var isFollow: Bool {
        if case .follow = self { return true }
        return false
    }

    /// 换算成组合/激活共用的 SlotChoice 写形
    public var slotChoice: SlotChoice {
        switch self {
        case .follow:
            return .auto
        case .use(let ref, let model):
            return SlotChoice(provider: ref.storageKey, model: model)
        }
    }

    /// 从配置读形换算回来：provider "auto" 且没写
    /// 模型＝跟随；"auto" 写了模型——本部署 auto 实际
    /// 就走主通道，归一为默认服务商指定（§119 记账）；
    /// 不在册的 provider 原样保真、不吞
    public static func from(
        choice: SlotChoice, namedProviders: [String]
    ) -> AuxAssignment {
        let provider = choice.provider
        let model = choice.model
        switch provider {
        case "auto", "":
            return model.isEmpty
                ? .follow : .use(.mainEndpoint, model: model)
        case "custom", "main":
            return .use(.mainEndpoint, model: model)
        default:
            return namedProviders.contains(provider)
                ? .use(.named(provider), model: model)
                : .use(.other(provider), model: model)
        }
    }

    /// 行内当前值人话：跟随主模型／<服务商> · <模型>
    public func valueLabel(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch self {
        case .follow:
            return L10n.string("跟随主模型", locale: locale)
        case .use(let ref, let model):
            let name = ref.label(locale: locale)
            return model.isEmpty ? name : "\(name) · \(model)"
        }
    }
}

// MARK: - 配置读写（Dashboard config 表示）

public enum AuxAssignments {
    /// 读一个用途的现行分配（缺失＝跟随）
    public static func assignment(
        in config: [String: JSONValue], slot key: String,
        namedProviders: [String]
    ) -> AuxAssignment {
        guard case .object(let aux) = config["auxiliary"] ?? .null,
              case .object(let slotObject) = aux[key] ?? .null
        else { return .follow }
        let choice = SlotChoice(
            provider: slotObject["provider"]?.stringValue ?? "auto",
            model: slotObject["model"]?.stringValue ?? ""
        )
        return AuxAssignment.from(
            choice: choice, namedProviders: namedProviders
        )
    }

    /// 读整表分配（只含注册表活槽）
    public static func allAssignments(
        in config: [String: JSONValue],
        namedProviders: [String]
    ) -> [String: AuxAssignment] {
        var out: [String: AuxAssignment] = [:]
        for slot in AuxSlotCatalog.all {
            out[slot.key] = assignment(
                in: config, slot: slot.key,
                namedProviders: namedProviders
            )
        }
        return out
    }

    /// enabled 开关现值（键缺失按开——Hermes 两槽出
    /// 厂即启用）
    public static func enabled(
        in config: [String: JSONValue], slot key: String
    ) -> Bool {
        guard case .object(let aux) = config["auxiliary"] ?? .null,
              case .object(let slotObject) = aux[key] ?? .null,
              let value = slotObject["enabled"]?.boolValue
        else { return true }
        return value
    }

    /// 写一个用途：只动 provider/model（enabled 给了
    /// 才动），同槽位其余键（timeout 等）原样保留
    public static func applying(
        _ assignment: AuxAssignment, enabled: Bool?,
        slot key: String, to config: [String: JSONValue]
    ) -> [String: JSONValue] {
        var config = config
        var aux: [String: JSONValue] = [:]
        if case .object(let existing) = config["auxiliary"] ?? .null {
            aux = existing
        }
        var slotObject: [String: JSONValue] = [:]
        if case .object(let existing) = aux[key] ?? .null {
            slotObject = existing
        }
        let choice = assignment.slotChoice
        slotObject["provider"] = .string(choice.provider)
        slotObject["model"] = .string(choice.model)
        if let enabled {
            slotObject["enabled"] = .bool(enabled)
        }
        aux[key] = .object(slotObject)
        config["auxiliary"] = .object(aux)
        return config
    }
}

// MARK: - 清单刷新差异（ekko 式先报差异）

public struct ModelListDiff: Equatable, Sendable {
    public var removed: [String]
    public var added: [String]

    public var isUnchanged: Bool {
        removed.isEmpty && added.isEmpty
    }

    /// 保序差异：removed 按旧表序、added 按新表序
    public static func between(
        old: [String], new: [String]
    ) -> ModelListDiff {
        let newSet = Set(new)
        let oldSet = Set(old)
        return ModelListDiff(
            removed: old.filter { !newSet.contains($0) },
            added: new.filter { !oldSet.contains($0) }
        )
    }
}

// MARK: - 模型清单治理（§150 B5，报告 hermes-studio-model-picker §7.3）

/// 清单呈现治理：搜索过滤＋超阈折叠的纯函数，设置
/// 页详情清单与默认选择面共用同一口径。阈值 40 是
/// 我方按手机屏收紧的取值（Studio 的治理线是 100，
/// 报告已标明非大厂原值）
public enum ModelListGovernance {
    public static let foldThreshold = 40

    public struct Presentation: Equatable, Sendable {
        /// 实际呈现的行（已过滤、已折叠）
        public var shown: [String]
        /// 折叠藏起的行数（搜索态恒 0）
        public var hiddenCount: Int
        /// 是否处于搜索过滤态
        public var isFiltering: Bool
        /// 过滤后总行数（搜索无结果时为 0）
        public var matchCount: Int

        public init(
            shown: [String], hiddenCount: Int,
            isFiltering: Bool, matchCount: Int
        ) {
            self.shown = shown
            self.hiddenCount = hiddenCount
            self.isFiltering = isFiltering
            self.matchCount = matchCount
        }
    }

    public static func presentation(
        models: [String], query: String, expanded: Bool
    ) -> Presentation {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            if expanded || models.count <= foldThreshold {
                return Presentation(
                    shown: models, hiddenCount: 0,
                    isFiltering: false, matchCount: models.count
                )
            }
            return Presentation(
                shown: Array(models.prefix(foldThreshold)),
                hiddenCount: models.count - foldThreshold,
                isFiltering: false, matchCount: models.count
            )
        }
        let needle = trimmed.lowercased()
        let matched = models.filter {
            $0.lowercased().contains(needle)
        }
        return Presentation(
            shown: matched, hiddenCount: 0,
            isFiltering: true, matchCount: matched.count
        )
    }
}

// MARK: - 测连接三态（人话，D3-10 口径）

public enum ProviderConnectionOutcome: Equatable, Sendable {
    /// 连通且拿到模型目录
    case connected(modelCount: Int)
    /// 接口通了，但没返回模型目录
    case connectedNoCatalog
    /// 没连上（message 已是人话原因）
    case failed(message: String)

    public func headline(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch self {
        case .connected(let count):
            return L10n.format(
                "连通，发现 %lld 个模型", locale: locale, count
            )
        case .connectedNoCatalog:
            return L10n.string("接口通了，但没返回模型目录", locale: locale)
        case .failed(let message):
            return message
        }
    }

    /// 下一步怎么办（连通态不需要）
    public func advice(
        locale: Locale = AppLocale.uiLocale
    ) -> String? {
        switch self {
        case .connected:
            return nil
        case .connectedNoCatalog:
            return L10n.string(
                "有些服务商不提供模型目录，可以手动填模型 ID，也可以先保存、之后再补。",
                locale: locale
            )
        case .failed:
            return L10n.string(
                "检查地址与密钥后再试；也可以先保存这家服务商，之后再测。",
                locale: locale
            )
        }
    }

    /// 失败/无目录时仍给出路：允许绕过「模型为空」
    /// 一闸先保存（其余校验照走）
    public var canSaveAnyway: Bool {
        switch self {
        case .connected: return false
        case .connectedNoCatalog, .failed: return true
        }
    }
}

// MARK: - 未配模型判定（聊天页引导）

public enum ModelSetupGuidance {
    /// 「无任何可用模型」才引导：网关候选为空、且具
    /// 名服务商的模型总数为零。服务商总数未知（配置
    /// 还没读到）时不报——宁可晚报，不许误报（生产
    /// 现行命名服务商为零但网关有候选，恒为 false）
    public static func needsSetup(
        gatewayModels: [String], providerModelTotal: Int?
    ) -> Bool {
        guard let providerModelTotal else { return false }
        return gatewayModels.isEmpty && providerModelTotal == 0
    }
}

// MARK: - 预设快照（组合降预设的抓取口径）

public enum PresetSnapshot {
    /// 整套快照：默认模型＋全部活槽的当前分配（跟随
    /// 项也显式记下，启用即真重置；与旧 ComboStarter
    /// 只收非跟随项的稀疏口径不同，§119 记账）
    public static func capture(
        config: [String: JSONValue],
        namedProviders: [String],
        id: String, name: String, updatedAt: TimeInterval
    ) -> ModelCombo {
        var aux: [String: SlotChoice] = [:]
        for slot in AuxSlotCatalog.all {
            aux[slot.key] = AuxAssignments.assignment(
                in: config, slot: slot.key,
                namedProviders: namedProviders
            ).slotChoice
        }
        return ModelCombo(
            id: id, name: name,
            mainModel: config["model"]?.stringValue,
            aux: aux, delegation: nil, fallback: [],
            includesFallback: false, updatedAt: updatedAt
        )
    }

    /// 预设是否给 MoA 两行留了非跟随分配（辅助页
    /// MoA 行显隐条件之一）
    public static func usesMoA(_ combo: ModelCombo) -> Bool {
        for key in ["moa_reference", "moa_aggregator"] {
            if let choice = combo.aux[key], choice != .auto {
                return true
            }
        }
        return false
    }
}

extension ModelCombo {
    /// 已单独指定的用途数（跟随不计）
    public var specifiedAuxCount: Int {
        aux.values.filter { $0 != .auto }.count
    }
}
