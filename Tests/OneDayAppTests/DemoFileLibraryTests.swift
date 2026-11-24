import Foundation
import OneDayCore
import XCTest
@testable import OneDayApp

/// §421 演示模式文件库死面修复钉测（§401.4 缺口一）：
/// 演示态资源库聚合读面自 0.50.60 改走伴生桥单流、
/// 桥无 demo 分支且演示态无桥钥，打开必落「产出目
/// 录没读出来」错误面、重试不恢复（死面）。修法＝
/// collect 在演示态回落演示回执：从 DemoHermesClient
/// files 种子面（2026-11-11 冻结清单「文件种子面」）
/// 装配名单，名单键加演示后缀与真实同址隔离。
/// ①装配：名单非空、冒烟门 A4 期待的三种子卡在位、
///   无目录行、path 不重复；
/// ②分类：文件段（mediaKind == nil）／影音段计数合
///   种子集口径；
/// ③名单店同路：演示键 refresh 结局 .loaded、名单
///   落店；快照只认演示键、真实键播种不串用；
/// ④点文件定义行为：种子文档经演示客户端 fileData
///   （FileOpenView 同路）取回非空；
/// ⑤结构：collect 含演示分叉与演示键后缀（源码钉，
///   防回退走桥死面）。
@MainActor
final class DemoFileLibraryTests: XCTestCase {

    private var tempDir: URL!
    private var snapshotURL: URL {
        tempDir.appendingPathComponent("snapshot.json")
    }

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "demo-lib-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func demoConfig() throws -> ServerConfig {
        try XCTUnwrap(
            ServerConfig(rawInput: "https://hermes.didichou.site")
        )
    }

    private func assemble() async throws -> [Deliverable] {
        try await DeliverablesView.demoDeliverables(
            client: DemoHermesClient(), config: try demoConfig()
        )
    }

    // MARK: - ① 装配名单

    func testDemoAssemblyReturnsSeedFiles() async throws {
        let items = try await assemble()
        XCTAssertFalse(items.isEmpty, "演示名单不得为空集")
        let names = Set(items.map { $0.entry.name })
        for expected in ["网络巡检周报.md", "每日简报-1108.txt", "交付说明.md"] {
            XCTAssertTrue(
                names.contains(expected),
                "冒烟门 A4 期待种子卡「\(expected)」应在演示名单内"
            )
        }
        XCTAssertTrue(
            items.allSatisfy { !$0.entry.isDirectory },
            "演示名单只收文件条目、目录行不入集"
        )
        XCTAssertEqual(
            Set(items.map { $0.entry.path }).count, items.count,
            "演示名单 path 不得重复"
        )
    }

    // MARK: - ② 分类

    func testDemoAssemblyClassification() async throws {
        let items = try await assemble()
        let documents = items.filter { $0.entry.mediaKind == nil }
        let media = items.filter { $0.entry.mediaKind != nil }
        XCTAssertGreaterThanOrEqual(
            documents.count, 4,
            "文件段应含种子文档（巡检周报／每日简报／weekly／交付说明）"
        )
        XCTAssertGreaterThanOrEqual(
            media.count, 10,
            "影音段应含种子影音（图 6／视频 2／音频 2）"
        )
        let documentNames = Set(documents.map { $0.entry.name })
        for expected in ["网络巡检周报.md", "每日简报-1108.txt", "交付说明.md"] {
            XCTAssertTrue(
                documentNames.contains(expected),
                "种子文档「\(expected)」应落文件段"
            )
        }
        let mediaNames = Set(media.map { $0.entry.name })
        XCTAssertTrue(
            mediaNames.contains("生成图-节点拓扑.png"),
            "种子生成图应落影音段"
        )
    }

    // MARK: - ③ 名单店同路＋键隔离

    func testDemoRefreshLoadsStoreAndSnapshotKeyIsIsolated()
        async throws
    {
        let demoKey = "https://hermes.didichou.site#demo"
        let store = LibraryListStore(snapshotFileURL: snapshotURL)
        let outcome = await store.refresh(
            currentConfigKey: demoKey
        ) {
            try await self.assemble()
        }
        XCTAssertEqual(outcome, .loaded, "演示对账应成功落店")
        let expectedCount = try await assemble().count
        XCTAssertEqual(
            store.deliverables?.count, expectedCount,
            "店内名单应与装配名单等量"
        )

        // 快照只认演示键：真实同址键播种不得串用
        let realKeyStore = LibraryListStore(
            snapshotFileURL: snapshotURL
        )
        realKeyStore.seedFromSnapshotIfNeeded(
            currentConfigKey: "https://hermes.didichou.site"
        )
        XCTAssertNil(
            realKeyStore.deliverables,
            "演示种子快照不得被真实键播种串用"
        )
        let demoKeyStore = LibraryListStore(
            snapshotFileURL: snapshotURL
        )
        demoKeyStore.seedFromSnapshotIfNeeded(
            currentConfigKey: demoKey
        )
        XCTAssertEqual(
            demoKeyStore.deliverables?.count,
            store.deliverables?.count,
            "演示键应能以自己的快照播种"
        )
    }

    // MARK: - ④ 点文件定义行为

    func testDemoSeedFileDataIsDefined() async throws {
        let client = DemoHermesClient()
        let config = try demoConfig()
        let markdown = try await client.fileData(
            config: config,
            path: "/opt/data/cache/documents/网络巡检周报.md"
        )
        XCTAssertFalse(markdown.isEmpty, "种子文档打开应有演示回执")
        let text = try await client.fileData(
            config: config,
            path: "/opt/data/cron/output/每日简报-1108.txt"
        )
        XCTAssertFalse(text.isEmpty, "种子简报打开应有演示回执")
    }

    // MARK: - ⑤ 结构钉（视图接线）

    func testCollectDemoWiringPins() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/OneDayApp/DeliverablesView.swift"
            )
        let src = try String(contentsOf: srcURL, encoding: .utf8)
        XCTAssertTrue(
            src.contains("Self.demoDeliverables("),
            "§421：collect 演示态应回落演示装配、不走桥死面"
        )
        XCTAssertTrue(
            src.contains("\"#demo\""),
            "§421：演示名单键应加 #demo 后缀与真实同址隔离"
        )
    }
}
