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

    // 辅助模型（§119）：自 rawConfig 派生的现行分配
    // 与两行 enabled 开关现值，load/写回后重算
    private(set) var auxAssignments: [String: AuxAssignment] = [:]
    private(set) var auxEnabled: [String: Bool] = [:]

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
            errorMessage = (error as? HermesError)?.userMessage ?? L10n.string("配置没读出来，可能是网络或服务暂时没响应")
        }
        await appState.refreshModelCatalog()
        if let config = appState.config {
            channelsFace = await frontClient.gatewayChannels(config: config)
        }
        await loadCombos(appState: appState)
        recomputeAux()
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
            notice = L10n.format("默认模型已切换为 %@。", model)
        } catch {
            notice = (error as? HermesError)?.userMessage ?? L10n.string("切换失败，请稍后再试。")
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
            notice = L10n.string("密钥没能保存到服务端，这家服务商还没加上。")
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
            notice = L10n.format("服务商 %@ 已添加。", name)
            return true
        } catch {
            notice = L10n.string("密钥已保存到服务端，但服务商条目没写成；再保存一次即可（同名密钥会被覆盖）。")
            return false
        }
    }

    /// 删除服务商：先查引用——有辅助模型或预设还指着
    /// 它就拦下并点名（§119 报告 3.1），不许删出悬空
    /// 引用；无引用才摘条目＋删 env 钥（删钥失败不回
    /// 滚条目删除——孤儿钥在服务端 env 里无引用、不生
    /// 效，notice 如实带一句）
    func deleteProvider(_ entry: ProviderRegistry.Entry, appState: AppState) async {
        let references = providerReferences(entry.name)
        if !references.isEmpty {
            notice = L10n.format(
                "「%@」正被这些地方用着：%@。先去改掉，再回来删。",
                entry.name, references.joined(separator: "、")
            )
            return
        }
        do {
            try await writeBack(appState: appState) { config in
                if case .object(var providers) = config["providers"] ?? .null {
                    providers[entry.name] = nil
                    config["providers"] = .object(providers)
                }
            }
        } catch {
            notice = (error as? HermesError)?.userMessage ?? L10n.string("删除失败，请稍后再试。")
            return
        }
        var envNote = ""
        if let keyEnv = entry.keyEnv, !keyEnv.isEmpty {
            do {
                try await appState.performAdmin { client, config in
                    try await client.deleteEnvVar(config: config, key: keyEnv)
                }
            } catch {
                envNote = L10n.string("（它的密钥还留在服务端，稍后可在「密钥」页删掉）")
            }
        }
        notice = L10n.format("服务商 %@ 已删除。%@", entry.name, envNote)
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
            notice = L10n.format("预设「%@」已保存。", combo.name)
            return true
        } catch {
            notice = L10n.string("预设没能存到服务端，请稍后再试。")
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
            notice = L10n.format("预设「%@」已删除。", combo.name)
        } catch {
            notice = L10n.string("删除没能存到服务端，请稍后再试。")
        }
    }

    /// 把当前设置存为一份预设（§119 快照口径：默认
    /// 模型＋全部用途的整套分配，跟随项也显式记下；
    /// 用户点名保存、可删改，不称推荐）
    func saveCurrentAsPreset(appState: AppState) async {
        let preset = PresetSnapshot.capture(
            config: rawConfig,
            namedProviders: providers.map(\.name),
            id: UUID().uuidString, name: L10n.string("当前配置"),
            updatedAt: Date().timeIntervalSince1970
        )
        await saveCombo(preset, appState: appState)
    }

    /// 激活：读最新 config → Core 拼装 → 整包写回 →
    /// meta 标记激活。主模型若不在网关候选内（直连专
    /// 属模型）拦下不写——全局默认只有名字没有路，
    /// 写了也是坏的，如实说明。
    func activateCombo(_ combo: ModelCombo, appState: AppState) async {
        if let mainModel = combo.mainModel,
           !ModelCatalog.isWritable(mainModel, candidates: appState.availableModels) {
            notice = L10n.format("这套预设的主模型 %@ 不在网关可用的模型里，没法设为全局默认；先在编辑里换一个，或在辅助模型里给某个用途指定它。", mainModel)
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
            notice = L10n.format("预设「%@」已启用。辅助模型若没立刻变，随服务下次重启生效。", combo.name)
        } catch {
            notice = (error as? HermesError)?.userMessage ?? L10n.string("启用失败，请稍后再试。")
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

// MARK: - §119 简化形态（服务商卡面＋辅助模型）

extension ModelManagementStore {

    /// 辅助面派生态重算（呈现只读本表，不各行现算）
    func recomputeAux() {
        let names = providers.map(\.name)
        auxAssignments = AuxAssignments.allAssignments(
            in: rawConfig, namedProviders: names
        )
        var enabled: [String: Bool] = [:]
        for slot in AuxSlotCatalog.all where slot.hasEnabledSwitch {
            enabled[slot.key] = AuxAssignments.enabled(
                in: rawConfig, slot: slot.key
            )
        }
        auxEnabled = enabled
    }

    /// 当前启用的预设是否含 MoA 分配（MoA 行显隐）
    var activePresetUsesMoA: Bool {
        guard let document = comboDocument,
              let active = document.combos.first(where: {
                  $0.id == document.activeComboID
              })
        else { return false }
        return PresetSnapshot.usesMoA(active)
    }

    /// 保存一行辅助分配：走 Dashboard config 全量写
    /// 回（通道选型见 DESIGN §119——与服务商/默认模
    /// 型同一条既有写路，不给伴生加新端点）；写回文
    /// 案如实标重启生效（热生效未验，§103.6 旧账③）
    func saveAux(
        slot key: String, assignment: AuxAssignment,
        enabled: Bool?, appState: AppState
    ) async {
        let staged = AuxAssignments.applying(
            assignment, enabled: enabled, slot: key, to: rawConfig
        )
        do {
            try await writeBack(appState: appState) { config in
                config["auxiliary"] = staged["auxiliary"]
            }
            recomputeAux()
            notice = L10n.string("已保存，下次重启 Hermes 后生效。")
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? L10n.string("保存失败，请稍后再试。")
        }
    }

    /// 谁在引用这家服务商：现行辅助分配（扫 config
    /// auxiliary 原始 provider 值，含注册表外用途）＋
    /// 已存预设。删卡前点名用
    func providerReferences(_ name: String) -> [String] {
        var out: [String] = []
        if case .object(let aux) = rawConfig["auxiliary"] ?? .null {
            for (key, value) in aux {
                guard case .object(let slotObject) = value,
                      slotObject["provider"]?.stringValue == name
                else { continue }
                out.append(L10n.format(
                    "辅助模型 · %@", AuxSlotCatalog.title(forKey: key)
                ))
            }
        }
        for combo in comboDocument?.combos ?? []
        where combo.aux.values.contains(where: { $0.provider == name }) {
            out.append(L10n.format("预设「%@」", combo.name))
        }
        return out.sorted()
    }

    // MARK: 测连接（三态；密钥经 reveal 只过手不留存）

    func testConnection(
        entry: ProviderRegistry.Entry, appState: AppState
    ) async -> ProviderConnectionOutcome {
        guard let baseURL = entry.baseURL, !baseURL.isEmpty else {
            return .failed(message: L10n.string("这家服务商还没填接口地址。"))
        }
        guard let keyEnv = entry.keyEnv, !keyEnv.isEmpty else {
            return .failed(message: L10n.string("这家服务商还没保存密钥。"))
        }
        do {
            let key = try await appState.performAdmin { client, config in
                try await client.revealEnvVar(config: config, key: keyEnv)
            }
            let models = try await probeClient.fetchModels(
                baseURL: baseURL, apiKey: key
            )
            return .connected(modelCount: models.count)
        } catch let error as ProviderProbeClient.ProbeFailure {
            return error.connectionOutcome
        } catch HermesError.demoLimitReached {
            // 演示空态（第 4 项）：取钥面在演示里不存在，
            // 统一文案一条
            return .failed(message: HermesError.demoLimitReached.userMessage)
        } catch {
            return .failed(message: L10n.string("测试没能完成，请稍后再试。"))
        }
    }

    /// 默认服务商（主通道）测连接：以目录刷新结果
    /// 为准——读到清单即连通
    func testMainEndpoint(
        appState: AppState
    ) async -> ProviderConnectionOutcome {
        await appState.refreshModelCatalog()
        return appState.availableModels.isEmpty
            ? .failed(message: L10n.string("没能读到网关的模型清单，检查网络与登录状态后再试。"))
            : .connected(modelCount: appState.availableModels.count)
    }

    // MARK: 清单刷新（先报差异，确认后才写）

    /// 拉新清单但不落盘：回结局＋新清单（连通时）
    func fetchRefreshedModels(
        entry: ProviderRegistry.Entry, appState: AppState
    ) async -> (outcome: ProviderConnectionOutcome, models: [String]?) {
        guard let baseURL = entry.baseURL, !baseURL.isEmpty,
              let keyEnv = entry.keyEnv, !keyEnv.isEmpty
        else {
            return (.failed(message: L10n.string("这家服务商还没填接口地址。")), nil)
        }
        do {
            let key = try await appState.performAdmin { client, config in
                try await client.revealEnvVar(config: config, key: keyEnv)
            }
            let models = try await probeClient.fetchModels(
                baseURL: baseURL, apiKey: key
            )
            return (.connected(modelCount: models.count), models)
        } catch let error as ProviderProbeClient.ProbeFailure {
            let outcome = error.connectionOutcome
            return (outcome, nil)
        } catch HermesError.demoLimitReached {
            return (.failed(message: HermesError.demoLimitReached.userMessage), nil)
        } catch {
            return (.failed(message: L10n.string("拉取没能完成，请稍后再试。")), nil)
        }
    }

    private func stashKey(for providerName: String) -> String {
        "providerPrevModels.\(providerName)"
    }

    /// 上一份清单（本机存模型名清单，非敏感；刷新
    /// 落盘时暂存，供「恢复上一份」）
    func previousModels(for entry: ProviderRegistry.Entry) -> [String]? {
        guard let data = UserDefaults.standard.data(
            forKey: stashKey(for: entry.name)
        ),
        let models = try? JSONDecoder().decode([String].self, from: data),
        models != entry.models
        else { return nil }
        return models
    }

    /// 确认后落盘新清单：先把现清单暂存为「上一份」
    func applyRefreshedModels(
        entry: ProviderRegistry.Entry, models: [String],
        appState: AppState
    ) async {
        if let data = try? JSONEncoder().encode(entry.models) {
            UserDefaults.standard.set(
                data, forKey: stashKey(for: entry.name)
            )
        }
        var updated = entry
        updated.models = models
        do {
            try await writeProviderEntry(updated, appState: appState)
            notice = L10n.format("「%@」的模型清单已更新，共 %lld 个。", entry.name, models.count)
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? L10n.string("清单没能保存，请稍后再试。")
        }
    }

    /// 恢复上一份清单（与现清单互换，恢复本身可再撤）
    func restorePreviousModels(
        entry: ProviderRegistry.Entry, appState: AppState
    ) async {
        guard let previous = previousModels(for: entry) else { return }
        if let data = try? JSONEncoder().encode(entry.models) {
            UserDefaults.standard.set(
                data, forKey: stashKey(for: entry.name)
            )
        }
        var updated = entry
        updated.models = previous
        do {
            try await writeProviderEntry(updated, appState: appState)
            notice = L10n.format("「%@」的模型清单已恢复到上一份，共 %lld 个。", entry.name, previous.count)
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? L10n.string("恢复没能保存，请稍后再试。")
        }
    }

    // MARK: 编辑服务商

    /// 编辑：改地址/清单；新密钥非空才经 /api/env 覆
    /// 盖（留空＝保留已存），条目只存 key_env 引用
    func updateProvider(
        entry: ProviderRegistry.Entry, baseURL: String,
        newKey: String, models: [String], appState: AppState
    ) async -> Bool {
        var updated = entry
        updated.baseURL = baseURL
        updated.models = models
        if updated.keyEnv == nil {
            updated.keyEnv = ProviderRegistry.envKey(
                forProviderName: entry.name
            )
        }
        if !newKey.isEmpty {
            do {
                try await appState.performAdmin { client, config in
                    try await client.setEnvVar(
                        config: config,
                        key: updated.keyEnv ?? "", value: newKey
                    )
                }
            } catch {
                notice = L10n.string("新密钥没能保存到服务端，这次修改还没生效。")
                return false
            }
        }
        do {
            try await writeProviderEntry(updated, appState: appState)
            notice = L10n.format("服务商 %@ 已更新。", entry.name)
            return true
        } catch {
            notice = (error as? HermesError)?.userMessage
                ?? L10n.string("修改没能保存，请稍后再试。")
            return false
        }
    }

    /// 条目写回底座（providers 字典只动点名条目）
    private func writeProviderEntry(
        _ entry: ProviderRegistry.Entry, appState: AppState
    ) async throws {
        try await writeBack(appState: appState) { config in
            var providers: [String: JSONValue] = [:]
            if case .object(let existing) = config["providers"] ?? .null {
                providers = existing
            }
            providers[entry.name] = ProviderRegistry.configValue(for: entry)
            config["providers"] = .object(providers)
        }
    }
}
