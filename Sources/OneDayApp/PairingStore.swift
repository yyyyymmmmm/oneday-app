import Foundation
import OneDayCore

/// 平台用户配对操作注入（DESIGN §359）：视图层以
/// AppState.performAdmin（自动重登通道）＋Hermes-
/// Client 四方法组装；测试以脚本注入，只验状态机
/// 本身（与 HealthCheckStore 执行口同式）
struct PairingOperations {
    var list: () async throws -> PairingListResponse
    var approve: (PairingPendingEntry) async throws -> PairingApproveReceipt
    var revoke: (PairingApprovedEntry) async throws -> Void
    var clearPending: () async throws -> PairingClearPendingReceipt
}

/// 待批数留痕（DESIGN §359）：设置根行「平台用户
/// 配对」副题的数据源——只记本页回读到的待批数
/// （按服务器隔离），不为副行单开轮询；进过本页
/// 才有数，没进过就是未知（根行降普通行、不占
/// 副题位）。与 HealthSummaryStore 同式
@MainActor
@Observable
/// §416 新鲜度普查豁免：待批数本地摘要落盘，无远端新鲜度问题（判定表见 DESIGN §416）
final class PairingSummaryStore {
    static let shared = PairingSummaryStore()

    private let defaults: UserDefaults
    private var pendingCounts: [String: Int] = [:]

    private static let defaultsKey = "pairing.pendingCount.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(
               [String: Int].self, from: data
           ) {
            pendingCounts = decoded
        }
    }

    /// 某服务器的待批数留痕；没留痕过为 nil（未知，
    /// 不许拿 0 冒充读过）
    func pendingCount(for serverBase: String?) -> Int? {
        guard let serverBase else { return nil }
        return pendingCounts[serverBase]
    }

    func savePendingCount(_ count: Int, serverBase: String?) {
        guard let serverBase else { return }
        pendingCounts[serverBase] = count
        if let data = try? JSONEncoder().encode(pendingCounts) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// 平台用户配对页状态机（DESIGN §359）：读＋三写，
/// 写后整表回读对账——批准进已批准列且离待批列、
/// 撤销不在已批准列、清待批后待批列为空，才算生
/// 效；回执自报一律不认。失败按 PairingAction-
/// Directive 分型给人话，清单保持服务端原样、不
/// 本地假挪行
@MainActor
@Observable
final class PairingStore {
    enum State {
        case idle
        case loading
        /// 会话失效（401 终局）：如实呈现未登录态，
        /// 不冒充空清单
        case notLoggedIn
        case failed(String)
        case ready(PairingListResponse)
    }

    private(set) var state: State = .idle
    /// 正在执行的写动作（按条目 id 去重防双击）
    private(set) var actingIDs: Set<String> = []
    private(set) var isClearing = false
    /// 动作结果的人话提示（页首呈现）：失败与未确
    /// 认用 problem 语气、良性结果用普通语气
    private(set) var note: String?
    private(set) var noteIsProblem = false

    private let summaryStore: PairingSummaryStore

    init(summaryStore: PairingSummaryStore = .shared) {
        self.summaryStore = summaryStore
    }

    // MARK: - 读

/// §416 新鲜度普查豁免：待批时效敏感——TTL 跳过会藏新配对请求，进面现读（判定表见 DESIGN §416）
    /// 拉两列清单。已有清单时刷新不闪空（保留旧清
    /// 单直到新回包落地）；刷新失败只留页首人话、
    /// 不丢已读到的清单
    func load(
        operations: PairingOperations, serverBase: String?
    ) async {
        let hadList: Bool = {
            if case .ready = state { return true }
            return false
        }()
        if !hadList { state = .loading }
        do {
            let response = try await operations.list()
            state = .ready(response)
            summaryStore.savePendingCount(
                response.pending.count, serverBase: serverBase
            )
        } catch let error as HermesError {
            handleLoadError(error, hadList: hadList)
        } catch {
            if hadList {
                note = "刷新没成功，下面还是上次读到的清单。"
                noteIsProblem = true
            } else {
                state = .failed("配对清单没读出来，请稍后再试。")
            }
        }
    }

    private func handleLoadError(_ error: HermesError, hadList: Bool) {
        if case .sessionExpired = error {
            state = .notLoggedIn
            return
        }
        if hadList {
            note = "刷新没成功：\(error.userMessage)"
            noteIsProblem = true
        } else {
            state = .failed(error.userMessage)
        }
    }

    // MARK: - 写（三件都走「受理 → 整表回读对账」）

    /// 批准一条待批：POST 受理后重拉清单，该用户进
    /// 已批准列且离待批列才算批准成功
    func approve(
        _ entry: PairingPendingEntry,
        operations: PairingOperations, serverBase: String?
    ) async {
        guard entry.canApprove, !actingIDs.contains(entry.id) else {
            return
        }
        actingIDs.insert(entry.id)
        defer { actingIDs.remove(entry.id) }
        note = nil
        do {
            _ = try await operations.approve(entry)
        } catch let error as HermesError {
            await handleActionError(
                error, operations: operations, serverBase: serverBase
            )
            return
        } catch {
            note = "批准没成功，请稍后再试。"
            noteIsProblem = true
            return
        }
        await load(operations: operations, serverBase: serverBase)
        if case .ready(let refreshed) = state {
            if PairingReadback.isApproveConfirmed(
                platform: entry.platform, userID: entry.userID,
                in: refreshed
            ) {
                note = nil
            } else {
                note = "批准请求已受理，但最新清单里还没生效——下拉刷新再确认。"
                noteIsProblem = true
            }
        }
    }

    /// 撤销一条已批准：POST 受理后重拉清单，该用户
    /// 不在已批准列才算撤销成功
    func revoke(
        _ entry: PairingApprovedEntry,
        operations: PairingOperations, serverBase: String?
    ) async {
        guard !actingIDs.contains(entry.id) else { return }
        actingIDs.insert(entry.id)
        defer { actingIDs.remove(entry.id) }
        note = nil
        do {
            try await operations.revoke(entry)
        } catch let error as HermesError {
            await handleActionError(
                error, operations: operations, serverBase: serverBase
            )
            return
        } catch {
            note = "撤销没成功，请稍后再试。"
            noteIsProblem = true
            return
        }
        await load(operations: operations, serverBase: serverBase)
        if case .ready(let refreshed) = state {
            if PairingReadback.isRevokeConfirmed(
                platform: entry.platform, userID: entry.userID,
                in: refreshed
            ) {
                note = nil
            } else {
                note = "撤销请求已受理，但最新清单里这条还在——下拉刷新再确认。"
                noteIsProblem = true
            }
        }
    }

    /// 清空全部待批（全平台一并清，服务端无按平台
    /// 参数）：回执 cleared 报实清条数，回读待批列
    /// 为空才算清干净
    func clearPending(
        operations: PairingOperations, serverBase: String?
    ) async {
        guard !isClearing,
              case .ready(let current) = state,
              !current.pending.isEmpty else { return }
        isClearing = true
        defer { isClearing = false }
        note = nil
        let receipt: PairingClearPendingReceipt
        do {
            receipt = try await operations.clearPending()
        } catch let error as HermesError {
            await handleActionError(
                error, operations: operations, serverBase: serverBase
            )
            return
        } catch {
            note = "清空没成功，请稍后再试。"
            noteIsProblem = true
            return
        }
        await load(operations: operations, serverBase: serverBase)
        if case .ready(let refreshed) = state {
            if PairingReadback.isClearConfirmed(in: refreshed) {
                note = receipt.cleared > 0
                    ? "已清空 \(receipt.cleared) 条待批申请。"
                    : "待批申请已清空。"
                noteIsProblem = false
            } else {
                note = "清空请求已受理，但最新清单里还有待批申请——下拉刷新再确认。"
                noteIsProblem = true
            }
        }
    }

    // MARK: - 写失败分型

    private func handleActionError(
        _ error: HermesError,
        operations: PairingOperations, serverBase: String?
    ) async {
        switch Self.directive(for: error) {
        case .gone:
            // 已过期/已被处理/已不在名单：良性，刷新对齐
            note = "这条已经不在了（可能已过期或刚被处理），清单已刷新。"
            noteIsProblem = false
            await load(operations: operations, serverBase: serverBase)
        case .platformLocked:
            note = "这个平台尝试次数过多，已被暂时锁定，过一会儿再试。"
            noteIsProblem = true
        case .sessionExpired:
            state = .notLoggedIn
        case .done, .failed:
            note = "操作没成功：\(error.userMessage)"
            noteIsProblem = true
        }
    }

    private static func directive(
        for error: HermesError
    ) -> PairingActionDirective {
        switch error {
        case .sessionExpired:
            return .sessionExpired
        case .unexpectedStatus(_, let status):
            return PairingActionDirective.directive(status: status)
        case .serverError(_, let status, _):
            return PairingActionDirective.directive(status: status)
        default:
            return .failed
        }
    }
}
