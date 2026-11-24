import Foundation

/// §451（发送机制换代）提交泵车道策略：纯判定层。
///
/// 背景：发送改「落盘即提交」——send() 落盘后条目
/// 经同会话 POST 串行泵立即提交，服务端 FIFO 排
/// 班受理多轮（session_admissions）。泵逐条走查
/// 本线程发件箱条目（线程内序），本策略回答「下一
/// 步提交谁／被谁堵住／无事可做」。
///
/// 严格保序（用户 2026-11-24 亲选）：一条未受理
/// 失败（POST 被拒、上传/链接等准备段失败）堵住
/// 其后全部条目的首次提交——泵停在失败条上，等
/// 其自动重试到点或用户手点重发解堵，后续不越
/// 过。已受理条目（账本在席）不堵：它们已在服务
/// 端 FIFO 内按序排班，与本地提交序无关。人工接
/// 管条（提交段孤儿等，OutboxAutoRetryPolicy 的
/// manualOnly）同堵：其投递结果不可知，越过它先
/// 发后条会造成服务端上下文错位。
///
/// 判定材料由 App 层组装（账本在席与否、失败自
/// 动重试是否到点走 OutboxAutoRetryPolicy 单源），
/// 本文件只算账、可单测钉死。
public enum SubmissionLane {

    /// 车道里的一条（按线程内条目序传入）
    public struct Entry: Equatable, Sendable {
        public var entryID: UUID
        /// 已受理：run 账本有此条（服务端已收存）
        public var hasLedgerEntry: Bool
        /// 人工接管：自动链永不碰、须用户裁决
        public var manualOnly: Bool
        /// 未受理失败：提交/准备段失败且无账本
        public var unacceptedFailure: Bool
        /// 失败条自动重试已到点（退避满/首次）
        public var failureRetryDue: Bool
        /// 待提交：已落盘、未提交、未失败
        public var awaitingSubmission: Bool

        public init(
            entryID: UUID,
            hasLedgerEntry: Bool = false,
            manualOnly: Bool = false,
            unacceptedFailure: Bool = false,
            failureRetryDue: Bool = false,
            awaitingSubmission: Bool = false
        ) {
            self.entryID = entryID
            self.hasLedgerEntry = hasLedgerEntry
            self.manualOnly = manualOnly
            self.unacceptedFailure = unacceptedFailure
            self.failureRetryDue = failureRetryDue
            self.awaitingSubmission = awaitingSubmission
        }
    }

    public enum Decision: Equatable, Sendable {
        /// 提交这一条（待提交首投，或失败条重试到点）
        case submit(UUID)
        /// 严格保序堵泵：停在未受理失败条上等解堵
        case blocked(failedEntryID: UUID)
        /// 人工接管条堵泵：等用户裁决（重发/撤回）
        case blockedManual(entryID: UUID)
        /// 车道清空：无待提交、无堵点
        case idle
    }

    public static func decision(entries: [Entry]) -> Decision {
        for entry in entries {
            // 已受理：在服务端 FIFO 内，不占提交车道
            if entry.hasLedgerEntry { continue }
            if entry.manualOnly {
                return .blockedManual(entryID: entry.entryID)
            }
            if entry.unacceptedFailure {
                return entry.failureRetryDue
                    ? .submit(entry.entryID)
                    : .blocked(failedEntryID: entry.entryID)
            }
            if entry.awaitingSubmission {
                return .submit(entry.entryID)
            }
            // 其余（已落定残影等）不参与判定，跳过
        }
        return .idle
    }
}
