import Foundation
import OneDayCore

/// 记忆条目数据中枢（P7，0.13.0 客户端先行）：契约
/// memory-bridge-contract-20261109.md——Hermes 无
/// 条目级 API、write-gate 桥无拟写发起面，条目读与
/// propose 暂存须桥扩展 /memories 路由组才成立；
/// 桥未扩展时集合 404，本店露「记忆条目尚未开通」，
/// 绝不拿状态计数或假数据冒充条目。写口径是全 App
/// 最严的一处：新建/修改/遗忘只许经 propose 暂存
/// 待批，裁决在活动格审批面（既有 write-gate 面），
/// 批准后回读 /memories 验落盘才标已生效——本地不
/// 做任何乐观落定。钥匙问题（noKey/401）露桥未
/// 连接；已就绪后刷新失败保持旧数据不翻态。
@MainActor
@Observable
final class MemoriesStore {
    enum LoadState: Equatable {
        case loading
        /// 桥未连接（钥匙没粘/被拒，消息说清是哪一种）
        case notConnected(String)
        /// 桥在、条目面未开通（集合端点 404）
        case sourceNotOpened(String)
        case failed(String)
        case ready
    }

    private(set) var loadState: LoadState = .loading
    private(set) var entries: [BridgeMemoryEntry] = []
    /// 详情缓存（按条目 id；进详情时拉全文）
    private(set) var details: [String: BridgeMemoryEntryDetail] = [:]
    private(set) var detailLoading: Set<String> = []
    private(set) var detailErrors: [String: String] = [:]
    /// 记忆闸门开关（/status 证据）：nil＝还没读到；
    /// false 时提交入口在面上禁用并注明（不靠猜）
    private(set) var memoryGateEnabled: Bool?
    /// 本会话发起的提案（按发起序，含已落定状态）
    private(set) var proposals: [MemoryProposal] = []
    /// 非本会话发起、仍在待批的 App 来源记录
    /// （上一会话遗留，认领呈现，不重复跟踪落定）
    private(set) var externalPending: [WriteGateRecord] = []
    /// 被待批改/删盯上的条目 digest（行上贴待批标）
    private(set) var pendingDigests: Set<String> = []
    private(set) var proposing = false
    private(set) var proposeError: String?
    /// 删除发起失败的人话（留在详情页行内，不弹模态）
    private(set) var notesOnDelete: String?

    private let bridge = MemoryBridgeClient()
    private let gate = WriteGateClient()
    private var loadInFlight = false

    func entry(id: String) -> BridgeMemoryEntry? {
        entries.first { $0.id == id }
    }

    /// 这一条是否正被一条待批改/删盯上（本会话
    /// 提案或认领到的待批记录，任一命中即贴标）
    func hasPendingOperation(_ entry: BridgeMemoryEntry) -> Bool {
        if pendingDigests.contains(entry.digest) { return true }
        return proposals.contains {
            $0.status == .pending && $0.entryId == entry.id
        }
    }

    /// 搜索过滤后的分组（纯函数在 Core）
    func groupedEntries(
        query: String
    ) -> [(target: MemoryTarget, entries: [BridgeMemoryEntry])] {
        MemoryEntryPresentation.groups(
            MemoryEntryPresentation.filtered(entries, query: query)
        )
    }

    /// 待批区是否有内容（本会话提案或遗留待批任一）
    var hasProposalRows: Bool {
        !proposals.isEmpty || !externalPending.isEmpty
    }

    // MARK: - 加载（条目＋闸门/待批/落定对账）

    func load(appState: AppState) async {
        guard !loadInFlight else { return }
        guard let config = appState.config else {
            loadState = .failed(L10n.string("尚未连接服务器。"))
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            entries = try await bridge.entries(config: config)
            loadState = .ready
        } catch let error as WriteGateError {
            if loadState == .ready { return }
            loadState = Self.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed(L10n.string("记忆条目没读出来，可能是网络或服务暂时没响应"))
        }
        if loadState == .ready {
            await refreshApprovals(appState: appState)
        }
    }

    /// 闸门状态＋待批认领＋提案落定对账：全程尽力而
    /// 为——这条链失败只让标记缺失，不推翻已就绪的
    /// 条目列表（条目是主数据，审批标记是附属）
    private func refreshApprovals(appState: AppState) async {
        guard let config = appState.config else { return }
        if let status = try? await gate.gateStatus(config: config) {
            memoryGateEnabled = status.supported
                ? status.memoryGateEnabled
                : nil
        }
        var pendingIDs: Set<String> = []
        var appPending: [WriteGateRecord] = []
        if let list = try? await gate.pendingList(config: config) {
            let mine = list.records.filter {
                $0.subsystem == .memory
                    && $0.origin == MemoryPendingMatching.appOrigin
            }
            appPending = mine
            pendingIDs = Set(mine.map(\.id))
            externalPending = mine.filter { record in
                !proposals.contains { $0.pendingId == record.id }
            }
            // 改/删型待批逐条拉详情，用 payload 的
            // old_text digest 给条目行贴标
            var digests: Set<String> = []
            for record in mine {
                if let detail = try? await gate.detail(
                    config: config, subsystem: .memory, id: record.id
                ), let digest = MemoryPendingMatching.targetedDigest(
                    payload: detail.record.payload
                ) {
                    digests.insert(digest)
                }
            }
            pendingDigests = digests
        }
        // 落定对账：离开待批的提案查已决记录＋回读验落盘
        guard proposals.contains(where: {
            $0.status == .pending || $0.status == .approvedUnconfirmed
        }) else { return }
        var decisions: [String: String] = [:]
        if let records = try? await bridge.decisions(config: config) {
            for record in records where record.subsystem == .memory {
                decisions[record.id] = record.decision
            }
        }
        proposals = proposals.map { proposal in
            guard proposal.status == .pending
                || proposal.status == .approvedUnconfirmed
            else { return proposal }
            var updated = proposal
            updated.status = MemoryProposalResolution.status(
                of: proposal, pendingIDs: pendingIDs,
                decisions: decisions, entries: entries
            )
            updated.note = Self.note(for: updated.status)
            return updated
        }
    }

    static func note(for status: MemoryProposalStatus) -> String? {
        switch status {
        case .pending:
            return L10n.string("已提交待审批，批准后才会生效。")
        case .landed:
            return nil
        case .approvedUnconfirmed:
            return L10n.string("已批准，但还没确认到变化，请下拉刷新核对。")
        case .rejected:
            return L10n.string("这条提交被驳回了，记忆保持原样。")
        case .unresolved:
            return L10n.string("这条提交已不在待批里，又没查到裁决记录，结果未确认。")
        }
    }

    static func state(for error: WriteGateError) -> LoadState {
        switch error {
        case .noKey:
            return .notConnected(
                L10n.string("还没有可用的登录信息：记忆条目用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。")
            )
        case .unauthorized:
            return .notConnected(
                L10n.string("服务器拒绝了这次登录。请到「设置」里检查登录是否还有效。")
            )
        case .bridgeMissing:
            return .sourceNotOpened(
                L10n.string("服务器上的写入审批还没有开通记忆条目。开通后，智能体的长期记忆会逐条出现在这里。")
            )
        case .recordGone:
            return .failed(L10n.string("这条记忆已经不在了，请刷新后重试。"))
        case .conflict:
            return .failed(L10n.string("内容已经变化，请刷新后重试。"))
        case .failed(let message):
            return .failed(message)
        }
    }

    static func message(for error: WriteGateError) -> String {
        switch error {
        case .noKey:
            return L10n.string("还没连上你的服务：还没有可用的登录信息。")
        case .unauthorized:
            return L10n.string("还没连上你的服务：服务器拒绝了这次登录。")
        case .bridgeMissing:
            return L10n.string("记忆条目面还没有开通。")
        case .recordGone:
            return L10n.string("这条记忆已经不在了。")
        case .conflict:
            return L10n.string("内容已经变化，请刷新后重试。")
        case .failed(let message):
            return message
        }
    }

    // MARK: - 详情

    func loadDetail(appState: AppState, id: String) async {
        guard details[id] == nil, !detailLoading.contains(id) else { return }
        guard let config = appState.config else {
            detailErrors[id] = L10n.string("尚未连接服务器。")
            return
        }
        detailLoading.insert(id)
        detailErrors.removeValue(forKey: id)
        defer { detailLoading.remove(id) }
        do {
            details[id] = try await bridge.entry(config: config, id: id)
        } catch let error as WriteGateError {
            detailErrors[id] = Self.message(for: error)
        } catch {
            detailErrors[id] = L10n.string("详情没读出来，可能是网络或服务暂时没响应")
        }
    }

    // MARK: - 发起待批（新建/修改/遗忘，全部 propose）

    func clearProposeError() {
        proposeError = nil
    }

    /// 提交前置口径：闸门状态已明确为关时先拦下
    /// （桥必然 409，不白跑）；状态未知不拦（桥是
    /// 唯一事实源），失败人话照样透传
    private func gateBlocked() -> Bool {
        if memoryGateEnabled == false {
            proposeError = L10n.string("记忆写入审批未启用，暂时不能提交。")
            return true
        }
        return false
    }

    func proposeCreate(
        appState: AppState, target: MemoryTarget, content: String
    ) async -> Bool {
        guard !proposing else { return false }
        if let problem = MemoryProposalValidation.problem(
            operation: .create, content: content
        ) {
            proposeError = problem
            return false
        }
        guard let config = appState.config else {
            proposeError = L10n.string("尚未连接服务器。")
            return false
        }
        guard !gateBlocked() else { return false }
        proposing = true
        proposeError = nil
        defer { proposing = false }
        do {
            let response = try await bridge.propose(
                config: config,
                request: .create(target: target, content: content)
            )
            proposals.append(MemoryProposal(
                pendingId: response.pendingId, operation: .create,
                targetRaw: target.rawValue, entryId: nil,
                baseDigest: nil, proposedContent: content,
                note: Self.note(for: .pending)
            ))
            await refreshApprovals(appState: appState)
            return true
        } catch let error as WriteGateError {
            proposeError = Self.message(for: error)
            return false
        } catch {
            proposeError = L10n.string("提交失败，请稍后再试。")
            return false
        }
    }

    func proposeUpdate(
        appState: AppState, entry: BridgeMemoryEntry,
        currentContent: String, newContent: String
    ) async -> Bool {
        guard !proposing else { return false }
        if let problem = MemoryProposalValidation.problem(
            operation: .update, content: newContent,
            originalContent: currentContent
        ) {
            proposeError = problem
            return false
        }
        guard let config = appState.config else {
            proposeError = L10n.string("尚未连接服务器。")
            return false
        }
        guard !gateBlocked() else { return false }
        proposing = true
        proposeError = nil
        defer { proposing = false }
        do {
            let response = try await bridge.propose(
                config: config,
                request: .update(entry: entry, content: newContent)
            )
            proposals.append(MemoryProposal(
                pendingId: response.pendingId, operation: .update,
                targetRaw: entry.targetRaw, entryId: entry.id,
                baseDigest: entry.digest, proposedContent: newContent,
                note: Self.note(for: .pending)
            ))
            await refreshApprovals(appState: appState)
            return true
        } catch let error as WriteGateError {
            proposeError = Self.message(for: error)
            return false
        } catch {
            proposeError = L10n.string("提交失败，请稍后再试。")
            return false
        }
    }

    func proposeDelete(
        appState: AppState, entry: BridgeMemoryEntry
    ) async -> Bool {
        guard !proposing else { return false }
        guard let config = appState.config else {
            notesOnDelete = L10n.string("尚未连接服务器。")
            return false
        }
        guard !gateBlocked() else {
            notesOnDelete = proposeError
            return false
        }
        proposing = true
        proposeError = nil
        defer { proposing = false }
        do {
            let response = try await bridge.propose(
                config: config, request: .delete(entry: entry)
            )
            proposals.append(MemoryProposal(
                pendingId: response.pendingId, operation: .delete,
                targetRaw: entry.targetRaw, entryId: entry.id,
                baseDigest: entry.digest, proposedContent: nil,
                note: Self.note(for: .pending)
            ))
            await refreshApprovals(appState: appState)
            return true
        } catch let error as WriteGateError {
            notesOnDelete = Self.message(for: error)
            return false
        } catch {
            notesOnDelete = L10n.string("提交失败，请稍后再试。")
            return false
        }
    }

    func clearDeleteNote() {
        notesOnDelete = nil
    }
}
