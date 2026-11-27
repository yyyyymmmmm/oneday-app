import Foundation
import XCTest

/// §371 结构钉测：0.50.92 真机启动闪退（§354 同病）——
/// §366 的抽屉运动窗记账处理器原挂 chatScaffold 根链，
/// 一层 .onChange 包裹整棵 scaffold 类型、真机首帧解析
/// ChatView 底部栏组合视图类型元数据时递归爆栈。修法＝
/// 迁至 chatSurface 子树链尾（§354.2 #1 同构）。元数据
/// 递归崩在实验室无法以运行复现（模拟器栈深与真机不
/// 同、§354.1 在案），本钉测在源码层把守迁位形态：防
/// 根链再增此包裹层时无声复发；行为终判归真机门
/// （§371.4）。
final class ChatRootChainStructureS371Tests: XCTestCase {

    private func chatViewSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OneDayApp")

        // #37 模块化拆分后 ChatView 分布在主文件和扩展中，合并读取
        let mainURL = srcRoot.appendingPathComponent("ChatView.swift")
        let overlaysURL = srcRoot.appendingPathComponent("ChatView+OverlaysAndModifiers.swift")
        let headerURL = srcRoot.appendingPathComponent("ChatView+HeaderAndActions.swift")
        let sendURL = srcRoot.appendingPathComponent("ChatView+SendAndOutbox.swift")

        var combined = try String(contentsOf: mainURL, encoding: .utf8)
        combined += "\n" + (try String(contentsOf: overlaysURL, encoding: .utf8))
        combined += "\n" + (try String(contentsOf: headerURL, encoding: .utf8))
        combined += "\n" + (try String(contentsOf: sendURL, encoding: .utf8))

        return combined
    }

    private func segment(
        _ src: String, from startMarker: String, to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(
            src.range(of: startMarker),
            "找不到段起点 \(startMarker)"
        )
        let end = try XCTUnwrap(
            src.range(
                of: endMarker,
                range: start.upperBound..<src.endIndex
            ),
            "找不到段终点 \(endMarker)"
        )
        return String(src[start.lowerBound..<end.lowerBound])
    }

    func testDrawerMotionHandlerLivesOnlyInChatSurfaceTail() throws {
        let src = try chatViewSource()
        let needle = "onChange(of: appState.router.drawerPresented)"
        XCTAssertEqual(
            src.components(separatedBy: needle).count - 1, 1,
            "§371：drawerPresented 处理器全文件应恰一处"
        )
        let scaffold = try segment(
            src,
            from: "private var chatScaffold",
            to: "private var chatSurface"
        )
        XCTAssertFalse(
            scaffold.contains(needle),
            "§371：chatScaffold 根链不许再挂 drawerPresented "
                + "包裹层（0.50.92 闪退定罪，§354 同病）"
        )
        let surface = try segment(
            src,
            from: "private var chatSurface",
            to: "private var overviewStatusWord"
        )
        XCTAssertEqual(
            surface.components(separatedBy: needle).count - 1, 1,
            "§371：处理器应位于 chatSurface 子树链内恰一处"
        )
        // 链尾落点：处理器在 .task(id: currentThreadID) 之后
        let taskIdx = try XCTUnwrap(
            surface.range(of: ".task(id: currentThreadID)"),
            "chatSurface 链尾 .task 不在位"
        )
        let handlerIdx = try XCTUnwrap(
            surface.range(of: needle),
            "chatSurface 链内找不到处理器"
        )
        XCTAssertTrue(
            handlerIdx.lowerBound > taskIdx.lowerBound,
            "§371：处理器应挂在 chatSurface 链尾（.task 之后）"
        )
        // 行为式把守：写入式与窗终点算法在位（§366 行为不许丢）
        XCTAssertTrue(
            surface.contains("nativeHandle.drawerMotionDeadline"),
            "§371：句柄写入不许丢"
        )
        XCTAssertTrue(
            surface.contains("DrawerSpringTiming.response"),
            "§371：窗终点弹簧口径不许丢"
        )
    }
}
