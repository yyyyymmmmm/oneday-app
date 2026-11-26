import Foundation
import Observation
import OneDayCore
import SwiftData

extension SessionLedger {
    // MARK: - 主线钦定（第 90 条收尾：持有迁入，同键）

    /// 主线种子已落位（0.27.0）：主线本地历史已导入
    /// 钦定会话——确认位与种子位由 markMainLinked
    /// 一并置真（链接流程把「会话存在」与「历史已
    /// 导入」一次做完，不再分两段各确认一半）
    /// 主线最近一次链接失败原因（0.27.0）：链接失败
    /// 不许再静默——原文落此、设置页「服务器与连接」
    /// 区如实展示，链接成功即清
    /// 主线认领记录（§330）：最近一次认领落定的留痕
    /// （认领到哪条/消息数/最近活动/归档位/候选数），
    /// 设置页「主线会话」呈现；归档位同时是「打开时
    /// 解档」的一次性凭据（解档落定即清位）
    /// 本地状态读取失败的人话提示（§332）：启动读
    /// 入时任一侧账解码失败即置位，设置页「主线会
    /// 话」呈现；自愈对账完成（目录可达）后清，诊
    /// 断痕永久留底
    /// 解码失败待自愈标记（§332）：ChatView 进主
    /// 线链接时消费一次——向服务端重新发现对账
    /// （rediscoverAfterStateReadFailure）；未登录
    /// 时不消费、留待登录后

    func designateMainThread(_ id: UUID) {
        mainThreadID = id
        identityStore.set(
            id.uuidString, forKey: IdentityKey.mainThreadID
        )
        // 双轨镜像：旧键同拍回写（§330，停写归下一版）
        defaults?.set(id.uuidString, forKey: Key.mainThreadID)
    }

    /// 主线的服务端会话 id：已有落存直接返回；缺失时
    /// 本地生成并持久化——§330 起本函数降为冷启动最
    /// 后手段：调用方必须先走 discoverAndClaimMain-
    /// line 确认服务端无主线（或认领落存）才许到这
    /// 里，生成值最终以服务端建会话回执为准改存
    func ensureMainServerSessionID() -> String {
        if let mainServerSessionID { return mainServerSessionID }
        let generated = "oneday-main-\(UUID().uuidString.lowercased())"
        setMainServerSessionID(generated)
        return generated
    }

    func setMainServerSessionID(_ id: String) {
        mainServerSessionID = id
        identityStore.set(
            id, forKey: IdentityKey.mainServerSessionID
        )
        defaults?.set(id, forKey: Key.mainServerSessionID)
    }

    func confirmMainServer() {
        mainServerConfirmed = true
        identityStore.set(
            true, forKey: IdentityKey.mainServerConfirmed
        )
        defaults?.set(true, forKey: Key.mainServerConfirmed)
    }

    /// 主线发送闸派生（§331）：id 已知即 ready——
    /// 发送路径的单点判据，种子/回补状态一律不进
    /// （它们是后台义务、不是发送前置）
    func mainSendGate() -> MainSendGate {
        guard let mainServerSessionID, !mainServerSessionID.isEmpty
        else { return .needsIdentity }
        return .ready(sessionID: mainServerSessionID)
    }

    /// 主线同步快照（§331，内存面不落盘：呈现素材，
    /// 进程重启后由下一轮同步动作重建）

    /// 同步动作落点回写快照（ChatView 的回补/种子
    /// 调度收口调用；数值口径与主线线程三字段同源）
    func updateMainSyncStatus(
        historyUnsynced: Bool, historyLoaded: Int,
        historyTotal: Int, seedState: SeedSyncState
    ) {
        mainSyncStatus = MainSyncStatus(
            historyUnsynced: historyUnsynced,
            historyLoaded: historyLoaded,
            historyTotal: historyTotal,
            seedState: seedState
        )
    }

    /// 主线链接落定（0.27.0）：会话存在＋种子已落
    /// 一并确认、失败留痕清零。§331 后种子位只剩
    /// 记账意义（发送闸见 mainSendGate），本函数仍
    /// 是「链接＋种子同轮落定」时的收口
    func markMainLinked() {
        confirmMainServer()
        mainServerSeeded = true
        identityStore.set(
            true, forKey: IdentityKey.mainServerSeeded
        )
        defaults?.set(true, forKey: Key.mainServerSeeded)
        mainLinkLastError = nil
        defaults?.removeObject(forKey: Key.mainLinkLastError)
    }

    /// 主线链接失败留痕（0.27.0）：原因原文落盘，
    /// 设置页展示；不置任何确认位，下次进页/发送
    /// 重试链接
    func noteMainLinkError(_ message: String) {
        mainLinkLastError = message
        defaults?.set(message, forKey: Key.mainLinkLastError)
    }

    // MARK: - 发现与认领（根治版包 1，DESIGN §330）

    /// 登录后发现与认领（第一动作）：本地身份缓存已
    /// 有 id 时不打扰服务端（.alreadyKnown）；缺失时
    /// 拉目录过纯函数判定——认领到则落存 id＋确认位
    /// ＋认领记录；目录确无主线回 .noCandidateOn-
    /// Server（调用方才许走冷启动铸造）；未登录/目
    /// 录不可达回 .directoryUnavailable（调用方不许
    /// 铸造、留未认领态待重试）。本函数永不铸造 id、
    /// 永不写服务端
    @discardableResult
    func discoverAndClaimMainline(
        appState: AppState
    ) async -> MainlineClaimOutcome {
        guard mainServerSessionID == nil else {
            return .alreadyKnown
        }
        guard appState.config != nil else {
            return .directoryUnavailable
        }
        guard let rows = await claimSessions(appState: appState)
        else { return .directoryUnavailable }
        return applyMainlineClaim(rows: rows)
    }

    /// 设置页手动重新发现（§330）：不短路现任 id——
    /// 现任仍在目录里回 .alreadyKnown（无事）；不在
    /// 目录里且有同标题候选则改认候选（指针接错/服
    /// 务端换代的支持面恢复路，改认在认领记录与诊
    /// 断痕里留名）；不在且无候选保留现任指针不清
    /// 空（名单未必完整、清空是破坏动作），原因落
    /// mainLinkLastError 呈现
    @discardableResult
    func rediscoverMainline(
        appState: AppState
    ) async -> MainlineClaimOutcome {
        guard appState.config != nil,
              let rows = await claimSessions(appState: appState)
        else {
            noteMainLinkError(
                "重新发现没完成：会话目录拉取失败，请检查连接后重试"
            )
            return .directoryUnavailable
        }
        if let current = mainServerSessionID,
           rows.contains(where: { $0.session.id == current }) {
            return .alreadyKnown
        }
        let outcome = applyMainlineClaim(rows: rows)
        if outcome == .noCandidateOnServer,
           mainServerSessionID != nil {
            noteMainLinkError(
                "服务器目录里没找到当前主线，也没有同名会话可认领——已保留现有绑定"
            )
        }
        return outcome
    }

    /// 解码失败自愈消费（§332）：ChatView 进主线
    /// 链接（ensureMainLink）入口调用——标记在册
    /// 且已登录时走一轮重新发现对账（复用 redis-
    /// coverMainline：现任在册无事、失效改认候选、
    /// 无候选保留现任不清指针）；目录不可达时提
    /// 示保留待下次启动再对账。标记一轮只消费一
    /// 次，不许每进一次主线都重拉目录
    func rediscoverAfterStateReadFailure(
        appState: AppState
    ) async {
        guard stateReadFailurePendingRediscovery else { return }
        guard appState.config != nil else { return }
        stateReadFailurePendingRediscovery = false
        let outcome = await rediscoverMainline(appState: appState)
        if outcome != .directoryUnavailable {
            localStateReadFailureNote = nil
        }
    }

    /// 认领候选行（与 adoptionSessions 同源、另带归
    /// 档位与行本体）：账本两段齐全时按段定归档位
    /// （可见段 false、归档段 true）；未齐全回落现拉
    /// include 全量、归档位读行本体。只用于候选检
    /// 索、不驱动删除，不需完整性闸（不完整至多漏
    /// 候选、方向保守）；拉不到返回 nil
    func claimSessions(
        appState: AppState
    ) async -> [(session: ServerSession, isArchived: Bool)]? {
        if hasLoadedFull {
            var seen = Set<String>()
            var rows: [(session: ServerSession, isArchived: Bool)] = []
            for session in visibleSessions
            where seen.insert(session.id).inserted {
                rows.append((session, session.isArchived ?? false))
            }
            for session in archivedSessions
            where seen.insert(session.id).inserted {
                rows.append((session, true))
            }
            return rows
        }
        guard let sessions = try? await Self.fetchAll(
            appState: appState, archived: "include"
        ).sessions else { return nil }
        return sessions.map { ($0, $0.isArchived ?? false) }
    }

    /// 身份对账取数（H1-d 体检第四组）：现拉一份服务
    /// 端目录全量（含归档段）连同完整性口径回给体检
    /// 面——对账认的是刚拉到的服务端目录，不拿本地
    /// 缓存投影冒充服务端所报。与 claimSessions 的区
    /// 别：那边为候选检索可读缓存、完整性不设闸；这
    /// 边是判定数据源，完整性口径必须原样带出（没拉
    /// 全就不下结论）。只读：不写服务端、不动本地账
    func identityCatalogSnapshot(
        appState: AppState
    ) async throws -> FetchResult {
        try await Self.fetchAll(
            appState: appState, archived: "include"
        )
    }

    /// 本机账本的目录投影条数（可见＋归档两段去重）：
    /// 只作对账时的漂移提示、不作判据；账本没整表加
    /// 载过时为 nil（没缓存就不提缓存的事）
    var localCatalogProjectionCount: Int? {
        guard hasLoadedFull else { return nil }
        var seen = Set<String>()
        for session in visibleSessions { seen.insert(session.id) }
        for session in archivedSessions { seen.insert(session.id) }
        return seen.count
    }

    /// 认领判定与落存（两口共用）：候选投影交 Core
    /// 纯函数（标题全等＋删除账排除＋既定序）；落存
    /// 只写本地身份缓存与认领记录——不写服务端、不
    /// 解档（归档位随记录留存，解档归打开动作）
    func applyMainlineClaim(
        rows: [(session: ServerSession, isArchived: Bool)]
    ) -> MainlineClaimOutcome {
        let candidates = rows.map {
            MainlineAdoptionCandidate(
                id: $0.session.id, title: $0.session.serverTitle,
                lastActivityAt: $0.session.endedAt
                    ?? $0.session.startedAt,
                isArchived: $0.isArchived
            )
        }
        // 防复活：本地删除账（删除引擎待删队列——删
        // 除未落定的会话服务端仍有其行）在册 id 先排
        // 除，判定本体在 Core 纯函数内过滤
        switch MainlineClaimDirective.directive(
            title: SideChatStore.mainTitle,
            candidates: candidates,
            excludedIDs: deletions.queue.sessionIDs
        ) {
        case .noCandidate:
            return .noCandidateOnServer
        case .claim(let id, let isArchived):
            return recordMainlineClaim(
                sessionID: id, candidateCount: 1,
                isArchived: isArchived, rows: rows
            )
        case .claimAmongMultiple(let id, let count, let isArchived):
            return recordMainlineClaim(
                sessionID: id, candidateCount: count,
                isArchived: isArchived, rows: rows
            )
        }
    }

    /// 认领落存：id 落身份缓存＋确认位置真＋认领记
    /// 录留痕（诊断痕＋设置页记录同源）；改认（原绑
    /// 定非空且不同）时在诊断痕里点名原绑定
    func recordMainlineClaim(
        sessionID: String, candidateCount: Int,
        isArchived: Bool,
        rows: [(session: ServerSession, isArchived: Bool)]
    ) -> MainlineClaimOutcome {
        let previous = mainServerSessionID
        setMainServerSessionID(sessionID)
        confirmMainServer()
        let row = rows.first { $0.session.id == sessionID }?.session
        let record = MainlineClaimRecord(
            sessionID: sessionID,
            messageCount: row?.messageCount,
            lastActivityAt: row?.endedAt ?? row?.startedAt,
            isArchived: isArchived,
            candidateCount: candidateCount,
            claimedAt: Date().timeIntervalSince1970
        )
        mainClaimRecord = record
        persist(record, Key.mainClaimRecord)
        var trace = "主线认领：服务端目录认领既有会话 \(sessionID)"
            + "（消息 \(record.messageCount.map(String.init) ?? "未知") 条"
            + "、同标题候选 \(candidateCount) 条"
            + (isArchived ? "、归档态保持" : "")
            + "）"
        if let previous, previous != sessionID {
            trace += "；原绑定 \(previous) 已改认"
        }
        ChatDiagTrace.record(trace)
        return .claimed(
            sessionID: sessionID,
            candidateCount: candidateCount,
            isArchived: isArchived
        )
    }

    /// 认领归档态的一次性解档（§330 主线裁定）：认
    /// 领时保持归档，用户打开主线（链接落定）时才
    /// 解——只认认领记录的归档位，落定即清位，用户
    /// 此后自行归档与本路无关；解档失败不清位、下
    /// 次打开再试
    func unarchiveClaimedMainlineIfNeeded(
        appState: AppState
    ) async {
        guard let record = mainClaimRecord, record.isArchived,
              record.sessionID == mainServerSessionID
        else { return }
        let outcome = await ServerSessionActions.setArchived(
            appState: appState, id: record.sessionID,
            archived: false
        )
        guard case .verified = outcome else { return }
        var updated = record
        updated.isArchived = false
        mainClaimRecord = updated
        persist(updated, Key.mainClaimRecord)
        unarchive(serverSessionID: record.sessionID)
        ChatDiagTrace.record(
            "主线认领归档已随打开解档：\(record.sessionID)"
        )
    }

    // MARK: - 归档列（第 90 条收尾：持有迁入＋双轨回写）

    /// 本地归档键集（`local:<uuid>` 与 `server:<id>`
    /// 双命名空间共用一集）：账本读入建归档列，写
    /// 路径仍回写原键 sideChats.archivedKeys——双轨
    /// 一版保回滚（旧版 App 读同键即恢复全功能），
    /// 停写/清键归下一大版本
    /// 删除归档失败留痕（0.21.0）：本地线程已删、关
    /// 联服务端会话归档 PATCH 失败待对账的会话 id
    /// 集（口径见 noteFailedSessionArchive）——随归
    /// 档列收编（施工图 §4.2）

    func archive(localThreadID: UUID) {
        archivedKeys.insert(SideChatArchive.localKey(localThreadID))
        persistArchived()
    }

    func archive(serverSessionID: String) {
        archivedKeys.insert(SideChatArchive.serverKey(serverSessionID))
        persistArchived()
    }

    func unarchive(localThreadID: UUID) {
        archivedKeys.remove(SideChatArchive.localKey(localThreadID))
        persistArchived()
    }

    func unarchive(serverSessionID: String) {
        archivedKeys.remove(SideChatArchive.serverKey(serverSessionID))
        persistArchived()
    }

    func persistArchived() {
        defaults?.set(Array(archivedKeys), forKey: Key.archivedKeys)
    }

    /// 抽屉删本地线程时关联服务端会话做归档（PATCH
    /// archived:true）——本地删除不被服务端动作阻
    /// 塞、归档尽力而为；失败不许静默吞：会话 id 落
    /// 此账留痕，该会话在管理页未归档段仍可见、可
    /// 手动归档收尾；日后归档成功（本表对账）由
    /// clearFailedSessionArchive 销账
    func noteFailedSessionArchive(_ sessionID: String) {
        guard !failedArchiveSessionIDs.contains(sessionID) else {
            return
        }
        failedArchiveSessionIDs.append(sessionID)
        persist(failedArchiveSessionIDs, Key.failedArchiveSessionIDs)
    }

    func clearFailedSessionArchive(_ sessionID: String) {
        guard failedArchiveSessionIDs.contains(sessionID) else {
            return
        }
        failedArchiveSessionIDs.removeAll { $0 == sessionID }
        persist(failedArchiveSessionIDs, Key.failedArchiveSessionIDs)
    }

    /// 真删落定后的本地清账（0.50.30）：服务端会话已
    /// 回查确认不存在，按其 id 挂在本地的账一并清掉
    /// ——标题覆盖、服务端形态归档键、归档失败留痕，
    /// 不留残影（id 若日后重现也不许被旧账染指）。
    /// 第 90 条收尾随归档列迁入本店：标题覆盖仍归
    /// SideChatStore 持有，经 appState 清项
    func purgeServerSessionRecords(
        _ sessionID: String, appState: AppState
    ) {
        appState.sideChats.setTitleOverride(nil, for: sessionID)
        unarchive(serverSessionID: sessionID)
        clearFailedSessionArchive(sessionID)
    }

    // MARK: - 关联表（第 90 条收尾：持有迁入，同键）

    /// 点子→旁聊关联（0.48.0，§122）：采纳时建的旁聊
    /// 线程 id 按点子 id 落盘，「打开对话」回同一条；
    /// 线程被删后关联失效、点按时补建并改写本表
    /// 目标→旁聊绑定（§123 H1）：目标 id → 线程 id 串。
    /// 用户在目标里「安排一件事」时创建/复用并落盘，
    /// 委派任务的进展与完成回响落进这个线程（绑定模式
    /// 与点子采纳的 ideaThreadIDs 同形，§122）
    /// 动态讨论待发信号（FA-1）：线程 id → 帖 id。
    /// 点「讨论」建旁聊时落盘；该线程第一条用户消息
    /// 发出后 ChatView 据此发一记 discuss 信号并销
    /// 账——信号只认首句（note 取首句自述偏好句），
    /// 漏发/永不发送的关联留着无副作用（下次该线程
    /// 首发仍是首句）

    func threadID(forIdeaID id: String) -> UUID? {
        ideaThreadIDs[id].flatMap { UUID(uuidString: $0) }
    }

    func linkThread(_ threadID: UUID, forIdeaID id: String) {
        ideaThreadIDs[id] = threadID.uuidString
        persist(ideaThreadIDs, Key.ideaThreadIDs)
    }

    /// 目标绑定的旁聊线程 id；未绑（还没在这个目标里
    /// 安排过事）为 nil
    func threadID(forGoalID goalID: String) -> UUID? {
        goalThreadIDs[goalID].flatMap(UUID.init(uuidString:))
    }

    func linkThread(_ threadID: UUID, forGoalID goalID: String) {
        goalThreadIDs[goalID] = threadID.uuidString
        persist(goalThreadIDs, Key.goalThreadIDs)
    }

    /// 讨论建聊时登记：线程的第一条用户消息要替这
    /// 篇帖发一记 discuss 信号
    func linkFeedDiscussThread(_ threadID: UUID, postID: String) {
        // 一帖一线程：同帖改挂新线程（旧线程已删后
        // 补建）时先摘其他线程的同帖关联，否则反查
        // 会捞回已删线程、discuss 每次都新建（去重
        // 失效、空会话堆积复发）
        for key in feedDiscussPostIDs
            .filter({ $0.value == postID }).map(\.key)
            where key != threadID.uuidString {
            feedDiscussPostIDs.removeValue(forKey: key)
        }
        feedDiscussPostIDs[threadID.uuidString] = postID
        persist(feedDiscussPostIDs, Key.feedDiscussPostIDs)
    }

    func feedDiscussPostID(forThreadID threadID: UUID) -> String? {
        feedDiscussPostIDs[threadID.uuidString]
    }

    /// 反查（§208 讨论去重）：这篇帖已有的讨论线程
    /// ——discuss() 先查本口，有则复用、不再堆空会话
    /// （与点子流「先查 link」同形）；关联在但线程
    /// 已删时由调用方校验存在性后决定补建
    func threadID(forFeedDiscussPostID postID: String) -> UUID? {
        feedDiscussPostIDs.first(where: {
            $0.value == postID
        }).flatMap { UUID(uuidString: $0.key) }
    }

    /// 信号发出即销账：一线程只报一次，note 只认
    /// 首句——销账先行于网络调用，失败不补发第二句
    func clearFeedDiscuss(forThreadID threadID: UUID) {
        guard feedDiscussPostIDs[threadID.uuidString] != nil else {
            return
        }
        feedDiscussPostIDs[threadID.uuidString] = nil
        persist(feedDiscussPostIDs, Key.feedDiscussPostIDs)
    }

}
