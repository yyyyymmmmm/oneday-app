import XCTest
import OneDayCore
@testable import OneDayApp

/// 存档引擎装配钉测（H1-b，台账 158）：执行口注入
/// 脚本，只验状态机——备份判读落痕（失败轮不落
/// 痕）、跑中禁重入、引擎失败人话化、检查点空/失败
/// 两态、留痕跨实例往返。日志判读的真形态在
/// OneDayCoreTests.OpsArchiveTests 钉。
@MainActor
final class ArchiveStoreTests: XCTestCase {

    private func makeRecordStore(
        suiteName: String = "archive-tests-\(UUID().uuidString)"
    ) -> BackupRecordStore {
        BackupRecordStore(
            defaults: UserDefaults(suiteName: suiteName)!
        )
    }

    private let attentionOutcome = ArchiveStore.BackupOutcome(
        lines: [
            "Backup incomplete",
            "Archive kept, but 9 file(s) could not be added",
        ],
        exitCode: 1,
        archivePath: "/opt/data/backups/hermes-backup-x.zip"
    )
    private let cleanOutcome = ArchiveStore.BackupOutcome(
        lines: ["1515 files scanned", "Time: 10.1s"],
        exitCode: 0,
        archivePath: "/opt/data/backups/hermes-backup-y.zip"
    )
    private let failedOutcome = ArchiveStore.BackupOutcome(
        lines: ["Error: unable to write archive"],
        exitCode: 1, archivePath: nil
    )

    func testRunBackupAttentionSavesRecord() async {
        let recordStore = makeRecordStore()
        let store = ArchiveStore(recordStore: recordStore)
        XCTAssertTrue(store.canStartBackup)

        await store.runBackup(serverBase: "https://a.test") {
            self.attentionOutcome
        }

        XCTAssertEqual(store.backupPhase, .finished)
        XCTAssertEqual(store.backupRun?.state, .attention)
        XCTAssertEqual(store.backupRun?.missingFileCount, 9)
        XCTAssertTrue(store.canStartBackup)

        let record = recordStore.record(for: "https://a.test")
        XCTAssertEqual(record?.state, .attention)
        XCTAssertEqual(record?.missingFileCount, 9)
        XCTAssertEqual(record?.archiveName, "hermes-backup-x.zip")
        // 按服务器隔离：别的服务器读不到这份留痕
        XCTAssertNil(recordStore.record(for: "https://b.test"))
    }

    func testRunBackupCleanSavesRecord() async {
        let recordStore = makeRecordStore()
        let store = ArchiveStore(recordStore: recordStore)

        await store.runBackup(serverBase: "https://a.test") {
            self.cleanOutcome
        }

        XCTAssertEqual(store.backupRun?.state, .clean)
        let record = recordStore.record(for: "https://a.test")
        XCTAssertEqual(record?.state, .clean)
        XCTAssertEqual(record?.archiveName, "hermes-backup-y.zip")
        XCTAssertNil(record?.missingFileCount)
    }

    func testFailedRunDoesNotOverwriteGoodRecord() async {
        let recordStore = makeRecordStore()
        let store = ArchiveStore(recordStore: recordStore)

        await store.runBackup(serverBase: "https://a.test") {
            self.cleanOutcome
        }
        await store.runBackup(serverBase: "https://a.test") {
            self.failedOutcome
        }

        // 本轮失败在本面如实呈现，但留痕仍是上次的好
        // 备份——检查单的新鲜度不能被失败轮冲掉
        XCTAssertEqual(store.backupRun?.state, .failed)
        XCTAssertEqual(store.backupPhase, .finished)
        let record = recordStore.record(for: "https://a.test")
        XCTAssertEqual(record?.state, .clean)
        XCTAssertEqual(record?.archiveName, "hermes-backup-y.zip")
    }

    func testRunBackupEngineFailureIsHumanized() async {
        let recordStore = makeRecordStore()
        let store = ArchiveStore(recordStore: recordStore)

        await store.runBackup(serverBase: "https://a.test") {
            throw HermesError.unreachable("桩")
        }

        if case .failed(let message) = store.backupPhase {
            XCTAssertEqual(message, "连不上服务器，检查网络后再试")
        } else {
            XCTFail("backup 应为 failed，实际 \(store.backupPhase)")
        }
        XCTAssertNil(store.backupRun)
        XCTAssertNil(recordStore.record(for: "https://a.test"))
    }

    func testRunBackupReentryDoesNotDoubleRun() async {
        let recordStore = makeRecordStore()
        let store = ArchiveStore(recordStore: recordStore)
        var calls = 0
        let execute: ArchiveStore.BackupExecutor = {
            calls += 1
            try await Task.sleep(for: .milliseconds(400))
            return self.cleanOutcome
        }

        let task = Task {
            await store.runBackup(
                serverBase: "https://a.test", execute: execute
            )
        }
        await Task.yield()
        XCTAssertTrue(store.isBackupRunning)
        XCTAssertFalse(store.canStartBackup)

        await store.runBackup(
            serverBase: "https://a.test", execute: execute
        )
        await task.value

        XCTAssertEqual(calls, 1)
        XCTAssertTrue(store.canStartBackup)
    }

    func testLoadCheckpointsEmptyIsHonestEmpty() async {
        let store = ArchiveStore(recordStore: makeRecordStore())

        await store.loadCheckpoints {
            CheckpointsResponse(sessions: [], totalBytes: 0)
        }

        XCTAssertEqual(store.checkpointsPhase, .finished)
        XCTAssertEqual(store.checkpoints?.isEmpty, true)
        XCTAssertEqual(store.checkpoints?.totalBytes, 0)
    }

    func testLoadCheckpointsFailureIsHumanized() async {
        let store = ArchiveStore(recordStore: makeRecordStore())

        await store.loadCheckpoints {
            throw HermesError.sessionExpired
        }

        if case .failed(let message) = store.checkpointsPhase {
            XCTAssertEqual(message, "登录已过期，重新连接后再试")
        } else {
            XCTFail(
                "checkpoints 应为 failed，实际 \(store.checkpointsPhase)"
            )
        }
        XCTAssertNil(store.checkpoints)
    }

    func testRecordStoreRoundTripAcrossInstances() {
        // 留痕往返：写完换一个新实例读同一份 defaults，
        // 读回的记录逐字段相等（模拟重启后读痕）
        let suite = "archive-tests-\(UUID().uuidString)"
        let writer = makeRecordStore(suiteName: suite)
        let record = BackupRecord(
            date: Date(timeIntervalSince1970: 1_763_000_000),
            serverBase: "https://a.test",
            archiveName: "hermes-backup-x.zip",
            state: .attention, missingFileCount: 7
        )
        writer.save(record)

        let reader = makeRecordStore(suiteName: suite)
        XCTAssertEqual(reader.record(for: "https://a.test"), record)
        XCTAssertNil(reader.record(for: "https://b.test"))
        XCTAssertNil(reader.record(for: nil))
    }
}
