import Foundation
import OneDayCore

/// 线程已读水位持久化（台账 148）：NEW 未读分界线
/// 的水位按线程落 UserDefaults（JSON）——Chat-
/// Thread/ChatEntry 模型自 §332 冻结、不许原地加
/// 字段，水位是纯客户端呈现记账（丢了只是某次打
/// 开少一条分界线、不伤数据），归宿与 FileOpen-
/// HistoryStore 同式。打开线程时 ChatView 读水位
/// 解析分界锚（Core UnreadDivider）、随即推进到
/// 当前末条。
@MainActor
@Observable
/// §416 新鲜度普查豁免：本地已读标记落盘店，无远端新鲜度问题（判定表见 DESIGN §416）
final class ThreadReadMarkStore {
    private struct Mark: Codable {
        var entryID: String?
        var date: TimeInterval
    }

    private var marks: [String: Mark] = [:]

    private static let defaultsKey = "chat.readMarks.v1"
    /// 记账封顶：超出按水位时刻淘汰最旧（分界线只
    /// 服务近用线程，陈年线程的水位丢弃无感）
    private static let capacity = 200

    init() {
        if let data = UserDefaults.standard.data(
            forKey: Self.defaultsKey
        ),
           let decoded = try? JSONDecoder().decode(
               [String: Mark].self, from: data
           ) {
            marks = decoded
        }
    }

    /// 某线程的已读水位（从未打开过 → nil）
    func watermark(
        for threadID: UUID
    ) -> UnreadDivider.Watermark? {
        guard let mark = marks[threadID.uuidString]
        else { return nil }
        return UnreadDivider.Watermark(
            entryID: mark.entryID.flatMap(UUID.init(uuidString:)),
            date: Date(timeIntervalSince1970: mark.date)
        )
    }

    /// 推进水位到指定条目并落盘（打开线程时以当前
    /// 末条调用——本次观看内分界锚已先解析定格，
    /// 推进不影响已解析的锚）
    func advance(
        for threadID: UUID, entryID: UUID, date: Date
    ) {
        marks[threadID.uuidString] = Mark(
            entryID: entryID.uuidString,
            date: date.timeIntervalSince1970
        )
        if marks.count > Self.capacity {
            let sorted = marks.sorted {
                $0.value.date < $1.value.date
            }
            for (key, _) in sorted.prefix(
                marks.count - Self.capacity
            ) {
                marks.removeValue(forKey: key)
            }
        }
        if let data = try? JSONEncoder().encode(marks) {
            UserDefaults.standard.set(
                data, forKey: Self.defaultsKey
            )
        }
    }
}
