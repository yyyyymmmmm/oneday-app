import Foundation
import OneDayCore

/// 未落定 run 的持久账本（0.31.0）：一轮生成提交前
/// 先落账（runID 后补）、落定即删——杀进程/切后台
/// 回来靠它恢复对账，判定逻辑在 Core（RunLedger
/// 纯函数），本类只管 UserDefaults 存取（与
/// SideChatStore 同模式；演示模式纯内存不落盘）。
@MainActor
@Observable
/// §416 新鲜度普查豁免：本地运行台账落盘店，无远端新鲜度问题（判定表见 DESIGN §416）
final class RunLedgerStore {
    private(set) var entries: [RunLedgerEntry] = []

    private let defaults: UserDefaults?

    private enum Key {
        static let entries = "runLedger.entries"
    }

    init(persisted: Bool) {
        defaults = persisted ? .standard : nil
        guard let defaults,
              let data = defaults.data(forKey: Key.entries),
              let decoded = try? JSONDecoder().decode(
                  [RunLedgerEntry].self, from: data
              )
        else { return }
        entries = decoded
    }

    func entry(forThreadID id: UUID) -> RunLedgerEntry? {
        RunLedger.entry(forThreadID: id.uuidString, in: entries)
    }

    /// §451：线程内全部未落定账（提交序）——多轮并
    /// 存后消费环/车道判定按此读全量，不再只看头条
    func entries(forThreadID id: UUID) -> [RunLedgerEntry] {
        RunLedger.entries(forThreadID: id.uuidString, in: entries)
    }

    /// §451：按 user 条目查账（撤回/在飞判定用）
    func entry(forUserEntryID id: UUID) -> RunLedgerEntry? {
        entries.first { $0.userEntryID == id.uuidString }
    }

    func upsert(_ entry: RunLedgerEntry) {
        entries = RunLedger.upsert(entries, entry)
        persist()
    }

    func remove(threadID: UUID) {
        entries = RunLedger.removing(
            threadID: threadID.uuidString, from: entries
        )
        persist()
    }

    /// §451：单轮清账——只删本轮这条，同线程其他未
    /// 落定轮不受牵连（落定链各点自此走此口）
    func remove(userEntryID: UUID) {
        entries = RunLedger.removing(
            userEntryID: userEntryID.uuidString, from: entries
        )
        persist()
    }

    private func persist() {
        guard let defaults else { return }
        defaults.set(
            try? JSONEncoder().encode(entries),
            forKey: Key.entries
        )
    }
}
