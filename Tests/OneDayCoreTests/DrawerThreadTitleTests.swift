import OneDayCore
import XCTest

/// 抽屉本地线程显示名解析（0.20.0 第三条）：手改名
/// 优先永不被覆盖；未手改时服务端 AI 标题压过本地
/// 派生快照；无服务端标题回落本地（纯本地线程路径）。
final class DrawerThreadTitleTests: XCTestCase {

    func testManualLocalTitleNeverOverriddenByServer() {
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "我改的名字",
                titleIsManual: true,
                serverTitle: "AI 起的名字"
            ),
            "我改的名字"
        )
    }

    func testServerTitleBeatsDerivedLocalSnapshot() {
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "做一个今日复盘",
                titleIsManual: false,
                serverTitle: "今日工作复盘"
            ),
            "今日工作复盘"
        )
    }

    func testMissingServerTitleFallsBackToLocal() {
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "你好",
                titleIsManual: false,
                serverTitle: nil
            ),
            "你好"
        )
    }

    func testBlankServerTitleFallsBackToLocal() {
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "你好",
                titleIsManual: false,
                serverTitle: "   "
            ),
            "你好"
        )
    }

    func testServerTitleIsTrimmed() {
        XCTAssertEqual(
            DrawerThreadTitle.resolve(
                localTitle: "旧名",
                titleIsManual: false,
                serverTitle: "  新名  "
            ),
            "新名"
        )
    }
}
