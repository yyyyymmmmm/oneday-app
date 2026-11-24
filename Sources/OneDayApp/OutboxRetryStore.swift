import Foundation
import OneDayCore

/// 发件箱自动重试记账（台账 154／G-04，DESIGN
/// §336）：按条目 id 记自动重试次数、最近尝试时刻
/// 与人工接管标记，判定走 Core OutboxAutoRetry-
/// Policy，本类只管 UserDefaults 存取（与 Run-
/// LedgerStore 同模式；演示模式纯内存不落盘）。
/// 记账随条目生灭：投递成功/撤回/编辑回收即清账，
/// 条目已不存在的残账由 drain 起手 prune 清掉，
/// 不许陈账无限累积。
@MainActor
@Observable
/// §416 新鲜度普查豁免：发件箱重试队列事件驱动，无读触发拉取（判定表见 DESIGN §416）
final class OutboxRetryStore {
    private(set) var records: [String: OutboxRetryRecord] = [:]

    private let defaults: UserDefaults?

    private enum Key {
        static let records = "outboxRetry.records"
    }

    init(persisted: Bool) {
        defaults = persisted ? .standard : nil
        guard let defaults,
              let data = defaults.data(forKey: Key.records),
              let decoded = try? JSONDecoder().decode(
                  [String: OutboxRetryRecord].self, from: data
              )
        else { return }
        records = decoded
    }

    func record(for entryID: UUID) -> OutboxRetryRecord? {
        records[entryID.uuidString]
    }

    /// 记一次自动重试（次数＋1、时刻落账）：发送
    /// 失败机制包（语义 2）改记账点——在自动重投
    /// 执行完毕后调用（无论成败），与成因同落；
    /// 旧口径在执行前记账，配合「受理清账」让账
    /// 在真终态前被扫掉，是死循环的账面一环
    func noteAutoAttempt(entryID: UUID, at date: Date) {
        var record = records[entryID.uuidString]
            ?? OutboxRetryRecord()
        record.attempts += 1
        record.lastAttemptAt = date
        records[entryID.uuidString] = record
        persist()
    }

    /// 失败成因落账（发送失败机制包·语义 3）：失
    /// 败落点（markTurnFailed）同点写——次数不动，
    /// 只记成因；政策准入、呈现投影、文案取词全
    /// 读它，不许成因只活在某次调用的局部变量里
    func setFailureKind(
        entryID: UUID, kind: SendFailureKind
    ) {
        var record = records[entryID.uuidString]
            ?? OutboxRetryRecord()
        guard record.lastFailureKind != kind else { return }
        record.lastFailureKind = kind
        records[entryID.uuidString] = record
        persist()
    }

    /// 打人工接管标记（提交段孤儿浮现，见 Core 策
    /// 略注）：保留已有次数，只加标记
    func markManualOnly(entryID: UUID) {
        var record = records[entryID.uuidString]
            ?? OutboxRetryRecord()
        guard !record.manualOnly else { return }
        record.manualOnly = true
        records[entryID.uuidString] = record
        persist()
    }

    func clear(entryID: UUID) {
        guard records.removeValue(
            forKey: entryID.uuidString
        ) != nil else { return }
        persist()
    }

    /// 清残账：id 不在现存条目集里的记录整批删除
    func prune(validEntryIDs: Set<String>) {
        let stale = records.keys.filter {
            !validEntryIDs.contains($0)
        }
        guard !stale.isEmpty else { return }
        for key in stale {
            records.removeValue(forKey: key)
        }
        persist()
    }

    private func persist() {
        guard let defaults else { return }
        defaults.set(
            try? JSONEncoder().encode(records),
            forKey: Key.records
        )
    }
}
