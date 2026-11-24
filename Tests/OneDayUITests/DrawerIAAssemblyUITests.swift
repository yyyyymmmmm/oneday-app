import XCTest

/// 台账 194 装配回归钉（UI 测试形态）：0.50.77 真
/// 机报抽屉「点子/动态/目标/资源库不见了、全部对
/// 话/主聊没有归类、顺序不对」——diff 定案：入口
/// 行是结构归位第二批（fc93ea8）在装配层整组退役
/// 的，当时装配层无任何断言钉住入口行集合与分组
/// 归属，CI 全绿照样出包。本套件打 -odDemoMode
/// 真 App 生产装配、按生产汉堡钮开抽屉，读系统
/// AX 按钮树（allElementsBoundByIndex 即树序、与
/// 视觉序同向，DrawerRowContextMenuTests 的失败
/// 取证快照实证），钉：
/// - 入口行全集在场且全序为：选项卡组头→主线聊
///   天→动态→点子→目标→资源库→全部对话→频道组
///   头→旁聊组头（六行被两组头夹住即归类成立）
/// - 折叠态：点「选项卡」组头后组内行退出按钮
///   树、组头与另两组在场；验毕再点一次展开复位
///   （折叠账跨启动持久，不许给后续套件留折叠态）
/// 为何走 UI 测试而非单测：进程内遍历拿不到
/// SwiftUI 生成的 AX 树——本仓 AttachmentPanel-
/// FitAssemblyTests 已实证「本环境 AX 树不填充、
/// 标签集为空集」，194 首版单测两轮 CI 复证（只
/// 采到真 UIKit 的搜索 TextField）；AX 树只在
/// XCUITest 的系统通道下真实填充，故装配钉落本
/// 层。全部对话行标签随系统语言本地化（CI 英文
/// 区域实测 "All conversations"），断言双名兼容
final class DrawerIAAssemblyUITests: XCTestCase {

    private let channelRowID = "drawer.row.channel.hermes"

    /// 钉序标签（全部对话双名归一为 "全部对话"）
    private let pinnedOrder = [
        "选项卡", "主线聊天", "动态", "点子",
        "目标", "资源库", "全部对话", "频道", "旁聊",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDrawerTabGroupAssemblyAndOrder() throws {
        let app = launchDemoApp()
        openDrawer(app)
        let sequence = pinnedSequence(in: app)
        XCTAssertEqual(
            sequence, pinnedOrder,
            "抽屉装配次序/归类不对（台账 194）；"
                + "实测钉序：\(sequence)；全树："
                + treeSnapshot(in: app)
        )
    }

    func testDrawerTabGroupCollapseHidesEntryRows() throws {
        let app = launchDemoApp()
        openDrawer(app)
        let header = app.buttons["选项卡"]
        XCTAssertTrue(
            header.waitForExistence(timeout: 10),
            "选项卡组头未出现；全树：\(treeSnapshot(in: app))"
        )
        header.tap()
        // 组内行退出：以「动态」消失为落定信号（上
        // 限 5 秒轮询），其余行随后一并断言
        let feedRow = app.buttons["动态"]
        let deadline = Date().addingTimeInterval(5)
        while feedRow.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(feedRow.exists, "折叠后「动态」仍在按钮树")
        for label in ["主线聊天", "点子", "目标", "资源库"] {
            XCTAssertFalse(
                app.buttons[label].exists,
                "折叠后「\(label)」仍在按钮树"
            )
        }
        XCTAssertFalse(
            app.buttons["全部对话"].exists
                || app.buttons["All conversations"].exists,
            "折叠后「全部对话」仍在按钮树"
        )
        for label in ["选项卡", "频道", "旁聊"] {
            XCTAssertTrue(
                app.buttons[label].exists,
                "折叠态下组头「\(label)」缺失"
            )
        }
        // 复位：再点组头展开，不给后续套件留折叠账
        header.tap()
        XCTAssertTrue(
            feedRow.waitForExistence(timeout: 5),
            "复位展开后「动态」未回归"
        )
    }

    // MARK: - 工具（开抽屉口径沿 DrawerRowContextMenuTests）

    private func launchDemoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-odDemoMode"]
        app.launch()
        return app
    }

    private func openDrawer(_ app: XCUIApplication) {
        let openButton = app.buttons["drawer.open"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 15),
            "生产抽屉入口未出现"
        )
        if openButton.isHittable {
            openButton.tap()
        }
        let row = app.buttons[channelRowID]
        XCTAssertTrue(
            row.waitForExistence(timeout: 10), "生产抽屉未打开"
        )
    }

    /// 按钮树序过滤出钉序标签（全部对话双名归一）
    private func pinnedSequence(in app: XCUIApplication) -> [String] {
        app.buttons.allElementsBoundByIndex.compactMap { element in
            switch element.label {
            case "全部对话", "All conversations":
                return "全部对话"
            case let label where pinnedOrder.contains(label):
                return label
            default:
                return nil
            }
        }
    }

    /// 失败取证：全树按钮的标识/标签紧凑清单（与
    /// DrawerRowContextMenuTests 同式）
    private func treeSnapshot(in app: XCUIApplication) -> String {
        app.buttons.allElementsBoundByIndex
            .map { "\($0.identifier)|\($0.label)" }
            .joined(separator: ", ")
    }
}
