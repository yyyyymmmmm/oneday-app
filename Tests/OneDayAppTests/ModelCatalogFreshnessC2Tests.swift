import OneDayCore
import XCTest
@testable import OneDayApp

/// §368 模型目录新鲜度门钉测：假客户端（Counting-
/// CatalogClient）逐口计数——三入口同 TTL 窗内触发
/// 只发一轮、并发触发单飞一轮、TTL 过期再拉、配置
/// 键变绕过 TTL、强制口必真拉、写后失效必真拉、两
/// 口全灭不落 stamp。三入口（ChatView .task／模型
/// 设置 load 冷路／聊天页重挂）在产品代码里同走
/// AppState.refreshModelCatalog 冷口，本套件以冷口
/// 连发模拟三入口同窗触发；手动三处走强制口另测。
@MainActor
final class ModelCatalogFreshnessC2Tests: XCTestCase {

    private let catalogKeys = [
        "rawConfig", "models", "modelOptionsRaw", "modelAnalytics"
    ]

    private func makeState(
        recorder: CatalogCallRecorder, delay: Double = 0,
        failCatalog: Bool = false
    ) -> AppState {
        AppState(
            client: CountingCatalogClient(
                recorder: recorder, rawConfigDelay: delay,
                failCatalog: failCatalog
            ),
            demoMode: .connected
        )
    }

    private func assertCounts(
        _ recorder: CatalogCallRecorder,
        _ expected: [String: Int],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for key in catalogKeys {
            XCTAssertEqual(
                recorder.count(key), expected[key] ?? 0,
                "目录口 \(key) 请求数不符", file: file, line: line
            )
        }
    }

    private var oneRound: [String: Int] {
        ["rawConfig": 1, "models": 1, "modelOptionsRaw": 1, "modelAnalytics": 1]
    }

    /// 三入口同窗连发（冷口×3）＝只发一轮 4 口
    func testRepeatedColdTriggersWithinTTLFetchOneRound() async {
        let recorder = CatalogCallRecorder()
        let state = makeState(recorder: recorder)
        await state.refreshModelCatalog()
        await state.refreshModelCatalog()
        await state.refreshModelCatalog()
        assertCounts(recorder, oneRound)
        // 目录落值仍走原消费口径：候选＝options ∪ 用量
        // ∪ 当前（别名集 gw-alias 只作排除）
        XCTAssertEqual(state.availableModels, ["m-a", "m-b"])
        XCTAssertEqual(state.defaultModel, "m-a")
    }

    /// 并发触发单飞：三路同时触发、应答延迟保证重叠
    /// 在飞，仍只发一轮
    func testConcurrentTriggersSingleFlightOneRound() async {
        let recorder = CatalogCallRecorder()
        let state = makeState(recorder: recorder, delay: 0.15)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask { await state.refreshModelCatalog() }
            }
        }
        assertCounts(recorder, oneRound)
    }

    /// TTL 内 0 请求；拨过 TTL 后再触发＝第二轮
    func testTTLExpiryFetchesAgain() async {
        let recorder = CatalogCallRecorder()
        let state = makeState(recorder: recorder)
        await state.refreshModelCatalog()
        assertCounts(recorder, oneRound)
        state.modelCatalogLoadedAt = Date(
            timeIntervalSinceNow: -AppState.modelCatalogTTL - 1
        )
        await state.refreshModelCatalog()
        assertCounts(recorder, [
            "rawConfig": 2, "models": 2,
            "modelOptionsRaw": 2, "modelAnalytics": 2
        ])
    }

    /// 配置键变（换服务器）绕过 TTL：TTL 内也真拉
    func testConfigKeyChangeBypassesTTL() async throws {
        let recorder = CatalogCallRecorder()
        let state = makeState(recorder: recorder)
        await state.refreshModelCatalog()
        assertCounts(recorder, oneRound)
        let other = try XCTUnwrap(
            ServerConfig(rawInput: "https://other.example.com")
        )
        try await state.connectDirect(config: other, apiKey: "k")
        // connectDirect 自身验密钥打了一次 models
        XCTAssertEqual(recorder.count("models"), 2)
        await state.refreshModelCatalog()
        XCTAssertEqual(recorder.count("rawConfig"), 2)
        XCTAssertEqual(recorder.count("modelOptionsRaw"), 2)
        XCTAssertEqual(recorder.count("modelAnalytics"), 2)
        XCTAssertEqual(recorder.count("models"), 3)
        XCTAssertEqual(
            state.modelCatalogLoadedForConfig, other.baseString
        )
    }

    /// 强制口：TTL 内也真拉；拉完冷口回归 0 请求
    func testForcedRefreshBypassesTTL() async {
        let recorder = CatalogCallRecorder()
        let state = makeState(recorder: recorder)
        await state.refreshModelCatalog()
        await state.refreshModelCatalogForced()
        assertCounts(recorder, [
            "rawConfig": 2, "models": 2,
            "modelOptionsRaw": 2, "modelAnalytics": 2
        ])
        await state.refreshModelCatalog()
        assertCounts(recorder, [
            "rawConfig": 2, "models": 2,
            "modelOptionsRaw": 2, "modelAnalytics": 2
        ])
    }

    /// 写后失效：setDefaultModel 写成功后，冷口必真拉
    func testSetDefaultModelInvalidatesCatalog() async throws {
        let recorder = CatalogCallRecorder()
        let state = makeState(recorder: recorder)
        await state.refreshModelCatalog()
        try await state.setDefaultModel("m-b")
        XCTAssertEqual(state.defaultModel, "m-b")
        XCTAssertEqual(recorder.count("updateConfig"), 1)
        // 写路径自身读了一次 rawConfig（整包写回口径）
        XCTAssertEqual(recorder.count("rawConfig"), 2)
        await state.refreshModelCatalog()
        XCTAssertEqual(recorder.count("rawConfig"), 3)
        XCTAssertEqual(recorder.count("modelOptionsRaw"), 2)
        XCTAssertEqual(recorder.count("modelAnalytics"), 2)
        XCTAssertEqual(recorder.count("models"), 2)
    }

    /// 两口全灭不落 stamp：每次触发都重试（失败恢复
    /// 与修前一致），不许被 TTL 吞掉重试
    func testTotalFailureLeavesNoStampAndRetries() async {
        let recorder = CatalogCallRecorder()
        let state = makeState(recorder: recorder, failCatalog: true)
        await state.refreshModelCatalog()
        await state.refreshModelCatalog()
        XCTAssertEqual(recorder.count("rawConfig"), 2)
        XCTAssertEqual(recorder.count("modelOptionsRaw"), 2)
        XCTAssertNil(state.modelCatalogLoadedAt)
    }
}
