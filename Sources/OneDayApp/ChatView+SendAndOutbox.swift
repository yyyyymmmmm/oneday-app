import NukeUI
import OneDayDesign
import OneDayCore
import Photos
import QuickLook
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ChatView 发件箱、发送提交泵与 Run 驱动引擎（#33 模块化拆分）

extension ChatView {
    // MARK: - 发件箱（台账 154／G-04，DESIGN §336）

    /// 发件箱成员判定（单点）：本条用户消息还没落
    /// 定在服务端——失败（sendFailed）、待发（de-
    /// liveryState=pending）、准备段瞬态被进程中断
    /// （queued/uploading/linking 落盘后无人接管）、
    /// 提交段孤儿（sending 但 run 账本无此轮且泵未
    /// 在提交本条）。呈现（动作面项集）、手动入口
    /// （重发/编辑/撤回）与提交泵共用本判定，不许
    /// 各写一份
    func isOutboxEntry(_ entry: ChatEntry) -> Bool {
        guard entry.role == "user", !entry.isSystemAnchored,
              entry.toolCardData == nil else { return false }
        if entry.sendFailed || entry.isPendingSend {
            return true
        }
        guard let state = entry.sendState else { return false }
        switch state {
        case .queued, .uploading, .linking, .failed:
            return true
        case .sending:
            // §451：逐条核账——本条无账本且泵未在提
            // 交本条，才是提交段孤儿（多轮并存后「整
            // 线程账本判空＋无流在跑」的旧口径作废：
            // 别的轮次在飞不该把本条的孤儿身份藏起
            // 来）
            return appState.runLedger.entry(
                forUserEntryID: entry.id
            ) == nil
                && !pumpInFlightEntryIDs.contains(entry.id)
        case .accepted:
            // 发送失败机制包（双轴语义）：已受理条目
            // 恒有账本、对账链管辖，不进发件箱动作
            // 面；账本缺失的受理态是孤儿变体（账本被
            // 异常清走）——浮回发件箱面交用户裁决，
            // 不许无声卡死
            return appState.runLedger.entry(
                forUserEntryID: entry.id
            ) == nil
        case .delivered:
            return false
        }
    }

    /// 发件箱条目的统一重发口（动作面与提交泵共
    /// 用）：失败条目走既有 resendFailedEntry；待
    /// 发与准备段中断条目先折回待发巷（markPend-
    /// ingSend——获得「未发送」可见标记与 resend-
    /// Pending 的入场资格）再走 resendPending。不
    /// 新建发送链、与手点同一条路
    func resumeOutboxEntry(_ entry: ChatEntry) {
        // §451：在飞守卫退役——重发只登记工单入
        // 泵、与任何在飞轮次共存（泵按序位提交）；
        // 旧守卫防的是 launchTurn 直驱叠发，入泵后
        // 无此患
        guard isOutboxEntry(entry) else { return }
        if entry.sendFailed {
            resendFailedEntry(entry)
            return
        }
        if !entry.isPendingSend {
            entry.markPendingSend(in: modelContext)
        }
        resendPending(entry)
    }

    /// 撤回未发送条目（台账 154）：本条从未在服务
    /// 端落定（失败/待发/中断态），撤回是纯本地动
    /// 作——删条目、清暂存载荷（内存格＋磁盘暂
    /// 存）、清自动重试记账、清指向本条的失败横幅
    /// 账。服务端无此条、不发任何请求
    func withdrawUnsentEntry(_ entry: ChatEntry) {
        // 在飞守卫（与 editUnsentEntry 同口径）：正
        // 被 launchTurn/driveRun 驱动的条目（发送在
        // 飞的 queued/uploading 本体）不许删——驱动
        // 链持其引用继续走，删之即与落定写口相撞。
        // 孤儿态条目无流在跑、恒可撤
        guard isOutboxEntry(entry),
              appState.runLedger.entry(
                  forUserEntryID: entry.id
              ) == nil,
              !pumpInFlightEntryIDs.contains(entry.id)
        else { return }
        let entryID = entry.id
        // §414：撤回的若是原位编辑的武装目标，武装
        // 同点作废（条目已删、写回无从谈起）
        if unsentEditTargetID == entryID {
            unsentEditTargetID = nil
            unsentEditFilesRepresented = false
        }
        failedFilePayloads[entryID] = nil
        pendingResendAttachments[entryID] = nil
        try? stagedSendStore.remove(entryID: entryID)
        appState.outboxRetry.clear(entryID: entryID)
        modelContext.delete(entry)
        try? modelContext.save()
    }

    /// 编辑未发送条目（台账 154；§414 改判原位）：
    /// 把内容与附件装载进发送舱并武装目标——装载
    /// 走既有载荷口径（图片全集在条目本体、文件
    /// 凭条目 id 回暂存重建、引用两槽按 send() 快
    /// 照的同款互斥回填）；原条目不删、不动，用户
    /// 改完点发送时由 send() 把新内容写回原条目
    /// 本体原位重发（performUnsentEditSend，同
    /// id/同位置）。旧「回收删条＋新条目新一轮」
    /// 作废：删条重建让失败消息在编辑一次后换位
    /// 换身份，与失败不消失定版相悖；旧虑「原地
    /// 改字让已拼装出站形态与条目分叉」由写回后
    /// 重走发件箱重发口消解（出站形态在重发时按
    /// 新条目内容现拼，不存在先拼后改）
    func editUnsentEntry(_ entry: ChatEntry) {
        guard isOutboxEntry(entry),
              let thread = entry.thread,
              thread.id == currentThreadID else { return }
        // §451：账本在飞不再挡编辑（本条未受理、编
        // 辑后由 send() 写回原位再入泵）；只挡泵正
        // 在提交本条的瞬时窗（写回会与提交段相撞）
        guard !pumpInFlightEntryIDs.contains(entry.id)
        else {
            showNotice("这条正在发送中，稍等一下再编辑。")
            return
        }
        // 发送舱有未发完的内容时不许回收覆盖（用户
        // 亲笔优先）：正文/附件/引用槽任一在场都算
        // 占用，先请用户处理完
        guard input.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              attachments.isEmpty, pendingQuote == nil,
              pendingFeedQuote == nil,
              pendingSourceQuote == nil
        else {
            showNotice("输入框里还有没发完的内容，先发掉或清空，再来编辑这条。")
            return
        }
        let text = entry.content
        let imageDatas = entry.allImageDatas
        let filePayloads = resendFilePayloads(
            entryID: entry.id
        )
        let quote = entry.quote
        let sourceQuote = entry.sourceQuote
        // §414：只武装＋装载，原条目原样留列（失败/
        // 待发标记、暂存、远端路径全不动）；文件面
        // 管辖按载荷可代表性记账（载荷不在而远端路
        // 径在场＝文件已在服务端，编辑只管正文/图
        // 片/引用，文件面在写回时原样保留）
        unsentEditTargetID = entry.id
        unsentEditFilesRepresented = !filePayloads.isEmpty
            || entry.remoteFilePaths.isEmpty
        input = text
        attachments = imageDatas.map {
            PendingAttachment(kind: .image($0))
        } + filePayloads.map {
            PendingAttachment(
                kind: .file(name: $0.name, data: $0.data)
            )
        }
        pendingQuote = quote
        switch sourceQuote {
        case .feed(let feedQuote):
            pendingFeedQuote = feedQuote
        case .idea, .file, .goal:
            pendingSourceQuote = sourceQuote
        case nil:
            break
        }
        composerFocusHandle.focus()
    }

    /// §414（修复包一·路三）：未发送编辑的发送落点
    /// ——新内容写回原条目本体（applyUnsentEdit：
    /// 同 id、同时刻、同位置，发送状态不动），附
    /// 件面按武装时的可代表性分工：可代表时以发
    /// 送舱快照重建——旧暂存（内存格＋磁盘）全
    /// 清、新载荷重暂存、远端路径作废待重传（上
    /// 传同名覆盖、口径见 uploadPendingFiles）；
    /// 不可代表时（文件已在服务端、载荷不在本
    /// 机）文件面一字不动、只改正文/图片/引用。
    /// 写回后走发件箱统一重发口 resumeOutbox-
    /// Entry（失败/待发/准备段中断三态同口分
    /// 发），标记与状态由重发链自理
    func performUnsentEditSend(
        target: ChatEntry, thread: ChatThread, text: String,
        pending: [PendingAttachment], quote: MessageQuote?,
        combinedSourceQuote: SourceQuote?,
        filesRepresented: Bool
    ) {
        let imageDatas = pending.compactMap(\.imageData)
        let filePayloads = pending.compactMap(\.filePayload)
        target.applyUnsentEdit(
            content: text, imageDatas: imageDatas,
            quote: quote, sourceQuote: combinedSourceQuote,
            in: modelContext
        )
        if filesRepresented {
            failedFilePayloads[target.id] = nil
            pendingResendAttachments[target.id] = nil
            try? stagedSendStore.remove(entryID: target.id)
            if !filePayloads.isEmpty {
                try? stagedSendStore.stage(
                    entryID: target.id,
                    payloads: filePayloads.map {
                        StagedSendPayload(
                            name: $0.name, data: $0.data
                        )
                    }
                )
            }
            target.remoteFilePathsData = nil
            try? modelContext.save()
        }
        // 发送失败机制包（语义 1 清账点③）：编辑重
        // 投＝用户显式新尝试——重试记账在此清零（预
        // 算由用户意志重置）；手点原样重发不清（见
        // resendFailedEntry 注）
        appState.outboxRetry.clear(entryID: target.id)
        resumeOutboxEntry(target)
    }

    // MARK: - §451 发送机制换代（提交泵＋消费环）

    /// 重发口组装（resendFailedEntry/resendPending/
    /// 泵的无工单重组共用）：种子按非待发序位摘除
    /// 本条自身（本条只以尾条身份经 run 投递、不许
    /// 在种子里先落一份）、出站只喂本条（引用拼装
    /// ＋本地图多模态，与 send() 尾条同口径）
    func resendJobParts(
        thread: ChatThread, entry: ChatEntry
    ) -> (seedSnapshot: [SeedEntry], outgoing: ChatMessage) {
        let nonPendingIDs = thread.sortedEntries
            .filter { !$0.isPendingSend }
            .map(\.id)
        var seedSnapshot = Self.seedEntries(of: thread)
        if let seedIndex = nonPendingIDs.firstIndex(
            of: entry.id
        ), seedIndex < seedSnapshot.count {
            seedSnapshot.remove(at: seedIndex)
        }
        var outgoing = ChatMessage(
            role: "user",
            content: MessageQuote.outgoingContent(
                userText: entry.content, quote: entry.quote,
                sourceQuote: entry.sourceQuote
            )
        )
        let entryImageDatas = entry.allImageDatas
        if !entryImageDatas.isEmpty {
            outgoing = ChatMessage(
                role: "user",
                text: MessageQuote.outgoingContent(
                    userText: entry.content, quote: entry.quote,
                    sourceQuote: entry.sourceQuote
                ),
                imageDataURLs: entryImageDatas.map {
                    "data:image/jpeg;base64,\($0.base64EncodedString())"
                }
            )
        }
        return (seedSnapshot, outgoing)
    }

    /// 泵的无工单重组（进程重启后的存量待发/失败条
    /// 目）：与手点重发同一组装口＋载荷回暂存重建
    func rebuiltSubmitJob(
        thread: ChatThread, entry: ChatEntry
    ) -> SubmitJob {
        let parts = resendJobParts(thread: thread, entry: entry)
        return SubmitJob(
            thread: thread, userEntry: entry,
            text: entry.content,
            filePayloads: resendFilePayloads(entryID: entry.id),
            presetFilePaths: entry.remoteFilePaths,
            seedSnapshot: parts.seedSnapshot,
            context: [parts.outgoing],
            frameStartedAt: nil
        )
    }

    /// 提交泵踢动口：同线程单泵防重入（泵内串行
    /// POST，跨线程各跑各的泵）
    func kickSubmitPump(thread: ChatThread) {
        guard !appState.isDemo else { return }
        let threadID = thread.id
        guard !submitPumpThreads.contains(threadID)
        else { return }
        submitPumpThreads.insert(threadID)
        submitPumpTasks[threadID] = Task {
            await runSubmitPump(thread: thread)
            submitPumpThreads.remove(threadID)
            submitPumpTasks[threadID] = nil
        }
    }

    /// §451 提交泵（App-1）：逐条按 SubmissionLane
    /// 车道判定取下一条提交，受理即走（不等落定，
    /// 消费环另接）；未受理失败堵泵（严格保序，用
    /// 户 2026-11-24 亲选）——停在失败条上、后续不
    /// 越过，等其自动重试到点（后续触发重跑本泵）
    /// 或用户手点重发解堵；离线折回待发巷同停泵
    /// （网络恢复等触发再跑）
    func runSubmitPump(thread: ChatThread) async {
        guard appState.config != nil, appState.apiKey != nil
        else { return }
        while !Task.isCancelled {
            surfaceSendingOrphans(in: thread)
            let ledgerIDs = Set(
                appState.runLedger.entries(
                    forThreadID: thread.id
                ).map(\.userEntryID)
            )
            var laneEntries: [SubmissionLane.Entry] = []
            var byID: [UUID: ChatEntry] = [:]
            // 本趟见到的最早退避到期点：泵退出时排唤
            // 醒钟（语义 4——闸与钟同源，B3 关账）
            var earliestBackoff: Date?
            for entry in thread.sortedEntries
            where isOutboxEntry(entry)
                || ledgerIDs.contains(entry.id.uuidString) {
                byID[entry.id] = entry
                let record = appState.outboxRetry.record(
                    for: entry.id
                )
                let policy = OutboxAutoRetryPolicy.decision(
                    state: entry.sendState, record: record,
                    now: Date()
                )
                if case .backoff(let until) = policy {
                    earliestBackoff = min(
                        earliestBackoff ?? until, until
                    )
                }
                let hasLedger = ledgerIDs.contains(
                    entry.id.uuidString
                )
                // 运行面失败（生成失败/超时/模型报错等）说明该条早已
                // 提交并被服务端受理过，不属于“未受理提交失败”，不许堵
                // 后续新消息的提交车道
                if entry.sendState == .failed,
                   !hasLedger,
                   submitJobs[entry.id] == nil,
                   record?.lastFailureKind?.isRunFace == true {
                    continue
                }
                let failed = entry.sendState == .failed
                    && !hasLedger
                // 准备段条目在退避中（P1-2 记账后）：与
                // 未受理失败同格堵泵等到点——不许被车
                // 道当残影跳过、更不许越过它先发后条
                // （严格保序）；有登记工单（用户编辑重
                // 投/手点）在场时不走此格、走提交格
                let prepInBackoff = !hasLedger && !failed
                    && submitJobs[entry.id] == nil
                    && (entry.sendState == .queued
                        || entry.sendState == .uploading
                        || entry.sendState == .linking)
                    && policy != .autoNow
                    && policy != .manualOnly
                    && policy != .notInQueue
                laneEntries.append(SubmissionLane.Entry(
                    entryID: entry.id,
                    hasLedgerEntry: hasLedger,
                    // 登记工单在场＝用户显式意志（手点
                    // 重发/编辑重投）：压过政策的人工接
                    // 管与成因钉死——否则钉死类成因的
                    // 条目点重发会被车道先堵死、工单永
                    // 不消费（钉测实证的生产缺陷）
                    manualOnly: policy == .manualOnly
                        && submitJobs[entry.id] == nil,
                    unacceptedFailure: failed || prepInBackoff,
                    failureRetryDue: failed
                        && (policy == .autoNow
                            || submitJobs[entry.id] != nil),
                    awaitingSubmission: !hasLedger && !failed
                        && entry.sendState != .sending
                        && entry.sendState != .accepted
                        && (submitJobs[entry.id] != nil
                            || policy == .autoNow)
                ))
            }
            switch SubmissionLane.decision(
                entries: laneEntries
            ) {
            case .submit(let entryID):
                guard let entry = byID[entryID] else { return }
                let registeredJob = submitJobs[entryID]
                let job = registeredJob
                    ?? rebuiltSubmitJob(
                        thread: thread, entry: entry
                    )
                submitJobs[entryID] = nil
                // 派发前状态快照：记账只认「已失败条目
                // 的再投」——首投（待发条目进程重启后
                // 被泵重建工单派发）不是重试、不记账
                // （ChatFailKeepPinTests 存储面钉）
                let wasFailed = entry.sendState == .failed
                let outcome = await performSubmission(job: job)
                // 自动重投记账（语义 2）：无登记工单＋
                // 派发前已失败＝策略批准的自动重投，
                // 执行完毕才记一笔（与成因同落——成因
                // 已在失败落点写入）；登记工单（本会话
                // 主动发送/手点重发/编辑重投）不计。
                // 离线停泊（没出门）与停止不计。旧口径
                // 执行前记账＋受理清账，两头夹击把账
                // 扫没
                if registeredJob == nil, wasFailed {
                    switch outcome {
                    case .accepted, .rejected, .prepareFailed:
                        // 抖动手本点一次抽定（语义 4）：
                        // 退避到期点须全程同值；泵每秒一轮
                        // 重算，若在判定处重抽会翻面
                        appState.outboxRetry.noteAutoAttempt(
                            entryID: entryID, at: Date(),
                            jitterUnit: Double.random(in: 0...1)
                        )
                    case .offlineParked, .rateLimitedParked,
                         .stopped:
                        break
                    }
                }
                switch outcome {
                case .accepted:
                    // 受理不清账（语义 1）：重试账活到
                    // run 真终态——落定成功在 applySet-
                    // tledTurn 清、落定失败留账钉死。
                    // 旧口径在此整线程扫清非发件箱条目
                    // 的账，是死循环的清账入口之一
                    kickConsumer()
                case .offlineParked:
                    if registeredJob != nil {
                        presentSendFailure(kind: .offlineNotSent)
                    }
                    armOutboxWake(
                        earliestBackoff, threadID: thread.id
                    )
                    return
                case .rejected, .prepareFailed,
                     .rateLimitedParked,
                     .stopped:
                    armOutboxWake(
                        earliestBackoff, threadID: thread.id
                    )
                    return
                }
            case .blocked, .blockedManual, .idle:
                armOutboxWake(
                    earliestBackoff, threadID: thread.id
                )
                return
            }
        }
    }

    /// 退避唤醒钟排布（语义 4）：泵退出时若本线程有
    /// 条目在退避中，把最早到期点排给调度器——到期
    /// 由 scheduleOutboxWake 踢泵续发，不许有闸无钟
    /// 靠下一次偶然触发（B3）
    func armOutboxWake(
        _ earliestBackoff: Date?, threadID: UUID
    ) {
        guard let earliestBackoff else { return }
        scheduleOutboxWake(at: earliestBackoff, threadID: threadID)
    }

    /// 唤醒调度器：只留最早一记（已有更早的到期点
    /// 在排时不覆盖）；到期先踢本线程提交泵、在看
    /// 线程同走 drain 记账卫生。回前台/网络恢复仍
    /// 是触发源（drain），本钟只补退避/等待门到期
    /// 这一类「时间到了」的事件
    func scheduleOutboxWake(
        at date: Date, threadID: UUID
    ) {
        if let scheduled = outboxWakeAt, scheduled <= date {
            return
        }
        outboxWakeTask?.cancel()
        outboxWakeAt = date
        outboxWakeTask = Task { @MainActor in
            let delay = date.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            outboxWakeAt = nil
            guard let thread = threads.first(
                where: { $0.id == threadID }
            ) else { return }
            kickSubmitPump(thread: thread)
            if thread.id == currentThreadID {
                drainOutboxIfNeeded()
            }
        }
    }

    /// §451 提交段（泵内单条）：上传待发文件（或沿
    /// 用已落盘远端路径）→ 定发送形态 → POST。失败
    /// 落点与旧 launchTurn 一字同：上传/链接失败
    /// markTurnFailed 原位挂标记（§414 路一）；上传
    /// 进度 UI 只写当前线程（他线程条目后台提交不
    /// 许污染在看线程的占位呈现）
    func performSubmission(
        job: SubmitJob
    ) async -> SubmissionOutcome {
        let thread = job.thread
        let userEntry = job.userEntry
        pumpInFlightEntryIDs.insert(userEntry.id)
        defer { pumpInFlightEntryIDs.remove(userEntry.id) }
        let showsUploadUI = thread.id == currentThreadID
        var fileServerPaths: [String] = job.presetFilePaths
        if fileServerPaths.isEmpty, !job.filePayloads.isEmpty {
            if showsUploadUI { isUploadingFiles = true }
            userEntry.markSendState(
                .uploading, in: modelContext
            )
            // 修法 C：进度初始化改按条目 ID 索引
            if showsUploadUI { uploadProgressFraction[userEntry.id] = 0 }
            do {
                fileServerPaths = try await uploadPendingFiles(
                    userEntry.id, job.filePayloads
                )
            } catch let failure as FileUploadFailure {
                if showsUploadUI { isUploadingFiles = false }
                markTurnFailed(
                    entry: userEntry,
                    filePayloads: job.filePayloads,
                    failureKind: .prepareFailed
                )
                // 拼接走收尾归一（P2-2）：reason 是服
                // 务端/系统自由文本、自带尾标点时旧拼
                // 法出双句号
                presentSendFailure(
                    kind: .prepareFailed,
                    message: SendFailureCopy.joiningReason(
                        head: "文件「\(failure.fileName)」没能上传，这条还没发出去：",
                        reason: failure.reason,
                        tail: "处理后点这条消息旁的感叹号重新发送。"
                    )
                )
                Haptics.error()
                return .prepareFailed
            } catch is CancellationError {
                if showsUploadUI { isUploadingFiles = false }
                return .stopped
            } catch {
                if showsUploadUI { isUploadingFiles = false }
                // 未知上传异常的文案也走分类（P5-1）：
                // 旧口径一句「文件上传失败…请稍后再
                // 试」包打天下，网络/服务端/解码不分。
                // 成因落账恒 .prepareFailed（语义 3：
                // 准备段失败钉死），分类只供呈现取词
                let presentKind = (error as? HermesError).map {
                    SendFailureKind.classify(submit: $0)
                } ?? .prepareFailed
                if presentKind == .offlineNotSent {
                    if !job.filePayloads.isEmpty {
                        failedFilePayloads[userEntry.id] = job.filePayloads
                        stagedSendStore.stageDetached(
                            entryID: userEntry.id,
                            payloads: job.filePayloads.map {
                                StagedSendPayload(name: $0.name, data: $0.data)
                            }
                        )
                    }
                    userEntry.markPendingSend(in: modelContext)
                    return .offlineParked
                }
                markTurnFailed(
                    entry: userEntry,
                    filePayloads: job.filePayloads,
                    failureKind: presentKind == .prepareFailed ? .prepareFailed : presentKind
                )
                presentSendFailure(kind: presentKind)
                Haptics.error()
                return .prepareFailed
            }
            if showsUploadUI {
                isUploadingFiles = false
                // 修法 C：清除进度改按条目 ID 索引
                uploadProgressFraction.removeValue(forKey: userEntry.id)
            }
            if Task.isCancelled { return .stopped }
            failedFilePayloads[userEntry.id] = nil
            try? stagedSendStore.remove(entryID: userEntry.id)
            userEntry.markSendState(.linking, in: modelContext)
            if !fileServerPaths.isEmpty {
                userEntry.remoteFilePathsData =
                    try? JSONEncoder().encode(fileServerPaths)
                try? modelContext.save()
                for (path, payload) in zip(
                    fileServerPaths, job.filePayloads
                ) {
                    FileMetadataStore.shared.record(
                        path: path,
                        size: Int64(payload.data.count),
                        modifiedAt: nil
                    )
                }
            }
        }
        let shape: (messages: [ChatMessage], sessionID: String?)
        do {
            shape = try await prepareSendShapeWithRetry(
                thread: thread, fullContext: job.context,
                seedEntries: job.seedSnapshot
            )
        } catch is CancellationError {
            return .stopped
        } catch {
            if Task.isCancelled { return .stopped }
            if let hermesError = error as? HermesError {
                let kind = SendFailureKind.classify(submit: hermesError)
                if kind == .offlineNotSent {
                    userEntry.markPendingSend(in: modelContext)
                    return .offlineParked
                }
                markTurnFailed(
                    entry: userEntry, failureKind: kind
                )
                presentSendFailure(
                    kind: kind,
                    detail: hermesError.diagnosticDetail
                )
                Haptics.error()
                return .prepareFailed
            }
            markTurnFailed(
                entry: userEntry, failureKind: .prepareFailed
            )
            // 拼接走收尾归一（P2-1）：userMessage 自
            // 带「。」时旧拼出「请稍后再试。。链接恢
            // 复后…」双句号叠字
            presentSendFailure(
                kind: .prepareFailed,
                message: SendFailureCopy.joiningReason(
                    head: "会话链接失败，这条还没发出去：",
                    reason: "服务端会话建立失败",
                    tail: "链接恢复后，点这条消息旁的感叹号重新发送。"
                )
            )
            Haptics.error()
            return .prepareFailed
        }
        if Task.isCancelled { return .stopped }
        // §135 D 案打点：落盘→链接一段（起点归工单
        // 自带——泵内后条不许借前条的起点串账）
        if let started = job.frameStartedAt {
            ChatDiagTrace.record(
                "发送打点 落盘→链接 "
                    + "\(Int(Date().timeIntervalSince(started) * 1000))ms"
            )
        }
        sendPinToken += 1
        let tail = FileSendAssembly.appendingFileRefs(
            to: shape.messages.last
                ?? ChatMessage(role: "user", content: job.text),
            serverPaths: fileServerPaths
        )
        userEntry.markSendState(.sending, in: modelContext)
        return await performSubmit(
            thread: thread, tail: tail,
            sessionID: shape.sessionID, userEntry: userEntry
        )
    }

    /// §451 POST 提交段：账本先落（runID 后补）、得
    /// 202 即受理——照 driveRun 提交段同口径：瞬态
    /// 有界重试（同 key 重演回原 run）、结果未知归
    /// 对账（账本留席交消费环）、明确拒绝定失败、
    /// 离线折回待发巷。154 幂等键与 driveRun 同铸
    /// 法（ensureIdempotencyKey：条目既有键恒沿用、
    /// 缺时铸造落盘），同条重投恒同 key、不双跑
    func performSubmit(
        thread: ChatThread, tail: ChatMessage,
        sessionID: String?, userEntry: ChatEntry
    ) async -> SubmissionOutcome {
        guard let config = appState.config,
              let apiKey = appState.apiKey, !apiKey.isEmpty
        else {
            markTurnFailed(
                entry: userEntry, failureKind: .authRejected
            )
            presentSendFailure(kind: .authRejected)
            return .rejected
        }
        let input: RunInput = tail.parts == nil
            ? .text(tail.content) : .message(tail)
        let choice = appState.sessionModelChoice(
            serverSessionID: sessionID, threadID: thread.id
        )
        let idempotencyKey = ensureIdempotencyKey(
            for: userEntry
        )
        appState.runLedger.upsert(RunLedgerEntry(
            threadID: thread.id.uuidString,
            sessionID: sessionID ?? "",
            runID: nil,
            idempotencyKey: idempotencyKey,
            userEntryID: userEntry.id.uuidString,
            submittedAt: Date()
        ))
        var attempt = 0
        var unknownAttempts = 0
        var gateWaits = 0
        while true {
            attempt += 1
            do {
                let response = try await appState.client
                    .submitRun(
                        config: config, apiKey: apiKey,
                        sessionID: sessionID ?? "",
                        input: input, model: choice.model,
                        provider: choice.providerField,
                        idempotencyKey: idempotencyKey
                    )
                appState.runLedger.upsert(RunLedgerEntry(
                    threadID: thread.id.uuidString,
                    sessionID: sessionID ?? "",
                    runID: response.runID,
                    idempotencyKey: idempotencyKey,
                    userEntryID: userEntry.id.uuidString,
                    submittedAt: Date()
                ))
                markAcceptedEntryAccepted(
                    thread: thread,
                    userEntryID: userEntry.id.uuidString
                )
                clearPendingDeliveryMark(entry: userEntry)
                return .accepted
            } catch let submitError {
                if Task.isCancelled {
                    markLedgerStopRequested(
                        userEntryID: userEntry.id
                    )
                    return .stopped
                }
                // 限流等待门（语义 3）：服务端明示等
                // 多久就等多久——不落失败、不计账；门
                // 内等满两轮仍被限，折回待发停泊＋排
                // 唤醒钟，到点自动续（仍不是失败）
                if let hermesError = submitError as? HermesError,
                   case .rateLimited(let retryAfter) = hermesError {
                    if gateWaits < 2 {
                        gateWaits += 1
                        try? await Task.sleep(
                            for: .seconds(min(retryAfter ?? 1, 30))
                        )
                        if Task.isCancelled {
                            markLedgerStopRequested(
                                userEntryID: userEntry.id
                            )
                            return .stopped
                        }
                        continue
                    }
                    appState.runLedger.remove(
                        userEntryID: userEntry.id
                    )
                    userEntry.markPendingSend(
                        in: modelContext
                    )
                    scheduleOutboxWake(
                        at: Date().addingTimeInterval(
                            min(retryAfter ?? 1, 300)
                        ),
                        threadID: thread.id
                    )
                    return .rateLimitedParked
                }
                switch RunSubmitRetry.classify(submitError) {
                case .notSentOffline:
                    appState.runLedger.remove(
                        userEntryID: userEntry.id
                    )
                    userEntry.markPendingSend(
                        in: modelContext
                    )
                    return .offlineParked
                case .transient:
                    if attempt
                        <= RunSubmitRetry.maxTransientRetries {
                        // 间隔走 RetryBackoff 同源退避＋
                        // 全抖动（P1-1）：旧固定 1.2s 无抖
                        // 动，多条同拍重撞
                        try? await Task.sleep(
                            for: .seconds(RetryBackoff.delay(
                                afterFailure: attempt,
                                jitterUnit: Double.random(
                                    in: 0...1
                                )
                            ))
                        )
                        if Task.isCancelled {
                            markLedgerStopRequested(
                                userEntryID: userEntry.id
                            )
                            return .stopped
                        }
                        continue
                    }
                    // 瞬态耗尽：结果未知——账本留席、待
                    // 发标记清，消费环对账同 key 重演取
                    // 回（不定性为错误、不双跑）
                    clearPendingDeliveryMark(entry: userEntry)
                    return .accepted
                case .unknown:
                    // 判不出成因（P1-1）：只许再试 1
                    // 次，耗尽同走结果未知交对账——旧
                    // 口径非 HermesError 一律判瞬态全额
                    // 重试，把未知错误当网络抖动
                    unknownAttempts += 1
                    if unknownAttempts
                        <= RunSubmitRetry.maxUnknownRetries {
                        try? await Task.sleep(
                            for: .seconds(RetryBackoff.delay(
                                afterFailure: unknownAttempts,
                                jitterUnit: Double.random(
                                    in: 0...1
                                )
                            ))
                        )
                        if Task.isCancelled {
                            markLedgerStopRequested(
                                userEntryID: userEntry.id
                            )
                            return .stopped
                        }
                        continue
                    }
                    clearPendingDeliveryMark(entry: userEntry)
                    return .accepted
                case .rejected:
                    appState.runLedger.remove(
                        userEntryID: userEntry.id
                    )
                    let hermesError =
                        (submitError as? HermesError)
                        ?? .unreachable(
                            submitError.localizedDescription
                        )
                    if hermesError.isSessionNotFound {
                        // 会话已在服务端消失（§223）：按
                        // 凭据面收口呈现，成因记 auth
                        markTurnFailed(
                            entry: userEntry,
                            failureKind: .authRejected
                        )
                        presentSendFailure(kind: .authRejected)
                    } else {
                        // 成因落账＋分类呈现（语义 3/5）：
                        // 旧口径落 .failed 时成因只剩一句
                        // 兜底文案，政策无从分档
                        let kind = SendFailureKind.classify(
                            submit: hermesError
                        )
                        markTurnFailed(
                            entry: userEntry, failureKind: kind
                        )
                        presentSendFailure(
                            kind: kind,
                            detail: hermesError.diagnosticDetail
                        )
                    }
                    return .rejected
                }
            }
        }
    }

    /// 154 幂等键铸法（与 driveRun 同口径单源）：条
    /// 目 clientMessageID 在席恒沿用，缺时铸造并落
    /// 盘——首投/自动重试/手点重发/中段原位重发跨
    /// 链恒同 key
    func ensureIdempotencyKey(
        for userEntry: ChatEntry
    ) -> String {
        if let existing = userEntry.clientMessageID {
            return existing
        }
        let minted = UUID().uuidString
        userEntry.clientMessageID = minted
        try? modelContext.save()
        return minted
    }

    /// 受理同点清待发标记（driveRun 旧口径：非失败
    /// 出口 deliveryState 清零，条目出待发巷）
    func clearPendingDeliveryMark(
        entry: ChatEntry
    ) {
        if entry.deliveryState != nil {
            entry.deliveryState = nil
            try? modelContext.save()
        }
    }

    /// 提交窗内停止：账本本条记停止意图，消费环接
    /// 管后对账先行真停止（driveRun 旧口径同）
    func markLedgerStopRequested(
        userEntryID: UUID
    ) {
        guard var ledgerEntry = appState.runLedger.entry(
            forUserEntryID: userEntryID
        ) else { return }
        ledgerEntry.stopRequested = true
        appState.runLedger.upsert(ledgerEntry)
    }

    /// 消费环踢动口：单例防重入
    func kickConsumer() {
        guard !appState.isDemo, consumeTask == nil
        else { return }
        consumeTask = Task {
            await runConsumerLoop()
            consumeTask = nil
        }
    }

    /// §451 消费环（App-3）：当前线程已受理未落定
    /// 轮次按提交序逐轮驱动——一轮落定才接下一轮
    /// （streamAssembler/轮次状态机单轮假设不动）。
    /// 驱动后本条仍在账（对账预算耗尽未落定）即停
    /// 环：留待回前台/进线程的 resumeRunIfNeeded
    /// 续，不许空转重试
    func runConsumerLoop() async {
        while !Task.isCancelled {
            guard scenePhase == .active,
                  let thread = currentThread,
                  let head = appState.runLedger.entries(
                      forThreadID: thread.id
                  ).first
            else { return }
            await driveAcceptedTurn(
                thread: thread, entry: head
            )
            if let uid = UUID(uuidString: head.userEntryID),
               appState.runLedger.entry(
                   forUserEntryID: uid
               ) != nil {
                return
            }
        }
    }

    /// §451 单轮驱动：已受理一轮的呈现重置＋半截回
    /// 填＋对账落定——本体即原 resumeRunIfNeeded 的
    /// 驱动段（参数化出账本条目），恢复与消费环共
    /// 用一份，不许两处分叉
    func driveAcceptedTurn(
        thread: ChatThread, entry: RunLedgerEntry
    ) async {
        runMachine = RunTurnStateMachine()
        if entry.runID != nil {
            runMachine.apply(.submitAccepted)
            // §426（缺陷一）：runID 在上一进程生命
            // 周期已确立＝服务器早已确认收到——恢
            // 复同点补记送达，不许条目在本进程里继
            // 续挂未确认态
            markAcceptedEntryAccepted(
                thread: thread,
                userEntryID: entry.userEntryID
            )
            runMachine.apply(.streamLost)
        } else {
            runMachine.apply(.submitAmbiguous)
        }
        if entry.stopRequested {
            runMachine.apply(.stopRequested)
        }
        activeRunThreadID = thread.id
        lastEventSeq = -1
        terminalOutputHint = nil
        terminalStatusHint = nil
        streamAssembler.reset()
        reasoningPublishGate.reset()
        resetStreamPresentation()
        reasoningStartedAt = nil
        // 半截呈现回填：上次落盘的本轮条目即当前可见
        // 内容（落定时以 transcript 整段替换）
        liveToolCards = []
        liveOrder = []
        livePartialEntryIDs = []
        if let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) {
            // §123（H1）：回响条目（echoKey 非空）不是
            // 本轮半截——不进半截名单、正文回填也不许
            // 把它当作助手半截正文吞进流式区
            // §165：审批锚定条目同族同守（谓词统一）
            // §414：候选面收口到 turnPartialCandidates
            // ——补待发豁免（账本滞留期落位的待发条目
            // 不许被当作本轮半截吞掉/删掉）与下一轮界
            // （中段重发轮之后已落定轮次不进半截名单）
            let partials = Self.turnPartialCandidates(
                in: thread, userEntry: userEntry
            )
            livePartialEntryIDs = partials.map(\.id)
            liveToolCards = partials
                .filter { $0.role == "tool" }
                .compactMap(\.toolCard)
            // 第 93 条：半截按段回填——落盘条目按时
            // 序走查，工具卡与助理段各自归位重建事件
            // 序；时序最末一条若是助理段，它就是断线
            // 时打开着的段（重挂后的增量只许拼进它），
            // 其余助理段一律封存只读。旧形态只取最末
            // 一段正文吞回单一缓冲：多段半截的前段就
            // 此从呈现消失、且与打开段混存。旧版落盘
            // 的单条合并半截（一段到底）在此即整条作
            // 打开段，行为与旧形态一致
            let ordered = partials.sorted {
                $0.createdAt < $1.createdAt
            }
            let openEntryID = ordered.last?.id
            var sealedTexts: [String] = []
            var openText = ""
            var rebuiltOrder: [LiveOrderItem] = []
            for partial in ordered {
                if partial.role == "tool",
                   let card = partial.toolCard {
                    rebuiltOrder.append(.tool(card.id))
                } else if partial.role == "assistant",
                          !partial.content.isEmpty {
                    if partial.id == openEntryID {
                        openText = partial.content
                        rebuiltOrder.append(.text)
                    } else {
                        rebuiltOrder.append(
                            .sealedText(sealedTexts.count)
                        )
                        sealedTexts.append(partial.content)
                    }
                }
            }
            if !rebuiltOrder.contains(.text) {
                rebuiltOrder.append(.text)
            }
            streamAssembler.restore(
                sealed: sealedTexts, current: openText
            )
            liveOrder = rebuiltOrder
            streamingText = ""
        } else {
            streamingText = ""
            // 0.36.10：无半截可回填时事件序仍立正文位
            // （卡列恒空、只剩 .text 一记）
            liveOrder = [.text]
        }
        // §385（总表 163）：续接在跑的一轮同起实时
        // 活动，落定即收（与 driveRun 同口径）
        await RunLiveActivityCenter.shared.begin(
            taskName: thread.title
        )
        isDrivingRun = true
        var mutableEntry = entry
        await reconcileRun(
            thread: thread, entry: &mutableEntry,
            demoMode: false
        )
        isDrivingRun = false
        await RunLiveActivityCenter.shared.end()
        // 发送失败机制包（语义 4）：对账收尾的全
        // 量 drain 删除（触发源收敛），只留定向踢
        // 泵一脚——泵已退出时排进来的条目要等本轮
        // 落定才成车道头条，没有这一脚只能等无关
        // 的外部事件。这一脚不可能自激成环：落定
        // 失败的头条在新记账口径下被车道堵住等手
        // 点（准入看成因＋退避带钟），踢泵只让车道
        // 重新判定一次、不会把失败条重投出去（死
        // 循环的必要条件是清账重置、已在语义 1/2
        // 切断；钉测 ChatFailKeepPinTests 钉此面）
        kickSubmitPump(thread: thread)
    }

    /// §451（App-4）落定锚解析：条目已钉 server-
    /// RowID 直用；未钉（本进程新发条目落定前恒未
    /// 钉）走 Core 配对图按本地序位查（与落定补缺
    /// 同一配对、判同口径单源）。解析不到回 nil，
    /// 由 settleRunFromTranscript 按在账轮数裁决
    /// （多轮并存时不许走无锚口径）
    func transcriptAnchorRowID(
        thread: ChatThread, entry: RunLedgerEntry,
        messages: [SessionMessage]
    ) -> Int? {
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return nil }
        if let pinned = userEntry.serverRowID {
            return pinned
        }
        let localUsers = thread.entries.filter {
            $0.role == "user"
        }
        guard let position = localUsers.firstIndex(
            where: { $0.id == userEntry.id }
        ) else { return nil }
        let pairs = RunTranscriptSettle.pairedRowIDs(
            messages: messages,
            localUserEntries: localUsers.map {
                (content: $0.content,
                 createdAt: $0.createdAt,
                 filePaths: $0.remoteFilePaths,
                 imagePaths: $0.remoteImagePaths)
            }
        )
        return pairs[position]
    }

    /// §451（App-6）：已受理未执行谓词——账本在
    /// 席、有 runID、且不是本线程最早未落定条（队
    /// 首可能已在服务端执行中、撤它走停止语义；非
    /// 队首必在服务端 FIFO 里排队未开轮）。消费环
    /// 恒驱动队首，谓词与驱动天然互斥
    func acceptedWithdrawAvailable(
        for entry: ChatEntry
    ) -> Bool {
        guard entry.role == "user",
              let thread = entry.thread,
              let ledgerEntry = appState.runLedger.entry(
                  forUserEntryID: entry.id
              ),
              ledgerEntry.runID != nil,
              let head = appState.runLedger.entries(
                  forThreadID: thread.id
              ).first,
              head.userEntryID != entry.id.uuidString
        else { return false }
        return true
    }

    /// §451（App-6）撤回已受理未执行条目：服务端
    /// stop（排队中的 admission 走 cancel_queued、
    /// 不会开轮）→ 摘本轮账本 → 删本地条目＋清暂
    /// 存/重试记账（与 withdrawUnsentEntry 同尾）。
    /// 极小竞态下若已开轮，stop 即中断该轮、其服
    /// 务端行按既有补缺口径回补呈现，本动作的保证
    /// 是「不再继续执行」
    func withdrawAcceptedEntry(_ entry: ChatEntry) {
        guard acceptedWithdrawAvailable(for: entry),
              let thread = entry.thread,
              let ledgerEntry = appState.runLedger.entry(
                  forUserEntryID: entry.id
              ),
              let runID = ledgerEntry.runID,
              let config = appState.config,
              let apiKey = appState.apiKey
        else { return }
        let entryID = entry.id
        Task {
            try? await appState.client.stopRun(
                config: config, apiKey: apiKey, runID: runID
            )
        }
        appState.runLedger.remove(userEntryID: entryID)
        if unsentEditTargetID == entryID {
            unsentEditTargetID = nil
            unsentEditFilesRepresented = false
        }
        failedFilePayloads[entryID] = nil
        pendingResendAttachments[entryID] = nil
        try? stagedSendStore.remove(entryID: entryID)
        appState.outboxRetry.clear(entryID: entryID)
        modelContext.delete(entry)
        try? modelContext.save()
        kickSubmitPump(thread: thread)
        kickConsumer()
    }

    /// 发件箱触发口（台账 154／G-04）：回前台/网络
    /// 恢复/切线程/进页四处同调本口。§451 起 drain
    /// 退役投递职责（旧 drainOutboxLoop 的串行派发
    /// 整条删除）——本口只剩记账卫生＋踢提交泵/消
    /// 费环：投递归泵（落盘即提交、严格保序）、已
    /// 受理轮次的驱动归消费环；连接配置缺失时不踢
    /// （没连上时尝试只会白烧重试次数）
    func drainOutboxIfNeeded() {
        guard !appState.isDemo,
              appState.config != nil, appState.apiKey != nil,
              let thread = currentThread
        else { return }
        outboxHousekeeping(in: thread)
        kickSubmitPump(thread: thread)
        kickConsumer()
    }

    /// 记账卫生（原 drain 趟首两件）：只清条目已不
    /// 存在的残账。
    /// 发送失败机制包（语义 1）：旧第二件「已落定
    /// 条目的旧重试账同清」（clearDeliveredOutbox-
    /// Records）整体退役——它按 !isOutboxEntry 在
    /// 受理后立刻把在飞条目的账扫掉，是 B1 清账错
    /// 位与死循环的一环；清账点全集只剩三处：落
    /// 定成功（applySettledTurn 按条）、用户撤
    /// 回、编辑重投
    func outboxHousekeeping(in thread: ChatThread) {
        let validIDs = Set(
            threads.flatMap {
                $0.entries.map { $0.id.uuidString }
            }
        )
        appState.outboxRetry.prune(validEntryIDs: validIDs)
    }

    /// 提交段孤儿浮现（DESIGN §336）：状态 sending
    /// 但 run 账本无此轮的条目——落账与提交之间极
    /// 小窗口内进程身亡所致，服务端是否受理不可
    /// 知。处置只两步：折回待发巷让它可见（未发送
    /// 行）、打人工接管标记让自动链永不重发它，
    /// 是否重发由用户看内容裁决。有账本在飞或正
    /// 在驱动的 sending 不在此列（对账链管辖）
    func surfaceSendingOrphans(in thread: ChatThread) {
        for entry in thread.sortedEntries
        where entry.sendState == .sending
            && !entry.sendFailed && !entry.isPendingSend {
            // §451：逐条核账——本条有账本＝对账链管
            // 辖（多轮并存后「整线程账本为空＋无流在
            // 跑」的旧守卫作废：别的轮次在飞不该把本
            // 条的孤儿身份藏起来）；泵正在提交本条
            // （.sending 已写、账本未落的瞬时窗）同
            // 跳过
            if appState.runLedger.entry(
                forUserEntryID: entry.id
            ) != nil { continue }
            if pumpInFlightEntryIDs.contains(entry.id) {
                continue
            }
            entry.markPendingSend(in: modelContext)
            appState.outboxRetry.markManualOnly(
                entryID: entry.id
            )
        }
    }

    /// 待发文件逐个上传（0.36.29，件四）：顺序即待
    /// 发顺序（@file 拼装顺序从它）；逐个经 9119
    /// 文件通道写 attachments/<文件名>（overwrite
    /// 覆盖同名）、取回执绝对路径；任一失败或回执
    /// 无落点即抛 FileUploadFailure 点名该文件——
    /// 整条拦下在 send 侧，不在此处吞单个文件。
    /// 服务端 attachments/ 副本无自动过期，本轮只
    /// 记账不做清理策略（契约报告边界口径）
    /// 修法 C：增加 entryID 参数，进度按条目索引
    func uploadPendingFiles(
        _ entryID: UUID,
        _ payloads: [(name: String, data: Data)]
    ) async throws -> [String] {
        // §237 P7：进度聚合按原始字节计（data_url 在
        // 客户端内的比例与原始字节同比例放大、比值
        // 不变）；tracker 线程安全，URLSession 回调
        // 队列直接写、呈现读聚合值。401 重登整传重试
        // 时单文件比例会从 0 重报，聚合峰值口径保证
        // 界面百分比不倒退
        let tracker = UploadProgressTracker(
            fileSizes: payloads.map(\.data.count)
        )
        var paths: [String] = []
        for payload in payloads {
            tracker.beginFile(size: payload.data.count)
            let receipt: ManagedFileUploadReceipt
            do {
                receipt = try await appState.performAdmin {
                    client, cfg in
                    // §410：只递原始字节——data_url 与请
                    // 求体组包在客户端内后台完成（流式写
                    // 临时文件），主 actor 不再同步付
                    // base64＋JSON 体的成形成本与内存峰值
                    try await client.uploadAttachment(
                        config: cfg,
                        path: FileSendAssembly.uploadPath(
                            fileName: payload.name
                        ),
                        fileName: payload.name,
                        data: payload.data,
                        onProgress: { fileFraction in
                            let aggregate = tracker
                                .updateCurrentFile(
                                    fraction: fileFraction
                                )
                            Task { @MainActor in
                                // 修法 C：进度写入改按条目 ID 索引
                                uploadProgressFraction[entryID] = aggregate
                            }
                        }
                    )
                }
            } catch let error as HermesError {
                throw FileUploadFailure(
                    fileName: payload.name,
                    reason: error.userMessage
                )
            }
            tracker.finishCurrentFile()
            // 修法 C：进度写入改按条目 ID 索引
            uploadProgressFraction[entryID] = tracker.fractionCompleted
            guard let serverPath = receipt.serverPath else {
                throw FileUploadFailure(
                    fileName: payload.name,
                    reason: "服务端没有返回文件落点。"
                )
            }
            ChatFileStore.shared.seedLocal(path: serverPath, data: payload.data)
            paths.append(serverPath)
        }
        return paths
    }

    /// 本轮出门形态（0.27.0 重写，状态机见 OneDayCore
    /// .SideChatLink）：全线程同口径两路——
    /// ①已链接（绑定非桶＋种子已落；主线的绑定/种
    ///   子位读 SideChatStore 双位）：会话模式——载
    ///   荷只取尾条＋会话头；旁聊锁模型与胶囊不一致
    ///   （且锁为我方所设）时先推一次会话内切换（尽
    ///   力而为：失败不挡发送、下轮再试——该端点的
    ///   公网送达缺口登记于 §54，属已知残留）；
    /// ②未链接：先走 performLink（建会话或 import
    ///   种子，seedEntries 为本轮条目落盘前的快照）
    ///   ——成功落绑定/种子位/锁模型、失败计数清零，
    ///   本轮随即以会话模式发出；**失败抛错整轮不
    ///   发**（0.21.0 的「失败回退无状态重放」整类
    ///   删除：无头发送在服务端按开头合并落库、是
    ///   串话入口，诊断档判死）；失败计数＋1、原因
    ///   留痕（旁聊落线程、主线落 SideChatStore）由
    ///   本函数记账，呈现与条目回滚在 send() 的
    ///   catch。用户在链接窗口内主动停止抛
    ///   CancellationError、不留痕（send 按停止语义
    ///   静默收尾）。
    /// 发送链接步退避重试（0.36.20，§86.3，治审计
    /// R2）：prepareSendShape 此前单发无重试——点发送
    /// 撞上瞬断即整轮不发＋弹横幅，是全发送链重试覆盖
    /// 最薄一环。本包装只对瞬断类失败（HermesError.
    /// isTransient，既有失败分型）做有界退避重试：总
    /// 尝试与提交步同量级（Core RetryBackoff.max-
    /// Attempts＝首发＋2 次）、全抖动退避同源；鉴权/
    /// 业务失败不重试、原样上抛走既有失败分支。重试
    /// 期间不产任何新文案（§86.5 呈现一档：静默期），
    /// 耗尽后才由调用方既有分支出失败横幅——本条消息
    /// 从未进入提交步，「未发送」口径属实。重试语义与
    /// 用户手动重按发送完全一致（主线是 ensure 幂等；
    /// 旁聊每次尝试内现铸定 id，极端时序下可能在服务
    /// 端多留一个空会话——无消息落入、与手按重发同
    /// 性质，不为此另造跨尝试 id 托管）
    func prepareSendShapeWithRetry(
        thread: ChatThread, fullContext: [ChatMessage],
        seedEntries: [SeedEntry]
    ) async throws -> (messages: [ChatMessage], sessionID: String?) {
        var attempts = 0
        while true {
            attempts += 1
            do {
                return try await prepareSendShape(
                    thread: thread, fullContext: fullContext,
                    seedEntries: seedEntries
                )
            } catch let error as HermesError {
                if Task.isCancelled {
                    throw CancellationError()
                }
                guard error.isTransient,
                      RetryBackoff.shouldRetry(afterAttempts: attempts)
                else { throw error }
                let wait = RetryBackoff.delay(
                    afterFailure: attempts,
                    jitterUnit: Double.random(in: 0...1)
                )
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                if Task.isCancelled {
                    throw CancellationError()
                }
            }
        }
    }

    func prepareSendShape(
        thread: ChatThread, fullContext: [ChatMessage],
        seedEntries: [SeedEntry]
    ) async throws -> (messages: [ChatMessage], sessionID: String?) {
        let store = appState.sessionLedger
        let isMain = thread.id == store.mainThreadID
        // §331 改判：计划只看绑定 id（主线代入钦定
        // id）——种子位退出判据：自有会话种子未落也
        // 直发、种子转后台义务（欠账在本分支顺带排
        // 调度，不拦本轮）；id 未知才走建立路
        let plan = isMain
            ? SideChatLink.sendPlan(
                serverSessionID: store.mainServerSessionID
            )
            : SideChatLink.sendPlan(
                serverSessionID: thread.serverSessionID
            )
        switch plan {
        case .session(let sessionID):
            if isMain {
                scheduleMainBackgroundSync()
            }
            if !isMain, SideChatLink.needsModelRelock(
                linkedModel: thread.linkedModel,
                capsuleModel: appState.chatModel(
                    serverSessionID: thread.serverSessionID,
                    threadID: thread.id
                )
            ) {
                let capsule = appState.chatModel(
                    serverSessionID: thread.serverSessionID,
                    threadID: thread.id
                )
                var pushed = false
                do {
                    try await appState
                        .performAdmin { client, config in
                            try await client
                                .updateServerSessionModel(
                                    config: config, id: sessionID,
                                    model: capsule
                                )
                        }
                    pushed = true
                } catch {
                    pushed = false
                }
                if pushed {
                    thread.linkedModel = capsule
                    try? modelContext.save()
                }
            }
            if !isMain {
                // §331：种子/回补欠账顺带排后台（防重
                // 入在调度器；本轮发送不等待、不受其
                // 成败影响）；旧账先派生再判欠账
                deriveLegacySeedObligation(thread)
                if thread.seedSyncState.needsSyncAttempt {
                    scheduleSeedSync(
                        thread: thread, seedSnapshot: seedEntries
                    )
                }
                if thread.historyUnsynced {
                    scheduleHistoryBackfillIfNeeded(thread: thread)
                }
            }
            return (
                SideChatLink.payload(
                    plan: plan, fullContext: fullContext
                ),
                sessionID
            )
        case .linkAndSeed:
            do {
                let linkedID: String
                if isMain {
                    guard await ensureMainLink(
                        seedSnapshot: seedEntries
                    ) else {
                        throw HermesError.unreachable(
                            store.mainLinkLastError
                                ?? "主线会话链接失败"
                        )
                    }
                    linkedID = store.ensureMainServerSessionID()
                } else {
                    // 目标 id：已存自有 id 沿用，其余（无
                    // 绑定/绑合并桶/绑他方会话待解绑）一
                    // 律新铸——合并桶绑定在此被自有 id
                    // 覆盖、桶本体零动作
                    let desiredID = thread.serverSessionID
                        .flatMap {
                            SideChatLink.isOwnSessionID($0)
                                ? $0 : nil
                        } ?? SideChatLink.newSessionID()
                    let linkModel = appState.chatModel(
                        serverSessionID: desiredID,
                        threadID: thread.id
                    )
                    do {
                        let outcome = try await performLink(
                            desiredID: desiredID, title: nil,
                            model: linkModel,
                            seedEntries: seedEntries
                        )
                        linkedID = outcome.sessionID
                        applySeedOutcome(
                            outcome, to: thread, seed: seedEntries
                        )
                    } catch let linkError {
                        // §331 探针恢复：链接多半死在种
                        // 子导入一步——回读确认锚点在
                        // （或空建保住存在性）即按已链
                        // 发送，种子转待导入由后台补；
                        // 探针也失败才按原错误整轮不发
                        guard let recoveredID =
                            await recoverLinkByProbe(
                                desiredID: desiredID, title: nil,
                                model: linkModel
                            )
                        else { throw linkError }
                        linkedID = recoveredID
                        thread.seedSyncState = SideChatLink
                            .seedTranscript(from: seedEntries).isEmpty
                            ? .notOwed : .pending
                    }
                    thread.serverSessionID = linkedID
                    thread.linkedModel = appState.chatModel(
                        serverSessionID: linkedID, threadID: thread.id
                    )
                    thread.linkFailureCount = 0
                    thread.linkLastError = nil
                    try? modelContext.save()
                    if thread.seedSyncState.needsSyncAttempt {
                        scheduleSeedSync(
                            thread: thread, seedSnapshot: seedEntries
                        )
                    }
                }
                return (
                    SideChatLink.payload(
                        plan: .session(sessionID: linkedID),
                        fullContext: fullContext
                    ),
                    linkedID
                )
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                if !isMain {
                    thread.linkFailureCount = SideChatLink
                        .failureCount(
                            afterFailure: thread.linkFailureCount
                        )
                    thread.linkLastError =
                        (error as? HermesError)?.userMessage
                        ?? "建会话失败"
                    try? modelContext.save()
                }
                throw error
            }
        }
    }

    /// 演示模式：种子对话的最后一句用户消息由假客户端
    /// 的 run 通道回完（0.31.0：演示也走 run 驱动——假
    /// 客户端 submitRun/runEvents 产定稿回复，落定走
    /// 状态 output 合成路径，不碰账本与 transcript）。
    /// 正常模式直接返回，零影响。
    func startDemoStreamIfNeeded() async {
        guard DemoMode.current.isDemo, !demoStreamStarted else {
            return
        }
        // 演示流稳健性（DESIGN-V4 §11.6 历史）：等待改有界
        // 长预算（线程与连接态齐备才开流，上限 20s），演示
        // 专用路径，正常模式第一行已返回
        for _ in 0..<80 where currentThread == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let thread = currentThread else {
            return
        }
        demoStreamStarted = true
        // 等种子渲染落稳再开流，截图窗口对齐流式中段
        try? await Task.sleep(for: .seconds(1))
        guard let userEntry = thread.sortedEntries
            .last(where: { $0.role == "user" }) else { return }
        streamingText = ""
        await driveRun(
            thread: thread,
            tail: ChatMessage(role: "user", content: userEntry.content),
            sessionID: nil, userEntry: userEntry, demoMode: true
        )
    }

    // MARK: - Run 驱动（0.31.0，任务制生成）

    /// 一轮 run 的全程驱动：提交（Idempotency-Key 同
    /// key 重演兜底）→ events 订阅呈现 → 断线转对账
    /// （状态轮询＋events 重挂＋transcript 落定）。旧
    /// runStream（chat completions 单连接流）与 0.20.0
    /// 的对账恢复（删半截以原上下文自动重发）整类退
    /// 役：生成与连接分家后，断线只是「结果未知」，
    /// 永不映射网络错误、永不自动重发（§58 铁律）。
    func driveRun(
        thread: ChatThread, tail: ChatMessage,
        sessionID: String?, userEntry: ChatEntry,
        demoMode: Bool = false
    ) async {
        guard let config = appState.config,
              let apiKey = appState.apiKey else {
            streamingText = nil
            resetStreamPresentation()
            reasoningStartedAt = nil
            presentSendFailure(kind: .authRejected)
            // 基础止血包（P1）：连接态缺失同样是本轮
            // 失败——条目留痕挂标记，恢复连接后点标
            // 记重发（演示态不挂，种子条目不是用户真
            // 发送）
            if !demoMode {
                markTurnFailed(
                    entry: userEntry, failureKind: .authRejected
                )
            }
            // 失败改判 error（0.36.2，表 D 语义归位）
            Haptics.error()
            sendTask = nil
            return
        }
        isDrivingRun = true
        // §385（总表 163）：实时活动随一轮起落——起
        // 跑沿启动、退出沿（defer 覆盖失败/取消一切
        // 出口）收
        await RunLiveActivityCenter.shared.begin(
            taskName: thread.title
        )
        defer {
            isDrivingRun = false
            Task { await RunLiveActivityCenter.shared.end() }
        }
        runMachine = RunTurnStateMachine()
        activeRunThreadID = thread.id
        lastEventSeq = -1
        livePartialEntryIDs = []
        terminalOutputHint = nil
        terminalStatusHint = nil
        streamAssembler.reset()
        reasoningPublishGate.reset()
        resetStreamPresentation()
        // §494：直播行只在新发轮武装（恢复轮走
        // resumeActiveRun、不经此点）
        streamPresentationArmed = true
        reasoningStartedAt = nil
        // 输入组装：尾条纯文本走字符串形态、多模态走
        // 单元素消息形态（探针实测两形态均成立）
        let input: RunInput = tail.parts == nil
            ? .text(tail.content) : .message(tail)
        let choice = appState.sessionModelChoice(
            serverSessionID: sessionID, threadID: thread.id
        )
        let provider = choice.providerField
        // 台账 154（DESIGN §383）：消息级幂等身份——
        // 账本幂等键自此取条目的 clientMessageID：首
        // 轮铸造并落盘，之后发件箱自动重试/手点重发/
        // 中段原位重发（§414）跨 driveRun 复用同一
        // id，服务
        // 端按此 id 回原 run（hermes-deploy 1.5.0 的
        // client_message_id 语义，头＋body 同值双带）；
        // 单轮内账本重演口径不变。demo 无服务端、键
        // 只在内存账本里用，仍现铸不落盘。
        let idempotencyKey: String
        if demoMode {
            idempotencyKey = UUID().uuidString
        } else if let existing = userEntry.clientMessageID {
            idempotencyKey = existing
        } else {
            idempotencyKey = UUID().uuidString
            userEntry.clientMessageID = idempotencyKey
            try? modelContext.save()
        }
        var ledgerEntry = RunLedgerEntry(
            threadID: thread.id.uuidString,
            sessionID: sessionID ?? "",
            runID: nil,
            idempotencyKey: idempotencyKey,
            userEntryID: userEntry.id.uuidString,
            submittedAt: Date()
        )
        if !demoMode {
            // 提交前先落账：进程在此后任何时点被杀，回
            // 来靠账本＋同 key 重演取回本轮（不双跑）
            appState.runLedger.upsert(ledgerEntry)
        }
        // 提交：瞬断同 key 重试至多两次（受理回执丢失
        // 时重演回原 run）；明确拒绝才是真失败；耗尽
        // 仍不明＝结果未知，进对账不定性为错误
        var submitError: HermesError?
        var attempts = 0
        var gateWaits = 0
        while true {
            do {
                let response = try await appState.client.submitRun(
                    config: config, apiKey: apiKey,
                    sessionID: sessionID ?? "",
                    input: input, model: choice.model,
                    provider: provider,
                    idempotencyKey: ledgerEntry.idempotencyKey
                )
                ledgerEntry.runID = response.runID
                if !demoMode {
                    appState.runLedger.upsert(ledgerEntry)
                }
                runMachine.apply(.submitAccepted)
                if !demoMode {
                    markAcceptedEntryAccepted(
                        thread: thread,
                        userEntryID: userEntry.id.uuidString
                    )
                }
                submitError = nil
                break
            } catch let error as HermesError {
                if Task.isCancelled {
                    // 提交窗口内被停止：账本留停止意图、
                    // 本地静默收尾；下次进本线程时对账链
                    // 重演取回 run 并真停止（resumeRun-
                    // IfNeeded），不在此处假装已取消
                    ledgerEntry.stopRequested = true
                    if !demoMode {
                        appState.runLedger.upsert(ledgerEntry)
                    }
                    runMachine.apply(.stopRequested)
                    finishRunPresentation(failed: false)
                    return
                }
                if case .notSentOffline = error {
                    // §414 增补（断网规格 5.2）：设备明
                    // 确无网、请求根本没出设备——不是
                    // 结果未知：不重试、不判 ambiguous、
                    // 不进对账。折回待发巷（待发标记＋
                    // queued 态、mayAutoResume）、清账
                    // 本、收尾呈现（占位行随 sendTask
                    // 收尾撤）；网络恢复/回前台后由发
                    // 件箱 drain 自动续发（同 key 幂等
                    // 不变）。真未知（回执丢失）仍走下
                    // 方瞬态重试→ambiguous→对账全套，
                    // 154 幂等本体不动
                    if !demoMode {
                        appState.runLedger.remove(
                            threadID: thread.id
                        )
                        userEntry.markPendingSend(
                            in: modelContext
                        )
                    }
                    finishRunPresentation(failed: false)
                    return
                }
                if case .rateLimited(let retryAfter) = error,
                   gateWaits < 2 {
                    // 限流等待门（语义 3，与提交泵同
                    // 规）：按服务端等待值等、不落失
                    // 败；等满两轮仍被限才落下方拒绝
                    // 收口（成因 .rateLimited 钉死）
                    gateWaits += 1
                    try? await Task.sleep(
                        for: .seconds(min(retryAfter ?? 1, 30))
                    )
                    if Task.isCancelled {
                        ledgerEntry.stopRequested = true
                        if !demoMode {
                            appState.runLedger.upsert(ledgerEntry)
                        }
                        runMachine.apply(.stopRequested)
                        finishRunPresentation(failed: false)
                        return
                    }
                    continue
                }
                if error.isTransient, attempts < 2 {
                    attempts += 1
                    // 间隔走 RetryBackoff 同源退避
                    // （P1-1，与提交泵同口径）
                    try? await Task.sleep(
                        for: .seconds(RetryBackoff.delay(
                            afterFailure: attempts,
                            jitterUnit: Double.random(in: 0...1)
                        ))
                    )
                    continue
                }
                submitError = error
                runMachine.apply(
                    error.isTransient
                        ? .submitAmbiguous : .submitRejected
                )
                break
            } catch {
                submitError = .unreachable("网络错误")
                runMachine.apply(.submitAmbiguous)
                break
            }
        }
        // 聊天可靠性包：重发轮的待发标记在此脱落——
        // 提交被受理、或结果未知转对账（.unknown 系），
        // 本轮自此归 run 账本/对账链负责，条目不再是
        // 「未发送」；只有明确拒绝（.failed）保持待
        // 发，让用户还能点按再试（拒绝横幅在下方分支
        // 照旧如实报）
        if userEntry.isPendingSend, runMachine.phase != .failed {
            userEntry.deliveryState = nil
            try? modelContext.save()
        }
        if let submitError, runMachine.phase == .failed {
            // 提交被明确拒绝（真失败）：本轮从未在服务
            // 端成立——消息留痕、横幅照实报、账本清除
            // 基础止血包（P1/P2）：留痕之外补失败标记
            // 与重发入口（旧口径只有横幅、再试只能重打）
            if !demoMode {
                appState.runLedger.remove(threadID: thread.id)
                markTurnFailed(
                    entry: userEntry,
                    failureKind: SendFailureKind.classify(
                        submit: submitError
                    )
                )
            }
            presentSendFailure(
                kind: SendFailureKind.classify(
                    submit: submitError
                ),
                detail: submitError.diagnosticDetail
            )
            finishRunPresentation(failed: true)
            return
        }
        // §494：发布心跳——50ms 一拍问发布门排
        // 空积压，与本轮同生共死（defer 取消）；
        // 未武装/无积压时 tick 恒空转、无副作用
        let publishTicker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .milliseconds(50)
                )
                if Task.isCancelled { break }
                tickStreamPublish()
            }
        }
        defer { publishTicker.cancel() }
        if case .generating(_) = runMachine.phase {
            await followRunEvents(
                thread: thread, entry: ledgerEntry,
                demoMode: demoMode
            )
        }
        if !runMachine.isSettled {
            await reconcileRun(
                thread: thread, entry: &ledgerEntry,
                demoMode: demoMode
            )
        }
    }

    /// events 订阅：增量入装配器/思考累积器（数据
    /// 面）、§494 起增量同点喂发布门出呈现快照
    /// （§409 步 A「不再发布呈现快照」口径作废）、
    /// 工具卡
    /// 实时拼装、思考预览（若服务端发出）同路；见
    /// 到终态事件记账返回，流自结束（断线/缓冲过
    /// 期）按「未见终态」进结果未知——不在此报错、
    /// 不做失败分型
    func followRunEvents(
        thread: ChatThread, entry: RunLedgerEntry,
        demoMode: Bool
    ) async {
        // §449.9：新一轮跟随起手先清活动短语（上一轮
        // 残值不许串轮）；工具在飞栈为本趟局部账
        appState.liveActivityPhrase = nil
        var liveToolStack: [(id: String, phrase: String)] = []
        guard let runID = entry.runID,
              let config = appState.config,
              let apiKey = appState.apiKey else { return }
        let stream = appState.client.runEvents(
            config: config, apiKey: apiKey,
            runID: runID, lastSeq: lastEventSeq
        )
        for await envelope in stream {
            if let seq = envelope.seq { lastEventSeq = seq }
            switch envelope.event {
            case .contentDelta(let delta),
                 .interim(let delta):
                if !delta.isEmpty {
                    // 0.36.10：正文首达记位（事件序编排）
                    // 第 93 条：封段后 .text 标记已被换成
                    // .sealedText，新段首增量在此重新记位
                    // ——位置即新段的事件位（工具卡之后）
                    noteLiveOrder(.text)
                    // §409 步 A/E：增量只入装配器累
                    // 积（纯累积器）；§494：同点把装
                    // 配器全文喂发布门、到拍出快照
                    streamAssembler.offer(delta)
                    offerStreamPublish()
                    // 机制还原（2.22.1/268）：短语是
                    // run 级的、不是工具瞬时的——正文
                    // 在流就是「正在回复」，不许因工具
                    // 栈空而消失（审批/澄清等待自有短
                    // 语、不覆盖）
                    if liveToolStack.isEmpty,
                       activeRunApproval == nil,
                       activeRunClarify == nil {
                        appState.liveActivityPhrase = "正在回复"
                    }
                }
            case .reasoningPreview(let text):
                if reasoningStartedAt == nil {
                    reasoningStartedAt = Date()
                }
                // 0.36.10：思考首达记位（事件序编排）
                noteLiveOrder(.reasoning)
                // §409 步 A/E：思考增量只入累积器
                reasoningPublishGate.offer(text)
                // 机制还原（2.22.1/268）＋v23 合并裁决：
                // 思考期同为 run 在干活——栈空且非审批/
                // 澄清等待时置短语；词面取 v23 的思考
                // 内容预览（尾 36 字），无内容回落
                // 「正在思考」
                let compactThought = text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if liveToolStack.isEmpty,
                   activeRunApproval == nil,
                   activeRunClarify == nil {
                    appState.liveActivityPhrase =
                        compactThought.isEmpty
                        ? "正在思考"
                        : "思考中 · \(String(compactThought.suffix(36)))"
                }
            case .toolStarted(let id, let name, let preview):
                // 第 93 条：工具开始＝服务端段边界——
                // 先封当前正文段再落卡，卡后的新段增量
                // 进新缓冲，不许再拼回本段
                sealStreamSegment()
                appendLiveToolCard(
                    id: id, name: name, preview: preview
                )
                // §449.9：活动短语入 AppState 单源（胶
                // 囊第二行/中枢状态行同读）；短语由
                // Core 映射表单点派生
                liveToolStack.append((
                    id: id,
                    phrase: ToolCardClassifier.activityPhrase(
                        forToolName: name
                    )
                ))
                appState.liveActivityPhrase =
                    liveToolStack.last?.phrase
            case .toolCompleted(
                let id, let name, let preview, let failed
            ):
                completeLiveToolCard(
                    id: id, name: name, preview: preview,
                    failed: failed
                )
                liveToolStack.removeAll { $0.id == id }
                // 机制还原（2.22.1/268）：工具完成
                // 不等于 run 结束——栈空时落「正在
                // 处理」续命到下一个事件，短语只在
                // 终态/流结束时才清（治间隙空白）
                if let top = liveToolStack.last {
                    appState.liveActivityPhrase = top.phrase
                } else if activeRunApproval == nil,
                          activeRunClarify == nil {
                    appState.liveActivityPhrase = "正在处理"
                }
            case .approvalRequest(let prompt):
                activeRunApproval = prompt
                appState.liveActivityPhrase = "等待你确认高危操作"
                Haptics.impact(.medium)
            case .approvalResponded:
                activeRunApproval = nil
            case .clarifyRequest(let prompt):
                activeRunClarify = prompt
                appState.liveActivityPhrase = "等待你的选择或补充"
                Haptics.impact(.light)
            case .clarifyResponded:
                activeRunClarify = nil
            case .terminal(let kind, let output):
                appState.liveActivityPhrase = nil
                activeRunApproval = nil
                activeRunClarify = nil
                terminalOutputHint = output
                // §494：终态拍全量发布——对账落定
                // 前直播行先呈全文（与装配器兜底逐
                // 字一致），落定同键换装无跳变
                flushStreamPublish()
                runMachine.apply(.statusTerminal(kind))
                return
            case .other(_):
                continue
            }
        }
        // 流结束而未见终态：结果未知（非错误）。半截
        // 先落盘，进程被回收也不凭空消失
        appState.liveActivityPhrase = nil
        if !runMachine.isSettled,
           case .generating(_) = runMachine.phase {
            runMachine.apply(.streamLost)
            // §494：半截落盘接管呈现前先全量发布
            // （落盘条目与直播行同文、换装无回退）
            flushStreamPublish()
            persistRunPartials(thread: thread)
        }
    }

    /// 封段（第 93 条）：工具边界到达时把当前正文段
    /// 在装配器内定稿入封存列——liveOrder 的 .text
    /// 标记原位换成 .sealedText（段的事件位不动，
    /// 半截落盘按此序成条）。§494：封段拍同点全
    /// 量发布（段已定稿、呈现不许等下一增量才追
    /// 上封存段）。当前段为空（工具先行/并行工
    /// 具连发边界）时装配器无段可封，此处整件空转
    func sealStreamSegment() {
        guard streamAssembler
            .sealCurrentSegment() != nil
        else { return }
        flushStreamPublish()
        let marker = LiveOrderItem.sealedText(
            streamAssembler.sealedSegments.count - 1
        )
        if let textIndex = liveOrder.firstIndex(of: .text) {
            liveOrder[textIndex] = marker
        } else {
            noteLiveOrder(marker)
        }
    }

    func appendLiveToolCard(
        id: String, name: String, preview: String
    ) {
        let cardID = id.isEmpty ? "live-\(lastEventSeq)" : id
        guard !liveToolCards.contains(
            where: { $0.id == cardID }
        ) else { return }
        // 0.36.10（诊断 D3-3/D3-4）：标题回落改中文类
        // 名（旧实现英文短名直出卡面）；摘要过净化与
        // 落定同口径。events 通道不带参数分片，靠参数
        // 分形的标题（memory/skill 动作形）直播期用泛
        // 称、落定以 transcript 真参数重建修正——两期
        // 形态差异只在标题粒度，落定为准
        let title = ToolCardClassifier.title(
            forToolName: name, arguments: ""
        ) ?? ToolCardClassifier.fallbackTitle(forToolName: name)
        liveToolCards.append(ToolCard(
            id: cardID, toolName: name,
            category: ToolCardClassifier.category(
                forToolName: name
            ),
            title: title,
            summary: ToolCardClassifier.sanitizedSummary(preview),
            result: nil, resultFailed: false
        ))
        noteLiveOrder(.tool(cardID))
    }

    func completeLiveToolCard(
        id: String, name: String, preview: String,
        failed: Bool
    ) {
        let cardID = id.isEmpty ? "live-\(lastEventSeq)" : id
        guard let index = liveToolCards.firstIndex(
            where: { $0.id == cardID }
        ) else {
            appendLiveToolCard(id: id, name: name, preview: "")
            completeLiveToolCard(
                id: id, name: name, preview: preview,
                failed: failed
            )
            return
        }
        let old = liveToolCards[index]
        // 0.36.10（诊断 D3-6）：直播结果先过 unwrap 与
        // 落定同口径——旧实现 preview 原文直存，与落
        // 定的剥包裹/分型形态前后两套，同一卡直播与
        // 落定可能长得不一样；失败标记取事件信号与
        // 结果自带信号的并集，落定时再以 transcript
        // 信号为准重算（D3-9）
        let unwrapped = ToolResultUnwrap.unwrap(preview)
        liveToolCards[index] = ToolCard(
            id: old.id, toolName: old.toolName,
            category: old.category, title: old.title,
            summary: old.summary, result: unwrapped.text,
            resultFailed: failed || unwrapped.failed
        )
    }

    /// 对账：以服务端为准把本轮落定。链路＝（缺
    /// runID 时同 key 重演取回）→（停止意图先行发
    /// stop）→ 状态轮询＋events 重挂＋transcript 落
    /// 定（状态只报命运、transcript 才是成品；状态
    /// 记录缺失时 transcript 单独定性）。预算（10 分
    /// 钟）耗尽停在未知：账本保留、下次进本线程续对
    /// 账，不报错、不重发。
    /// run 丢失的访问记账＋终局裁决（发送失败机制
    /// 包·语义 6）：记一次「查无此 run」的访问——计
    /// 数＋首查时刻回写账本（跨访问累计，旧口径每
    /// 次访问从零磨 600s、账本永不终局）；累计达
    /// 标（访问 ≥3 次或首查距今 ≥24h，双闸取或，RunLedger.
    /// missingRunIsLost）→ 摘账本＋条目判失败可重
    /// 发（成因 .runResultLost 落账钉死、不自动重
    /// 发）＋终局呈现，返回 true；未达标返回 false
    /// （账本保留、下次访问续查）。极少数同访双记
    /// （观察窗与耗尽段同访各记一次）至多让次数闸
    /// 提前一次访问触发——run 持续查不到本身已是
    /// 强证据，口径可接受
    func recordMissingRunVisit(
        thread: ChatThread, entry: inout RunLedgerEntry,
        demoMode: Bool
    ) -> Bool {
        entry.missingReconcileCount += 1
        if entry.firstMissingAt == nil {
            entry.firstMissingAt = Date()
        }
        if !demoMode {
            appState.runLedger.upsert(entry)
        }
        guard RunLedger.missingRunIsLost(
            missingCount: entry.missingReconcileCount,
            firstMissingAt: entry.firstMissingAt,
            now: Date()
        ) else { return false }
        if !demoMode,
           let uid = UUID(uuidString: entry.userEntryID) {
            appState.runLedger.remove(userEntryID: uid)
        }
        if let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) {
            markTurnFailed(
                entry: userEntry, failureKind: .runResultLost
            )
        }
        presentSendFailure(kind: .runResultLost)
        Haptics.error()
        return true
    }

    func reconcileRun(
        thread: ChatThread, entry: inout RunLedgerEntry,
        demoMode: Bool
    ) async {
        guard let config = appState.config,
              let apiKey = appState.apiKey else { return }
        if runMachine.phase == .unknown {
            runMachine.apply(.foregrounded)
        }
        var deadline = Date().addingTimeInterval(600)
        // 对账分型（发送失败机制包·语义 7）：查询失
        // 败＝无证据，不烧 600s 预算——每次无证据轮
        // 询顺延期限，总顺延封顶 600s 防死服务端无
        // 限续命
        var deadlineExtensions: TimeInterval = 0
        // 本次访问首次见真 missing（状态端点 404）
        // 的时刻：持续 60s 仍无 transcript 证据才记
        // 一次「丢失访问」（跨访问累计见 RunLedger-
        // Entry.missingReconcileCount）
        var missingPollsStartedAt: Date?
        // §153：重演取回用本会话当前执行选择（与首提同源）
        let replayChoice = appState.sessionModelChoice(
            serverSessionID: entry.sessionID, threadID: thread.id
        )
        var transcriptMisses = 0
        while !runMachine.isSettled {
            if Task.isCancelled { return }
            // runID 缺失（受理回执丢失/提交窗口被杀）：
            // 同 key 重演取回——服务端幂等保证不双跑
            if entry.runID == nil {
                guard let replayInput = runReplayInput(
                    thread: thread, entry: entry
                ) else {
                    // 用户条目已不在（线程被清）：本轮无
                    // 从恢复，清账收尾（§451：只清本轮
                    // 这条，同线程其他未落定轮不许牵连）
                    if !demoMode,
                       let uid = UUID(
                           uuidString: entry.userEntryID
                       ) {
                        appState.runLedger.remove(
                            userEntryID: uid
                        )
                    }
                    finishRunPresentation(failed: false)
                    return
                }
                do {
                    let response = try await appState.client
                        .submitRun(
                            config: config, apiKey: apiKey,
                            sessionID: entry.sessionID,
                            input: replayInput,
                            model: replayChoice.model,
                            provider: replayChoice.providerField,
                            idempotencyKey: entry.idempotencyKey
                        )
                    entry.runID = response.runID
                    if !demoMode {
                        appState.runLedger.upsert(entry)
                    }
                    runMachine.apply(.submitAccepted)
                    if !demoMode {
                        markAcceptedEntryAccepted(
                            thread: thread,
                            userEntryID: entry.userEntryID
                        )
                    }
                } catch let replayError {
                    if let hermesError = replayError as? HermesError,
                       case .rateLimited(let retryAfter) = hermesError {
                        try? await Task.sleep(
                            for: .seconds(min(retryAfter ?? 1, 30))
                        )
                        continue
                    }
                    switch RunSubmitRetry.classify(replayError) {
                    case .notSentOffline:
                        if !demoMode,
                           let uid = UUID(uuidString: entry.userEntryID),
                           let userEntry = thread.entries.first(where: { $0.id == uid }) {
                            appState.runLedger.remove(userEntryID: uid)
                            userEntry.markPendingSend(in: modelContext)
                        }
                        presentSendFailure(kind: .offlineNotSent)
                        finishRunPresentation(failed: false)
                        return
                    case .rejected:
                        let hermesError = (replayError as? HermesError)
                            ?? .unreachable(replayError.localizedDescription)
                        let kind: SendFailureKind = hermesError.isSessionNotFound
                            ? .authRejected
                            : SendFailureKind.classify(submit: hermesError)
                        if !demoMode,
                           let uid = UUID(uuidString: entry.userEntryID) {
                            appState.runLedger.remove(userEntryID: uid)
                            if let userEntry = thread.entries.first(where: { $0.id == uid }) {
                                markTurnFailed(entry: userEntry, failureKind: kind)
                            }
                        }
                        presentSendFailure(
                            kind: kind,
                            detail: hermesError.diagnosticDetail
                        )
                        finishRunPresentation(failed: true)
                        return
                    case .transient, .unknown:
                        // 重演提交抛错同属无证据（传输/服务
                        // 端问题）：顺延期限、不烧预算
                        if deadlineExtensions < 600 {
                            deadline = deadline
                                .addingTimeInterval(3)
                            deadlineExtensions += 3
                        }
                        if Date() > deadline { break }
                        try? await Task.sleep(for: .seconds(3))
                        continue
                    }
                }
            }
            guard let runID = entry.runID else { continue }
            // 停止意图先行（账本/机器任一置位）
            if runMachine.stopRequested || entry.stopRequested {
                if !runMachine.stopRequested {
                    runMachine.apply(.stopRequested)
                }
                try? await appState.client.stopRun(
                    config: config, apiKey: apiKey, runID: runID
                )
            }
            // 已有终态证据（events 先行到达）：trans-
            // cript 落定；迟迟不落（或演示态无 trans-
            // cript）以状态 output 合成落定
            if runMachine.terminalKind != nil {
                if !demoMode,
                   await settleRunFromTranscript(
                       thread: thread, entry: entry
                   ) {
                    return
                }
                transcriptMisses += 1
                if demoMode || transcriptMisses >= 2 {
                    settleRunFromStatusOutput(
                        thread: thread, entry: entry
                    )
                    return
                }
                try? await Task.sleep(for: .milliseconds(1500))
                continue
            }
            // 状态轮询（对账分型，语义 7）：抛错＝查
            // 询失败＝无证据——旧口径 try? 把抛错与
            // 404 一并压成 nil 判 missing，网络抖动/
            // 鉴权失败/5xx 全被记成「run 不见了」，
            // 600s 磨完给假终局；现只有客户端明确
            // 404（runStatus 返 nil）才是真 missing
            let status: RunStatusResponse?
            do {
                status = try await appState.client.runStatus(
                    config: config, apiKey: apiKey, runID: runID
                )
            } catch {
                if deadlineExtensions < 600 {
                    deadline = deadline.addingTimeInterval(3)
                    deadlineExtensions += 3
                }
                try? await Task.sleep(for: .seconds(3))
                continue
            }
            switch status {
            case .some(let value) where value.status.isTerminal:
                terminalStatusHint = value
                let effectiveStatus =
                    (value.status == .failed && (runMachine.stopRequested || entry.stopRequested))
                    ? .cancelled
                    : value.status
                runMachine.apply(.statusTerminal(effectiveStatus))
            case .some(let value) where value.status.isActive:
                runMachine.apply(.statusRunning)
                // 仍在生成：重挂 events 续看（缓冲还在
                // 能接上直播；已扫则流立即结束回轮询）
                await followRunEvents(
                    thread: thread, entry: entry,
                    demoMode: demoMode
                )
                if runMachine.terminalKind != nil { continue }
                // 缓冲已扫时 events 会立即空转返回：轮询
                // 必须带间隔，防忙循环空烧
                try? await Task.sleep(for: .seconds(2))
                if Date() > deadline { break }
            case .some:
                // 状态词无法归类：无证据，继续轮询
                try? await Task.sleep(for: .seconds(3))
            case .none:
                // 真 missing（状态端点 404）：转 trans-
                // cript 单独定性；transcript 也无证据且
                // missing 持续 60s → 本次访问记账＋裁
                // 决（终局判失败，或留账下次续查）
                if missingPollsStartedAt == nil {
                    missingPollsStartedAt = Date()
                }
                runMachine.apply(.statusMissing)
                if await settleRunFromTranscript(
                    thread: thread, entry: entry
                ) {
                    return
                }
                if let started = missingPollsStartedAt,
                   Date().timeIntervalSince(started) > 60 {
                    if recordMissingRunVisit(
                        thread: thread, entry: &entry,
                        demoMode: demoMode
                    ) {
                        finishRunPresentation(failed: true)
                    } else {
                        showNotice(
                            "这条的生成结果暂时没查到，稍后回到本对话会继续确认。",
                            tier: .extended
                        )
                        finishRunPresentation(failed: false)
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(3))
            }
            if Date() > deadline { break }
        }
        if !runMachine.isSettled {
            runMachine.apply(.settleExhausted)
            persistRunPartials(thread: thread)
            if entry.runID == nil {
                // §414 增补（断网规格 5.2）：本轮从未
                // 被服务端受理（runID 恒 nil）却磨满
                // 预算——「生成仍在服务器进行中」对
                // 它是假话。折回待发巷（待发标记＋
                // queued 态）、清账本（账本留着只会
                // 让后续发送全撞忙碌守卫、条目永无标
                // 记），提示照实说还没发出去；网络恢
                // 复后 drain 自动续发
                if !demoMode,
                   let userEntry = thread.entries.first(
                       where: {
                           $0.id.uuidString == entry.userEntryID
                       }
                   ) {
                    userEntry.markPendingSend(
                        in: modelContext
                    )
                    // §451：清账只清本轮这条
                    if let uid = UUID(
                        uuidString: entry.userEntryID
                    ) {
                        appState.runLedger.remove(
                            userEntryID: uid
                        )
                    }
                }
                showNotice(
                    "这条还没发出去，网络恢复后会自动发送，也可以点按消息旁的时钟重发。",
                    tier: .extended
                )
                finishRunPresentation(failed: false)
            } else if missingPollsStartedAt != nil {
                // 本次访问见过真 missing、预算先磨完
                // （未满 60s 观察窗）：同样记一次访问
                // ＋裁决，不许带「还在生成」的假话退
                // 场（语义 6）
                if recordMissingRunVisit(
                    thread: thread, entry: &entry,
                    demoMode: demoMode
                ) {
                    finishRunPresentation(failed: true)
                } else {
                    showNotice(
                        "这条的生成结果暂时没查到，稍后回到本对话会继续确认。",
                        tier: .extended
                    )
                    finishRunPresentation(failed: false)
                }
            } else {
                // 体面出口：生成仍在服务端进行（或结
                // 果待查），账本保留、下次进本线程自
                // 动续对账——runID 在席时这句是真话，
                // 保留现行语义
                showNotice(
                    "生成仍在服务器进行中，稍后回到本对话会自动补齐结果。",
                    tier: .extended
                )
                finishRunPresentation(failed: false)
            }
        }
    }

    /// 同 key 重演提交的输入重建：源头是本地用户条目
    /// 本身（正文＋引用折叠＋图片），不另存载荷副本
    func runReplayInput(
        thread: ChatThread, entry: RunLedgerEntry
    ) -> RunInput? {
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return nil }
        let text = MessageQuote.outgoingContent(
            userText: userEntry.content, quote: userEntry.quote,
            sourceQuote: userEntry.sourceQuote
        )
        // §152：重演源头是本地条目全集——旧口径只
        // 取 imageData 首图，同 key 重演（提交回执
        // 丢失时）会把多图消息在服务端降成单图
        let localImages = userEntry.allImageDatas
        if !localImages.isEmpty {
            return .message(ChatMessage(
                role: "user", text: text,
                imageDataURLs: localImages.map {
                    "data:image/jpeg;base64,"
                        + $0.base64EncodedString()
                }
            ))
        }
        return .text(text)
    }

    /// transcript 落定：拉服务端会话历史、提取本轮段
    /// （Core RunTranscriptSettle）、整段替换本地半
    /// 截。段已落定返回 true；尚未出现（服务端还没
    /// flush 完）返回 false 由对账重试
    func settleRunFromTranscript(
        thread: ChatThread, entry: RunLedgerEntry
    ) async -> Bool {
        guard let messages = try? await appState
            .performAdmin({ client, cfg in
                try await client.sessionMessages(
                    config: cfg, id: entry.sessionID
                )
            }) else { return false }
        // 0.36.29（题 B 自愈）：段落定之前先对账补
        // 缺——存档有、本地缺的 user 条目补回（定
        // 案与口径见 healMissingUserEntries），补完
        // 再走既有落定，助手条目不归此路补造
        healMissingUserEntries(
            thread: thread, sessionID: entry.sessionID,
            messages: messages
        )
        // §451（App-4 硬门）：落定提取改锚本轮
        // serverRowID——多轮已受理时旧「末条 user
        // 行」锚会把后轮的段落到本轮头上（串段）。
        // 锚解析不到且同线程还有别的未落定轮时不许
        // 走无锚口径：本轮按未落定回对账重试（终态
        // 证据在席时对账自会转状态合成落定兜底——
        // 那条路按 runID 取数、不串段）
        let anchorRowID = transcriptAnchorRowID(
            thread: thread, entry: entry, messages: messages
        )
        if anchorRowID == nil,
           appState.runLedger.entries(
               forThreadID: thread.id
           ).count > 1 {
            runMachine.apply(.transcriptPending)
            return false
        }
        let settled = RunTranscriptSettle.settle(
            messages: messages, anchorRowID: anchorRowID
        )
        guard settled.found else {
            runMachine.apply(.transcriptPending)
            return false
        }
        // transcript-only 定性（无状态证据）时先把段的
        // 性质喂给状态机：失败段＝failed；停止意图在
        // 场＝cancelled；其余＝completed
        if runMachine.terminalKind == nil {
            if runMachine.stopRequested || entry.stopRequested {
                runMachine.apply(.statusTerminal(.cancelled))
            } else if settled.failed {
                runMachine.apply(.statusTerminal(.failed))
            } else {
                runMachine.apply(.statusTerminal(.completed))
            }
        }
        applySettledTurn(
            thread: thread, entry: entry, settled: settled
        )
        return true
    }

    /// 落定对账补缺（0.36.29，题 B 自愈）：新建旁聊
    /// 首发出现过「服务端存档完好、本地线程只剩助
    /// 手回复」的首句消失——静态审计已排除发送/落
    /// 盘/导入/落定四链的删除与过滤路径，剩余嫌疑
    /// 在新建＋切换＋首发同瞬间的本地时序缝（未证
    /// 死，定案等级中）。修法不赌竞态细节：以已拉
    /// 取的 transcript 为锚，Core 对账判缺（内容＋
    /// 时间窗、只认 user 条目），缺的补回呈现层；
    /// 发送链与落盘删除面一律不动。补缺发生时记
    /// 一条诊断读数（会话 id＋补回条数）留证，供
    /// 后续升格定案
    func healMissingUserEntries(
        thread: ChatThread, sessionID: String,
        messages: [SessionMessage]
    ) {
        let localUsers = thread.entries
            .filter { $0.role == "user" }
            .map {
                (content: $0.content, createdAt: $0.createdAt,
                 filePaths: $0.remoteFilePaths,
                 imagePaths: $0.remoteImagePaths)
            }
        let reconcile = RunTranscriptSettle.reconcileUserMessages(
            messages: messages, localUserEntries: localUsers
        )
        // §121 题二 a（对账回填）：配上对但本地条目缺
        // 服务端附件路径的，把路径集回填落盘——发送
        // 回填（sendTask）管新消息，本路管存量（发送
        // 回填上线前已发的消息在本线程下一次落定自
        // 动补牌）。定位键＝规范正文＋createdAt（与
        // Core 配对同锚）；回填只补缺字段、不动正文
        if !reconcile.pathBackfills.isEmpty {
            var backfilled = 0
            for backfill in reconcile.pathBackfills {
                guard let entry = thread.entries.first(where: {
                    $0.role == "user"
                        && $0.createdAt == backfill.createdAt
                        && SessionHistoryImport
                            .normalizedUserContent($0.content)
                            .text.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ) == backfill.text
                }) else { continue }
                if !backfill.filePaths.isEmpty,
                   entry.remoteFilePaths.isEmpty {
                    entry.remoteFilePathsData =
                        try? JSONEncoder().encode(backfill.filePaths)
                    backfilled += 1
                }
                if !backfill.imagePaths.isEmpty,
                   entry.remoteImagePaths.isEmpty {
                    entry.remoteImagePathsData =
                        try? JSONEncoder().encode(backfill.imagePaths)
                    backfilled += 1
                }
            }
            if backfilled > 0 {
                try? modelContext.save()
                ChatDiagTrace.record(
                    "落定回填附件路径 session=\(sessionID) fields=\(backfilled)"
                )
            }
        }
        let missing = reconcile.missing
        guard !missing.isEmpty else { return }
        for message in missing {
            // 0.46.1（§116）：补回也走规范化——展开块
            // 还原成干净正文＋附件路径落盘，不把给模型
            // 的脚手架原文补进气泡
            let normalized = SessionHistoryImport
                .normalizedUserContent(message.content)
            let healed = ChatEntry(
                role: "user", content: normalized.text,
                thread: thread,
                remoteImagePaths: normalized.imagePaths,
                remoteFilePaths: normalized.fileRefs
            )
            // 时刻以服务端存档为准（排序锚）；存档
            // 无时刻时保留插入时刻（落定助手条目随
            // 后以当前时刻落位，相对序仍成立）
            if let date = message.date {
                healed.createdAt = date
            }
            // 台账 187：补回条目出自服务端行——同点
            // 钉桩＋镜像（与导入落盘同口径）
            if message.id > 0 {
                healed.serverRowID = Int(exactly: message.id)
            }
            healed.applyReactions(message.reactions)
            modelContext.insert(healed)
        }
        try? modelContext.save()
        ChatDiagTrace.record(
            "落定补缺 session=\(sessionID) healed=\(missing.count)"
        )
    }

    /// 状态 output 合成落定（transcript 迟迟不落或演
    /// 示态）：终局文本取状态/事件 output，工具卡用
    /// 直播拼装的现成品——只作兜底，正常轮次以
    /// transcript 为准
    func settleRunFromStatusOutput(
        thread: ChatThread, entry: RunLedgerEntry
    ) {
        let userStopped = runMachine.stopRequested || entry.stopRequested
        if runMachine.terminalKind == .failed && !userStopped {
            deleteTurnPartialEntries(
                thread: thread, entry: entry
            )
            if !appState.isDemo,
               let uid = UUID(uuidString: entry.userEntryID) {
                // §451：清账只清本轮这条
                appState.runLedger.remove(userEntryID: uid)
            }
            // 基础止血包（P5/P2）：服务端原文只作分型
            // 输入与诊断留痕，界面只呈现 HermesError
            // 人话档（RunFailureClassifier）；本轮用户
            // 条目挂失败标记、点标记重发
            let failure = RunFailureClassifier.classify(
                errorText: terminalStatusHint?.error,
                outputText: terminalStatusHint?.output
                    ?? terminalOutputHint
            )
            ChatDiagTrace.record(
                "run 失败分型（状态合成落定）kind=\(failure)"
                    + " run=\(entry.runID ?? "-")"
            )
            if !appState.isDemo {
                markRunFailure(
                    entry: entry, in: thread, failure: failure
                )
            }
            presentSendFailure(
                kind: SendFailureKind.classify(run: failure),
                detail: failure.diagnosticDetail
            )
            runMachine.apply(.transcriptSettled)
            finishRunPresentation(failed: true)
            return
        }
        let output = terminalStatusHint?.output
            ?? terminalOutputHint
        // 第 93 条：兜底全文走装配器合并口径（各段
        // 以 "\n\n" 连接，与 transcript 落定拼接同
        // 制）——旧单闸全文是跨段直接拼接，与落库
        // 形态不一致
        let fallbackText = streamAssembler.mergedFullText
        let settled = SettledRunTurn(
            found: true,
            toolCards: liveToolCards,
            reasoning: nil,
            finalText: (output?.isEmpty == false)
                ? output
                : (fallbackText.isEmpty ? nil : fallbackText),
            failed: false, failureText: nil
        )
        applySettledTurn(
            thread: thread, entry: entry, settled: settled,
            unverified: true
        )
    }

    /// §426（缺陷一）：提交受理同点把本轮用户条
    /// 目标记送达——服务器确认收到＝发送成功，气
    /// 泡即刻回全色、时钟离席，不等整轮落定。旧
    /// 链 delivered 唯一写点在 applySettledTurn
    /// （落定），受理后整段生成期条目恒挂未确认
    /// 态（用户真机截图钉死）。三受理点（首提/
    /// 对账重演/恢复确立）与占位文案相位门共用
    /// .submitAccepted 同一信号、不新造第二信
    /// 号；落定点的既有写点保留作兜底（幂等同
    /// 值）。已送达/无状态条目不动（remainsIn-
    /// Queue 守卫），失败态条目在重发受理时经此
    /// 清失败标记（markSendState 的 accepted/
    /// delivered 同组语义自带）
    func markAcceptedEntryAccepted(
        thread: ChatThread, userEntryID: String
    ) {
        guard let userEntry = thread.entries.first(
                  where: { $0.id.uuidString == userEntryID }
              ),
              userEntry.sendState?.remainsInQueue == true
        else { return }
        // 发送失败机制包（语义 1 双轴）：内部状态落
        // .accepted 而非 .delivered——呈现与 §426 不
        // 变（markSendState 的 accepted 组合同 deliv-
        // ered：清失败标记＋送达投影，气泡全色、时钟
        // 离席），但条目在 run 真终态前不脱离发件箱
        // 语义：重试记账活到落定、发件箱判定不再把
        // 在飞条目当已完成（B1 清账错位的根）
        userEntry.markSendState(.accepted, in: modelContext)
    }

    /// 落定入账：整段替换本轮半截条目（工具卡＋带思
    /// 考回填的助手正文），触感与标题回流沿旧口径，
    /// 账本清除
    func applySettledTurn(
        thread: ChatThread, entry: RunLedgerEntry,
        settled: SettledRunTurn,
        unverified: Bool = false
    ) {
        // H2-a 自动朗读的在场判读：本轮是不是用户在
        // 本页亲手发出并看着落定的（发送打点起点只
        // 在这种轮有；恢复轮/后台轮无起点）——必须
        // 在下方打点消费清零之前先记下来
        let watchedTurn = sendFrameStartedAt != nil
        // §135 D 案打点：发送→落定全程一段（仅用户
        // 在飞发送的落定轮有起点；恢复轮与后台轮无
        // 起点、不记）。入口先记先清：失败分支同样
        // 消费读数，不许残留起点污染下一轮
        if entry.threadID == thread.id.uuidString,
           let started = sendFrameStartedAt {
            ChatDiagTrace.record(
                "发送打点 发送→落定 "
                    + "\(Int(Date().timeIntervalSince(started) * 1000))ms"
            )
            sendFrameStartedAt = nil
            sendFrameRestickLogged = false
        }
        runMachine.apply(.transcriptSettled)
        let phase = runMachine.phase
        deleteTurnPartialEntries(thread: thread, entry: entry)
        let userStopped = runMachine.stopRequested || entry.stopRequested
        if settled.failed && !userStopped {
            // 基础止血包（P5/P2）：同状态合成落定——
            // 原文（终态回执＋段失败文本）只作分型输
            // 入，界面只呈现人话档；用户条目挂失败标
            // 记、点标记重发
            let failure = RunFailureClassifier.classify(
                errorText: terminalStatusHint?.error,
                outputText: terminalStatusHint?.output
                    ?? settled.failureText
            )
            ChatDiagTrace.record(
                "run 失败分型（落定）kind=\(failure)"
                    + " run=\(entry.runID ?? "-")"
            )
            if !appState.isDemo {
                // §451：清账只清本轮这条
                if let uid = UUID(
                    uuidString: entry.userEntryID
                ) {
                    appState.runLedger.remove(
                        userEntryID: uid
                    )
                }
                markRunFailure(
                    entry: entry, in: thread, failure: failure
                )
            }
            presentSendFailure(
                kind: SendFailureKind.classify(run: failure),
                detail: failure.diagnosticDetail
            )
            finishRunPresentation(failed: true)
            return
        }
        // 基础止血包（P1/P2）：成功落定清本轮用户条目
        // 的失败标记——重发成功后旧标记不许残留（首
        // 发成功轮条目恒无标记，本支为空转）；§237：
        // 同点把发送状态落到 delivered（统一写口同
        // 步清 sendFailed 与 deliveryState），队列态
        // 至此出列、不许残留 sending/failed 旧值
        if !appState.isDemo,
           let userEntry = thread.entries.first(
               where: { $0.id.uuidString == entry.userEntryID }
           ) {
            // 台账 187：落定同点钉桩——本轮锚点 user
            // 行的服务端行 id 钉进本地条目（反应寻址
            // 坐标）；已钉不覆（坐标恒定、覆写无义）
            if let rowID = settled.userRowID,
               userEntry.serverRowID == nil {
                userEntry.serverRowID = rowID
                // 0.51.2（消息乱序修复）：钉桩同点把
                // createdAt 校正为该行服务端时刻——
                // 本地发送时刻与服务端时刻自此同域，
                // 排序不再双时钟混排（见 sortedEntries）
                if let rowDate = settled.userRowDate {
                    userEntry.createdAt = rowDate
                }
            }
            userEntry.markSendState(.delivered, in: modelContext)
            // 修法 A：发送完成（状态变为 .delivered）后
            // 清除乐观快照，恢复使用持久化数据
            optimisticAttachments.removeValue(forKey: userEntry.id)
            // 发送失败机制包（语义 1 清账点①）：run
            // 真终态落定成功——本条重试记账在此单点
            // 清（按条目 id、不扫线程）；失败支不许
            // 清（账留着钉死准入）
            appState.outboxRetry.clear(entryID: userEntry.id)
        }
        let endDate = Date()
        for (index, card) in settled.toolCards.enumerated() {
            let cardEntry = ChatEntry(
                role: "tool", content: "", thread: thread,
                toolCard: card
            )
            // 0.51.2（消息乱序修复）：工具卡落其来
            // 源行的服务端时刻，不再用本地 endDate
            // 盖戳（取不到才回落旧口径兜底）
            cardEntry.createdAt =
                (index < settled.toolCardDates.count
                    ? settled.toolCardDates[index] : nil)
                ?? endDate.addingTimeInterval(
                    Double(index) * 0.001
                )
            modelContext.insert(cardEntry)
        }
        if !settled.attachments.isEmpty {
            DeliveryStore.shared.ingest(settled.attachments)
        }
        // H2-a：本轮落定的助手条目（自动朗读的取材
        // 口，与下方 finished 分支的触感同点消费）
        var landedAssistantEntry: ChatEntry?
        if let text = settled.finalText, !text.isEmpty {
            let assistantEntry = ChatEntry(
                role: "assistant", content: text,
                thread: thread, reasoning: settled.reasoning,
                reasoningSeconds: nil
            )
            landedAssistantEntry = assistantEntry
            // 台账 187：正文恰出自单条服务端行时同点
            // 钉桩（多行拼接成文恒 nil、不钉错行——
            // 见 SettledRunTurn.assistantRowID 口径）
            assistantEntry.serverRowID = settled.assistantRowID
            // §441：多行拼接成文时 assistantRowID 恒
            // nil——本条目即段内拼接体、其末行正是
            // 选择框 attach 的落点行，改钉 options-
            // RowID 使卡有行可挂（寻址语义＝段末行）
            if assistantEntry.serverRowID == nil,
               let optionsRowID = settled.optionsRowID {
                assistantEntry.serverRowID = optionsRowID
            }
            if let options = settled.options,
               let optionsRowID = settled.optionsRowID {
                appState.optionsOverlay.seed(
                    threadID: thread.id,
                    card: .init(
                        serverRowID: optionsRowID,
                        options: options
                    )
                )
            }
            // 0.51.2（密码卡修复）：凭据请求块与选
            // 择框同构——本条目即段内拼接体、块的落
            // 点行是段内带块的最后一条 assistant
            // 行；未钉桩时改钉该行 id 使卡有行可
            // 挂，并播种覆盖层，渲染凭块同步出卡
            if assistantEntry.serverRowID == nil,
               let vaultRowID = settled.vaultRequestRowID {
                assistantEntry.serverRowID = vaultRowID
            }
            if let vaultRequest = settled.vaultRequest,
               let vaultRowID = settled.vaultRequestRowID {
                appState.vaultRequestOverlay.seed(
                    threadID: thread.id,
                    serverRowID: vaultRowID,
                    block: vaultRequest
                )
            }
            // 0.51.2（消息乱序修复）：助手条目落其
            // 末行服务端时刻，不再用本地 endDate
            // 盖戳（取不到才回落旧口径兜底）——旧
            // 盖戳使多段回复首段被压到后段之后沉底
            assistantEntry.createdAt = settled.assistantRowDate
                ?? endDate.addingTimeInterval(
                    Double(settled.toolCards.count) * 0.001
                        + 0.001
                )
            modelContext.insert(assistantEntry)
            // 兜底落定或未钉桩的助手条目打上「待核验」标记，下次尾对账自动以服务端真源原位覆写
            if unverified || assistantEntry.serverRowID == nil {
                UnverifiedEntryStore.shared.mark(assistantEntry.id)
            }
            // §247（包 4）：落定映射登记——本条目在
            // 新承载里沿用本轮流式行键建行（同键换
            // 代＝落定不换装）；映射只记账不判事，
            // 旧承载与未开新路时均无消费方、无副作用
            streamSettleMap.record(
                entryID: assistantEntry.id,
                streamRowKey: StreamingRowIdentity
                    .streamRowKey(userEntryID: entry.userEntryID)
            )
            thread.updatedAt = Date()
        }
        if !settled.toolCards.isEmpty
            || settled.finalText?.isEmpty == false {
            try? modelContext.save()
        }
        if !appState.isDemo,
           let uid = UUID(uuidString: entry.userEntryID) {
            // §451：清账只清本轮这条——同线程后轮的账
            // 本还等着消费环逐轮驱动
            appState.runLedger.remove(userEntryID: uid)
        }
        // 结果触感与收尾（旧 runStream 同口径）：完成
        // 有正文给 .success；真取消给「已停止生成」
        // （5 秒自消）；失败已在上分支处理。断线/切后
        // 台恢复后落定成功全程静默（§140 提示纪律第
        // 1 条「成功不报」——旧「已重新连接，回复已
        // 补齐。」播报与 runWasDetached 旗已整条摘除）
        if phase == .finished {
            if settled.finalText?.isEmpty == false {
                Haptics.success()
                // §411 自动朗读：只读用户在场看完的
                // 本轮——恢复/后台落定沿 §140 静默口
                // 径不出声；开关判读（默认关）收在播
                // 放器 autoReadIfEnabled 内，落定点不
                // 再读偏好；未开通、正在听别条时播放
                // 器内部自拒
                if watchedTurn, let landedAssistantEntry {
                    SpeechPlayer.shared.autoReadIfEnabled(
                        entryID: landedAssistantEntry.id,
                        content: landedAssistantEntry.content,
                        appState: appState
                    )
                }
            }
            // 标题回流触发（0.21.0 沿用）：已链接旁聊
            // 一轮完整落地后顶刷新令牌等服务端 AI 标题
            if thread.serverSessionID != nil,
               thread.id != appState.sessionLedger.mainThreadID {
                appState.noteLinkedSideChatTurnFinished()
            }
        } else if phase == .cancelled {
            // 停止按钮已提供即时视觉与触感反馈，不再弹多余文字提示
        }
        finishRunPresentation(failed: false)
    }

    /// 本轮半截候选的单点谓词（§414 抽出，整段替换
    /// 与半截回填共用）：用户条目之后、下一轮用户
    /// 条目之前的非锚定非待发条目。「下一轮」界＝
    /// 其后首个非待发的用户条目（待发条目未被服
    /// 务端受理、不构成轮次边界，其自身另有待发
    /// 豁免）。旧口径只有「用户条目之后必属本轮」
    /// 一条（发送互斥下成立）；§414 中段条目原位
    /// 重发后该前提失效——本轮用户条目之后可以躺
    /// 着已落定的后续轮次，靠本界免于陪葬。常规
    /// 轮（用户条目居末）无下一轮、界不生效，行
    /// 为与旧口径逐字同。既有豁免并入谓词：§123/
    /// §165 系统锚定条目（跨面并发落盘、不属本
    /// 轮）、待发条目（从未被服务端受理、不属任
    /// 何一轮的半截，用户消息不许陪葬）
    static func turnPartialCandidates(
        in thread: ChatThread, userEntry: ChatEntry
    ) -> [ChatEntry] {
        let nextTurnStart = thread.sortedEntries.first(
            where: {
                $0.id != userEntry.id
                    && $0.createdAt > userEntry.createdAt
                    && $0.role == "user"
                    && !$0.isPendingSend
            }
        )?.createdAt
        return thread.entries.filter {
            $0.id != userEntry.id
                && $0.createdAt > userEntry.createdAt
                && !$0.isSystemAnchored
                && !$0.isPendingSend
                && (nextTurnStart == nil
                    || $0.createdAt < nextTurnStart!)
        }
    }

    /// 整段替换的删除面：已落盘的半截名单＋本轮半
    /// 截候选（turnPartialCandidates，含下一轮界）
    func deleteTurnPartialEntries(
        thread: ChatThread, entry: RunLedgerEntry
    ) {
        deleteLivePartialEntries(in: thread)
        guard let userEntry = thread.entries.first(
            where: { $0.id.uuidString == entry.userEntryID }
        ) else { return }
        for candidate in Self.turnPartialCandidates(
            in: thread, userEntry: userEntry
        ) {
            modelContext.delete(candidate)
        }
        try? modelContext.save()
    }

    /// 结果未知时的半截落盘（进程被回收也不凭空消
    /// 失）：工具卡与已累积正文按条目落盘、记 id 供
    /// 落定时整段替换（与旧 interrupted 落盘同制）。
    /// 第 93 条：正文按段成条——封存段与当前段各成
    /// 一条助理条目、按 liveOrder 的事件序与工具卡
    /// 交错落盘（时序即恢复回填的段序凭据）；旧形态
    /// 把整轮正文拼成一条，跨段混存正是串字在落盘
    /// 侧的同根形态（回填只能整段吞回单一缓冲、前
    /// 段与后段就此混为一谈）。标记外的卡/段（回填
    /// 重挂等）按卡序/段序殿后补齐，不丢件
    func persistRunPartials(thread: ChatThread) {
        // §409 步 E：装配器/累积器已是纯累积形态，
        // fullSegments/fullText 每拍恒精确——旧
        // flush 定稿两行随发布语义退役删除，落盘
        // 直读两口径（条目写入逻辑逐字不变）
        deleteLivePartialEntries(in: thread)
        let reasoningText = reasoningPublishGate.fullText
        let segments = streamAssembler.fullSegments
        let sealedCount = streamAssembler
            .sealedSegments.count
        let endDate = Date()
        var ids: [UUID] = []
        var slot = 0
        var insertedAssistant = false
        func persistCard(_ card: ToolCard) {
            let cardEntry = ChatEntry(
                role: "tool", content: "", thread: thread,
                toolCard: card
            )
            cardEntry.createdAt = endDate.addingTimeInterval(
                Double(slot) * 0.001
            )
            slot += 1
            modelContext.insert(cardEntry)
            ids.append(cardEntry.id)
        }
        func persistSegment(_ text: String) {
            // 思考挂第一条助理条目：思考是本轮的单一
            // 折叠单元、不按段拆（与落定口径同）
            let assistantEntry = ChatEntry(
                role: "assistant", content: text,
                thread: thread,
                reasoning: !insertedAssistant
                    && !reasoningText.isEmpty
                    ? reasoningText : nil,
                reasoningSeconds: nil
            )
            assistantEntry.createdAt = endDate
                .addingTimeInterval(Double(slot) * 0.001)
            slot += 1
            modelContext.insert(assistantEntry)
            insertedAssistant = true
            ids.append(assistantEntry.id)
        }
        var persistedCardIDs: Set<String> = []
        var persistedSegments: Set<Int> = []
        for marker in liveOrder {
            switch marker {
            case .reasoning:
                continue
            case .sealedText(let index):
                if segments.indices.contains(index) {
                    persistSegment(segments[index])
                    persistedSegments.insert(index)
                }
            case .text:
                // 当前段在 fullSegments 中的下标恒为封
                // 存段数（有内容才在列）
                if streamAssembler.hasCurrentContent,
                   segments.indices.contains(sealedCount) {
                    persistSegment(segments[sealedCount])
                    persistedSegments.insert(sealedCount)
                }
            case .tool(let id):
                if let card = liveToolCards.first(
                    where: { $0.id == id }
                ) {
                    persistCard(card)
                    persistedCardIDs.insert(id)
                }
            }
        }
        for card in liveToolCards
        where !persistedCardIDs.contains(card.id) {
            persistCard(card)
        }
        for (index, text) in segments.enumerated()
        where !persistedSegments.contains(index) {
            persistSegment(text)
        }
        if insertedAssistant {
            thread.updatedAt = Date()
        }
        if !ids.isEmpty {
            try? modelContext.save()
        }
        livePartialEntryIDs = ids
    }

    func deleteLivePartialEntries(
        in thread: ChatThread
    ) {
        guard !livePartialEntryIDs.isEmpty else { return }
        for candidate in thread.entries
        where livePartialEntryIDs.contains(candidate.id) {
            modelContext.delete(candidate)
        }
        livePartialEntryIDs = []
    }

    /// 呈现收尾：清流式状态与在途标记（触感由各落定
    /// 分支自理，此处只在失败时补 .error——调用方
    /// 已给触感的路径传 failed=false 防双响；0.36.2
    /// 失败触感自 .warning 改判 .error，表 D 归位）
    func finishRunPresentation(failed: Bool) {
        if failed {
            Haptics.error()
        }
        // §494：全部落定/失败/取消出口共用收尾
        // ——发布态同点整清，直播行随占位条件消
        // 失、落定条目同键接位
        resetStreamPresentation()
        streamingText = nil
        reasoningStartedAt = nil
        sendTask = nil
        activeRunThreadID = nil
        // 0.36.10（诊断 D2 补根）：直播区至此必须清
        // 空——旧实现漏清 liveToolCards，落定条目已
        // 入列后残留直播卡仍在列表尾同屏渲染、且挂
        // 「进行中」，正是判词 5 截图底部那截残影。
        // 本函数是全部落定/失败/取消出口的共用收尾，
        // 清在此处不误伤对账中途（persistRunPartials
        // 在调用本函数之前已把半截转入条目）
        liveToolCards = []
        liveOrder = []
        activeRunApproval = nil
        activeRunClarify = nil
        // 第 93 条：封存段真值在装配器本体内，下
        // 一轮 driveRun 起点归零，视图侧无镜像可清
    }

    /// 停止（0.31.0）：runs 通道真取消——发 stop 后
    /// 由订阅/对账链等终态落定、部分产物按 transcr-
    /// ipt 呈现；提交窗口内则取消本地提交任务（账本
    /// 已留停止意图，下次对账执行真停止）
    /// 大厂级 0ms 即时停止生成（ChatGPT / Claude / 豆包标准三层刹停）：
    /// 1. 立即触感反馈 + 取消本地 SSE 流与提交泵任务（不再苦等服务端响应）；
    /// 2. 立即把已流式吐出的半截正文定格落盘（绝不丢已生成的字）并恢复输入框空闲态；
    /// 3. 后台并发通知服务端 `stopRun` 真正终止远端推理与工具执行，节省 Token。
    func requestRunStop() {
        guard isStreaming || activeRunThreadID != nil || sendTask != nil else { return }
        Haptics.impact(.light)

        let targetThreadID = activeRunThreadID ?? currentThreadID
        let partialContent = (streamingText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 标记停止意图并取出服务端 runID（在清理 UI 态前读取）
        runMachine.apply(.stopRequested)
        var serverRunID: String?
        if let threadID = targetThreadID,
           var entry = appState.runLedger.entry(forThreadID: threadID) {
            entry.stopRequested = true
            serverRunID = entry.runID
            appState.runLedger.upsert(entry)
        }

        // 2. 立即取消本地在飞任务与提交泵（所有阶段统一即时生效）
        sendTask?.cancel()
        sendTask = nil
        if let threadID = targetThreadID {
            submitPumpTasks[threadID]?.cancel()
            submitPumpTasks[threadID] = nil
        }

        // 3. 若已有流式半截正文且尚未落盘，立刻定格保存为助手条目（保留用户已看到的半截内容）
        if !partialContent.isEmpty,
           let thread = currentThread,
           thread.id == targetThreadID {
            let lastAssistant = thread.sortedEntries.last(where: { $0.role == "assistant" && $0.toolCard == nil })
            if lastAssistant?.content.trimmingCharacters(in: .whitespacesAndNewlines) != partialContent {
                let stoppedEntry = ChatEntry(
                    role: "assistant",
                    content: partialContent,
                    thread: thread
                )
                modelContext.insert(stoppedEntry)
                try? modelContext.save()
            }
        }

        // 4. 0ms 恢复前端空闲态（按钮立刻切回可用、隐藏加载动画）
        finishRunPresentation(failed: false)
        showNotice(L10n.string("已停止生成"), tier: .brief)

        // 5. 后台异步通知服务端真终止（即使弱网/超时也不卡死界面）
        if let runID = serverRunID,
           let config = appState.config,
           let apiKey = appState.apiKey {
            Task.detached {
                try? await appState.client.stopRun(
                    config: config, apiKey: apiKey, runID: runID
                )
            }
        }
    }

    /// 向正在执行的 run 注入纠偏指令（POST /v1/runs/{id}/steer）
    func steerActiveRun(runID: String, text: String) {
        guard let config = appState.config,
              let apiKey = appState.apiKey else { return }
        Haptics.impact(.light)
        Task {
            do {
                let receipt = try await appState.client.steerRun(
                    config: config, apiKey: apiKey, runID: runID, input: text
                )
                if receipt.accepted {
                    showNotice(L10n.string("已向生成中的任务插入纠偏指令"), tier: .brief)
                } else {
                    showNotice(L10n.string("当前任务暂无法插入纠偏"), tier: .brief)
                }
            } catch {
                ChatDiagTrace.record("steer_run_failed: \(error.localizedDescription)")
                showNotice(L10n.string("纠偏指令发送失败"), tier: .brief)
            }
        }
    }

    /// 响应运行中等待审批的工具请求（POST /v1/runs/{id}/approval）
    func respondActiveRunApproval(
        runID: String, prompt: RunApprovalPrompt, choice: String
    ) {
        guard let config = appState.config,
              let apiKey = appState.apiKey else { return }
        Haptics.impact(.light)
        activeRunApproval = nil
        Task {
            do {
                try await appState.client.respondRunApproval(
                    config: config,
                    apiKey: apiKey,
                    runID: runID,
                    requestID: prompt.requestID,
                    choice: choice,
                    executionGeneration: prompt.executionGeneration
                )
                let label = choice == "deny" ? "已拒绝此操作" : "已批准继续执行"
                showNotice(L10n.string(label), tier: .brief)
            } catch {
                activeRunApproval = prompt
                ChatDiagTrace.record("run_approval_failed: \(error.localizedDescription)")
                showNotice(L10n.string("审批响应发送失败，请重试"), tier: .brief)
            }
        }
    }

    /// 回答运行中等待澄清的问题（POST /v1/runs/{id}/clarify）
    func respondActiveRunClarify(
        runID: String, prompt: RunClarifyPrompt, answer: String
    ) {
        guard let config = appState.config,
              let apiKey = appState.apiKey else { return }
        Haptics.impact(.light)
        activeRunClarify = nil
        Task {
            do {
                try await appState.client.respondRunClarify(
                    config: config,
                    apiKey: apiKey,
                    runID: runID,
                    requestID: prompt.requestID,
                    answer: answer,
                    executionGeneration: prompt.executionGeneration
                )
                showNotice(L10n.string("已提交答复，任务继续执行"), tier: .brief)
            } catch {
                activeRunClarify = prompt
                ChatDiagTrace.record("run_clarify_failed: \(error.localizedDescription)")
                showNotice(L10n.string("答复发送失败，请重试"), tier: .brief)
            }
        }
    }

    /// 在服务端无损克隆当前会话为新分支（POST /api/sessions/{id}/fork）
    func forkCurrentSession() {
        guard !appState.isDemo,
              let sessionID = currentThread?.serverSessionID,
              let config = appState.config,
              let apiKey = appState.apiKey else { return }
        Haptics.selection()
        Task {
            do {
                let forked = try await appState.client.forkServerSession(
                    config: config, apiKey: apiKey, id: sessionID, title: nil
                )
                appState.router.pendingChatSessionID = forked.id
                showNotice(L10n.string("已创建分支会话"), tier: .brief)
            } catch {
                ChatDiagTrace.record("fork_session_failed: \(error.localizedDescription)")
                showNotice(L10n.string("分支会话创建失败"), tier: .brief)
            }
        }
    }

    /// 进线程/回前台时恢复未落定 run（杀进程/切后台/
    /// 预算耗尽遗留）：半截呈现回填＋对账落定。无账
    /// 本或驱动在途即返回
    func resumeRunIfNeeded() async {
        guard !appState.isDemo, !isDrivingRun,
              scenePhase == .active,
              let thread = currentThread,
              let entry = appState.runLedger.entry(
                  forThreadID: thread.id
              ) else { return }
        await driveAcceptedTurn(thread: thread, entry: entry)
    }

}
