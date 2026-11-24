import Foundation
import OneDayCore
import SwiftData

/// 本地种子后台同步（根治版包 2，DESIGN §331）：
/// 种子（本地独有历史）自本包退出发送路径——发送
/// 只认绑定 id，种子是独立的后台义务，由本器按线
/// 程 seedSyncState 记账推进。决策以**回读为准**：
/// 每轮先 GET 服务端会话行，按现状分路——不存在
/// 则 import 落行、存在空行则 import 补种、存在且
/// 已有内容则不冒进上行（条数恰等于种子转录条数
/// ＝自家种子先前已落、回执丢失过，记仅文本已同
/// 步；否则记 localOnly，本地保留、如实标记）。
/// import 的 request_id 按 SideChatLink.seed-
/// RequestID 稳定派生：同一份种子重试恒同 id，围
/// 栏收据重放＋回读双查双层幂等，不重复落消息。
@MainActor
final class SessionSeedSyncer {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// 同步一轮。仅 needsSyncAttempt（待导入/失败待
    /// 重试）态有动作，其余态原样返回现态；种子快
    /// 照由调用方按 ChatView.seedEntries 口径备好
    /// （待发条目已剔除——种子只含服务端应有历史）
    @discardableResult
    func syncSeed(
        thread: ChatThread, seed: [SeedEntry],
        title: String?, model: String?,
        context: ModelContext
    ) async -> SeedSyncState {
        let current = thread.seedSyncState
        guard current.needsSyncAttempt,
              let sessionID = thread.serverSessionID,
              !sessionID.isEmpty,
              !SideChatLink.isMergeBucket(sessionID),
              appState.config != nil
        else { return current }
        let transcript = SideChatLink.seedTranscript(from: seed)
        guard !transcript.isEmpty else {
            // 义务凭空消失（本地历史已清）：结清记账
            thread.seedSyncState = .notOwed
            try? context.save()
            return .notOwed
        }
        thread.seedSyncState = .importing
        try? context.save()
        // 回读决策：GET 不到（404）与 GET 失败分开
        // ——前者是落行时机，后者是本轮失败
        let existing: ServerSession?
        do {
            existing = try await appState.performAdmin { client, config in
                try await client.serverSession(
                    config: config, id: sessionID
                )
            }
        } catch let error as HermesError {
            if case .unexpectedStatus(_, let status) = error,
               status == 404 {
                existing = nil
            } else {
                return noteFailure(error, thread: thread, context: context)
            }
        } catch {
            return noteFailure(error, thread: thread, context: context)
        }
        if let existing {
            let serverCount = existing.messageCount ?? 0
            if serverCount > 0 {
                // 已有内容：条数恰合种子＝自家种子已
                // 落（回执丢失过的重试轮）；否则服务
                // 端另有内容，种子不上行、仅本地保留
                let settled: SeedSyncState =
                    serverCount == transcript.count
                    ? .syncedTextOnly : .localOnly
                if settled == .syncedTextOnly {
                    thread.serverSeeded = true
                }
                thread.seedSyncState = settled
                try? context.save()
                return settled
            }
            return await importSeed(
                thread: thread, sessionID: sessionID,
                transcript: transcript, title: title,
                model: model,
                expectedRevision: existing.runtimeRevision ?? 0,
                context: context
            )
        }
        return await importSeed(
            thread: thread, sessionID: sessionID,
            transcript: transcript, title: title,
            model: model, expectedRevision: 0,
            context: context
        )
    }

    /// import 一步（稳定 request_id；力学与 ChatView
    /// .importSeed 同源——围栏修订取回读值、2xx 之
    /// 外全记失败态，不在此吞错装成功）
    private func importSeed(
        thread: ChatThread, sessionID: String,
        transcript: [SeedEntry], title: String?,
        model: String?, expectedRevision: Int,
        context: ModelContext
    ) async -> SeedSyncState {
        let body = SideChatLink.importSessionBody(
            id: sessionID, title: title, model: model,
            messages: transcript,
            lockUpdatedAt: Date().timeIntervalSince1970
        )
        do {
            try await appState.performAdmin { client, config in
                try await client.importServerSession(
                    config: config,
                    requestID: SideChatLink.seedRequestID(
                        sessionID: sessionID, messages: transcript
                    ),
                    expectedRevision: expectedRevision,
                    sessionBody: body
                )
            }
        } catch {
            return noteFailure(error, thread: thread, context: context)
        }
        thread.serverSeeded = true
        thread.seedSyncState = .syncedTextOnly
        try? context.save()
        return .syncedTextOnly
    }

    /// 失败记账：态落 failed 待重试、原因原文落线
    /// 程失败留痕面（与链接失败同面，设置/诊断可
    /// 见），计数递增
    private func noteFailure(
        _ error: Error, thread: ChatThread,
        context: ModelContext
    ) -> SeedSyncState {
        thread.seedSyncState = .failed
        thread.linkFailureCount += 1
        thread.linkLastError = (error as? HermesError)?.userMessage
            ?? error.localizedDescription
        try? context.save()
        return .failed
    }
}
