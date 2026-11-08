import OneDayCore
import XCTest

/// 服务端翻译层（0.3.7）：平台名/状态词/类别映射的
/// 单一事实源把守——已知值逐项对表，未知类别回落
/// 「其他」不许直出原文，未知状态回落「未知」。
final class ServerLabelsTests: XCTestCase {
    func testPlatformNames() {
        XCTAssertEqual(ServerLabels.platformName("api_server"), "API 接口")
        XCTAssertEqual(ServerLabels.platformName("API_SERVER"), "API 接口")
        XCTAssertEqual(ServerLabels.platformName("dashboard"), "控制台")
        XCTAssertEqual(ServerLabels.platformName("cli"), "命令行")
        XCTAssertEqual(ServerLabels.platformName("cron"), "定时任务")
        // 品牌专名无中文通称，原样保留（内容名不是内部标识）
        XCTAssertEqual(ServerLabels.platformName("telegram"), "telegram")
        XCTAssertEqual(ServerLabels.platformName("discord"), "discord")
    }

    func testPlatformStates() {
        XCTAssertEqual(ServerLabels.platformState("connected"), "已连接")
        XCTAssertEqual(ServerLabels.platformState("disconnected"), "未连接")
        XCTAssertEqual(ServerLabels.platformState("error"), "异常")
        XCTAssertEqual(ServerLabels.platformState("restarting"), "重启中")
        XCTAssertEqual(ServerLabels.platformState("some_new_state"), "未知")
        XCTAssertEqual(ServerLabels.platformState(nil), "未知")
    }

    func testGatewayStates() {
        XCTAssertEqual(ServerLabels.gatewayState("running", running: nil), "运行中")
        XCTAssertEqual(ServerLabels.gatewayState("stopped", running: nil), "已停止")
        XCTAssertEqual(ServerLabels.gatewayState(nil, running: true), "运行中")
        XCTAssertEqual(ServerLabels.gatewayState(nil, running: false), "未运行")
    }

    func testCategoryMapping() {
        XCTAssertEqual(ServerLabels.categoryLabel("llm"), "模型")
        XCTAssertEqual(ServerLabels.categoryLabel("search"), "搜索")
        XCTAssertEqual(ServerLabels.categoryLabel("tools"), "工具")
        XCTAssertEqual(ServerLabels.categoryLabel("research"), "研究")
        XCTAssertEqual(ServerLabels.categoryLabel("coding"), "开发")
        XCTAssertEqual(ServerLabels.categoryLabel(" LLM "), "模型")
    }

    /// 未知/缺失类别回落「其他」，原始英文永不透出
    func testUnknownCategoryFallsBack() {
        XCTAssertEqual(
            ServerLabels.categoryLabel("quantum_entanglement"),
            ServerLabels.otherCategory
        )
        XCTAssertEqual(ServerLabels.categoryLabel(nil), ServerLabels.otherCategory)
        XCTAssertEqual(ServerLabels.categoryLabel(""), ServerLabels.otherCategory)
    }

    func testGroupingKeepsOrderAndPinsOtherLast() {
        let items = [
            (name: "a", cat: "quantum"),
            (name: "b", cat: "llm"),
            (name: "c", cat: "search"),
            (name: "d", cat: "llm"),
            (name: "e", cat: nil as String?),
        ]
        let groups = ServerLabels.grouped(items) { $0.cat }
        XCTAssertEqual(groups.map(\.label), ["搜索", "模型", "其他"])
        XCTAssertEqual(groups[1].items.map(\.name), ["b", "d"])
        XCTAssertEqual(groups[2].items.map(\.name), ["a", "e"])
    }

    func testChineseDetection() {
        XCTAssertTrue(ServerLabels.isChineseText("深度求索的密钥"))
        XCTAssertTrue(ServerLabels.isChineseText("DeepSeek 密钥"))
        XCTAssertFalse(ServerLabels.isChineseText("API key for DeepSeek"))
        XCTAssertFalse(ServerLabels.isChineseText(""))
    }
}
