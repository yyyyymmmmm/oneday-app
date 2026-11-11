import Foundation

/// 模型组合（0.37.0 模型包·分配层）：用户逐槽位自选、
/// 存成自己的组合、多套可切换。口径依 model-provider-
/// status-design-20261110 §5 定版（用户「自定义部署」
/// 原话）：开发方不预置决定，唯一例外是一套「当前配置」
/// 起始示例（把现状存成组合供改、可删改）。config 里
/// 只放当前激活的那套赋值。存储落点后随复杂化全清
/// 第 5 项改判：组合定义落 App 本地（PresetStore），
/// 「服务端为真源」口径作废、多设备不互通（用户
/// 2026-11-11 16:33 按抉择书 A 案拍板；旧桥文档经
/// PresetMigration 稠密化迁入，缺失活槽填跟随）。
///
/// 粒度诚实边界（§5.3，UI 文案须如实）：组合全局生效；
/// 只有主模型一格有会话级例外（会话锁），其余槽位
/// （看图／标题／压缩等）全机共用一套。

/// 一个槽位的选择：provider 取值口径——"auto"＝跟随
/// 默认链、"main"＝主端点（经网关）、其余＝具名提供商
/// 名；model 为空＝该槽位不指定模型（交服务端默认）。
public struct SlotChoice: Codable, Equatable, Sendable {
    public var provider: String
    public var model: String

    public init(provider: String, model: String) {
        self.provider = provider
        self.model = model
    }

    /// 跟随默认（未改过的槽位）
    public static let auto = SlotChoice(provider: "auto", model: "")

    /// provider 的人话短标（编辑器与详情共用）
    public var providerLabel: String {
        providerLabel(locale: AppLocale.uiLocale)
    }

    /// 短标的目录取词形（0.42.1 国际化长尾包）：
    /// provider 名是用户自加的内容、原样直通
    public func providerLabel(locale: Locale) -> String {
        switch provider {
        case "auto": return L10n.string("自动", locale: locale)
        // D3-13（随 §119 销）：「端点」是 §8 禁用词，
        // 主通道改称默认服务商；custom 是生产写形、
        // 与 main 同归一
        case "main", "custom":
            return L10n.string("默认服务商（经网关）", locale: locale)
        default: return L10n.format("直连 · %@", locale: locale, provider)
        }
    }
}

/// 一套组合：只存被用户改过的槽位（aux 稀疏字典），
/// 缺席的槽位激活时不触碰 config 现值。
public struct ModelCombo: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// 主模型槽位：nil＝激活时不动服务端默认模型
    public var mainModel: String?
    /// auxiliary 槽位（键＝槽位键名，如 vision）
    public var aux: [String: SlotChoice]
    /// 委派槽位：nil＝不动
    public var delegation: SlotChoice?
    /// 故障转移链（有序，空＝不动；显式清空走编辑器开关
    /// 之外的语义：见 ComboActivation 注）
    public var fallback: [SlotChoice]
    /// 是否在激活时写故障转移链（区分「不动」与「清空」）
    public var includesFallback: Bool
    public var updatedAt: Double

    public init(
        id: String, name: String, mainModel: String?,
        aux: [String: SlotChoice], delegation: SlotChoice?,
        fallback: [SlotChoice], includesFallback: Bool,
        updatedAt: Double
    ) {
        self.id = id
        self.name = name
        self.mainModel = mainModel
        self.aux = aux
        self.delegation = delegation
        self.fallback = fallback
        self.includesFallback = includesFallback
        self.updatedAt = updatedAt
    }

    /// 组合摘要（一行人话：动了哪些格，给列表行用）
    public var summaryLine: String {
        summaryLine(locale: AppLocale.uiLocale)
    }

    /// 摘要的目录取词形（0.42.1 国际化长尾包）：
    /// 模型名是内容、原样直通，只模板走目录
    public func summaryLine(locale: Locale) -> String {
        var parts: [String] = []
        if let mainModel {
            parts.append(L10n.format("主模型 %@", locale: locale, mainModel))
        }
        // D3-01（随 §119 销）：只数已单独指定的用途，
        // 跟随项不算「设置过」
        let specified = specifiedAuxCount
        if specified > 0 {
            parts.append(L10n.format(
                "已给 %lld 个用途指定模型", locale: locale, specified
            ))
        }
        if delegation != nil {
            parts.append(L10n.string("含委派设置", locale: locale))
        }
        if includesFallback {
            parts.append(fallback.isEmpty
                ? L10n.string("备用链未启用", locale: locale)
                : L10n.format(
                    "备用链 %lld 级", locale: locale, fallback.count
                ))
        }
        return parts.isEmpty
            ? L10n.string("还没有给任何用途单独指定，都跟随主模型", locale: locale)
            : parts.joined(separator: " · ")
    }
}

/// 组合文档：组合全集＋当前激活的那套 id。原为桥
/// meta 上的整体存取形态（GET/PUT 一把梭），第 5 项
/// 起同一形态落 App 本地 PresetStore，桥侧仅余一次
/// 性迁移读取。
public struct ModelComboDocument: Codable, Equatable, Sendable {
    public var combos: [ModelCombo]
    public var activeComboID: String?

    public init(combos: [ModelCombo], activeComboID: String?) {
        self.combos = combos
        self.activeComboID = activeComboID
    }

    public static let empty = ModelComboDocument(
        combos: [], activeComboID: nil
    )
}

// MARK: - 槽位目录

/// 槽位注册表已随 §119 迁往 AuxModelSettings.swift
/// （19 活槽新注册表 AuxSlotCatalog，含死槽排除与
/// 11＋8 分层；旧 12 槽目录含已死的 web_extract，
/// 就此退役）。

// MARK: - 现行值读取（编辑器回显与起始示例共用）

public enum ComboCurrentValues {
    /// 自 config 读一个 aux 槽位的现行选择：槽位对象取
    /// provider/model 两键（其余键如 timeout 不归组合管，
    /// 读不到即 auto）
    public static func auxChoice(
        in config: [String: JSONValue], slot: String
    ) -> SlotChoice {
        guard case .object(let aux) = config["auxiliary"] ?? .null,
              case .object(let fields) = aux[slot] ?? .null else {
            return .auto
        }
        return SlotChoice(
            provider: fields["provider"]?.stringValue ?? "auto",
            model: fields["model"]?.stringValue ?? ""
        )
    }

    /// 自 config 读委派槽位现行选择
    public static func delegationChoice(
        in config: [String: JSONValue]
    ) -> SlotChoice? {
        guard case .object(let fields) = config["delegation"] ?? .null
        else { return nil }
        let provider = fields["provider"]?.stringValue ?? ""
        let model = fields["model"]?.stringValue ?? ""
        if provider.isEmpty && model.isEmpty { return nil }
        return SlotChoice(
            provider: provider.isEmpty ? "auto" : provider, model: model
        )
    }

    /// 自 config 读故障转移链现行值
    public static func fallbackChain(
        in config: [String: JSONValue]
    ) -> [SlotChoice] {
        guard case .array(let items) = config["fallback_providers"] ?? .null
        else { return [] }
        return items.compactMap { item in
            guard case .object(let fields) = item else { return nil }
            return SlotChoice(
                provider: fields["provider"]?.stringValue ?? "auto",
                model: fields["model"]?.stringValue ?? ""
            )
        }
    }
}

// MARK: - 起始示例（§5.6 降格口径：现状快照、可删改）

public enum ComboStarter {
    /// 把当前 config 存成一套组合：只收「与默认不同」的
    /// 槽位（provider 非 auto 或指定了 model 的），主模型
    /// 取当前默认，故障转移链如实带上。名字由调用方给
    /// （UI 固定用「当前配置」），不称推荐、不称预设。
    public static func fromCurrentConfig(
        _ config: [String: JSONValue], id: String, name: String,
        updatedAt: Double
    ) -> ModelCombo {
        var aux: [String: SlotChoice] = [:]
        if case .object(let auxDict) = config["auxiliary"] ?? .null {
            for key in auxDict.keys {
                let choice = ComboCurrentValues.auxChoice(
                    in: config, slot: key
                )
                if choice != .auto { aux[key] = choice }
            }
        }
        let fallback = ComboCurrentValues.fallbackChain(in: config)
        return ModelCombo(
            id: id,
            name: name,
            mainModel: config["model"]?.stringValue,
            aux: aux,
            delegation: ComboCurrentValues.delegationChoice(in: config),
            fallback: fallback,
            includesFallback: !fallback.isEmpty,
            updatedAt: updatedAt
        )
    }
}

// MARK: - 激活拼装（纯函数：组合 → config 变体）

public enum ComboActivation {
    /// 把一套组合的赋值拼进 config 全量（写回前的唯一
    /// 拼装口径）：只改组合点名的键——model（组合有主
    /// 模型时）、auxiliary 各槽位的 provider/model 两键
    /// （槽位对象其余键原样保留）、delegation 的
    /// provider/model、fallback_providers（组合声明管
    /// 这一段时整表替换）。未知字段全程 JSONValue 原样
    /// 保留，与 ModelSettingsView 的写回纪律一致。
    public static func apply(
        _ combo: ModelCombo, to config: [String: JSONValue]
    ) -> [String: JSONValue] {
        var result = config
        if let mainModel = combo.mainModel, !mainModel.isEmpty {
            result["model"] = .string(mainModel)
        }
        if !combo.aux.isEmpty {
            var aux: [String: JSONValue] = [:]
            if case .object(let existing) = result["auxiliary"] ?? .null {
                aux = existing
            }
            for (slot, choice) in combo.aux {
                var fields: [String: JSONValue] = [:]
                if case .object(let existing) = aux[slot] ?? .null {
                    fields = existing
                }
                fields["provider"] = .string(choice.provider)
                fields["model"] = .string(choice.model)
                aux[slot] = .object(fields)
            }
            result["auxiliary"] = .object(aux)
        }
        if let delegation = combo.delegation {
            var fields: [String: JSONValue] = [:]
            if case .object(let existing) = result["delegation"] ?? .null {
                fields = existing
            }
            fields["provider"] = .string(delegation.provider)
            fields["model"] = .string(delegation.model)
            result["delegation"] = .object(fields)
        }
        if combo.includesFallback {
            result["fallback_providers"] = .array(
                combo.fallback.map { choice in
                    .object([
                        "provider": .string(choice.provider),
                        "model": .string(choice.model),
                    ])
                }
            )
        }
        return result
    }

    /// 激活前的人话说明（确认弹窗与结果提示共用，含
    /// 粒度诚实边界，§5.3）：写清动哪些格＋已有会话不
    /// 受影响＋辅助槽位全机共用。
    public static func activationNotice(
        for combo: ModelCombo, locale: Locale = AppLocale.uiLocale
    ) -> String {
        var lines: [String] = []
        if combo.mainModel != nil {
            lines.append(L10n.format(
                "新会话将默认用 %@；已有会话不受影响。",
                locale: locale, combo.mainModel ?? ""
            ))
        }
        if !combo.aux.isEmpty || combo.delegation != nil
            || combo.includesFallback {
            lines.append(L10n.string(
                "看图、标题等辅助设置对整台服务生效，所有会话共用。",
                locale: locale
            ))
        }
        if lines.isEmpty {
            lines.append(L10n.string(
                "这套预设还没有给任何用途单独指定，启用不会改动现在的配置。",
                locale: locale
            ))
        }
        return lines.joined(separator: "\n")
    }
}
