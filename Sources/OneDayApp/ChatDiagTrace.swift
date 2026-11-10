import Foundation
import os

/// 聊天面诊断留痕（0.36.29）：沿听写诊断同口径——
/// os 日志＋UserDefaults 快照双写，供事后经诊断面
/// 回收读数升格定案；只留最近 20 条、带时间戳，
/// 纯留证，不参与任何业务判定、不上屏打扰用户。
/// 落点：落定对账补缺（题 B 自愈证据）与选文件
/// 失败原文（题 C）共用此一处，不再各起炉灶
enum ChatDiagTrace {
    private static let log = Logger(
        subsystem: "site.didichou.oneday", category: "chat-diag"
    )
    private static let key = "chat.diag.traces"
    private static let cap = 20

    static func record(_ line: String) {
        log.info("\(line, privacy: .public)")
        let stamp = ISO8601DateFormatter().string(from: Date())
        var traces = snapshots
        traces.append("\(stamp) \(line)")
        if traces.count > cap {
            traces.removeFirst(traces.count - cap)
        }
        UserDefaults.standard.set(traces, forKey: key)
    }

    static var snapshots: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}
