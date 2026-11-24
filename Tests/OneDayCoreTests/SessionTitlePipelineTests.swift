import OneDayCore
import XCTest

/// 标题单管线（第 67 条包二，2026-11-15）Core 钉
/// 测：优先级只此一处实现——本地手改名＞服务端标
/// 题＞本地快照＞首条消息派生＞人话名兜底。钉全序
/// 列逐层压过、本地段旧语义（快照原样直通、空串
/// 不改道派生）、服务端段与 resolvedTitle 旧口径
/// 等值（服务端标题＞派生摘要＞人话名）
final class SessionTitlePipelineTests: XCTestCase {

    private func resolve(
        manual: String? = nil, server: String? = nil,
        snapshot: String? = nil, derived: String? = nil,
        fallback: String = "未命名会话"
    ) -> String {
        SessionTitlePipeline.resolve(
            manualLocalTitle: manual,
            serverTitle: server,
            localSnapshotTitle: snapshot,
            derivedTitle: derived,
            humanFallback: fallback
        )
    }

    func testManualBeatsEverything() {
        XCTAssertEqual(
            resolve(
                manual: "手改名", server: "服务端名",
                snapshot: "快照", derived: "派生"
            ),
            "手改名"
        )
    }

    func testServerBeatsSnapshotAndDerived() {
        XCTAssertEqual(
            resolve(
                server: "服务端名", snapshot: "快照",
                derived: "派生"
            ),
            "服务端名"
        )
    }

    func testSnapshotBeatsDerived() {
        XCTAssertEqual(
            resolve(snapshot: "快照", derived: "派生"),
            "快照"
        )
    }

    func testDerivedBeatsFallback() {
        XCTAssertEqual(
            resolve(derived: "派生"), "派生"
        )
    }

    func testFallbackIsLastResort() {
        XCTAssertEqual(resolve(), "未命名会话")
    }

    /// 本地段旧语义：快照空串也原样直通、不改道派
    /// 生（DrawerThreadTitle 末位回落逐字不变）
    func testEmptySnapshotPassesThroughVerbatim() {
        XCTAssertEqual(
            resolve(snapshot: "", derived: "派生"), ""
        )
    }

    /// 服务端段等值：resolvedTitle 经管线后与旧口
    /// 径逐例一致（有服务端标题／只有首条消息／皆无）
    func testResolvedTitleEquivalence() {
        let zh = Locale(identifier: "zh-Hans")
        let titled = try! JSONDecoder().decode(
            ServerSession.self,
            from: Data(
                "{\"id\":\"s-1\",\"title\":\"服务端标题\"}"
                    .utf8
            )
        )
        XCTAssertEqual(
            titled.resolvedTitle(
                firstUserMessage: "首条消息", locale: zh
            ),
            "服务端标题"
        )
        let untitled = try! JSONDecoder().decode(
            ServerSession.self,
            from: Data("{\"id\":\"s-2\"}".utf8)
        )
        XCTAssertEqual(
            untitled.resolvedTitle(
                firstUserMessage: "首条消息内容", locale: zh
            ),
            "首条消息内容"
        )
        XCTAssertEqual(
            untitled.resolvedTitle(
                firstUserMessage: nil, locale: zh
            ),
            "未命名会话"
        )
    }
}
