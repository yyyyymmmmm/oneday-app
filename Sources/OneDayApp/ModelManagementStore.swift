import Foundation
import OneDayCore

/// 模型管理中枢（0.37.0 模型包）：模型页三层共用一个
/// 数据口——接入层（提供商名册＋网关渠道只读）、清单
/// 层（来源标注）、分配层（组合存取与激活）。写口纪
/// 律沿 ModelSettingsView 旧规：config 先读全量、只改
/// 目标键、整包写回，未知字段原样保留；提供商密钥先
/// 经 /api/env 落服务端、配置只存 key_env 引用，App
/// 本地永不留存密钥。
@MainActor
@Observable
final class ModelManagementStore {
    private(set) var rawConfig: [String: JSONValue] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var notice: String?

    // 渠道只读面（初始 loading，load 时落定）
    private(set) var channelsFace: GatewayChannelsFace = .loading

    // 组合（桥 meta）：faceMissing＝存储面未开通
    private(set) var comboDocument: ModelComboDocument?
    private(set) var combosFaceMissing = false
    private(set) var combosLoadFailed = false

    private let frontClient = CompanionFrontClient()
    private let comboClient = ModelComboClient()
    private let probeClient = ProviderProbeClient()

    // MARK: - 派生

    var currentModel: String? { rawConfig["model"]?.stringValue }

    var providers: [ProviderRegistry.Entry] {
        ProviderRegistry.entries(from: rawConfig["providers"])
    }

    /// 清单层：网关候选（AppState 管线）＋提供商直连
    /// 模型，来源标注、别名硬排除（Core 口径）
    func annotatedModels(appState: AppState) -> [AnnotatedModel] {
        ModelSourceAnnotation.annotate(
            gatewayCandidates: appState.availableModels,
            providers: providers,
            gatewayAliases: appState.gatewayAliases
        )
    }

    /// config 里实际存在的全部 aux 槽位键（编辑器据此
    /// 分常用/其他两组，不拿官方全量名单冒充本机现状）
    var presentAuxSlots: [String] {
        guard case .object(let aux) = rawConfig["auxiliary"] ?? .null
        else { return [] }
        return aux.keys.sorted()
    }

    // MARK: - 加载

    func load(appState: AppState) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            rawConfig = try await appState.performAdmin { client, config in
                try await client.rawConfig(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "配置读取失败。"
        }
        await appState.refreshModelCatalog()
        if let config = appState.config {
            channelsFace = await frontClient.gatewayChannels(config: config)
        }
        await loadCombos(appState: appState)
    }

    private func loadCombos(appState: AppState) async {
        guard let config = appState.config else { return }
        do {
            comboDocument = try await comboClient.loadDocument(config: config)
            combosFaceMissing = false
            combosLoadFailed = false
        } catch let error as OneDayBridgeError {
            if error == .bridgeMissing {
                combosFaceMissing = true
            } else {
                combosLoadFailed = true
            }
        } catch {
            combosLoadFailed = true
        }
    }

    // MARK: - 默认模型（旧行为平移：候选校验＋写回）

    func setDefaultModel(_ model: String, appState: AppState) async {
        guard ModelCatalog.isWritable(
            model, candidates: appState.availableModels
        ) else {
            notice = HermesError.modelNotUpstream(model).userMessage
            return
        }
        do {
            try await writeBack(appState: appState) { $0["model"] = .string(model) }
            appState.noteDefaultModel(model)
            notice = "默认模型已切换为 \(model)。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换失败，请稍后再试。"
        }
    }

    // MARK: - 提供商（接入层）

    /// 探针：拉对方模型列表（添加表单的连通性检查，
    /// 密钥只过手不留存）
    func probeProviderModels(
        baseURL: String, apiKey: String
    ) async throws -> [String] {
        try await probeClient.fetchModels(baseURL: baseURL, apiKey: apiKey)
    }

    /// 添加提供商：先落密钥（/api/env）→ 再写条目
    /// （config providers，只存引用）。条目写失败时钥
    /// 已在服务端 env 里——同名重试保存会覆盖同名钥，
    /// 不扩散；notice 如实说明停在哪一步。
    func addProvider(
        name: String, baseURL: String, apiKey: String,
        models: [String], appState: AppState
    ) async -> Bool {
        let entry = ProviderRegistry.Entry(
            name: name,
            baseURL: baseURL,
            keyEnv: ProviderRegistry.envKey(forProviderName: name),
            models: models
        )
        do {
            try await appState.performAdmin { client, config in
                try await client.setEnvVar(
                    config: config, key: entry.keyEnv ?? "", value: apiKey
                )
            }
        } catch {
            notice = "密钥没能保存到服务端，这家提供商还没加上。"
            return false
        }
        do {
            try await writeBack(appState: appState) { config in
                var providers: [String: JSONValue] = [:]
                if case .object(let existing) = config["providers"] ?? .null {
                    providers = existing
                }
                providers[name] = ProviderRegistry.configValue(for: entry)
                config["providers"] = .object(providers)
            }
            notice = "提供商 \(name) 已添加。"
            return true
        } catch {
            notice = "密钥已保存到服务端，但提供商条目没写成；再保存一次即可（同名密钥会被覆盖）。"
            return false
        }
    }

    /// 删除提供商：摘条目＋删 env 钥（删钥失败不回滚
    /// 条目删除——孤儿钥在服务端 env 里无引用、不生效，
    /// notice 如实带一句）
    func deleteProvider(_ entry: ProviderRegistry.Entry, appState: AppState) async {
        do {
            try await writeBack(appState: appState) { config in
                if case .object(var providers) = config["providers"] ?? .null {
                    providers[entry.name] = nil
                    config["providers"] = .object(providers)
                }
            }
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
            return
        }
        var envNote = ""
        if let keyEnv = entry.keyEnv, !keyEnv.isEmpty {
            do {
                try await appState.performAdmin { client, config in
                    try await client.deleteEnvVar(config: config, key: keyEnv)
                }
            } catch {
                envNote = "（它的密钥还留在服务端，稍后可在「密钥」页删掉）"
            }
        }
        notice = "提供商 \(entry.name) 已删除。\(envNote)"
    }

    // MARK: - 组合（分配层）

    /// 保存一套组合（新建/编辑同口：按 id 替换或追加）
    func saveCombo(_ combo: ModelCombo, appState: AppState) async -> Bool {
        guard let config = appState.config else { return false }
        var document = comboDocument ?? .empty
        if let index = document.combos.firstIndex(where: { $0.id == combo.id }) {
            document.combos[index] = combo
        } else {
            document.combos.append(combo)
        }
        do {
            try await comboClient.saveDocument(config: config, document: document)
            comboDocument = document
            notice = "组合「\(combo.name)」已保存。"
            return true
        } catch {
            notice = "组合没能存到服务端，请稍后再试。"
            return false
        }
    }

    func deleteCombo(_ combo: ModelCombo, appState: AppState) async {
        guard let config = appState.config else { return }
        var document = comboDocument ?? .empty
        document.combos.removeAll { $0.id == combo.id }
        if document.activeComboID == combo.id {
            document.activeComboID = nil
        }
        do {
            try await comboClient.saveDocument(config: config, document: document)
            comboDocument = document
            notice = "组合「\(combo.name)」已删除。"
        } catch {
            notice = "删除没能存到服务端，请稍后再试。"
        }
    }

    /// 把当前配置存为第一套组合（起始示例口径：现状
    /// 快照、用户点名保存、可删改，不称推荐）
    func saveStarterCombo(appState: AppState) async {
        let starter = ComboStarter.fromCurrentConfig(
            rawConfig, id: UUID().uuidString, name: "当前配置",
            updatedAt: Date().timeIntervalSince1970
        )
        await saveCombo(starter, appState: appState)
    }

    /// 激活：读最新 config → Core 拼装 → 整包写回 →
    /// meta 标记激活。主模型若不在网关候选内（直连专
    /// 属模型）拦下不写——全局默认只有名字没有路，
    /// 写了也是坏的，如实说明。
    func activateCombo(_ combo: ModelCombo, appState: AppState) async {
        if let mainModel = combo.mainModel,
           !ModelCatalog.isWritable(mainModel, candidates: appState.availableModels) {
            notice = "这套组合的主模型 \(mainModel) 不在网关可用的模型里，没法设为全局默认；先在编辑里换一个，或把它放到某个槽位里按直连用。"
            return
        }
        do {
            let fresh = try await appState.performAdmin { client, config in
                try await client.rawConfig(config: config)
            }
            let mutated = ComboActivation.apply(combo, to: fresh)
            try await appState.performAdmin { client, config in
                try await client.updateConfig(config: config, newConfig: mutated)
            }
            rawConfig = mutated
            if let mainModel = combo.mainModel {
                appState.noteDefaultModel(mainModel)
            }
            if let config = appState.config {
                var document = comboDocument ?? .empty
                document.activeComboID = combo.id
                try? await comboClient.saveDocument(
                    config: config, document: document
                )
                comboDocument = document
            }
            notice = "组合「\(combo.name)」已启用。辅助槽位若没立刻变，随服务下次重启生效。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "启用失败，请稍后再试。"
        }
    }

    // MARK: - 写回底座（先读全量在本 store 的 rawConfig
    // 上改、整包写回；与旧页同纪律）

    private func writeBack(
        appState: AppState,
        _ mutate: (inout [String: JSONValue]) -> Void
    ) async throws {
        var updated = rawConfig
        mutate(&updated)
        try await appState.performAdmin { client, config in
            try await client.updateConfig(config: config, newConfig: updated)
        }
        rawConfig = updated
    }
}
