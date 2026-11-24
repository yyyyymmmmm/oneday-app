import Foundation
import OneDayCore

/// Webhooks 操作注入（DESIGN §390）：视图层以 AppState
/// .performAdmin＋HermesClient 五口组装；测试脚本注入
struct WebhooksOperations {
    var load: () async throws -> WebhooksPage
    var create: (WebhookCreateInput) async throws -> WebhookCreateReceipt
    var delete: (String) async throws -> Void
    var setEnabled: (String, Bool) async throws -> Void
    var enablePlatform: () async throws -> WebhooksEnableReceipt
}

/// 外部事件（Webhooks）页状态机（H11，DESIGN §390）：
/// 订阅真值在服务端 webhook 订阅存储（与 CLI 同一份），
/// 本店只是镜像。写口纪律同 §359：受理后整表回读对账
/// （建＝名单里出现、删＝消失、启停＝enabled 同值）；
/// 建订阅回的一次性密钥只存本店内存、页面展示一次，
/// 不落盘、不进日志——丢了只能删掉重建
@MainActor
@Observable
final class WebhooksStore {
    enum State {
        case idle
        case loading
        case notLoggedIn
        case failed(String)
        case ready(WebhooksPage)
    }

    private(set) var state: State = .idle
    private(set) var actingNames: Set<String> = []
    private(set) var isEnablingPlatform = false
    private(set) var note: String?
    private(set) var noteIsProblem = false
    /// 刚建成的订阅的一次性密钥（名＋密钥）：页面展示
    /// 一次，用户关掉即清；服务端此后只回 secret_set
    private(set) var oneTimeSecret: (name: String, secret: String)?

    var page: WebhooksPage? {
        if case .ready(let page) = state { return page }
        return nil
    }

/// §416 新鲜度普查豁免：config 编辑面（ops 注入）——读待编辑现值、写后回读对账（判定表见 DESIGN §416）
    func load(ops: WebhooksOperations) async {
        if case .ready = state {
            // 已有真值时刷新不闪空
        } else {
            state = .loading
        }
        do {
            state = .ready(try await ops.load())
        } catch let error as HermesError {
            if case .sessionExpired = error {
                state = .notLoggedIn
            } else {
                state = .failed(error.userMessage)
            }
        } catch {
            state = .failed("读取外部事件失败，请稍后再试。")
        }
    }

    /// 建订阅：本地预检先行；回执密钥存 oneTimeSecret；
    /// 回读名单出现同名才算建成
    func create(ops: WebhooksOperations, input: WebhookCreateInput) async {
        guard page != nil else { return }
        let problems = input.problems
        guard problems.isEmpty else {
            setNote(problems[0], problem: true)
            return
        }
        let name = WebhookCreateInput.normalizedName(input.name)
        guard !actingNames.contains(name) else { return }
        actingNames.insert(name)
        defer { actingNames.remove(name) }
        do {
            let receipt = try await ops.create(input)
            if let secret = receipt.secret, !secret.isEmpty {
                oneTimeSecret = (name: receipt.route.name, secret: secret)
            }
            let fresh = try await ops.load()
            state = .ready(fresh)
            if fresh.subscriptions.contains(where: { $0.name == receipt.route.name }) {
                setNote("订阅「\(receipt.route.name)」已建好", problem: false)
            } else {
                setNote("服务端受理了新建，但回读名单里还没有它，先按服务端原样显示。", problem: true)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("新建订阅失败，请稍后再试。", problem: true)
        }
    }

    /// 删订阅：回读消失才算删掉
    func delete(ops: WebhooksOperations, name: String) async {
        guard !actingNames.contains(name) else { return }
        actingNames.insert(name)
        defer { actingNames.remove(name) }
        do {
            try await ops.delete(name)
            let fresh = try await ops.load()
            state = .ready(fresh)
            if fresh.subscriptions.contains(where: { $0.name == name }) {
                setNote("服务端受理了删除，但回读里它还在，先按服务端原样显示。", problem: true)
            } else {
                if oneTimeSecret?.name == name { oneTimeSecret = nil }
                setNote("订阅「\(name)」已删除", problem: false)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("删除订阅失败，请稍后再试。", problem: true)
        }
    }

    /// 启停一条：回读 enabled 同值才算生效（热生效、无需重启）
    func setEnabled(
        ops: WebhooksOperations, name: String, enabled: Bool
    ) async {
        guard !actingNames.contains(name) else { return }
        actingNames.insert(name)
        defer { actingNames.remove(name) }
        do {
            try await ops.setEnabled(name, enabled)
            let fresh = try await ops.load()
            state = .ready(fresh)
            let row = fresh.subscriptions.first { $0.name == name }
            if row?.enabled == enabled {
                setNote(
                    enabled ? "订阅「\(name)」已启用" : "订阅「\(name)」已停用",
                    problem: false
                )
            } else {
                setNote("服务端受理了启停，但回读对不上，先按服务端原样显示。", problem: true)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("启停订阅失败，请稍后再试。", problem: true)
        }
    }

    /// 开平台：服务端伴随网关重启编排——needs_restart
    /// 为真时如实交代「还没自动重启」，不报假成功
    func enablePlatform(ops: WebhooksOperations) async {
        guard !isEnablingPlatform else { return }
        isEnablingPlatform = true
        defer { isEnablingPlatform = false }
        do {
            let receipt = try await ops.enablePlatform()
            let fresh = try await ops.load()
            state = .ready(fresh)
            if receipt.needsRestart {
                setNote("平台开关已打开，但网关还没自动重启——重启后外部事件才开始进来。", problem: true)
            } else if fresh.platformEnabled {
                setNote("外部事件已开启", problem: false)
            } else {
                setNote("服务端受理了开启，但回读仍是关着的，先按服务端原样显示。", problem: true)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("开启外部事件失败，请稍后再试。", problem: true)
        }
    }

    func dismissOneTimeSecret() {
        oneTimeSecret = nil
    }

    private func setNote(_ text: String, problem: Bool) {
        note = text
        noteIsProblem = problem
    }
}
