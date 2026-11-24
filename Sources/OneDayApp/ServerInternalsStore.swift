import Foundation
import OneDayCore

/// H13 小件操作注入（DESIGN §390）：视图层以 AppState
/// .performAdmin 组装；测试脚本注入
struct ServerInternalsOperations {
    var curatorStatus: () async throws -> CuratorStatus
    var setCuratorPaused: (Bool) async throws -> Void
    var activeProfileName: () async throws -> String?
    var runCurator: (String?) async throws -> OpsSpawnResponse
    var sessionStats: () async throws -> SessionStoreStats
    var opsHooks: () async throws -> OpsHooksPage
}

/// H13 小件数据层（DESIGN §390）：三件各自独立成败——
/// ①技能策展 curator 状态（技能面消费）：暂停/恢复写后
/// 回读对账、立即跑一次先取当前档案名指名（服务端对
/// 无名目标拒绝执行，多档案在役时不许蒙）；
/// ②会话存储统计（状态面消费）：与 /api/system/stats
/// 不同物——那是系统面，这是会话库口径（折行同名单）；
/// ③ops/hooks 只读对账（自动化面消费）：本体 config
/// hooks 是唯一真源（伴生无此模块），本店只读不写。
@MainActor
@Observable
final class ServerInternalsStore {
    private(set) var curator: CuratorStatus?
    private(set) var curatorFailed = false
    private(set) var curatorNotLoggedIn = false
    private(set) var curatorBusy = false
    private(set) var stats: SessionStoreStats?
    private(set) var statsFailed = false
    private(set) var hooks: OpsHooksPage?
    private(set) var hooksFailed = false
    private(set) var note: String?
    private(set) var noteIsProblem = false

    /// 三件各拉各的：一件失败只降级自己那一段（串行
    /// 执行——ops 是主线程隔离的操作组，并发发送会触
    /// 区域隔离红线；三件都是小读、串行不亏体感）
/// §416 新鲜度普查豁免：config 编辑面（ops 注入）——读待编辑现值、写后回读对账（判定表见 DESIGN §416）
    func loadAll(ops: ServerInternalsOperations) async {
        await loadCurator(ops: ops)
        await loadStats(ops: ops)
        await loadHooks(ops: ops)
    }

    func loadCurator(ops: ServerInternalsOperations) async {
        do {
            curator = try await ops.curatorStatus()
            curatorFailed = false
            curatorNotLoggedIn = false
        } catch let error as HermesError {
            if case .sessionExpired = error {
                curatorNotLoggedIn = true
            } else {
                curatorFailed = true
            }
        } catch {
            curatorFailed = true
        }
    }

    func loadStats(ops: ServerInternalsOperations) async {
        do {
            stats = try await ops.sessionStats()
            statsFailed = false
        } catch {
            statsFailed = true
        }
    }

    func loadHooks(ops: ServerInternalsOperations) async {
        do {
            hooks = try await ops.opsHooks()
            hooksFailed = false
        } catch {
            hooksFailed = true
        }
    }

    /// 暂停/恢复策展：回读 paused 同值才算生效
    func setCuratorPaused(
        ops: ServerInternalsOperations, paused: Bool
    ) async {
        guard !curatorBusy else { return }
        curatorBusy = true
        defer { curatorBusy = false }
        do {
            try await ops.setCuratorPaused(paused)
            let fresh = try await ops.curatorStatus()
            curator = fresh
            if fresh.paused == paused {
                setNote(paused ? "技能整理已暂停" : "技能整理已恢复", problem: false)
            } else {
                setNote("服务端受理了，但回读对不上，先按服务端原样显示。", problem: true)
            }
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("操作失败，请稍后再试。", problem: true)
        }
    }

    /// 立即跑一次策展：先取当前档案名指名再触发；回执
    /// pid 只作已受理凭据，跑完与否看下次状态回读的
    /// last_run_at（本店不假报完成）
    func runCuratorNow(ops: ServerInternalsOperations) async {
        guard !curatorBusy else { return }
        curatorBusy = true
        defer { curatorBusy = false }
        do {
            let profile = try await ops.activeProfileName()
            _ = try await ops.runCurator(profile)
            setNote("已让它现在整理一次，在后台跑，跑完后这里的「上次整理」会更新。", problem: false)
        } catch let error as HermesError {
            setNote(error.userMessage, problem: true)
        } catch {
            setNote("触发整理失败，请稍后再试。", problem: true)
        }
    }

    private func setNote(_ text: String, problem: Bool) {
        note = text
        noteIsProblem = problem
    }
}
