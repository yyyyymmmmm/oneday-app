import Foundation

/// 提供商名册（0.37.0 模型包·接入层）：用户自加的具名
/// 提供商条目——名／接口地址／密钥引用／模型清单。口径
/// 依 model-provider-status-design-20261110 §6 定版：
/// 密钥不进配置明文、不进 App 本地存储；配置条目只存
/// `key_env` 引用，真钥经 /api/env 写服务端 env。App
/// 只提供机制（表单＋验活＋候选呈现），不预置任何一家。
public enum ProviderRegistry {

    // MARK: - 条目模型

    /// 一条具名提供商（自 /api/config 的 providers 字典解出）
    public struct Entry: Equatable, Identifiable, Sendable {
        public var name: String
        public var baseURL: String?
        /// 配置里引用的 env 变量名（只存引用、不存值）
        public var keyEnv: String?
        /// 该提供商声明的模型（添加时自 /models 拉取或手填）
        public var models: [String]

        public var id: String { name }

        public init(
            name: String, baseURL: String?, keyEnv: String?,
            models: [String]
        ) {
            self.name = name
            self.baseURL = baseURL
            self.keyEnv = keyEnv
            self.models = models
        }
    }

    /// 自 config 的 providers 字典解出全部条目（按名排序；
    /// 形状不合的子项跳过不崩，与 ModelSettingsView 旧读
    /// 口径一致并扩出 key_env／models 两字段）
    public static func entries(from providersValue: JSONValue?) -> [Entry] {
        guard case .object(let dict) = providersValue ?? .null else {
            return []
        }
        return dict.keys.sorted().compactMap { name in
            guard case .object(let fields) = dict[name] ?? .null else {
                return nil
            }
            var models: [String] = []
            if case .array(let items) = fields["models"] ?? .null {
                models = items.compactMap { $0.stringValue }
                    .filter { !$0.isEmpty }
            }
            return Entry(
                name: name,
                baseURL: fields["base_url"]?.stringValue,
                keyEnv: fields["key_env"]?.stringValue,
                models: models
            )
        }
    }

    /// 条目 → 配置 JSONValue（写回 providers 字典用）。
    /// 字段与 Hermes 具名 provider 模板同形：base_url／
    /// key_env；models 为本 App 的候选标注来源，一并落盘。
    public static func configValue(for entry: Entry) -> JSONValue {
        var fields: [String: JSONValue] = [:]
        if let baseURL = entry.baseURL, !baseURL.isEmpty {
            fields["base_url"] = .string(baseURL)
        }
        if let keyEnv = entry.keyEnv, !keyEnv.isEmpty {
            fields["key_env"] = .string(keyEnv)
        }
        if !entry.models.isEmpty {
            fields["models"] = .array(entry.models.map { .string($0) })
        }
        return .object(fields)
    }

    // MARK: - 命名与密钥引用

    /// 提供商名 → env 变量名：只保留 ASCII 字母数字
    /// （大写），其余字符一律折下划线、ONEDAY_PROVIDER_
    /// 前缀。密钥只以此名落服务端 env。纯中文名会派生
    /// 出空 slug——回落 PROVIDER 兜底段，不产生双下划线
    /// 连缀的怪名（重名风险由表单重名闸先行拦下）。
    public static func envKey(forProviderName name: String) -> String {
        let slug = name.uppercased().map { ch -> Character in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) ? ch : "_"
        }
        let collapsed = String(slug)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return "ONEDAY_PROVIDER_\(collapsed.isEmpty ? "PROVIDER" : collapsed)_KEY"
    }

    // MARK: - 表单校验（添加提供商，§6.2 四件套）

    public enum DraftProblem: Equatable, Sendable {
        case emptyName
        case duplicateName
        case envKeyCollision
        case badBaseURL
        case emptyKey
        case noModels

        /// 人话文案（宪法 §8：不出现字段名以外的行话）
        public var message: String {
            switch self {
            case .emptyName: return "先给这家提供商起个名字。"
            case .duplicateName: return "已经有一家同名的提供商了，换个名字。"
            case .envKeyCollision: return "这个名字与已有提供商的密钥位置冲突，换个名字（加个英文词区分一下）。"
            case .badBaseURL: return "接口地址不对：要以 http:// 或 https:// 开头。"
            case .emptyKey: return "密钥还没填。"
            case .noModels: return "还没有模型：先拉取模型列表，或手动填一个模型名。"
            }
        }
    }

    /// 添加表单校验（existingNames/existingEnvKeys 为现
    /// 名册：重名拦、派生 env 名碰撞也拦——纯中文名都会
    /// 派生到同一个兜底 env 名，第二家必须换名）
    public static func validateDraft(
        name: String, baseURL: String, apiKey: String,
        models: [String], existingNames: [String],
        existingEnvKeys: [String] = []
    ) -> DraftProblem? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return .emptyName }
        if existingNames.contains(trimmedName) { return .duplicateName }
        if existingEnvKeys.contains(envKey(forProviderName: trimmedName)) {
            return .envKeyCollision
        }
        let url = baseURL.trimmingCharacters(in: .whitespaces)
        guard url.hasPrefix("http://") || url.hasPrefix("https://"),
              url.count > 8 else { return .badBaseURL }
        if apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyKey
        }
        if models.allSatisfy({
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }) { return .noModels }
        return nil
    }

    // MARK: - /models 回执解析（验活与模型拉取，§6.4）

    /// 提供商 GET {base}/models 的回执 → 模型 id 列表。
    /// 主形态 OpenAI 式 {"data":[{"id":…}]}；兼容 {"models":[…]}
    /// 与裸数组。保序去重，网关别名不在此排除（那是候选
    /// 拼装层 ModelCatalog 的事），但空串剔除。
    public static func parseModelList(from root: JSONValue) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        func add(_ raw: String?) {
            guard let raw else { return }
            let id = raw.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, seen.insert(id).inserted else { return }
            ids.append(id)
        }
        func collect(_ value: JSONValue) {
            switch value {
            case .array(let items):
                for item in items {
                    if case .object(let fields) = item {
                        add(fields["id"]?.stringValue
                            ?? fields["model"]?.stringValue
                            ?? fields["name"]?.stringValue)
                    } else {
                        add(item.stringValue)
                    }
                }
            case .string(let id):
                add(id)
            default:
                break
            }
        }
        if case .object(let fields) = root {
            if let data = fields["data"] { collect(data) }
            if ids.isEmpty, let models = fields["models"] {
                collect(models)
            }
        } else {
            collect(root)
        }
        return ids
    }
}

// MARK: - 模型来源标注（清单层，§6.5 复合条目）

/// 一个可选模型条目＝模型名＋来源。同名模型可同时以
/// 「经网关」与「直连·某提供商」两条出现——选哪个来源
/// 就是选哪条路，不另设提供商切换开关（那与会话锁的
/// 粒度对不上，是假控件）。
public struct AnnotatedModel: Equatable, Identifiable, Sendable {
    public enum Source: Equatable, Sendable {
        /// 经自建网关（候选管线来的模型，现架构的默认路）
        case gateway
        /// 直连具名提供商（绕过网关、无网关统计，须如实标注）
        case direct(provider: String)

        /// 行内来源短标（人话）
        public var label: String {
            switch self {
            case .gateway: return "经网关"
            case .direct(let provider): return "直连 · \(provider)"
            }
        }
    }

    public var model: String
    public var source: Source

    public var id: String {
        switch source {
        case .gateway: return "gw::\(model)"
        case .direct(let provider): return "direct::\(provider)::\(model)"
        }
    }

    public init(model: String, source: Source) {
        self.model = model
        self.source = source
    }
}

public enum ModelSourceAnnotation {
    /// 拼装标注清单：候选管线（网关路）在前、具名提供商
    /// 的模型（直连路）随后（按提供商名序）。两路都硬
    /// 排除网关别名（ModelCatalog 纪律不回退：别名混进
    /// 直连清单同样会误导写入）。同路同名去重。
    public static func annotate(
        gatewayCandidates: [String],
        providers: [ProviderRegistry.Entry],
        gatewayAliases: Set<String>
    ) -> [AnnotatedModel] {
        var result: [AnnotatedModel] = []
        var seen = Set<String>()
        func append(_ model: String, _ source: AnnotatedModel.Source) {
            let id = AnnotatedModel(model: model, source: source).id
            guard !model.isEmpty, !gatewayAliases.contains(model),
                  seen.insert(id).inserted else { return }
            result.append(AnnotatedModel(model: model, source: source))
        }
        for model in gatewayCandidates {
            append(model, .gateway)
        }
        for provider in providers {
            for model in provider.models {
                append(model, .direct(provider: provider.name))
            }
        }
        return result
    }
}
