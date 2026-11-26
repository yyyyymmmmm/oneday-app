import Foundation
import Observation
import OneDayCore

/// 「总是允许」轻通知（与 iOS 同语义）：批准落定后
/// 出一条可撤销提示，撤销只删规则、不回滚已批准的
/// 那一条；5 秒自动收起
struct MacAlwaysAllowToast: Identifiable, Equatable {
    let id = UUID()
    let rule: WriteGateRule
    let scopeLabel: String
}

/// 批准与授权状态店（棒 2，对位 #18/#19）：两族待批
/// ——执行批准（/v1/approvals 逐条记录）与写闸批准
/// （/v1/write-gate，Core 模型与文案单源）——加授
/// 权管理（/v1/grants 统一清单＋写闸规则）。裁决语
/// 义逐字对 App：写闸三档钮走 Core ApprovalCardSpec
/// 的动作栈派生；「总是允许」先建规则后批准、失败
/// 不批不移除；exec 撤销以事后清单回读为终局。
@MainActor
@Observable
final class MacApprovalStore {
    // 执行批准
    private(set) var execRecords: [MacExecApproval] = []
    private(set) var ledgerDegraded = false
    private(set) var execLoaded = false
    var execNote: String?

    // 写闸批准（诚实三态走 Core ApprovalSectionState）
    private(set) var gateState: ApprovalSectionState = .loading
    private(set) var gateStatus: WriteGateStatus?
    private(set) var decisions: [WriteGateDecisionRecord] = []
    /// 逐条卡面留痕（裁决失败原因等，键＝记录 id）
    var cardNotes: [String: String] = [:]

    // 授权管理
    private(set) var grants: GrantsListResponse?
    private(set) var grantsNote: String?
    private(set) var rules: [WriteGateRule] = []
    private(set) var rulesLoaded = false
    var rulesNote: String?

    // 进行态
    private(set) var decidingIDs: Set<String> = []
    private(set) var revokingIDs: Set<String> = []
    private(set) var alwaysAllowToast: MacAlwaysAllowToast?
    private var toastTask: Task<Void, Never>?

    /// 待批总数（菜单栏/Dock 角标共用口径：两族相加）
    var pendingTotal: Int {
        execPending.count + gatePending.count
    }

    var execPending: [MacExecApproval] {
        execRecords.filter { $0.isPending }
    }

    var execDecided: [MacExecApproval] {
        execRecords.filter { !$0.isPending }
    }

    var gatePending: [WriteGateRecord] {
        if case .ready(let records) = gateState { return records }
        return []
    }

    /// 本会话的执行待批（聊天停靠区口径：属本会话、
    /// 待批、有活等待者；新近在前转先进先审）
    func execPending(forSessionID sessionID: String?) -> [MacExecApproval] {
        let scoped = execPending.filter { record in
            guard record.answerable else { return false }
            guard let sessionID else { return true }
            return record.sessionID == sessionID
        }
        return scoped.sorted {
            ($0.createdAt ?? 0) < ($1.createdAt ?? 0)
        }
    }

    /// 本会话的写闸待批（记录自带锚点判定，Core
    /// appliesToChat 同口径）
    func gatePending(forSessionID sessionID: String?) -> [WriteGateRecord] {
        gatePending.filter { $0.appliesToChat(sessionID: sessionID) }
    }

    // MARK: - 刷新（各面 best-effort 独立成败，不互相拖垮）

    func refresh(session: SessionStore) async {
        guard session.isConnected, let config = session.config,
              let key = session.apiKey else { return }
        let client = session.chatClient
        if let response = try? await client.approvalsList(
            config: config, apiKey: key
        ) {
            execRecords = response.approvals
            ledgerDegraded = response.ledgerDegraded
            execLoaded = true
        }
        await refreshGate(session: session)
        if let fetched = try? await client.writeGateDecisions(
            config: config, apiKey: key
        ) {
            decisions = fetched
        }
        await refreshGrants(session: session)
        await refreshRules(session: session)
    }

    /// 写闸状态组装（ApprovalSectionState.resolve 单
    /// 源）：status 拿不到/不支持 → 通道未接通；两键
    /// 皆关 → 未启用；否则 ready（空即真无待批）
    func refreshGate(session: SessionStore) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        let client = session.chatClient
        let status = try? await client.writeGateStatus(
            config: config, apiKey: key
        )
        gateStatus = status
        var records: [WriteGateRecord]?
        if let pending = try? await client.writeGatePending(
            config: config, apiKey: key
        ) {
            records = pending.records
        }
        gateState = ApprovalSectionState.resolve(
            status: status, records: records
        )
    }

    func refreshGrants(session: SessionStore) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        if let response = try? await session.chatClient.grants(
            config: config, apiKey: key
        ) {
            grants = response
        }
    }

    func refreshRules(session: SessionStore) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        if let fetched = try? await session.chatClient.writeGateRules(
            config: config, apiKey: key
        ) {
            rules = fetched
            rulesLoaded = true
        }
    }

    // MARK: - 执行批准裁决

    func decideExec(
        _ record: MacExecApproval, choice: String,
        session: SessionStore
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        guard !decidingIDs.contains(record.id) else { return }
        decidingIDs.insert(record.id)
        defer { decidingIDs.remove(record.id) }
        do {
            try await session.chatClient.resolveApproval(
                config: config, apiKey: key, requestID: record.id,
                choice: choice, reason: nil
            )
            execNote = nil
        } catch let error as HermesError {
            if case .unexpectedStatus(_, let status) = error,
               status == 409 {
                execNote = "这条批准已被处理或已无等待者，已按服务器最新状态刷新。"
            } else {
                execNote = error.userMessage
            }
        } catch {
            execNote = error.localizedDescription
        }
        await refresh(session: session)
    }

    // MARK: - 写闸裁决（批准/驳回）

    func decideGate(
        _ record: WriteGateRecord, approve: Bool,
        session: SessionStore
    ) async {
        guard record.canDecide, let config = session.config,
              let key = session.apiKey else { return }
        guard !decidingIDs.contains(record.id) else { return }
        decidingIDs.insert(record.id)
        defer { decidingIDs.remove(record.id) }
        do {
            let response = try await session.chatClient.writeGateDecide(
                config: config, apiKey: key,
                subsystem: record.subsystem, id: record.id,
                approve: approve
            )
            if response.success {
                cardNotes.removeValue(forKey: record.id)
            } else if let line = ApprovalCardCopy.reasonLine(
                for: response
            ) {
                cardNotes[record.id] = line
            } else {
                cardNotes[record.id] = "裁决未生效，请稍后再试。"
            }
        } catch let error as MacWriteGateError {
            cardNotes[record.id] = error.userMessage
        } catch {
            cardNotes[record.id] = error.localizedDescription
        }
        await refresh(session: session)
    }

    // MARK: - 「总是允许」（先建规则、后批准；与 iOS 同序同文案）

    func decideAlways(
        _ record: WriteGateRecord, session: SessionStore
    ) async {
        guard record.canDecide, let config = session.config,
              let key = session.apiKey else { return }
        guard !decidingIDs.contains(record.id) else { return }
        // 防呆守卫：批不了的死单不建规则、不批准，
        // 只留原因（Core reasonLine 单读口）
        if record.isBlocked {
            cardNotes[record.id] = ApprovalCardCopy.reasonLine(
                for: record
            )
            return
        }
        decidingIDs.insert(record.id)
        cardNotes.removeValue(forKey: record.id)
        let createdRule: WriteGateRule
        do {
            createdRule = try await session.chatClient
                .createWriteGateRule(
                    config: config, apiKey: key,
                    subsystem: record.subsystem, origin: record.origin
                )
        } catch {
            cardNotes[record.id] =
                "「总是允许」没能记住（规则建立失败），这条仍在待批中。"
            decidingIDs.remove(record.id)
            return
        }
        await refreshRules(session: session)
        decidingIDs.remove(record.id)
        await decideGate(record, approve: true, session: session)
        showAlwaysAllowToast(
            rule: createdRule,
            scopeLabel: ApprovalCardCopy.alwaysAllowScope(for: record)
        )
    }

    private func showAlwaysAllowToast(
        rule: WriteGateRule, scopeLabel: String
    ) {
        toastTask?.cancel()
        let toast = MacAlwaysAllowToast(
            rule: rule, scopeLabel: scopeLabel
        )
        alwaysAllowToast = toast
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if self?.alwaysAllowToast?.id == toast.id {
                self?.alwaysAllowToast = nil
            }
        }
    }

    func dismissAlwaysAllowToast() {
        toastTask?.cancel()
        toastTask = nil
        alwaysAllowToast = nil
    }

    /// 轻通知上的撤销：只删规则（已批准的那条不回滚）
    func undoAlwaysAllow(session: SessionStore) async {
        guard let toast = alwaysAllowToast else { return }
        dismissAlwaysAllowToast()
        await revokeRule(toast.rule, session: session)
    }

    // MARK: - 规则与授权撤销

    /// 撤销一条写闸规则：成功即本地移除；失败保留并
    /// 留痕，随后按服务端真值重拉对账
    func revokeRule(
        _ rule: WriteGateRule, session: SessionStore
    ) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        guard !revokingIDs.contains(rule.id) else { return }
        revokingIDs.insert(rule.id)
        defer { revokingIDs.remove(rule.id) }
        rulesNote = nil
        do {
            try await session.chatClient.deleteWriteGateRule(
                config: config, apiKey: key, id: rule.id
            )
            rules.removeAll { $0.id == rule.id }
        } catch let error as MacWriteGateError {
            rulesNote = error.userMessage
            await refreshRules(session: session)
        } catch {
            rulesNote = "撤销没能生效，请稍后再试。"
            await refreshRules(session: session)
        }
    }

    /// 撤销一条命令授权：成败不认回执、只认事后清单
    /// 回读（Core GrantReadback 同口径）；404 按已不
    /// 在处理、409 明示未确认，不许报假成功
    func revokeGrant(
        _ entry: GrantEntry, session: SessionStore
    ) async {
        guard entry.canRevokeHere, let patternKey = entry.patternKey,
              let config = session.config, let key = session.apiKey
        else { return }
        guard !revokingIDs.contains(entry.grantKey) else { return }
        revokingIDs.insert(entry.grantKey)
        defer { revokingIDs.remove(entry.grantKey) }
        grantsNote = nil
        do {
            let (status, code) = try await session.chatClient
                .revokeGrant(
                    config: config, apiKey: key, patternKey: patternKey
                )
            switch GrantRevokeDirective.directive(
                status: status, serverCode: code
            ) {
            case .done, .notFound:
                break  // 进回读确认
            case .wrongChannel:
                grantsNote = "这条授权不走本通道撤销。"
                return
            case .unverified:
                grantsNote = "服务端自检未过，这条授权可能仍在，已按最新清单刷新。"
                await refreshGrants(session: session)
                return
            case .failed:
                grantsNote = "撤销没能生效，请稍后再试。"
                await refreshGrants(session: session)
                return
            }
            await refreshGrants(session: session)
            if let refreshed = grants,
               !GrantReadback.isConfirmedAbsent(
                   grantKey: entry.grantKey, in: refreshed
               ) {
                grantsNote = "撤销未确认：这条授权仍在清单里。"
            }
        } catch {
            grantsNote = "撤销没能生效，请稍后再试。"
        }
    }
}
