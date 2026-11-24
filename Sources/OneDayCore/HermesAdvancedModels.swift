import Foundation

/// 高级能力面模型（H8 委派路由／H9 MoA＋辅助端点／H11 Webhooks／
/// H13 小件：curator＋sessions/stats＋ops/hooks；DESIGN §390）。
///
/// 契约冻结依据＝官方仓 v0.23.0 源码逐 handler 实查（2026-11-23）：
/// - 委派：hermes_cli/web_routers/delegation.py——GET /api/delegation/
///   routing 回 {configured, blocked_reason, backends[{name,label,
///   description,available,reason,builtin}], model_map{options,
///   default}, profile_routes{profiles,default}, profiles[]}；写口
///   PUT /api/delegation/backend {backend}、PUT .../backends/model_map
///   {options,default}（整块替换、逐条校验：name/description/model
///   必填、provider 或 base_url 至少其一、default 须在名单内、名
///   不许重复；api_key 回的是脱敏预览、原样带回服务端保留真钥）、
///   PUT .../backends/profile_routes {profiles,default}（名必须是
///   已存在档案、不许重复、default 须在名单内）。
/// - MoA：web_routers/models.py——GET /api/model/moa 回 normalize
///   形 {default_preset, active_preset, presets{名: preset}, 平铺
///   兼容字段, privacy_filter}；PUT /api/model/moa 收 MoaConfig-
///   Payload（presets 整图为权威、省名即删），写前 validate_moa_
///   payload 硬拒（每 preset 至少一个完整 reference 槽＋aggrega-
///   tor 完整，槽完整＝provider 与 model 都非空，422 连问题上行）。
/// - 辅助：GET /api/model/auxiliary 回 {tasks[{task,provider,
///   model,base_url,reasoning_effort,local_endpoint,插件行另带
///   label/hint/plugin/inherit_from/effective}], main{provider,
///   model}}；POST /api/model/set {scope,task,provider,model,...}
///   写同一 config.yaml 的 auxiliary 节（贵模型确认时回 ok:false
///   ＋confirm_required，带 confirm_expensive_model 重发才落）。
/// - Webhooks：web_routers/ops.py——GET /api/webhooks 回
///   {enabled, base_url, subscriptions[摘要]}（摘要含 url 与
///   secret_set、永不回密钥本体）；POST /api/webhooks 建订阅、
///   密钥只在建时回一次；DELETE /api/webhooks/{name}；PUT
///   /api/webhooks/{name}/enabled {enabled}（热生效）；POST
///   /api/webhooks/enable 开平台（触发网关重启、回 needs_restart）。
/// - Curator：web_routers/status.py——GET /api/curator 回
///   {enabled,paused,interval_hours,last_run_at,min_idle_hours,
///   stale_after_days,archive_after_days}；PUT /api/curator/paused
///   {paused}；POST /api/curator/run（后台动作，回 {ok,pid,name}，
///   多档案在役时须带 profile 指名）。
/// - 会话统计：GET /api/sessions/stats 回 {total, active_store,
///   archived, messages, by_source{}}（口径 exclude_children=
///   true：压缩链折一行，与会话名单同口径）。
/// - 钩子：GET /api/ops/hooks 回 {hooks[{event,matcher,command,
///   timeout,allowed,approved_at,executable}], valid_events[]}。
///
/// 解析一律走 JSONValue 容错形（与 KanbanModels 同法）：服务端
/// 字段增减不炸解码；呈现层只认本文件钉死的字段口径。

// MARK: - 共用取数（JSONValue 字典口）

extension JSONValue {
    /// 本文件专用（KanbanModels 的同名访问器是
    /// fileprivate、跨文件不可见，故自带一份）
    fileprivate var advObjectDict: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    fileprivate var advArrayValues: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }
}

private func advString(_ dict: [String: JSONValue], _ key: String) -> String {
    dict[key]?.stringValue ?? ""
}

private func advBool(_ dict: [String: JSONValue], _ key: String, fallback: Bool = false) -> Bool {
    dict[key]?.boolValue ?? fallback
}

private func advNumber(_ dict: [String: JSONValue], _ key: String) -> Double? {
    if case .number(let value) = dict[key] ?? .null { return value }
    return nil
}

private func advDict(_ dict: [String: JSONValue], _ key: String) -> [String: JSONValue] {
    dict[key]?.advObjectDict ?? [:]
}

private func advArray(_ dict: [String: JSONValue], _ key: String) -> [JSONValue] {
    dict[key]?.advArrayValues ?? []
}

// MARK: - H8 委派路由

/// 一个可委派后端（官方 BackendInfo ＋ router 补的 builtin）
public struct DelegationBackendInfo: Equatable, Sendable, Identifiable {
    public var name: String
    public var label: String
    public var description: String
    public var available: Bool
    /// 不可用原因（available 为真时为空串）
    public var reason: String
    public var builtin: Bool

    public var id: String { name }

    public init(
        name: String, label: String = "", description: String = "",
        available: Bool, reason: String = "", builtin: Bool = false
    ) {
        self.name = name
        self.label = label
        self.description = description
        self.available = available
        self.reason = reason
        self.builtin = builtin
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        self.init(
            name: advString(dict, "name"),
            label: advString(dict, "label"),
            description: advString(dict, "description"),
            available: advBool(dict, "available"),
            reason: advString(dict, "reason"),
            builtin: advBool(dict, "builtin")
        )
    }

    /// 呈现名：label 缺失回落 name 本体，不编造
    public var displayLabel: String { label.isEmpty ? name : label }
}

/// 一条模型路由（model_map 的一个 option）：重活/杂活分流的
/// 命名路线，智能体读 description 选路。未知字段进 extras、
/// 写回时原样带回（服务端 ROUTE_KEYS 内的字段靠提交条目往返
/// 保全，客户端吞掉即丢配置）。
public struct DelegationModelRoute: Equatable, Sendable, Identifiable {
    public var name: String
    public var routeDescription: String
    public var provider: String
    public var model: String
    public var baseURL: String
    public var apiMode: String
    public var reasoningEffort: String
    public var serviceTier: String
    /// 读回的脱敏预览（非空＝服务端已存密钥）；写回原样带回、
    /// 服务端识别预览后保留真钥——客户端永不经手真钥
    public var apiKeyPreview: String
    /// 本文件未建模的原始字段（往返保全用）
    public var extras: [String: JSONValue]
    /// 编辑态（不来自服务端）：改名前的原名——写回时带
    /// original_name 让服务端把密钥预览对回原条目真钥
    public var originalName: String?
    /// 编辑态（不来自服务端）：用户新填的密钥——非空时
    /// 优先于预览写回；客户端只在提交瞬间经手、落盘在服务端
    public var pendingAPIKey: String?

    public var id: String { name }

    public init(
        name: String, routeDescription: String = "", provider: String = "",
        model: String = "", baseURL: String = "", apiMode: String = "",
        reasoningEffort: String = "", serviceTier: String = "",
        apiKeyPreview: String = "", extras: [String: JSONValue] = [:],
        originalName: String? = nil, pendingAPIKey: String? = nil
    ) {
        self.name = name
        self.routeDescription = routeDescription
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
        self.apiMode = apiMode
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
        self.apiKeyPreview = apiKeyPreview
        self.extras = extras
        self.originalName = originalName
        self.pendingAPIKey = pendingAPIKey
    }

    private static let modeledKeys: Set<String> = [
        "name", "description", "provider", "model", "base_url",
        "api_mode", "reasoning_effort", "service_tier", "api_key",
    ]

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        var extras: [String: JSONValue] = [:]
        for (key, value) in dict where !Self.modeledKeys.contains(key) {
            extras[key] = value
        }
        self.init(
            name: advString(dict, "name"),
            routeDescription: advString(dict, "description"),
            provider: advString(dict, "provider"),
            model: advString(dict, "model"),
            baseURL: advString(dict, "base_url"),
            apiMode: advString(dict, "api_mode"),
            reasoningEffort: advString(dict, "reasoning_effort"),
            serviceTier: advString(dict, "service_tier"),
            apiKeyPreview: advString(dict, "api_key"),
            extras: extras
        )
    }

    /// PUT 条目拼装：空字段不发（服务端按缺失处理）；密钥只发
    /// 预览或用户新填值（pendingAPIKey 非空优先），改名时带
    /// original_name 让服务端把预览对回原条目的真钥
    public func putFields() -> [String: JSONValue] {
        var out = extras
        out["name"] = .string(name)
        if !routeDescription.isEmpty { out["description"] = .string(routeDescription) }
        if !provider.isEmpty { out["provider"] = .string(provider) }
        if !model.isEmpty { out["model"] = .string(model) }
        if !baseURL.isEmpty { out["base_url"] = .string(baseURL) }
        if !apiMode.isEmpty { out["api_mode"] = .string(apiMode) }
        if !reasoningEffort.isEmpty { out["reasoning_effort"] = .string(reasoningEffort) }
        if !serviceTier.isEmpty { out["service_tier"] = .string(serviceTier) }
        if let pendingAPIKey, !pendingAPIKey.isEmpty {
            out["api_key"] = .string(pendingAPIKey)
        } else if !apiKeyPreview.isEmpty {
            out["api_key"] = .string(apiKeyPreview)
        }
        if let originalName, originalName != name {
            out["original_name"] = .string(originalName)
        }
        return out
    }
}

/// 一条档案路由（profile_routes 的一个 profile 条目）
public struct DelegationProfileRoute: Equatable, Sendable, Identifiable {
    public var name: String
    public var routeDescription: String

    public var id: String { name }

    public init(name: String, routeDescription: String = "") {
        self.name = name
        self.routeDescription = routeDescription
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        self.init(
            name: advString(dict, "name"),
            routeDescription: advString(dict, "description")
        )
    }

    public func putFields() -> [String: JSONValue] {
        var out: [String: JSONValue] = ["name": .string(name)]
        if !routeDescription.isEmpty {
            out["description"] = .string(routeDescription)
        }
        return out
    }
}

/// GET /api/delegation/routing 全量读数（当前档案口径）
public struct DelegationRouting: Equatable, Sendable {
    /// 现行委派后端名（config 的 delegation.backend）
    public var configured: String
    /// 现行后端在本机跑不了的原因（nil＝能跑）
    public var blockedReason: String?
    public var backends: [DelegationBackendInfo]
    public var modelRoutes: [DelegationModelRoute]
    public var modelRouteDefault: String?
    public var profileRoutes: [DelegationProfileRoute]
    public var profileRouteDefault: String?
    /// 全部已存在档案名（档案路由只能指这里的名字）
    public var profiles: [String]

    public init(
        configured: String, blockedReason: String? = nil,
        backends: [DelegationBackendInfo] = [],
        modelRoutes: [DelegationModelRoute] = [],
        modelRouteDefault: String? = nil,
        profileRoutes: [DelegationProfileRoute] = [],
        profileRouteDefault: String? = nil,
        profiles: [String] = []
    ) {
        self.configured = configured
        self.blockedReason = blockedReason
        self.backends = backends
        self.modelRoutes = modelRoutes
        self.modelRouteDefault = modelRouteDefault
        self.profileRoutes = profileRoutes
        self.profileRouteDefault = profileRouteDefault
        self.profiles = profiles
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        let modelMap = advDict(dict, "model_map")
        let profileRoutesDict = advDict(dict, "profile_routes")
        self.init(
            configured: advString(dict, "configured"),
            blockedReason: dict["blocked_reason"]?.stringValue,
            backends: advArray(dict, "backends").map(DelegationBackendInfo.init),
            modelRoutes: advArray(modelMap, "options").map(DelegationModelRoute.init),
            modelRouteDefault: modelMap["default"]?.stringValue,
            profileRoutes: advArray(profileRoutesDict, "profiles").map(DelegationProfileRoute.init),
            profileRouteDefault: profileRoutesDict["default"]?.stringValue,
            profiles: advArray(dict, "profiles").compactMap(\.stringValue)
        )
    }
}

/// 委派写口的本地预检（与服务端校验逐条同义，DESIGN §390）：
/// 先在本地拦下必被 400 的提交，把服务端原文留作终局口径。
public enum DelegationValidation {
    /// 模型路由整块校验：逐条 name/description/model 必填、
    /// provider 或 base_url 至少其一、名不重复、default 在名单内
    public static func modelRouteProblems(
        routes: [DelegationModelRoute], defaultRoute: String?
    ) -> [String] {
        var problems: [String] = []
        var seen: Set<String> = []
        for (index, route) in routes.enumerated() {
            let label = route.name.isEmpty
                ? "第 \(index + 1) 条路线" : "路线「\(route.name)」"
            if route.name.isEmpty {
                problems.append("第 \(index + 1) 条路线缺名字。")
            } else if !seen.insert(route.name).inserted {
                problems.append("两条路线都叫「\(route.name)」，名字不能重复。")
            }
            if route.routeDescription.isEmpty {
                problems.append("\(label)缺说明——智能体靠说明选路，不能空着。")
            }
            if route.model.isEmpty {
                problems.append("\(label)缺模型。")
            }
            if route.provider.isEmpty && route.baseURL.isEmpty {
                problems.append("\(label)缺服务商（或自定义地址）。")
            }
        }
        if let defaultRoute, !defaultRoute.isEmpty,
           !routes.contains(where: { $0.name == defaultRoute }) {
            problems.append("默认路线「\(defaultRoute)」不在路线名单里。")
        }
        return problems
    }

    /// 档案路由整块校验：名必须是已存在档案、不重复、default 在名单内
    public static func profileRouteProblems(
        routes: [DelegationProfileRoute], defaultRoute: String?,
        knownProfiles: [String]
    ) -> [String] {
        var problems: [String] = []
        var seen: Set<String> = []
        for route in routes {
            if route.name.isEmpty {
                problems.append("有一条档案路由没选档案。")
                continue
            }
            if !knownProfiles.contains(route.name) {
                problems.append("档案「\(route.name)」不存在。")
            }
            if !seen.insert(route.name).inserted {
                problems.append("档案「\(route.name)」在名单里出现了两次。")
            }
        }
        if let defaultRoute, !defaultRoute.isEmpty,
           !routes.contains(where: { $0.name == defaultRoute }) {
            problems.append("默认档案「\(defaultRoute)」不在名单里。")
        }
        return problems
    }
}

// MARK: - H9 MoA（多模型会商）

/// 一个 MoA 槽位（reference 一员或 aggregator 本体）
public struct MoaSlot: Equatable, Sendable {
    public var provider: String
    public var model: String
    /// nil＝不特别指定（写时不发该键）
    public var reasoningEffort: String?
    public var enabled: Bool

    public init(
        provider: String = "", model: String = "",
        reasoningEffort: String? = nil, enabled: Bool = true
    ) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.enabled = enabled
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        self.init(
            provider: advString(dict, "provider"),
            model: advString(dict, "model"),
            reasoningEffort: dict["reasoning_effort"]?.stringValue,
            enabled: advBool(dict, "enabled", fallback: true)
        )
    }

    /// 槽完整＝provider 与 model 都非空（服务端 _slot_problem 口径）
    public var isComplete: Bool { !provider.isEmpty && !model.isEmpty }

    public func putFields(includeEnabled: Bool) -> [String: JSONValue] {
        var out: [String: JSONValue] = [
            "provider": .string(provider),
            "model": .string(model),
        ]
        if let reasoningEffort { out["reasoning_effort"] = .string(reasoningEffort) }
        if includeEnabled { out["enabled"] = .bool(enabled) }
        return out
    }
}

/// 一份 MoA 预设：多家参考模型先各自给意见、汇总模型合成一份
public struct MoaPreset: Equatable, Sendable {
    public var referenceModels: [MoaSlot]
    public var aggregator: MoaSlot
    public var referenceTemperature: Double?
    public var aggregatorTemperature: Double?
    public var referenceTimeout: Double?
    /// 参考模型失败时的披露策略："loud"（明说）／"silent"
    public var degradedReferencePolicy: String
    public var fanout: String?
    public var enabled: Bool

    public init(
        referenceModels: [MoaSlot] = [], aggregator: MoaSlot = MoaSlot(),
        referenceTemperature: Double? = nil, aggregatorTemperature: Double? = nil,
        referenceTimeout: Double? = nil, degradedReferencePolicy: String = "loud",
        fanout: String? = nil, enabled: Bool = true
    ) {
        self.referenceModels = referenceModels
        self.aggregator = aggregator
        self.referenceTemperature = referenceTemperature
        self.aggregatorTemperature = aggregatorTemperature
        self.referenceTimeout = referenceTimeout
        self.degradedReferencePolicy = degradedReferencePolicy
        self.fanout = fanout
        self.enabled = enabled
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        self.init(
            referenceModels: advArray(dict, "reference_models").map(MoaSlot.init),
            aggregator: MoaSlot(jsonValue: dict["aggregator"] ?? .null),
            referenceTemperature: advNumber(dict, "reference_temperature"),
            aggregatorTemperature: advNumber(dict, "aggregator_temperature"),
            referenceTimeout: advNumber(dict, "reference_timeout"),
            degradedReferencePolicy: advString(dict, "degraded_reference_policy").isEmpty
                ? "loud" : advString(dict, "degraded_reference_policy"),
            fanout: dict["fanout"]?.stringValue,
            enabled: advBool(dict, "enabled", fallback: true)
        )
    }

    /// 写时校验（服务端 validate_moa_payload 同义）：至少一个
    /// 完整参考槽＋汇总槽完整；不完整不许发（服务端 422 硬拒、
    /// 且读时容错会把半填预设静默换成出厂默认＝数据丢失）
    public func problems(named name: String) -> [String] {
        var problems: [String] = []
        for (index, slot) in referenceModels.enumerated() where !slot.isComplete {
            problems.append("预设「\(name)」第 \(index + 1) 个参考模型还没选全（服务商和模型都要选）。")
        }
        if !referenceModels.contains(where: \.isComplete) {
            problems.append("预设「\(name)」至少要有一个完整的参考模型。")
        }
        if !aggregator.isComplete {
            problems.append("预设「\(name)」的汇总模型还没选全（服务商和模型都要选）。")
        }
        return problems
    }

    public func putFields() -> [String: JSONValue] {
        var out: [String: JSONValue] = [
            "reference_models": .array(referenceModels.map {
                .object($0.putFields(includeEnabled: true))
            }),
            "aggregator": .object(aggregator.putFields(includeEnabled: false)),
            "degraded_reference_policy": .string(degradedReferencePolicy),
            "enabled": .bool(enabled),
        ]
        if let referenceTemperature { out["reference_temperature"] = .number(referenceTemperature) }
        if let aggregatorTemperature { out["aggregator_temperature"] = .number(aggregatorTemperature) }
        if let referenceTimeout { out["reference_timeout"] = .number(referenceTimeout) }
        if let fanout { out["fanout"] = .string(fanout) }
        return out
    }
}

/// GET /api/model/moa 全量读数（normalize 形）
public struct MoaConfig: Equatable, Sendable {
    public var defaultPreset: String
    /// 空串＝未单独指定生效预设（用 defaultPreset）
    public var activePreset: String
    /// 预设名 → 预设（字典序呈现，服务端 map 无序）
    public var presets: [String: MoaPreset]

    public var presetNames: [String] { presets.keys.sorted() }

    /// 实际生效的预设名（active 非空取 active、否则 default）
    public var effectivePresetName: String {
        activePreset.isEmpty ? defaultPreset : activePreset
    }

    public init(
        defaultPreset: String = "default", activePreset: String = "",
        presets: [String: MoaPreset] = [:]
    ) {
        self.defaultPreset = defaultPreset
        self.activePreset = activePreset
        self.presets = presets
    }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        var presets: [String: MoaPreset] = [:]
        for (name, value) in advDict(dict, "presets") {
            presets[name] = MoaPreset(jsonValue: value)
        }
        self.init(
            defaultPreset: advString(dict, "default_preset").isEmpty
                ? "default" : advString(dict, "default_preset"),
            activePreset: advString(dict, "active_preset"),
            presets: presets
        )
    }

    /// PUT 整图拼装（presets 整图权威：图里没有的名字＝删除）
    public func putBody() -> [String: JSONValue] {
        var presetFields: [String: JSONValue] = [:]
        for (name, preset) in presets {
            presetFields[name] = .object(preset.putFields())
        }
        return [
            "default_preset": .string(defaultPreset),
            "active_preset": .string(activePreset),
            "presets": .object(presetFields),
        ]
    }

    /// 全部预设的写时校验汇总（任一不过＝整图不发）
    public func allProblems() -> [String] {
        presetNames.flatMap { presets[$0]?.problems(named: $0) ?? [] }
    }

    /// 模型选择器的会商组：每个预设一行（provider=moa、
    /// model=预设名——发送层逐请求带 provider 字段、服务端
    /// 按预设名解析 Moa 运行时，agent/agent_init 实证）
    public func pickerGroup() -> ChatModelGroup {
        ChatModelGroup(
            title: "多模型会商",
            choices: presetNames.map { name in
                ChatModelChoice(
                    model: name, providerField: "moa",
                    isDefault: name == effectivePresetName
                )
            }
        )
    }
}

// MARK: - H9 辅助模型专用端点

/// GET /api/model/auxiliary 的一行（一个辅助用途的现行分配）
public struct AuxiliaryTaskRow: Equatable, Sendable, Identifiable {
    public var task: String
    public var provider: String
    public var model: String
    public var baseURL: String
    public var reasoningEffort: String?
    /// base_url 指向本机/局域网端点（免费本地 vs 付费在册的提示位）
    public var localEndpoint: Bool
    /// 插件注册行才带（内置行由客户端注册表命名）
    public var label: String?
    public var hint: String?
    public var plugin: String?
    /// 继承自哪个基础槽（非 nil 时本行未钉死、effective 为现行解析值）
    public var inheritFrom: String?
    public var effectiveProvider: String?
    public var effectiveModel: String?

    public var id: String { task }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        let effective = advDict(dict, "effective")
        task = advString(dict, "task")
        provider = advString(dict, "provider")
        model = advString(dict, "model")
        baseURL = advString(dict, "base_url")
        reasoningEffort = dict["reasoning_effort"]?.stringValue
        localEndpoint = advBool(dict, "local_endpoint")
        label = dict["label"]?.stringValue
        hint = dict["hint"]?.stringValue
        plugin = dict["plugin"]?.stringValue
        inheritFrom = dict["inherit_from"]?.stringValue
        effectiveProvider = effective["provider"]?.stringValue
        effectiveModel = effective["model"]?.stringValue
    }

    /// 换算成辅助面现行分配口径（与 config 读形同一 AuxAssignment
    /// 归一：provider "auto"＝跟随、写了模型归默认服务商指定）
    public func assignment(namedProviders: [String]) -> AuxAssignment {
        AuxAssignment.from(
            choice: SlotChoice(provider: provider, model: model),
            namedProviders: namedProviders
        )
    }
}

/// GET /api/model/auxiliary 全量读数
public struct AuxiliaryTasksResponse: Equatable, Sendable {
    public var tasks: [AuxiliaryTaskRow]
    public var mainProvider: String
    public var mainModel: String

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        let main = advDict(dict, "main")
        tasks = advArray(dict, "tasks").map(AuxiliaryTaskRow.init)
        mainProvider = advString(main, "provider")
        mainModel = advString(main, "model")
    }

    public func row(forTask task: String) -> AuxiliaryTaskRow? {
        tasks.first { $0.task == task }
    }
}

/// POST /api/model/set 回执：贵模型未确认时 ok=false＋
/// confirm_required=true（不是错误——带确认重发才落盘）
public struct ModelSetReceipt: Equatable, Sendable {
    public var ok: Bool
    public var confirmRequired: Bool
    public var confirmMessage: String?

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        ok = advBool(dict, "ok")
        confirmRequired = advBool(dict, "confirm_required")
        confirmMessage = dict["confirm_message"]?.stringValue
    }
}

// MARK: - H11 Webhooks

/// 一条 webhook 订阅（读摘要：含投递地址与 secret_set、
/// 永不含密钥本体）
public struct WebhookRoute: Equatable, Sendable, Identifiable {
    public var name: String
    public var routeDescription: String
    public var events: [String]
    /// 投递目标："log"＝只记日志，或平台名（telegram 等）
    public var deliver: String
    public var deliverOnly: Bool
    public var prompt: String
    public var script: String
    public var skills: [String]
    public var createdAt: String?
    /// 外部系统要打的完整地址（服务端按 base_url 拼）
    public var url: String
    public var secretSet: Bool
    public var enabled: Bool

    public var id: String { name }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        name = advString(dict, "name")
        routeDescription = advString(dict, "description")
        events = advArray(dict, "events").compactMap(\.stringValue)
        deliver = advString(dict, "deliver")
        deliverOnly = advBool(dict, "deliver_only")
        prompt = advString(dict, "prompt")
        script = advString(dict, "script")
        skills = advArray(dict, "skills").compactMap(\.stringValue)
        createdAt = dict["created_at"]?.stringValue
        url = advString(dict, "url")
        secretSet = advBool(dict, "secret_set")
        enabled = advBool(dict, "enabled", fallback: true)
    }
}

/// GET /api/webhooks 全量读数
public struct WebhooksPage: Equatable, Sendable {
    /// webhook 平台总开关（关时建订阅被服务端拒）
    public var platformEnabled: Bool
    public var baseURL: String
    public var subscriptions: [WebhookRoute]

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        platformEnabled = advBool(dict, "enabled")
        baseURL = advString(dict, "base_url")
        subscriptions = advArray(dict, "subscriptions").map(WebhookRoute.init)
    }
}

/// 建订阅入参（POST /api/webhooks）
public struct WebhookCreateInput: Equatable, Sendable {
    public var name: String
    public var routeDescription: String
    public var events: [String]
    public var prompt: String
    public var skills: [String]
    public var deliver: String
    public var deliverOnly: Bool
    public var deliverChatID: String

    public init(
        name: String, routeDescription: String = "", events: [String] = [],
        prompt: String = "", skills: [String] = [], deliver: String = "log",
        deliverOnly: Bool = false, deliverChatID: String = ""
    ) {
        self.name = name
        self.routeDescription = routeDescription
        self.events = events
        self.prompt = prompt
        self.skills = skills
        self.deliver = deliver
        self.deliverOnly = deliverOnly
        self.deliverChatID = deliverChatID
    }

    /// 服务端命名规范化同义：小写、空格转连字符
    public static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// 命名预检（服务端正则 ^[a-z0-9][a-z0-9_-]*$ 同义）
    public static func nameProblem(_ raw: String) -> String? {
        let name = normalizedName(raw)
        if name.isEmpty { return "先给这条订阅起个名字。" }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-"
        )
        guard let first = name.first, first.isLetter || first.isNumber,
              name.unicodeScalars.allSatisfy(allowed.contains) else {
            return "名字只能用小写字母、数字、连字符和下划线，并以字母或数字开头。"
        }
        return nil
    }

    /// 直达投递（deliver_only）须有真实目标，deliver=log 被服务端拒
    public var problems: [String] {
        var out: [String] = []
        if let problem = Self.nameProblem(name) { out.append(problem) }
        if deliverOnly && deliver == "log" {
            out.append("直达投递要选一个真实目标（只记日志不行）。")
        }
        return out
    }

    public func putBody() -> [String: JSONValue] {
        var out: [String: JSONValue] = [
            "name": .string(Self.normalizedName(name)),
            "events": .array(events.map(JSONValue.string)),
            "skills": .array(skills.map(JSONValue.string)),
            "deliver": .string(deliver),
            "deliver_only": .bool(deliverOnly),
        ]
        if !routeDescription.isEmpty { out["description"] = .string(routeDescription) }
        if !prompt.isEmpty { out["prompt"] = .string(prompt) }
        if !deliverChatID.isEmpty { out["deliver_chat_id"] = .string(deliverChatID) }
        return out
    }
}

/// 建订阅回执＝订阅摘要＋一次性密钥（只此一次回，丢了只能删建）
public struct WebhookCreateReceipt: Equatable, Sendable {
    public var route: WebhookRoute
    public var secret: String?

    public init(jsonValue: JSONValue) {
        route = WebhookRoute(jsonValue: jsonValue)
        secret = (jsonValue.advObjectDict ?? [:])["secret"]?.stringValue
    }
}

/// POST /api/webhooks/enable 回执（开平台伴随网关重启编排）
public struct WebhooksEnableReceipt: Equatable, Sendable {
    public var ok: Bool
    /// true＝重启没自动起来、需人工处理（回执原文口径）
    public var needsRestart: Bool

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        ok = advBool(dict, "ok")
        needsRestart = advBool(dict, "needs_restart")
    }
}

// MARK: - H13 小件：curator／会话统计／钩子

/// GET /api/curator：技能策展（curator）自动半边的状态面——
/// 它在后台定期复盘整理技能库（归档陈旧技能等），本面只呈现
/// 状态＋暂停/恢复＋立即跑一次，策展本体在服务端
public struct CuratorStatus: Equatable, Sendable {
    public var enabled: Bool
    public var paused: Bool
    public var intervalHours: Double?
    public var lastRunAt: String?
    public var minIdleHours: Double?
    public var staleAfterDays: Double?
    public var archiveAfterDays: Double?

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        enabled = advBool(dict, "enabled")
        paused = advBool(dict, "paused")
        intervalHours = advNumber(dict, "interval_hours")
        lastRunAt = dict["last_run_at"]?.stringValue
        minIdleHours = advNumber(dict, "min_idle_hours")
        staleAfterDays = advNumber(dict, "stale_after_days")
        archiveAfterDays = advNumber(dict, "archive_after_days")
    }
}

/// GET /api/sessions/stats：会话存储统计（口径复核落点——
/// exclude_children=true 与会话名单折行同口径；App 既有
/// /api/system/stats 是系统面统计、两者不同物，见 §390）
public struct SessionStoreStats: Equatable, Sendable {
    public struct SourceCount: Equatable, Sendable, Identifiable {
        public var source: String
        public var count: Int
        public var id: String { source }
    }

    public var total: Int
    public var activeStore: Int
    public var archived: Int
    public var messages: Int
    public var bySource: [SourceCount]

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        func intValue(_ key: String) -> Int {
            Int(advNumber(dict, key) ?? 0)
        }
        total = intValue("total")
        activeStore = intValue("active_store")
        archived = intValue("archived")
        messages = intValue("messages")
        bySource = advDict(dict, "by_source")
            .map { pair in
                let count: Int
                if case .number(let number) = pair.value {
                    count = Int(number)
                } else {
                    count = 0
                }
                return SourceCount(source: pair.key, count: count)
            }
            .sorted { $0.count > $1.count }
    }
}

/// 一条已配置的 shell 钩子（GET /api/ops/hooks 只读面对账用：
/// Hermes 本体 config hooks 是唯一真源——伴生 companion 无
/// hooks 模块（部署包清单实查，§390），本面只读、不建第二轨；
/// 增删钩子＝写任意 shell 命令的同意书，不在手机面开放）
public struct OpsHookRow: Equatable, Sendable, Identifiable {
    public var event: String
    public var matcher: String
    public var command: String
    public var timeout: Double?
    /// 是否已在同意名单（allowed 才真的会触发）
    public var allowed: Bool
    public var approvedAt: String?
    /// 脚本当前是否可执行
    public var executable: Bool

    public var id: String { "\(event)|\(command)" }

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        event = advString(dict, "event")
        matcher = advString(dict, "matcher")
        command = advString(dict, "command")
        timeout = advNumber(dict, "timeout")
        allowed = advBool(dict, "allowed")
        approvedAt = dict["approved_at"]?.stringValue
        executable = advBool(dict, "executable")
    }
}

/// GET /api/ops/hooks 全量读数
public struct OpsHooksPage: Equatable, Sendable {
    public var hooks: [OpsHookRow]
    public var validEvents: [String]

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        hooks = advArray(dict, "hooks").map(OpsHookRow.init)
        validEvents = advArray(dict, "valid_events").compactMap(\.stringValue)
    }
}

// MARK: - H8 附带：kanban 拆解回执

/// POST /api/plugins/kanban/tasks/{id}/decompose 回执：
/// 非 ok 不是 HTTP 错误——ok=false 时 reason 是服务端原文
/// （如辅助模型没配好），呈现层照原文给人话出处
public struct KanbanDecomposeReceipt: Equatable, Sendable {
    public var ok: Bool
    public var taskID: String
    public var reason: String
    public var fanout: Bool
    public var childIDs: [String]
    public var newTitle: String?

    public init(jsonValue: JSONValue) {
        let dict = jsonValue.advObjectDict ?? [:]
        ok = advBool(dict, "ok")
        taskID = advString(dict, "task_id")
        reason = advString(dict, "reason")
        fanout = advBool(dict, "fanout")
        childIDs = advArray(dict, "child_ids").compactMap(\.stringValue)
        newTitle = dict["new_title"]?.stringValue
    }

    /// 结果人话：成功报拆出几张子卡；失败照 reason 出处
    public var summary: String {
        if ok {
            return childIDs.isEmpty
                ? "已拆解。"
                : "已拆成 \(childIDs.count) 张子任务。"
        }
        return reason.isEmpty ? "这次没拆成，服务端没给原因。" : reason
    }
}

// MARK: - Decodable 桥（HermesClient 的 getJSON/sendJSONDecoding
// 泛型口径：全部高级面模型经 JSONValue 一次解码再分发，与
// KanbanTaskDetail 同法）

public protocol JSONValueDecodable: Decodable {
    init(jsonValue: JSONValue)
}

public extension JSONValueDecodable {
    init(from decoder: Decoder) throws {
        self.init(jsonValue: try JSONValue(from: decoder))
    }
}

extension DelegationRouting: JSONValueDecodable {}
extension MoaConfig: JSONValueDecodable {}
extension AuxiliaryTasksResponse: JSONValueDecodable {}
extension ModelSetReceipt: JSONValueDecodable {}
extension WebhooksPage: JSONValueDecodable {}
extension WebhookCreateReceipt: JSONValueDecodable {}
extension WebhooksEnableReceipt: JSONValueDecodable {}
extension CuratorStatus: JSONValueDecodable {}
extension SessionStoreStats: JSONValueDecodable {}
extension OpsHooksPage: JSONValueDecodable {}
extension KanbanDecomposeReceipt: JSONValueDecodable {}
