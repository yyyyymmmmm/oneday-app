import Foundation

/// 空会话清理安全处置（§234，2026-11-14 大厂九项④
/// 拍板）：禁用无围栏裸删——旧形态是客户端一发
/// DELETE /api/sessions/empty、服务端把全部空会话
/// 一次清光（无清单、无对账、无留痕、删错无从核
/// 对）。定版处置四件，全部在本文件与调用方落码：
/// 1. **dry-run 先行**：先全量扫描算出候选清单给人
///    看，默认停在预览、什么都不删；
/// 2. **围栏**：动手前客户端候选数必须与服务端空会
///    话计数（/api/sessions/empty/count）对账一致，
///    不一致即整场作废；删除逐条走既有围栏单删
///    （ServerSessionActions.delete），不走批量端点；
/// 3. **审计留痕**：候选快照在动手前先落审计记录
///    （EmptyCleanupAuditRecord），执行结果逐段回
///    填——中途进程死掉也留得下「本打算删什么」；
/// 4. **可恢复核验**：删后全量重扫，候选逐条核对
///    已消失/仍在，结果写回审计记录才算收口。
public enum EmptySessionCleanup {
    /// 候选口径：消息数明确为 0 才算空会话；计数缺
    /// 失（nil，投影面没带）一律不算——口径不明不删
    public static func candidates(
        from sessions: [ServerSession]
    ) -> [ServerSession] {
        sessions.filter { $0.messageCount == 0 }
    }

    /// 围栏对账：客户端按消息数口径数出的候选数，
    /// 必须与服务端自报的空会话数一字不差；对不上
    /// 说明两边口径不一致（扫描面不全/服务端口径
    /// 不同），整场不许动手
    public static func countsMatch(
        candidateCount: Int, serverCount: Int
    ) -> Bool {
        candidateCount == serverCount
    }

    /// 删后核验：候选 id 逐条对重扫存活集——不在存
    /// 活集＝已核验消失，仍在＝没删净（如实上报，
    /// 不许拿「接口返回成功」冒充删净）
    public static func verify(
        candidateIDs: [String], survivingIDs: Set<String>
    ) -> Verification {
        var gone: [String] = []
        var remaining: [String] = []
        for id in candidateIDs {
            if survivingIDs.contains(id) {
                remaining.append(id)
            } else {
                gone.append(id)
            }
        }
        return Verification(goneIDs: gone, remainingIDs: remaining)
    }

    public struct Verification: Equatable, Sendable {
        public var goneIDs: [String]
        public var remainingIDs: [String]

        public init(goneIDs: [String], remainingIDs: [String]) {
            self.goneIDs = goneIDs
            self.remainingIDs = remainingIDs
        }
    }
}

/// 一次清理的审计记录（落盘留痕，App 侧持久化）：
/// 计划段（plannedAt/扫描数/服务端计数/候选快照）
/// 在第一条删除动手前就写入；执行段（deletedIDs/
/// failures）与核验段（verified*）逐段回填。
public struct EmptyCleanupAuditRecord: Codable, Equatable, Sendable,
    Identifiable
{
    public var id: String
    public var plannedAt: String
    public var scannedCount: Int
    public var serverReportedCount: Int
    public var candidates: [Candidate]
    public var deletedIDs: [String]
    public var failures: [Failure]
    /// nil＝尚未核验（未执行/执行中/核验未成）
    public var verifiedGoneIDs: [String]?
    public var verifiedRemainingIDs: [String]?
    /// nil＝未收口（计划已落盘但执行没走完）
    public var finishedAt: String?

    public struct Candidate: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var startedAt: String?

        public init(id: String, title: String, startedAt: String?) {
            self.id = id
            self.title = title
            self.startedAt = startedAt
        }
    }

    public struct Failure: Codable, Equatable, Sendable {
        public var id: String
        public var reason: String

        public init(id: String, reason: String) {
            self.id = id
            self.reason = reason
        }
    }

    public init(
        id: String, plannedAt: String, scannedCount: Int,
        serverReportedCount: Int, candidates: [Candidate],
        deletedIDs: [String] = [], failures: [Failure] = [],
        verifiedGoneIDs: [String]? = nil,
        verifiedRemainingIDs: [String]? = nil,
        finishedAt: String? = nil
    ) {
        self.id = id
        self.plannedAt = plannedAt
        self.scannedCount = scannedCount
        self.serverReportedCount = serverReportedCount
        self.candidates = candidates
        self.deletedIDs = deletedIDs
        self.failures = failures
        self.verifiedGoneIDs = verifiedGoneIDs
        self.verifiedRemainingIDs = verifiedRemainingIDs
        self.finishedAt = finishedAt
    }
}
