import Foundation

/// 顶栏模型清单的分组结构（§153，模型重构·顶栏包
/// B1）：按服务商分组呈现全部已配服务商与其模型，
/// 参照 Hermes Studio 两栏级联的信息结构（先服务商、
/// 后模型），落地用系统 List 分段形态（全面原生令）。
/// 数据全量同源：网关组＝/api/model/options 回执的
/// providers 行（生产定型，见 §153.1）＋具名服务商组
/// ＝ProviderRegistry 注册表读数（与设置页同一份
/// config），Gateway 具名条目并入网关组不另立组。
public struct ChatModelChoice: Equatable, Sendable, Identifiable {
    /// 执行身份：模型 id（执行值）
    public var model: String
    /// 发送时的 provider 字段：网关组（裸 custom 路）与
    /// 具名组（custom:<名> 落盘 slug 形）都带；回执里
    /// 的内置服务商（如 deepseek 官方行）不带逐请求
    /// provider——服务端按自身默认路走，与现行清单外
    /// 模型的发送口径一致（providerField nil 分支）
    public var providerField: String?
    /// 是否全局默认（回执 is_current 行的默认模型）
    public var isDefault: Bool

    public var id: String { "\(providerField ?? "")|\(model)" }

    public init(
        model: String, providerField: String?,
        isDefault: Bool = false
    ) {
        self.model = model
        self.providerField = providerField
        self.isDefault = isDefault
    }

    /// provider 字段 → 人话来源（与 AnnotatedModel
    /// 的来源口径同源：nil＝服务端自理不标注）
    public var sourceLabel: String? {
        guard let providerField else { return nil }
        if providerField == "custom" { return "经网关" }
        if providerField.hasPrefix("custom:") {
            return "直连 · \(String(providerField.dropFirst("custom:".count)))"
        }
        return nil
    }
}

/// 一组＝一家服务商＋其模型清单（保回执/注册表序）
public struct ChatModelGroup: Equatable, Sendable, Identifiable {
    /// 段头名（网关组＝「默认服务商」；具名组＝注册表
    /// 键原名，与设置页卡面同名同物）
    public var title: String
    public var choices: [ChatModelChoice]
    public var id: String { title }

    public init(title: String, choices: [ChatModelChoice]) {
        self.title = title
        self.choices = choices
    }
}

public enum ChatModelGroups {

    /// 网关组的 provider 字段（裸 custom：网关按名落
    /// 上游渠道，§15 既有实测口径）
    public static let gatewayProviderField = "custom"

    /// 网关组标题（拼装与判定同源单点，§156：呈现层
    /// 与可见性判定不许再散写这四个字面量比对）
    public static let gatewayGroupTitle = "默认服务商"

    /// 全量分组拼装（B1 唯一拼装口）：
    /// 1. 网关组在前：options 回执 providers 行中
    ///    is_current 之外的 custom 行＋Gateway 具名条
    ///    目的注册表清单合并（回执序在前、注册表补后）；
    ///    回执无 custom 行时回落网关候选扁平清单
    ///    （availableModels 既有管线，等同旧世界单组）；
    ///    具名行 is_current 时其默认模型也在网关组标
    ///    默认（默认的路在那家、模型走网关目录实证在册）。
    /// 2. 具名服务商各组随后：注册表序＝名字序，跳过
    ///    Gateway 具名条目（已并网关组）；每行默认标
    ///    记认回执 is_current 行的默认模型。
    /// 3. 回执里注册表外的行（内置服务商直连行，如
    ///    deepseek 官方）如实成组置后——它们是服务端
    ///    目录的一部分，不许藏；provider 字段不带
    ///    （发送按服务端默认路）。
    /// 4. 一切组硬排除网关别名（ModelCatalog 纪律）；
    ///    空组不呈现。
    public static func build(
        optionsRoot: JSONValue?,
        providers: [ProviderRegistry.Entry],
        gatewayCandidates: [String],
        defaultModel: String?,
        gatewayAliases: Set<String>
    ) -> [ChatModelGroup] {
        // options 回执 providers 行（定型解析）
        struct Row {
            var slug: String
            var isCurrent: Bool
            var models: [String]
        }
        var rows: [Row] = []
        if let optionsRoot,
           case .object(let root) = optionsRoot,
           case .array(let items) = root["providers"] ?? .null {
            for item in items {
                guard case .object(let fields) = item,
                      let slug = fields["slug"]?.stringValue,
                      !slug.isEmpty
                else { continue }
                var models: [String] = []
                if case .array(let list) = fields["models"] ?? .null {
                    models = list.compactMap { $0.stringValue }
                        .filter { !$0.isEmpty }
                }
                rows.append(Row(
                    slug: slug,
                    isCurrent: (fields["is_current"] ?? .null) == .bool(true),
                    models: models
                ))
            }
        }
        let currentRow = rows.first { $0.isCurrent }
        // 默认模型：回读优先（顶层 model 字段），回落
        // config 拍平的 defaultModel
        var optionsDefaultModel: String?
        if let optionsRoot, case .object(let root) = optionsRoot {
            optionsDefaultModel = root["model"]?.stringValue
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        let effectiveDefault = optionsDefaultModel ?? defaultModel

        func usable(_ models: [String]) -> [String] {
            var seen = Set<String>()
            return models.filter {
                !$0.isEmpty && !gatewayAliases.contains($0)
                    && seen.insert($0).inserted
            }
        }
        // 默认标记只认「默认模型＋默认所在行」同中：
        // ownerSlug＝本组对应的回执行 slug 口径（网关组
        // ＝custom；具名组＝条目名；外行组＝行 slug），
        // 与 is_current 行归一化后比对
        func choice(
            _ model: String, providerField: String?,
            ownerSlug: String
        ) -> ChatModelChoice {
            let isDefault = effectiveDefault == model
                && currentRow.map {
                    MainModelAssignment.slug(forProviderName: ownerSlug)
                        == MainModelAssignment.slug(
                            forProviderName: $0.slug
                        )
                } ?? false
            return ChatModelChoice(
                model: model, providerField: providerField,
                isDefault: isDefault
            )
        }

        var groups: [ChatModelGroup] = []

        // —— 网关组
        let gatewayEntry = providers.first {
            MainModelAssignment.isGatewayIdentity($0.name)
        }
        let customRows = rows.filter {
            MainModelAssignment.slug(forProviderName: $0.slug) == "custom"
                || MainModelAssignment.isGatewayIdentity($0.slug)
        }
        var gatewayModels: [String] = []
        for row in customRows { gatewayModels += row.models }
        if let gatewayEntry { gatewayModels += gatewayEntry.models }
        gatewayModels = usable(gatewayModels)
        if gatewayModels.isEmpty {
            gatewayModels = usable(gatewayCandidates)
        }
        if !gatewayModels.isEmpty {
            groups.append(ChatModelGroup(
                title: gatewayGroupTitle,
                choices: gatewayModels.map {
                    choice(
                        $0, providerField: gatewayProviderField,
                        ownerSlug: "custom"
                    )
                }
            ))
        }

        // —— 具名服务商组（注册表序）
        for entry in providers
        where !MainModelAssignment.isGatewayIdentity(entry.name) {
            let models = usable(entry.models)
            guard !models.isEmpty else { continue }
            let field = "custom:"
                + MainModelAssignment.slug(forProviderName: entry.name)
            groups.append(ChatModelGroup(
                title: entry.name,
                choices: models.map {
                    choice($0, providerField: field, ownerSlug: entry.name)
                }
            ))
        }

        // —— 回执里注册表外的行（内置服务商等）
        let namedSlugs = Set(providers.map {
            MainModelAssignment.slug(forProviderName: $0.name)
        })
        for row in rows {
            let slug = MainModelAssignment.slug(forProviderName: row.slug)
            if slug == "custom" || slug == "gateway"
                || namedSlugs.contains(slug) { continue }
            let models = usable(row.models)
            guard !models.isEmpty else { continue }
            groups.append(ChatModelGroup(
                title: row.slug,
                choices: models.map {
                    choice($0, providerField: nil, ownerSlug: row.slug)
                }
            ))
        }
        return groups
    }

    /// 搜索过滤（跨组搜模型名，保组序；组名命中整组留）
    public static func filtered(
        _ groups: [ChatModelGroup], query: String
    ) -> [ChatModelGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.title.localizedCaseInsensitiveContains(needle) {
                return group
            }
            let kept = group.choices.filter {
                $0.model.localizedCaseInsensitiveContains(needle)
            }
            return kept.isEmpty
                ? nil
                : ChatModelGroup(title: group.title, choices: kept)
        }
    }
}

/// 本会话模型选择的解析（B2，纯口径可单测）：会话自
/// 己选过用会话的；没选过用服务端默认播种（默认在分
/// 组清单内才认）；都没有回落分组第一项。执行值
/// （model＋providerField）恒从分组清单取——显示与
/// 发送同源同物（B4）。
public enum SessionModelResolution {
    public static func resolve(
        stored: ChatModelChoice?,
        groups: [ChatModelGroup],
        serverDefault: ChatModelChoice?
    ) -> ChatModelChoice? {
        if let stored,
           groups.contains(where: {
               $0.choices.contains(stored)
           }) {
            return stored
        }
        if let serverDefault,
           groups.contains(where: {
               $0.choices.contains(serverDefault)
           }) {
            return serverDefault
        }
        return groups.first?.choices.first
    }

    /// 服务端默认在分组清单里的落点：先认 isDefault
    /// 标记行，没有再按模型名找第一处（默认模型走网
    /// 关目录时名在网关组，§153.1 实证）
    public static func serverDefaultChoice(
        in groups: [ChatModelGroup], defaultModel: String?
    ) -> ChatModelChoice? {
        for group in groups {
            if let hit = group.choices.first(where: { $0.isDefault }) {
                return hit
            }
        }
        guard let defaultModel else { return nil }
        for group in groups {
            if let hit = group.choices.first(where: {
                $0.model == defaultModel
            }) {
                return hit
            }
        }
        return nil
    }
}
