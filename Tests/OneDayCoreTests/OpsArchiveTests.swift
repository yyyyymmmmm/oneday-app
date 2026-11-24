import XCTest
@testable import OneDayCore

/// 存档段映射层钉测（H1-b，台账 158）：fixture 按
/// H1-0 探活实测形态冻结——backup incomplete 轮的原
/// 文标记（`Backup incomplete`＋`Archive kept, but
/// N file(s) could not be added`、exit 1）分缺 9 与
/// 缺 7 两轮；干净轮＝无标记＋exit 0；checkpoints
/// 用探活实调回的恒空形状。判读口径改一寸，这里先红。
final class OpsArchiveTests: XCTestCase {

    // MARK: - checkpoints DTO（探活冻结形状）

    func testCheckpointsDecodesEmptyRealShape() throws {
        let json = #"{"sessions": [], "total_bytes": 0}"#
        let decoded = try JSONDecoder().decode(
            CheckpointsResponse.self, from: Data(json.utf8)
        )
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(decoded.totalBytes, 0)
    }

    func testCheckpointsDecodesSessions() throws {
        let json = #"{"sessions": [{"session": "s-1", "files": 3, "bytes": 2048}, {"session": "s-2", "files": 1, "bytes": 512}], "total_bytes": 2560}"#
        let decoded = try JSONDecoder().decode(
            CheckpointsResponse.self, from: Data(json.utf8)
        )
        XCTAssertFalse(decoded.isEmpty)
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.sessions[0].session, "s-1")
        XCTAssertEqual(decoded.sessions[0].files, 3)
        XCTAssertEqual(decoded.sessions[0].bytes, 2048)
        XCTAssertEqual(decoded.totalBytes, 2560)
    }

    func testSpawnResponseDecodesBackupArchive() throws {
        // backup 回执比体检两端点多带 archive 产物路径
        let json = #"{"ok": true, "pid": 42, "name": "backup", "archive": "/opt/data/backups/hermes-backup-2026-11-19-231535-3f18c0b1.zip"}"#
        let decoded = try JSONDecoder().decode(
            OpsSpawnResponse.self, from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.name, "backup")
        XCTAssertEqual(
            decoded.archive,
            "/opt/data/backups/hermes-backup-2026-11-19-231535-3f18c0b1.zip"
        )
    }

    // MARK: - backup 三态判读（探活真实形态）

    private let archivePath =
        "/opt/data/backups/hermes-backup-2026-11-19-231535-3f18c0b1.zip"
    private let archiveName =
        "hermes-backup-2026-11-19-231535-3f18c0b1.zip"

    func testBackupCleanRun() {
        // 干净轮：无 incomplete 标记、exit 0（CLI 自报
        // 耗时行是探活引用过的原文形态）
        let run = BackupLogParser.parse(
            lines: ["1515 files scanned", "Time: 10.1s"],
            exitCode: 0, archivePath: archivePath
        )
        XCTAssertEqual(run.state, .clean)
        XCTAssertEqual(run.headline, "备份完成")
        XCTAssertEqual(run.archiveName, archiveName)
        XCTAssertNil(run.missingFileCount)
    }

    func testBackupIncompleteNineFilesIsAttentionNotFailure() {
        // 探活实调轮：缺 9 文件、exit 1——常态尾巴，
        // 判失败就是天天误报
        let run = BackupLogParser.parse(
            lines: [
                "Backup incomplete",
                "Archive kept, but 9 file(s) could not be added",
            ],
            exitCode: 1, archivePath: archivePath
        )
        XCTAssertEqual(run.state, .attention)
        XCTAssertEqual(run.missingFileCount, 9)
        XCTAssertEqual(run.headline, "已备份，有 9 个文件没纳入")
        XCTAssertEqual(run.archiveName, archiveName)
    }

    func testBackupIncompleteSevenFilesIsAttention() {
        // 服务器修掉 memories 两文件后的复跑轮：缺 7
        let run = BackupLogParser.parse(
            lines: [
                "Backup incomplete",
                "Archive kept, but 7 file(s) could not be added",
            ],
            exitCode: 1, archivePath: archivePath
        )
        XCTAssertEqual(run.state, .attention)
        XCTAssertEqual(run.missingFileCount, 7)
        XCTAssertEqual(run.headline, "已备份，有 7 个文件没纳入")
    }

    func testBackupIncompleteWithoutCountStillAttention() {
        let run = BackupLogParser.parse(
            lines: ["Backup incomplete", "Archive kept"],
            exitCode: 1, archivePath: archivePath
        )
        XCTAssertEqual(run.state, .attention)
        XCTAssertNil(run.missingFileCount)
        XCTAssertEqual(run.headline, "已备份，有几个文件没纳入")
    }

    func testBackupMarkersTrumpExitCode() {
        // exit 在此组不可直接用：就算回 0，incomplete
        // 标记在就是注意档
        let run = BackupLogParser.parse(
            lines: [
                "Backup incomplete",
                "Archive kept, but 3 file(s) could not be added",
            ],
            exitCode: 0, archivePath: archivePath
        )
        XCTAssertEqual(run.state, .attention)
        XCTAssertEqual(run.missingFileCount, 3)
    }

    func testBackupFailedWithoutProduct() {
        // 无产物、无保留标记、exit 非 0 → 失败
        let run = BackupLogParser.parse(
            lines: ["Error: unable to write archive"],
            exitCode: 1, archivePath: nil
        )
        XCTAssertEqual(run.state, .failed)
        XCTAssertEqual(run.headline, "备份没成功")
        XCTAssertNil(run.archiveName)
    }

    func testBackupIncompleteWithoutProductIsFailure() {
        // 只有 incomplete 一词、产物证据全无 → 不许
        // 冒充已备份
        let run = BackupLogParser.parse(
            lines: ["Backup incomplete"],
            exitCode: 1, archivePath: nil
        )
        XCTAssertEqual(run.state, .failed)
    }

    // MARK: - 留痕往返与新鲜度

    func testBackupRecordCodableRoundTrip() throws {
        let record = BackupRecord(
            date: Date(timeIntervalSince1970: 1_763_000_000),
            serverBase: "https://example.test",
            archiveName: archiveName,
            state: .attention, missingFileCount: 9
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            BackupRecord.self, from: data
        )
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.headline, "已备份，有 9 个文件没纳入")
        // 留痕只存判读摘要：不许出现原始日志字样
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("could not be added"))
        XCTAssertFalse(text.contains("lines"))
    }

    func testBackupFreshnessWindow() {
        let now = Date(timeIntervalSince1970: 1_763_000_000)
        let fresh = BackupRecord(
            date: now.addingTimeInterval(-6 * 24 * 3600),
            serverBase: "https://example.test", state: .clean
        )
        XCTAssertTrue(fresh.isFresh(now: now))
        let stale = BackupRecord(
            date: now.addingTimeInterval(-8 * 24 * 3600),
            serverBase: "https://example.test", state: .clean
        )
        XCTAssertFalse(stale.isFresh(now: now))
    }

    // MARK: - 升级前检查单判断

    private let now = Date(timeIntervalSince1970: 1_763_000_000)

    private func freshBackup() -> BackupRecord {
        BackupRecord(
            date: now.addingTimeInterval(-3600),
            serverBase: "https://example.test",
            archiveName: archiveName, state: .clean
        )
    }

    private func healthSummary() -> HealthCheckSummary {
        HealthCheckSummary(
            date: now, serverBase: "https://example.test",
            doctor: HealthGroupSummary(
                verdict: .ok, headline: "自检通过",
                passCount: 36, warnCount: 0, failCount: 0
            ),
            audit: nil
        )
    }

    func testReadinessNeedsBackupFirst() {
        let judge = ArchiveReadinessJudge.judge(
            backup: nil, health: healthSummary(), now: now
        )
        XCTAssertFalse(judge.ready)
        XCTAssertTrue(judge.headline.contains("先做一次备份"))
    }

    func testReadinessRejectsStaleBackup() {
        let stale = BackupRecord(
            date: now.addingTimeInterval(-8 * 24 * 3600),
            serverBase: "https://example.test", state: .clean
        )
        let judge = ArchiveReadinessJudge.judge(
            backup: stale, health: healthSummary(), now: now
        )
        XCTAssertFalse(judge.ready)
        XCTAssertTrue(judge.headline.contains("超过 7 天"))
    }

    func testReadinessSuggestsHealthCheckWhenBackupFresh() {
        let judge = ArchiveReadinessJudge.judge(
            backup: freshBackup(), health: nil, now: now
        )
        XCTAssertFalse(judge.ready)
        XCTAssertTrue(judge.headline.contains("体检"))
    }

    func testReadinessReadyWithFreshBackupAndHealth() {
        let judge = ArchiveReadinessJudge.judge(
            backup: freshBackup(), health: healthSummary(),
            now: now
        )
        XCTAssertTrue(judge.ready)
        XCTAssertTrue(judge.headline.contains("可以升级"))
    }
}
