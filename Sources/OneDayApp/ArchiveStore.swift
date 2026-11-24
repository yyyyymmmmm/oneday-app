import Foundation
import OneDayCore

/// 备份留痕（H1-b）：每台服务器只存最近一次可用备
/// 份的判读摘要（时间＋产物名＋三态＋未纳入数），原
/// 始日志永不落盘（可能含敏感路径）。归宿与 Health-
/// SummaryStore 同式（UserDefaults JSON、按 server-
/// Base 隔离）；存档段与升级前检查单共读同一份
/// （shared）。
@MainActor
@Observable
/// §416 新鲜度普查豁免：本地备份痕落盘店，无远端新鲜度问题（判定表见 DESIGN §416）
final class BackupRecordStore {
    static let shared = BackupRecordStore()

    private let defaults: UserDefaults
    private var records: [String: BackupRecord] = [:]

    private static let defaultsKey = "archive.lastBackup.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(
               [String: BackupRecord].self, from: data
           ) {
            records = decoded
        }
    }

    func record(for serverBase: String?) -> BackupRecord? {
        guard let serverBase else { return nil }
        return records[serverBase]
    }

    func save(_ record: BackupRecord) {
        records[record.serverBase] = record
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// 存档引擎（H1-b）：备份走与体检同一套 spawn＋poll
/// （OpsActionRunner，动作名 backup），检查点是同步
/// GET。两件事互相独立：一件失败不拖垮另一件。检查
/// 点清理（prune）删除行为未知——本引擎不给它留任
/// 何入口，界面也不许出现清理按钮（蓝图既定口径）。
@MainActor
@Observable
final class ArchiveStore {
    /// 阶段与体检面共用同一枚举（跑中带起始时刻、
    /// 失败带人话原因），不另造一套
    typealias Phase = HealthCheckStore.Phase

    /// 备份一轮的执行口：注入点与 HealthCheckStore
    /// 同层——「跑到终态并带回本轮日志切片＋退出码
    /// ＋spawn 回执产物路径」；生产实现是 OpsAction-
    /// Runner，测试注入脚本。
    typealias BackupExecutor =
        @MainActor () async throws -> BackupOutcome

    struct BackupOutcome: Sendable {
        var lines: [String]
        var exitCode: Int?
        var archivePath: String?
    }

    /// 检查点读取口（测试注入脚本）
    typealias CheckpointsFetcher =
        @MainActor () async throws -> CheckpointsResponse

    private(set) var backupPhase: Phase = .idle
    private(set) var backupRun: BackupRun?
    private(set) var checkpointsPhase: Phase = .idle
    private(set) var checkpoints: CheckpointsResponse?

    private let recordStore: BackupRecordStore

    init(recordStore: BackupRecordStore = .shared) {
        self.recordStore = recordStore
    }

    var isBackupRunning: Bool { backupPhase.isRunning }
    /// 备份串行化：跑中禁用重入（服务端同名动作只
    /// 有一个跟踪槽，与体检同一口径）
    var canStartBackup: Bool { !isBackupRunning }

    // MARK: - 对外入口（生产）

    func runBackup(appState: AppState) async {
        guard let base = appState.config?.baseString else {
            backupPhase = .failed("还没连上服务器")
            return
        }
        await runBackup(serverBase: base) {
            let outcome = try await OpsActionRunner.run(
                appState: appState, actionName: "backup"
            ) { client, config in
                try await client.opsBackup(config: config)
            }
            return BackupOutcome(
                lines: outcome.lines,
                exitCode: outcome.exitCode,
                archivePath: outcome.spawnArchive
            )
        }
    }

    func loadCheckpoints(appState: AppState) async {
        guard appState.config?.baseString != nil else {
            checkpointsPhase = .failed("还没连上服务器")
            return
        }
        await loadCheckpoints {
            try await appState.performAdmin { client, config in
                try await client.opsCheckpoints(config: config)
            }
        }
    }

/// §416 新鲜度普查豁免：检查点会话级单拉（已有数据不重拉、失败直拉重试），同 CronStore 口径（判定表见 DESIGN §416）
    /// 进面首拉：已有数据就不重拉（失败重试走
    /// loadCheckpoints 直拉）
    func loadCheckpointsIfNeeded(appState: AppState) async {
        guard checkpoints == nil, !checkpointsPhase.isRunning
        else { return }
        await loadCheckpoints(appState: appState)
    }

    // MARK: - 状态机（测试可注入执行口）

    func runBackup(
        serverBase: String, execute: BackupExecutor
    ) async {
        guard !isBackupRunning else { return }
        backupPhase = .running(since: Date())
        do {
            let outcome = try await execute()
            let run = BackupLogParser.parse(
                lines: outcome.lines,
                exitCode: outcome.exitCode,
                archivePath: outcome.archivePath
            )
            backupRun = run
            backupPhase = .finished
            // 落痕口径：只记可用备份（干净／注意档）；
            // 失败轮不落痕——留痕的语义是「最近一次可
            // 用备份」，失败只在本面呈现，不许把上次的
            // 好备份冲掉（检查单靠这份痕判新鲜度）
            if run.state != .failed {
                recordStore.save(
                    BackupRecord(
                        date: Date(), serverBase: serverBase,
                        archiveName: run.archiveName,
                        state: run.state,
                        missingFileCount: run.missingFileCount
                    )
                )
            }
        } catch {
            backupPhase = .failed(
                HealthCheckStore.humanMessage(for: error)
            )
        }
    }

    func loadCheckpoints(fetch: CheckpointsFetcher) async {
        guard !checkpointsPhase.isRunning else { return }
        checkpointsPhase = .running(since: Date())
        do {
            checkpoints = try await fetch()
            checkpointsPhase = .finished
        } catch {
            checkpointsPhase = .failed(
                HealthCheckStore.humanMessage(for: error)
            )
        }
    }
}
