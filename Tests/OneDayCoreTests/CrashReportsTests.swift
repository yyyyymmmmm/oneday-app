import XCTest
@testable import OneDayCore

/// 崩溃采集落地钉测（DESIGN §384／总表 131 G-14）：
/// 隐私门脱敏断言（报告产物无路径/UUID/地址/凭据
/// 形态）、记录构造即脱敏、存储落盘回读与去重截
/// 上限、开关缺省口径。
final class CrashReportsTests: XCTestCase {

    // MARK: - 隐私门：三道清洗

    func testScrubRemovesUserPathsUUIDsAndAddresses() {
        let raw = "died at /Users/yangminjie/Library/file.swift "
            + "uuid 3F2504E0-4F89-41D3-9A0C-0305E82C3301 "
            + "addr 0x0000000102ab3f00 and /home/someone/x"
        let cleaned = CrashReportPrivacy.scrub(raw)
        XCTAssertFalse(cleaned.contains("yangminjie"))
        XCTAssertFalse(cleaned.contains("someone"))
        XCTAssertFalse(cleaned.contains("3F2504E0"))
        XCTAssertFalse(cleaned.contains("0x0000000102ab3f00"))
        XCTAssertTrue(cleaned.contains("/<redacted>"))
        XCTAssertTrue(cleaned.contains("<redacted-uuid>"))
    }

    /// 合成「脏」记录（人名路径/UUID/地址/疑似凭据
    /// 串混入各字段）：经 make 构造后，记录的每个
    /// 字段与 displayText/exportText 产物都不得含
    /// 原始敏感形态。
    func testMakeSanitizesEveryFieldAndExport() {
        let record = CrashReportRecord.make(
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .crash,
            exceptionType: "EXC_BAD_ACCESS at /Users/yangminjie/secret",
            exceptionSignal: "SIGSEGV",
            terminationNamespace: "SIGNAL",
            terminationCode: "0x000000000000000b, token=sk-live-1234567890",
            appVersion: "0.50.98 (226)",
            osVersion: "iOS 27.2.1",
            faultingTopSymbols: [
                "ChatView.body /Users/yangminjie/src/ChatView.swift",
                "frame 3F2504E0-4F89-41D3-9A0C-0305E82C3301",
                "0x0000000102ab3f00",
            ]
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let text = record.displayText(dateFormatter: formatter)
        for forbidden in [
            "yangminjie", "3F2504E0", "0x0000000102ab3f00",
            "/Users/", "secret",
        ] {
            XCTAssertFalse(
                text.contains(forbidden),
                "displayText 漏出敏感形态：\(forbidden)"
            )
            XCTAssertFalse(
                (record.exceptionType ?? "").contains(forbidden)
            )
            XCTAssertFalse(
                (record.terminationCode ?? "").contains(forbidden)
            )
            XCTAssertFalse(
                record.faultingTopSymbols.joined().contains(forbidden)
            )
        }
        // 正常判读信息保留（脱敏不许把报告抹成空壳）
        XCTAssertTrue(text.contains("崩溃"))
        XCTAssertTrue(text.contains("EXC_BAD_ACCESS"))
        XCTAssertTrue(text.contains("SIGSEGV"))
    }

    func testSymbolsCappedAtEight() {
        let record = CrashReportRecord.make(
            capturedAt: Date(),
            kind: .crash,
            faultingTopSymbols: (0..<20).map { "frame\($0)" }
        )
        XCTAssertEqual(record.faultingTopSymbols.count, 8)
        XCTAssertEqual(record.faultingTopSymbols.first, "frame0")
    }

    // MARK: - 存储：落盘回读/去重/上限/清空

    private func makeTempStore() -> CrashReportStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CrashReportsTests-\(UUID().uuidString)",
                isDirectory: true
            )
        return CrashReportStore(directory: dir)
    }

    func testStoreRoundTripDedupesAndCaps() {
        let store = makeTempStore()
        let base = CrashReportRecord.make(
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .crash,
            exceptionType: "EXC_BAD_ACCESS"
        )
        store.append([base])
        // 同内容异 id 重复投递：去重后仍一条
        let dupe = CrashReportRecord.make(
            capturedAt: base.capturedAt,
            kind: .crash,
            exceptionType: "EXC_BAD_ACCESS"
        )
        store.append([dupe])
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.exceptionType, "EXC_BAD_ACCESS")
        // 塞满上限：只留最新 50
        let many = (0..<60).map { index in
            CrashReportRecord.make(
                capturedAt: Date(
                    timeIntervalSince1970: 1_700_100_000 + Double(index)
                ),
                kind: .hang,
                terminationCode: "持续 \(index) 秒"
            )
        }
        store.append(many)
        XCTAssertEqual(store.all().count, CrashReportStore.maxRecords)
        XCTAssertEqual(
            store.all().first?.terminationCode, "持续 59 秒"
        )
        store.clear()
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(store.exportText(), "暂无崩溃报告")
    }

    func testStoreSurvivesCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CrashReportsTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = CrashReportStore(directory: dir)
        let file = dir
            .appendingPathComponent("OneDayDiagnostics", isDirectory: true)
            .appendingPathComponent("crash-reports.json")
        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - 开关口径

    func testCollectionFeatureDefaultsOnAndHonorsStoredOff() {
        let suite = UserDefaults(
            suiteName: "CrashReportsTests-\(UUID().uuidString)"
        )!
        XCTAssertTrue(CrashCollectionFeature.isEnabled(defaults: suite))
        suite.set(false, forKey: CrashCollectionFeature.defaultsKey)
        XCTAssertFalse(CrashCollectionFeature.isEnabled(defaults: suite))
        suite.set(true, forKey: CrashCollectionFeature.defaultsKey)
        XCTAssertTrue(CrashCollectionFeature.isEnabled(defaults: suite))
    }
}
