import Foundation
import OneDayCore

/// 点子数据中枢（P5，0.11.0；0.32.0 P1 升级）：oneday-
/// bridge 点子仓的状态面＋「转任务」的执行面。口径：
/// ①桥未连接/未开通与 GoalsStore 同分法（共用其静态
/// 映射，不另立一套说法）；②写动作分档（§233）：转
/// 任务/新建/删除等确认类仍回读确认才算完成；**放
/// 下/忽略改乐观**——卡当拍离场、后台 PATCH，失败
/// 卡回来＋行内提示；③转任务经 P3 KanbanStore 适配层落板——板未开通
/// 如实提示、不假成功，确认建卡后把任务 id 经 PATCH
/// 回写桥端 idea（taskId＋status=adopted，服务端为
/// 「已转」唯一真源；0.32.0 退役旧本地 convertedIdeaIDs
/// 标记，换设备/清缓存不再丢状态）；④忽略走 PATCH
/// dismissed、不弹确认（低风险动作不打扰）；⑤关联
/// 目标名只从同批拉到的目标列表解析，解析不到不显示、
/// 不编名（目标被删后服务端会把 goalId 置 null，回读
/// 即自愈）；⑥生成管道账面（generationInfo）只供空态
/// 与页脚节奏文案，拉不到时这两处降级、不假造。
@MainActor
@Observable
final class IdeasStore {
    typealias LoadState = GoalsStore.LoadState

    private(set) var loadState: LoadState = .loading
    private(set) var ideas: [BridgeIdea] = []
    /// 关联目标解析与新建 picker 的数据源（拉不到只
    /// 降级这两处，点子本体照常）
    private(set) var goals: [BridgeGoal] = []
    /// 生成管道账面（上次/下次运行与近轮记录）；旧桥
    /// 无此端点时为 nil，空态按「清完」侧收、不编时间
    private(set) var generationInfo: BridgeGenerationInfo?
    /// 正在转任务/忽略/删除的点子 id
    private(set) var actingIDs: Set<String> = []
    /// 正在新建（表单防重复提交）
    private(set) var creating = false
    private(set) var createError: String?
    /// 卡内行内提示（转任务/忽略/删除的人话，不弹模态）
    private(set) var notes: [String: String] = [:]
    /// 最近一次删除的成功回响（同类面口径：文件页/
    /// 交付物页删成落「已删除「名」。」小字明示）；
    /// 只在回读确认消失时落字，新一次删除开始即清、
    /// 不叠旧回响；删除未落定不落此字（只走 notes）
    private(set) var deleteNotice: String?

    private let client: OneDayBridgeClientProtocol
    private var loadInFlight = false
    /// 新鲜度门（§367）：读触发先过门，TTL 内零请求
    private var freshness = FreshnessGate(
        ttl: FreshnessGate.standardListTTL
    )

    init(client: OneDayBridgeClientProtocol = OneDayBridgeClient()) {
        self.client = client
    }

    // MARK: - 呈现口径（收口在 Core IdeaBoard）

    /// 待阅：生成卡在前、手记在后，各按时间倒序。
    /// §177 后只余内部用途（忽略回读确认判据），不
    /// 再是页面分区——页面结构走 domainSections
    var pendingIdeas: [BridgeIdea] {
        IdeaBoard.pendingList(ideas)
    }

    /// 已采纳：近 30 天。§177 后只余内部用途（任务
    /// 板预拉判据），不再是页面分区
    var adoptedIdeas: [BridgeIdea] {
        IdeaBoard.adoptedList(ideas, now: Date().timeIntervalSince1970)
    }

    /// 页面唯一结构（§177 立形、§459 换键）：领域
    /// 小节（标题＋卡片），分节键＝domain（旧
    /// category 只作折算兜底），口径收口在 Core
    /// IdeaBoard.domainSections。
    /// §415 改存储快照：旧计算属性每次访问重分组
    /// （body 一趟多次访问多次付账）——现由三个数
    /// 据变更漏斗（installLoadedIdeas/applyOpti-
    /// misticDismiss/restoreDismissed）在落点重算，
    /// 呈现侧读零计算（照资源库快照模板收口）
    private(set) var domainSections: [IdeaDomainSection] = []

    /// 分节快照修订号（§415）：每次重算 +1，钉测
    /// 以此断言呈现侧反复读不重算
    private(set) var domainSectionsRevision = 0

    /// 快照重算落点（数据变更漏斗共用）：入参口径
    /// 与旧计算属性逐字同（IdeaBoard.domainSec-
    /// tions＋当前时刻——已采纳 30 天窗随数据变更
    /// 刷新，与旧「下次访问重算」在可见面同果）
    private func refreshDomainSections() {
        domainSections = IdeaBoard.domainSections(
            ideas, now: Date().timeIntervalSince1970
        )
        domainSectionsRevision += 1
    }

    var hasVisibleIdeas: Bool {
        !domainSections.isEmpty
    }

    /// 空态分法：还没生产过 vs 这一轮已清完
    var emptyKind: IdeaBoard.EmptyKind {
        IdeaBoard.emptyKind(
            totalIdeas: ideas.count,
            lastRunAt: generationInfo?.lastRunAt
        )
    }

    func isConverted(_ idea: BridgeIdea) -> Bool {
        idea.isAdopted
    }

    func goalTitle(for idea: BridgeIdea) -> String? {
        guard let goalId = idea.goalId else { return nil }
        return goals.first { $0.id == goalId }?.title
    }

    /// 已采纳行尾的任务状态文案：从任务板快照按
    /// taskId 查列名派生；查不到回 nil（只显已转任务）
    func taskStatusText(
        for idea: BridgeIdea, kanban: KanbanStore
    ) -> String? {
        let raw = idea.taskId.flatMap { id in
            kanban.snapshot?.tasks.first { $0.id == id }?.status
        }
        return IdeaBoard.taskStatusText(
            idea: idea, taskStatusRaw: raw
        )
    }

    // MARK: - 加载

    /// 读触发入口（§367 新鲜度门）：TTL 内且配置没变
    /// 直接用已载数据、零请求；首载/过期/换服务器才
    /// 走 load 全量。下拉刷新与错误态重试不经此门、
    /// 恒走 load 强制
    func loadIfNeeded(appState: AppState) async {
        await loadIfNeeded(appState: appState, now: Date())
    }

    /// 时刻注入的门控本体（钉测用：推进时刻验过期）
    func loadIfNeeded(appState: AppState, now: Date) async {
        guard !freshness.isFresh(
            configKey: appState.config?.baseString, now: now
        ) else { return }
        await load(appState: appState, now: now)
    }

    func load(appState: AppState, now: Date = Date()) async {
        guard !loadInFlight else { return }
        guard let config = appState.config else {
            loadState = .failed(L10n.string("尚未连接服务器。"))
            return
        }
        loadInFlight = true
        defer { loadInFlight = false }
        do {
            installLoadedIdeas(
                try await client.ideas(config: config)
            )
            loadState = .ready
            freshness.stamp(configKey: config.baseString, now: now)
            // §219：名单到手即扫 §219 前的旧点子预填
            // 存量（逐字再生须拿原点子，这是最早能严
            // 格核验的时点；判定从严、亲笔零误伤，
            // 与 FeedStore 的动态清扫同式）
            appState.sideChats.purgeLegacyIdeaDrafts(
                ideas: ideas,
                links: appState.sessionLedger.ideaThreadIDs
            )
        } catch let error as OneDayBridgeError {
            if loadState == .ready { return }
            loadState = GoalsStore.state(for: error)
        } catch {
            if loadState == .ready { return }
            loadState = .failed(L10n.string("点子没读出来，可能是网络或服务暂时没响应"))
        }
        // 附带面：目标列表与生成账面，失败只降级对应呈现
        if let fetched = try? await client.goals(config: config) {
            goals = fetched
        }
        if let fetched = try? await client.generationInfo(
            config: config
        ) {
            generationInfo = fetched
        }
    }

    /// 静默回读（写动作确认专用）：失败不翻态、不动旧数
    private func refetch(appState: AppState) async {
        guard let config = appState.config else { return }
        if let fetched = try? await client.ideas(config: config) {
            installLoadedIdeas(fetched)
            // 写后回读即全量现值：落账新鲜度（回读本身
            // 不经门、不许被门跳过，§367.4）
            freshness.stamp(
                configKey: config.baseString, now: Date()
            )
        }
        if let fetched = try? await client.goals(config: config) {
            goals = fetched
        }
        if let fetched = try? await client.generationInfo(
            config: config
        ) {
            generationInfo = fetched
        }
    }

    // MARK: - 新建（POST→回读确认出现才算完成）

    func create(
        appState: AppState, title: String, detail: String,
        goalId: String?, category: String?
    ) async -> Bool {
        guard !creating else { return false }
        guard let config = appState.config else {
            createError = L10n.string("尚未连接服务器。")
            return false
        }
        creating = true
        createError = nil
        defer { creating = false }
        let request = BridgeIdeaCreateRequest.make(
            title: title, detail: detail, goalId: goalId,
            category: category
        )
        do {
            let created = try await client.createIdea(
                config: config, request: request
            )
            await refetch(appState: appState)
            if ideas.contains(where: { $0.id == created.id }) {
                return true
            }
            createError = L10n.string("点子已提交，但还没有在列表里确认出现，请关闭后刷新核对。")
            return false
        } catch let error as OneDayBridgeError {
            createError = GoalsStore.message(for: error)
            return false
        } catch {
            createError = L10n.string("点子创建失败，请稍后再试。")
            return false
        }
    }

    // MARK: - 删除（DELETE→回读确认消失才算完成）

    func delete(appState: AppState, idea: BridgeIdea) async {
        // 新一次删除动作开始：旧回响先清，落点由本次
        // 回读定（未连接等早退分支同口径，不留陈字）
        deleteNotice = nil
        guard !actingIDs.contains(idea.id) else { return }
        guard let config = appState.config else {
            notes[idea.id] = L10n.string("尚未连接服务器。")
            return
        }
        actingIDs.insert(idea.id)
        notes.removeValue(forKey: idea.id)
        defer { actingIDs.remove(idea.id) }
        do {
            try await client.deleteIdea(config: config, id: idea.id)
            await refetch(appState: appState)
            applyDeleteOutcome(
                idea: idea,
                stillPresent: ideas.contains(
                    where: { $0.id == idea.id }
                )
            )
        } catch let error as OneDayBridgeError {
            if case .recordGone = error {
                await refetch(appState: appState)
                if !ideas.contains(where: { $0.id == idea.id }) {
                    // 服务端已无此条＝删成（以回读为准）
                    applyDeleteOutcome(idea: idea, stillPresent: false)
                    return
                }
            }
            notes[idea.id] = GoalsStore.message(for: error)
        } catch {
            notes[idea.id] = L10n.string("删除失败，请稍后再试。")
        }
    }

    /// 删除回读落点收口（列表长按菜单与详情 sheet
    /// 两处确认路径共用一个漏斗）：回读确认消失才算
    /// 删成——落删除回响明示删了哪条；还在列表＝未
    /// 落定，只留痕不报已删
    func applyDeleteOutcome(idea: BridgeIdea, stillPresent: Bool) {
        if stillPresent {
            notes[idea.id] = L10n.string("删除已发出，但列表里还在，请刷新核对。")
        } else {
            deleteNotice = L10n.format("已删除「%@」。", idea.title)
        }
    }

    // MARK: - 忽略（§233 乐观：卡先离场，后台 PATCH）

    /// 名单装载收口（load/回读/测试共用一个落点）
    func installLoadedIdeas(_ loaded: [BridgeIdea]) {
        ideas = loaded
        refreshDomainSections()
    }

    /// 乐观离场落点：把点子从本地名单摘掉并返回摘下
    /// 的原条（失败恢复用）；不在名单里返回 nil
    func applyOptimisticDismiss(ideaID: String) -> BridgeIdea? {
        guard let index = ideas.firstIndex(
            where: { $0.id == ideaID }
        ) else { return nil }
        let removed = ideas.remove(at: index)
        refreshDomainSections()
        return removed
    }

    /// 失败恢复落点：原条放回名单（呈现序由 IdeaBoard
    /// 派生排序，不靠数组位置）；已在名单里不重复插
    func restoreDismissed(_ idea: BridgeIdea) {
        guard !ideas.contains(where: { $0.id == idea.id })
        else { return }
        ideas.append(idea)
        refreshDomainSections()
    }

    /// 低风险动作：不弹确认；**卡当拍先离场**，后台
    /// PATCH dismissed＋回读对账——回读后仍在待阅列
    /// 说明服务端没落定，呈现已随回读把卡带回＋留
    /// 提示；网络失败把卡放回＋行内提示。已忽略是终
    /// 态（设计档 §1.4），页内不给恢复入口——想留的
    /// 点子请用删除前的详情页细看。
    /// tooGeneric＝用户标「太泛了」（0.39.0）：随 PATCH 带
    /// dismissReason，桥计入下一轮生成的避让与具体性校准
    func dismiss(
        appState: AppState, idea: BridgeIdea,
        tooGeneric: Bool = false
    ) async {
        guard !actingIDs.contains(idea.id) else { return }
        guard let config = appState.config else {
            notes[idea.id] = L10n.string("尚未连接服务器。")
            return
        }
        actingIDs.insert(idea.id)
        notes.removeValue(forKey: idea.id)
        defer { actingIDs.remove(idea.id) }
        let removed = applyOptimisticDismiss(ideaID: idea.id)
        do {
            _ = try await client.patchIdea(
                config: config, id: idea.id,
                request: BridgeIdeaPatchRequest(
                    status: .dismissed,
                    dismissReason: tooGeneric ? "tooGeneric" : nil
                )
            )
            await refetch(appState: appState)
            if pendingIdeas.contains(where: { $0.id == idea.id }) {
                notes[idea.id] = L10n.string("忽略已发出，但列表里还在，请刷新核对。")
            }
        } catch let error as OneDayBridgeError {
            if let removed { restoreDismissed(removed) }
            notes[idea.id] = GoalsStore.message(for: error)
        } catch {
            if let removed { restoreDismissed(removed) }
            notes[idea.id] = L10n.string("忽略失败，请稍后再试。")
        }
    }

    // MARK: - 一键转任务（经 P3 kanban 适配层＋回写桥）

    /// 流程：先让 KanbanStore 探板（未开通→如实提示、
    /// 不往下走）→ 按 IdeaTaskPlan 组装标题/正文 →
    /// createTaskReturningID（建卡→催派→回板确认并回
    /// 任务 id）→ PATCH 回写桥 taskId（桥同步置
    /// adopted）→ 回读确认点子上 taskId 落字才算完成。
    /// 回写失败时任务已在板上、点子未标已转：如实留在
    /// notes，不假成功、也不回滚任务
    func convertToTask(
        appState: AppState, idea: BridgeIdea, kanban: KanbanStore
    ) async {
        guard !actingIDs.contains(idea.id) else { return }
        guard !isConverted(idea) else {
            notes[idea.id] = L10n.string("这个点子已经转成任务了。")
            return
        }
        guard let config = appState.config else {
            notes[idea.id] = L10n.string("尚未连接服务器。")
            return
        }
        actingIDs.insert(idea.id)
        notes.removeValue(forKey: idea.id)
        defer { actingIDs.remove(idea.id) }

        await kanban.load(appState: appState)
        switch kanban.loadState {
        case .unavailable:
            notes[idea.id] = L10n.string("任务板未开通，暂时不能把点子转成任务。")
            return
        case .failed(let message):
            notes[idea.id] = message
            return
        case .loading:
            notes[idea.id] = L10n.string("任务板状态还没确认好，请稍后再试。")
            return
        case .ready:
            break
        }
        let plan = IdeaTaskPlan.make(
            idea: idea, goalTitle: goalTitle(for: idea)
        )
        let taskID = await kanban.createTaskReturningID(
            appState: appState, title: plan.title, body: plan.body
        )
        guard let taskID else {
            notes[idea.id] = kanban.createError
                ?? L10n.string("任务没有确认建成，请到枢纽任务段核对（聊天页点顶部胶囊打开）。")
            return
        }
        do {
            _ = try await client.patchIdea(
                config: config, id: idea.id,
                request: BridgeIdeaPatchRequest(taskId: taskID)
            )
            await refetch(appState: appState)
            let after = ideas.first { $0.id == idea.id }
            if after?.taskId != taskID {
                notes[idea.id] = L10n.string("任务已建在任务板上，但点子的「已转」标记回写后没确认上，请刷新核对。")
            } else {
                // 触感矩阵（0.36.2，规格 §2.3）：点子
                // 采纳＝任务成功——只在回读确认 taskId
                // 落字（＝采纳真落定）时响，未确认分支
                // 只留 notes 不响
                Haptics.success()
            }
        } catch let error as OneDayBridgeError {
            notes[idea.id] = L10n.string("任务已建在任务板上，但回写点子状态失败：")
                + GoalsStore.message(for: error)
        } catch {
            notes[idea.id] = L10n.string("任务已建在任务板上，但回写点子状态失败，请刷新核对。")
        }
    }

    // MARK: - kind 落地（§459）：立为目标／建为例行

    /// 立为目标：POST /goals 建目标（标题＝点子标题、
    /// 备注＝点子正文、分类＝旧 category 折算的目
    /// 标分类）→ 回读目标列表确认新目标在列 → PATCH
    /// 点子 adopted 回写 → 回读确认点子状态落字才算
    /// 完成（回读判据，与转任务同档）。回写失败时目
    /// 标已建成、点子未标：如实留 notes、不假成功、
    /// 不回滚目标
    func convertToGoal(appState: AppState, idea: BridgeIdea) async {
        guard !actingIDs.contains(idea.id) else { return }
        guard !isConverted(idea) else {
            notes[idea.id] = L10n.string("这个点子已经落地了。")
            return
        }
        guard let config = appState.config else {
            notes[idea.id] = L10n.string("尚未连接服务器。")
            return
        }
        actingIDs.insert(idea.id)
        notes.removeValue(forKey: idea.id)
        defer { actingIDs.remove(idea.id) }
        do {
            let created = try await client.createGoal(
                config: config,
                request: BridgeGoalCreateRequest.make(
                    title: idea.title,
                    note: idea.detail,
                    category: GoalCategory.from(idea.category)
                )
            )
            // 回读判据一：目标已在列表（服务端真源）
            if let fetched = try? await client.goals(
                config: config
            ) {
                goals = fetched
            }
            guard goals.contains(where: { $0.id == created.id })
            else {
                notes[idea.id] = L10n.string(
                    "目标已提交，但回读列表里还没确认到，请刷新核对。"
                )
                return
            }
            try await markAdopted(appState: appState, idea: idea)
        } catch is IdeaAdoptionUnconfirmed {
            // notes 已在回写段就地落字，不覆写
        } catch let error as OneDayBridgeError {
            notes[idea.id] = GoalsStore.message(for: error)
        } catch {
            notes[idea.id] = L10n.string("立为目标失败，请稍后再试。")
        }
    }

    /// 建为例行的回写段：例行本体由 CronJobFormView
    /// 建成、存在性回读在视图侧（共享 CronStore 名
    /// 单含新 job id）先行确认后以 routineConfirmed
    /// 传入；未确认到不回写、如实留 notes（不许标
    /// 已采纳）；确认后只做点子侧回写＋回读确认
    func markAdoptedForRoutine(
        appState: AppState, idea: BridgeIdea,
        routineConfirmed: Bool
    ) async {
        guard !actingIDs.contains(idea.id) else { return }
        guard appState.config != nil else {
            notes[idea.id] = L10n.string("尚未连接服务器。")
            return
        }
        guard routineConfirmed else {
            notes[idea.id] = L10n.string(
                "例行已提交，但回读列表里还没确认到，请刷新核对。"
            )
            return
        }
        actingIDs.insert(idea.id)
        notes.removeValue(forKey: idea.id)
        defer { actingIDs.remove(idea.id) }
        do {
            try await markAdopted(appState: appState, idea: idea)
        } catch is IdeaAdoptionUnconfirmed {
            // notes 已在回写段就地落字，不覆写
        } catch let error as OneDayBridgeError {
            notes[idea.id] = GoalsStore.message(for: error)
        } catch {
            notes[idea.id] = L10n.string("例行已建成，但点子状态回写失败，请刷新核对。")
        }
    }

    /// 采纳回写共用段：PATCH {status: adopted} → 静
    /// 默回读 → 点子状态落 adopted 才算成；未落字
    /// 以 OneDayBridgeError 之外的哨兵错误上抛由调用
    /// 方落 notes（此处直接落 notes 并以 throw 收口
    /// 防双写——调用方 catch 只处理桥错误与未知错
    /// 误，本段的未确认分支已自带 notes、经哨兵跳过）
    private func markAdopted(
        appState: AppState, idea: BridgeIdea
    ) async throws {
        guard let config = appState.config else { return }
        _ = try await client.patchIdea(
            config: config, id: idea.id,
            request: BridgeIdeaPatchRequest(status: .adopted)
        )
        await refetch(appState: appState)
        let after = ideas.first { $0.id == idea.id }
        if after?.status == .adopted {
            Haptics.success()
        } else {
            notes[idea.id] = L10n.string(
                "已建成，但点子的「已落地」标记回写后没确认上，请刷新核对。"
            )
            throw IdeaAdoptionUnconfirmed()
        }
    }

    /// 采纳回写未确认哨兵（notes 已就地落字，catch
    /// 侧勿再覆写）
    private struct IdeaAdoptionUnconfirmed: Error {}
}
