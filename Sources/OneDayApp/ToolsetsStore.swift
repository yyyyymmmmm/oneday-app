import Foundation
import OneDayCore

/// 工具集治理数据层（DESIGN §358；台账 34）：手机会话
/// （api_server 平台）工具集的真值镜像＋全部写口的编排。
/// 纪律（与 §355 命令授权区同构）：
/// - 读面真源是 GET /v1/toolsets（8642），不是 9119 的
///   配置面视图（那是 cli 口径）；config-only 集（stt）
///   的真值在 config 节，经 rawConfig 合成（见
///   ToolsetStateResolution）；
/// - 一切写口（启停/provider/model/终端后端）成功只算
///   受理——随即回读真源、ToolsetReadback 判定确认才
///   算生效；未确认如实留人话、界面保持服务端原样，
///   不本地假变；
/// - 未连接/无凭据不是失败、更不是空清单，如实说未就绪。

@MainActor
@Observable
final class ToolsetsStore {
    enum State {
        case idle
        case loading
        /// 已打开页面但还没连上服务器（未连接/无凭据）
        case unavailable(String)
        case failed(String)
        case ready
    }

    private(set) var state: State = .idle
    /// 最近一次服务端清单（真源镜像，只被回读结果覆写）
    private(set) var list: ToolsetsListResponse?
    /// config 承托集的真值表（stt 等 config-only 集）
    private(set) var configEnabled: [String: Bool] = [:]
    /// config 没读到：config 承托集的状态未能确认，页面
    /// 须明示（不许拿读面假值冒充真值）
    private(set) var configUnread = false
    /// 终端后端（列表页尾独立段；与清单分开成败——后端
    /// 读不到不拖垮工具集清单）
    private(set) var backends: TerminalBackends?
    private(set) var backendsUnread = false
    private(set) var togglingNames: Set<String> = []
    private(set) var selectingBackend = false
    /// 列表页提示（页首呈现）：失败与未确认用 problem
    /// 语气、良性结果用普通语气
    private(set) var note: String?
    private(set) var noteIsProblem = false

    // MARK: 详情（细调）

    /// 一个工具集的细调装载结果：面板与模型目录分开
    /// 成败（一面读不到不拖垮另一面）
    struct Detail: Equatable {
        var panel: ToolsetConfigPanel?
        var panelFailed = false
        var catalog: ToolsetModelCatalog?
        var catalogFailed = false
        var loading = false
    }

    private(set) var detailName: String?
    private(set) var detail = Detail()
    private(set) var detailBusy = false
    private(set) var detailNote: String?
    private(set) var detailNoteIsProblem = false

    // MARK: - 读

/// §416 新鲜度普查豁免：清单与 config 真值同拉的编辑面，现值口径（判定表见 DESIGN §416）
    /// 拉清单＋config 真值＋终端后端。未连接/无凭据 →
    /// .unavailable（不冒充空清单）；清单失败 → .failed
    /// 如实呈现；config/后端是附带真源，各自失败只降级
    /// 对应呈现、不拖垮清单。已有清单时刷新不闪空
    func load(appState: AppState) async {
        guard let config = appState.config,
              let apiKey = appState.apiKey else {
            state = .unavailable(
                "还没连上服务器，连上后这里会显示手机会话能用的工具集。"
            )
            return
        }
        if case .ready = state {
            // 刷新中保留现清单
        } else {
            state = .loading
        }
        do {
            let response = try await appState.client.toolsets(
                config: config, apiKey: apiKey
            )
            list = response
            state = .ready
        } catch let error as HermesError {
            state = .failed(error.userMessage)
            return
        } catch {
            state = .failed("工具集清单没读出来，请稍后再试。")
            return
        }
        await reloadConfigTruth(appState: appState)
        await reloadBackends(appState: appState)
    }

    /// 只重拉清单＋config 真值（写后回读用）：失败不改
    /// state（页面保持 ready＋旧镜像，由调用方留人话）
    private func reloadTruth(appState: AppState) async -> Bool {
        guard let config = appState.config,
              let apiKey = appState.apiKey else { return false }
        do {
            list = try await appState.client.toolsets(
                config: config, apiKey: apiKey
            )
        } catch {
            return false
        }
        await reloadConfigTruth(appState: appState)
        return true
    }

    /// config 真值附带拉取：失败置 configUnread（呈现层
    /// 明示个别集状态未确认），不抛错
    private func reloadConfigTruth(appState: AppState) async {
        guard let config = appState.config else { return }
        do {
            let raw = try await appState.client.rawConfig(
                config: config
            )
            configEnabled = ToolsetStateResolution
                .configBackedEnabled(in: raw)
            configUnread = false
        } catch {
            configUnread = true
        }
    }

    private func reloadBackends(appState: AppState) async {
        guard let config = appState.config else { return }
        do {
            backends = try await appState.client.terminalBackends(
                config: config
            )
            backendsUnread = false
        } catch {
            backendsUnread = true
        }
    }

    // MARK: - 启停

    /// 翻一个集的开关：PUT 成功只是受理——随即回读清单
    /// ＋config 真值，合成有效态与目标一致才算生效；未
    /// 确认/失败都如实留人话，清单保持服务端原样
    func toggle(
        _ row: ToolsetRow, to target: Bool, appState: AppState
    ) async {
        guard !togglingNames.contains(row.name) else { return }
        guard let config = appState.config,
              let apiKey = appState.apiKey else {
            note = "还没连上服务器，暂时改不了。"
            noteIsProblem = true
            return
        }
        togglingNames.insert(row.name)
        defer { togglingNames.remove(row.name) }
        note = nil
        do {
            _ = try await appState.client.setToolsetEnabled(
                config: config, apiKey: apiKey,
                name: row.name, enabled: target
            )
        } catch let error as HermesError {
            await handleToggleError(error, appState: appState)
            return
        } catch {
            note = "开关没改成功，请稍后再试。"
            noteIsProblem = true
            return
        }
        // 回读确认：重拉真源，合成有效态对上才算数
        guard await reloadTruth(appState: appState),
              let refreshed = list else {
            note = "开关请求已发，但最新状态没读回来，下拉刷新再确认。"
            noteIsProblem = true
            return
        }
        if ToolsetReadback.isToggleConfirmed(
            name: row.name, target: target,
            in: refreshed, configEnabled: configEnabled
        ) {
            note = nil
        } else {
            note = "开关请求已受理，但回读状态还没变，可能还没生效——下拉刷新再确认。"
            noteIsProblem = true
        }
    }

    private func handleToggleError(
        _ error: HermesError, appState: AppState
    ) async {
        let directive: ToolsetToggleDirective
        switch error {
        case .serverError(_, let status, let code):
            directive = ToolsetToggleDirective.directive(
                status: status, serverCode: code
            )
        case .unexpectedStatus(_, let status):
            directive = ToolsetToggleDirective.directive(
                status: status, serverCode: nil
            )
        case .apiKeyRejected:
            directive = .unauthorized
        default:
            directive = .failed
        }
        switch directive {
        case .unknownToolset:
            // 集已不在服务端清单里：良性，刷新对齐
            note = "这个工具集已经不在服务端的清单里了，下面已是最新清单。"
            noteIsProblem = false
            _ = await reloadTruth(appState: appState)
        case .unauthorized:
            note = "登录密钥被服务器拒绝，开关没改成——请检查连接后重试。"
            noteIsProblem = true
        case .invalidRequest:
            note = "开关请求没被服务端接受（请求形态不对），开关状态没变。"
            noteIsProblem = true
        case .done, .failed:
            note = "开关没改成功：\(error.userMessage)"
            noteIsProblem = true
        }
    }

    // MARK: - 终端后端

    /// 选终端后端：写后回读 active 对上才算生效
    func selectBackend(
        _ backend: TerminalBackend, appState: AppState
    ) async {
        guard !selectingBackend else { return }
        guard backend.status.isSelectable else {
            note = "「\(backend.displayLabel)」还没就绪，暂时选不了。"
            noteIsProblem = true
            return
        }
        guard let config = appState.config else {
            note = "还没连上服务器，暂时改不了。"
            noteIsProblem = true
            return
        }
        selectingBackend = true
        defer { selectingBackend = false }
        note = nil
        do {
            try await appState.client.selectTerminalBackend(
                config: config, backend: backend.name
            )
        } catch let error as HermesError {
            note = "终端后端没切换成功：\(error.userMessage)"
            noteIsProblem = true
            return
        } catch {
            note = "终端后端没切换成功，请稍后再试。"
            noteIsProblem = true
            return
        }
        await reloadBackends(appState: appState)
        if let refreshed = backends,
           ToolsetReadback.isBackendConfirmed(
               refreshed, name: backend.name
           ) {
            note = nil
        } else {
            note = "切换请求已受理，但回读的当前后端还没变——下拉刷新再确认。"
            noteIsProblem = true
        }
    }

    // MARK: - 详情细调

    /// 进详情时装载细调两面（面板/目录分开成败）
    func loadDetail(name: String, appState: AppState) async {
        detailName = name
        detail = Detail(loading: true)
        detailNote = nil
        guard let config = appState.config else {
            detail = Detail(panelFailed: true, catalogFailed: true)
            return
        }
        var next = Detail()
        do {
            next.panel = try await appState.client.toolsetConfig(
                config: config, name: name
            )
        } catch {
            next.panelFailed = true
        }
        do {
            next.catalog = try await appState.client.toolsetModels(
                config: config, name: name
            )
        } catch {
            next.catalogFailed = true
        }
        // 详情页可能已切到别的集，迟到的回包不覆写
        guard detailName == name else { return }
        detail = next
    }

    /// 选 provider：写后回读面板 active_provider 对上
    /// 才算生效
    func selectProvider(
        _ provider: ToolsetProvider, appState: AppState
    ) async {
        guard let name = detailName, !detailBusy else { return }
        guard let config = appState.config else {
            detailNote = "还没连上服务器，暂时改不了。"
            detailNoteIsProblem = true
            return
        }
        detailBusy = true
        defer { detailBusy = false }
        detailNote = nil
        do {
            try await appState.client.selectToolsetProvider(
                config: config, name: name, provider: provider.name
            )
        } catch let error as HermesError {
            detailNote = "服务商没切换成功：\(error.userMessage)"
            detailNoteIsProblem = true
            return
        } catch {
            detailNote = "服务商没切换成功，请稍后再试。"
            detailNoteIsProblem = true
            return
        }
        do {
            let panel = try await appState.client.toolsetConfig(
                config: config, name: name
            )
            detail.panel = panel
            detail.panelFailed = false
            if ToolsetReadback.isProviderConfirmed(
                panel, provider: provider.name
            ) {
                detailNote = nil
            } else {
                detailNote = "切换请求已受理，但回读的当前服务商还没变——退出重进再确认。"
                detailNoteIsProblem = true
            }
        } catch {
            detailNote = "切换请求已发，但最新状态没读回来——退出重进再确认。"
            detailNoteIsProblem = true
        }
    }

    /// 选后端模型：写后回读目录 current 对上才算生效
    func selectModel(
        _ model: ToolsetModelOption, appState: AppState
    ) async {
        guard let name = detailName, !detailBusy else { return }
        guard let config = appState.config else {
            detailNote = "还没连上服务器，暂时改不了。"
            detailNoteIsProblem = true
            return
        }
        detailBusy = true
        defer { detailBusy = false }
        detailNote = nil
        do {
            try await appState.client.selectToolsetModel(
                config: config, name: name, model: model.id
            )
        } catch let error as HermesError {
            detailNote = "模型没切换成功：\(error.userMessage)"
            detailNoteIsProblem = true
            return
        } catch {
            detailNote = "模型没切换成功，请稍后再试。"
            detailNoteIsProblem = true
            return
        }
        do {
            let catalog = try await appState.client.toolsetModels(
                config: config, name: name
            )
            detail.catalog = catalog
            detail.catalogFailed = false
            if ToolsetReadback.isModelConfirmed(
                catalog, model: model.id
            ) {
                detailNote = nil
            } else {
                detailNote = "切换请求已受理，但回读的当前模型还没变——退出重进再确认。"
                detailNoteIsProblem = true
            }
        } catch {
            detailNote = "切换请求已发，但最新状态没读回来——退出重进再确认。"
            detailNoteIsProblem = true
        }
    }
}
