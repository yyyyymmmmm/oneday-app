import Foundation
import OneDayCore

/// 委派路由操作注入（DESIGN §390）：视图层以 AppState
/// .performAdmin＋HermesClient 委派四口组装；测试以脚本
/// 注入，只验状态机本身（与 PairingStore 执行口同式）
struct DelegationRoutingOperations {
    var load: () async throws -> DelegationRouting
    var setBackend: (String) async throws -> Void
    var setModelMap: ([DelegationModelRoute], String?) async throws -> Void
    var setProfileRoutes: ([DelegationProfileRoute], String?) async throws -> Void
}

/// 委派路由页状态机（H8，DESIGN §390）：子智能体干活时
/// 走哪个后端、重活/杂活怎么分流、能以哪些档案身份跑——
/// 全部真值在服务端 config 的 delegation 节，本店只是
/// 镜像。纪律与 §359 同构：一切写口成功只算受理，随即
/// 整面回读对账（后端名/路线名单/默认项逐项同值）才算
/// 生效；未确认如实留人话、界面保持服务端原样
@MainActor
@Observable
final class DelegationRoutingStore {
    enum State {
        case idle
        case loading
        /// 会话失效（401 终局）：如实呈现，不冒充空面
        case notLoggedIn
        case failed(String)
        case ready(DelegationRouting)
    }

    private(set) var state: State = .idle
    private(set) var isWriting = false
    private(set) var note: String?
    private(set) var noteIsProblem = false

    var routing: DelegationRouting? {
        if case .ready(let routing) = state { return routing }
        return nil
    }

    // MARK: - 读

/// §416 新鲜度普查豁免：config 编辑面（ops 注入）——读待编辑现值、写后回读对账（判定表见 DESIGN §416）
    func load(ops: DelegationRoutingOperations) async {
        if case .ready = state {
            // 已有真值时刷新不闪空
        } else {
            state = .loading
        }
        do {
            let fresh = try await ops.load()
            state = .ready(fresh)
        } catch let error as HermesError {
            handleLoadError(error)
        } catch {
            state = .failed("读取委派路由失败，请稍后再试。")
        }
    }

    private func handleLoadError(_ error: HermesError) {
        if case .sessionExpired = error {
            state = .notLoggedIn
        } else {
            state = .failed(error.userMessage)
        }
    }

    // MARK: - 写（受理→回读对账）

    /// 切换委派后端：回读 configured 同名才算生效
    func selectBackend(
        ops: DelegationRoutingOperations, backend: String
    ) async {
        guard let current = routing, !isWriting else { return }
        guard current.configured != backend else { return }
        isWriting = true
        defer { isWriting = false }
        do {
            try await ops.setBackend(backend)
            let fresh = try await ops.load()
            state = .ready(fresh)
            if fresh.configured == backend {
                setNote("委派后端已换成「\(backend)」", problem: false)
            } else {
                setNote(
                    "服务端受理了切换，但回读仍是「\(fresh.configured)」，先按原样显示。",
                    problem: true
                )
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("切换后端失败，请稍后再试。", problem: true)
        }
    }

    /// 保存模型路由整块：本地预检（与服务端校验同义）先行，
    /// 写后回读名单与默认项逐项对账
    func saveModelMap(
        ops: DelegationRoutingOperations,
        routes: [DelegationModelRoute], defaultRoute: String?
    ) async {
        guard routing != nil, !isWriting else { return }
        let problems = DelegationValidation.modelRouteProblems(
            routes: routes, defaultRoute: defaultRoute
        )
        guard problems.isEmpty else {
            setNote(problems[0], problem: true)
            return
        }
        isWriting = true
        defer { isWriting = false }
        do {
            try await ops.setModelMap(routes, defaultRoute)
            let fresh = try await ops.load()
            state = .ready(fresh)
            let namesMatch = fresh.modelRoutes.map(\.name) == routes.map(\.name)
            let defaultMatch = fresh.modelRouteDefault == defaultRoute
            if namesMatch && defaultMatch {
                setNote("模型路由已保存", problem: false)
            } else {
                setNote("服务端受理了保存，但回读对不上，先按服务端原样显示。", problem: true)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("保存模型路由失败，请稍后再试。", problem: true)
        }
    }

    /// 保存档案路由整块：同上（校验含档案必须存在）
    func saveProfileRoutes(
        ops: DelegationRoutingOperations,
        routes: [DelegationProfileRoute], defaultRoute: String?
    ) async {
        guard let current = routing, !isWriting else { return }
        let problems = DelegationValidation.profileRouteProblems(
            routes: routes, defaultRoute: defaultRoute,
            knownProfiles: current.profiles
        )
        guard problems.isEmpty else {
            setNote(problems[0], problem: true)
            return
        }
        isWriting = true
        defer { isWriting = false }
        do {
            try await ops.setProfileRoutes(routes, defaultRoute)
            let fresh = try await ops.load()
            state = .ready(fresh)
            let namesMatch = fresh.profileRoutes.map(\.name) == routes.map(\.name)
            let defaultMatch = fresh.profileRouteDefault == defaultRoute
            if namesMatch && defaultMatch {
                setNote("档案路由已保存", problem: false)
            } else {
                setNote("服务端受理了保存，但回读对不上，先按服务端原样显示。", problem: true)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("保存档案路由失败，请稍后再试。", problem: true)
        }
    }

    private func setNote(_ text: String, problem: Bool) {
        note = text
        noteIsProblem = problem
    }
}
