import Foundation

// MARK: - Hermes ops 存档端点（H1-b 存档段，台账 158）
//
// 契约据 2026-11-19 H1-0 探活实测冻结（pkg-hermes-ops-
// probe-20261119）：backup 与 doctor 同为 spawn＋poll
// 两段式（触发回执额外带 archive 产物路径）；check-
// points 是同步结构化 GET，但现役实例影子存储恒空
// ——存档新鲜度以备份产物为准，checkpoints 只如实
// 呈现、不当新鲜度数据源。prune（检查点清理）删除
// 行为未知，App 侧不放行：本文件连它的 DTO 都不留。

/// GET /api/ops/checkpoints（同步；结构经源码＋实测互证）
public struct CheckpointsResponse: Decodable, Sendable, Equatable {
    public struct Session: Decodable, Sendable, Equatable {
        public let session: String
        public let files: Int
        public let bytes: Int

        public init(session: String, files: Int, bytes: Int) {
            self.session = session
            self.files = files
            self.bytes = bytes
        }
    }

    public let sessions: [Session]
    public let totalBytes: Int

    enum CodingKeys: String, CodingKey {
        case sessions
        case totalBytes = "total_bytes"
    }

    public init(sessions: [Session], totalBytes: Int) {
        self.sessions = sessions
        self.totalBytes = totalBytes
    }

    /// 现役实例恒空（影子存储未在用）——空是真实状态，
    /// 界面如实显「暂无检查点」，不许拿它判新鲜度
    public var isEmpty: Bool { sessions.isEmpty }
}

// MARK: - backup 日志判读（三态）

/// 一轮 backup 的判读结果。口径（探活 §四冻结）：
/// exit_code 不可直接用——incomplete 常态就是 exit 1，
/// 判成「备份失败」会天天误报；判读只认「产物在不在
/// ＋未纳入计数在不在」：产物在且无未纳入＝干净成功；
/// 产物在但有未纳入＝已备份（注意档），报清缺几个；
/// 无产物＝失败。
public struct BackupRun: Sendable, Equatable {
    public enum State: String, Codable, Sendable, Equatable {
        case clean
        case attention
        case failed

        /// 状态一词（点色旁的短文案不用它，留给日志/调试）
        public var word: String {
            switch self {
            case .clean: return "完成"
            case .attention: return "注意"
            case .failed: return "失败"
            }
        }
    }

    public var state: State
    /// 未纳入文件数（日志 `N file(s) could not be added`
    /// 原文计数）；只有 incomplete 标记、数不出来时为 nil
    public var missingFileCount: Int?
    /// 产物文件名（spawn 回执 archive 绝对路径的末段）；
    /// 无产物为 nil
    public var archiveName: String?
    public var exitCode: Int?

    public init(
        state: State, missingFileCount: Int? = nil,
        archiveName: String? = nil, exitCode: Int? = nil
    ) {
        self.state = state
        self.missingFileCount = missingFileCount
        self.archiveName = archiveName
        self.exitCode = exitCode
    }

    public var headline: String {
        Self.headline(state: state, missingFileCount: missingFileCount)
    }

    /// 三态人话（BackupRun 与 BackupRecord 共用一份措辞）
    public static func headline(
        state: State, missingFileCount: Int?
    ) -> String {
        switch state {
        case .clean:
            return "备份完成"
        case .attention:
            if let missingFileCount {
                return "已备份，有 \(missingFileCount) 个文件没纳入"
            }
            return "已备份，有几个文件没纳入"
        case .failed:
            return "备份没成功"
        }
    }
}

/// backup 富文本日志判读器：只认探活实测冻结的两个
/// 标记——`Backup incomplete` 与 `Archive kept, but
/// N file(s) could not be added`；其余行一概不猜。
public enum BackupLogParser {
    public static func parse(
        lines: [String], exitCode: Int?, archivePath: String?
    ) -> BackupRun {
        var missing: Int?
        var sawIncomplete = false
        var sawArchiveKept = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.contains("Backup incomplete") {
                sawIncomplete = true
            }
            if line.contains("Archive kept") {
                sawArchiveKept = true
            }
            if let count = firstCount(
                #"(\d+)\s+file\(s\) could not be added"#, in: line
            ) {
                missing = count
            }
        }

        let archiveName = archivePath.flatMap { path -> String? in
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.split(separator: "/").last.map(String.init)
        }
        // 产物证据：回执路径、「Archive kept」原文、未纳
        // 入计数行（该行本身就是「归档已保留，但…」的
        // 后半句）任一成立即算产物在
        let hasProduct = archiveName != nil || sawArchiveKept
            || missing != nil

        let state: BackupRun.State
        if sawIncomplete || missing != nil {
            // incomplete 是常态尾巴：产物在＝注意档，
            // 产物不在才判失败；exit 多少不参与判读
            state = hasProduct ? .attention : .failed
        } else if exitCode == 0 {
            state = .clean
        } else if exitCode == nil, archiveName != nil {
            // 退出码未知但产物在手、无未纳入证据——
            // 以产物为准（探活 §四判读规则）
            state = .clean
        } else {
            state = .failed
        }
        return BackupRun(
            state: state, missingFileCount: missing,
            archiveName: archiveName, exitCode: exitCode
        )
    }

    private static func firstCount(
        _ pattern: String, in text: String
    ) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }
}

// MARK: - 备份留痕（只存判读摘要，不存原始日志）

/// 上次备份留痕（按服务器存一份最新）：语义是「最近
/// 一次可用备份」——失败轮不落痕（失败只在本面呈现，
/// 不许把上次的好备份冲掉）。只存时间、产物名与判读
/// 结论；**大小不入痕**：没有备份列表端点、下载端点
/// 只能整包拉，不存在可信的大小来源，不编造（探活
/// 修正 #2 的呈现口径：留痕＋产物名呈现）。
public struct BackupRecord: Codable, Sendable, Equatable {
    public var date: Date
    public var serverBase: String
    public var archiveName: String?
    public var state: BackupRun.State
    public var missingFileCount: Int?

    public init(
        date: Date, serverBase: String,
        archiveName: String? = nil,
        state: BackupRun.State,
        missingFileCount: Int? = nil
    ) {
        self.date = date
        self.serverBase = serverBase
        self.archiveName = archiveName
        self.state = state
        self.missingFileCount = missingFileCount
    }

    public var headline: String {
        BackupRun.headline(
            state: state, missingFileCount: missingFileCount
        )
    }

    /// 新鲜度（升级前检查单口径，施工图 2.4）：7 天内
    /// 算新鲜，超过提示先做一次新的
    public func isFresh(now: Date) -> Bool {
        now.timeIntervalSince(date) < 7 * 24 * 3600
    }
}

// MARK: - 升级前检查单（与体检结论联动的人话判断）

/// 升级前检查单判断（施工图 2.4 的呈现口径）：有新
/// 鲜备份＋体检跑过＝可以升级；缺哪样说哪样。只做
/// 呈现与判断，不执行升级（升级本体归 G-10/包4 线）。
public struct ArchiveReadiness: Sendable, Equatable {
    public var ready: Bool
    public var headline: String

    public init(ready: Bool, headline: String) {
        self.ready = ready
        self.headline = headline
    }
}

public enum ArchiveReadinessJudge {
    public static func judge(
        backup: BackupRecord?, health: HealthCheckSummary?,
        now: Date
    ) -> ArchiveReadiness {
        guard let backup else {
            return ArchiveReadiness(
                ready: false, headline: "升级前先做一次备份"
            )
        }
        guard backup.isFresh(now: now) else {
            return ArchiveReadiness(
                ready: false,
                headline: "最近备份超过 7 天了，升级前先做一次新的"
            )
        }
        guard health != nil else {
            return ArchiveReadiness(
                ready: false,
                headline: "备份是新的；升级前建议先跑一次体检"
            )
        }
        return ArchiveReadiness(
            ready: true,
            headline: "备份是新的、体检也跑过了，可以升级"
        )
    }
}
