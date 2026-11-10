import Foundation
import OneDayCore

/// 未落定 run 的持久账本（0.31.0）：一轮生成提交前
/// 先落账（runID 后补）、落定即删——杀进程/切后台
/// 回来靠它恢复对账，判定逻辑在 Core（RunLedger
/// 纯函数），本类只管 UserDefaults 存取（与
/// SideChatStore 同模式；演示模式纯内存不落盘）。
@MainActor
@Observable
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

    private func persist() {
        guard let defaults else { return }
        defaults.set(
            try? JSONEncoder().encode(entries),
            forKey: Key.entries
        )
    }
}
