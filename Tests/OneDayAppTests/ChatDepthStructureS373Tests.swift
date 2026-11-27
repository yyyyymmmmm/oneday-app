import XCTest

/// §373 结构钉测：0.50.92/0.50.93 真机启动闪退二轮——
/// ChatView 视图类型嵌套总深度贴悬崖（反射实测
/// bottomBar 深度 52/长 37,379、inputBar 42/28,357、
/// composerCard 35/25,874），§371 单点迁层只把元数据
/// 递归耗尽点往深挪一格（bottomBar→composerCard）。
/// 修法＝三段子树提取为独立 View 结构体（ChatBottom-
/// BarViews.swift）＋ChatView 侧薄组装函数经 AnyView
/// 擦除边界交付子条，修后同口径实测 body 深度
/// 17/11/20、结构体类型本身深度 0（§373.4）。本钉测
/// 在源码层把守提取形态：防后人把三段再内联回
/// ChatView 时无声复发；元数据递归崩实验室不可运行
/// 复现（§373.5），行为终判归真机门。
final class ChatDepthStructureS373Tests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let srcURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: srcURL, encoding: .utf8)
    }

    func testBottomBarStackExtractedAsStandaloneStructs() throws {
        let bar = try source(
            "Sources/OneDayApp/ChatBottomBarViews.swift"
        )
        for decl in [
            "struct ChatBottomBarView: View",
            "struct ChatInputBarView: View",
            "struct ChatComposerCardView: View",
        ] {
            XCTAssertTrue(
                bar.contains(decl),
                "§373：\(decl) 应在 ChatBottomBarViews.swift 内"
            )
        }
        // 三段各有自有 body（非转发壳）
        XCTAssertEqual(
            bar.components(separatedBy: "var body: some View")
                .count - 1,
            3,
            "§373：三结构体应各有自有 body"
        )
    }

    func testChatViewNoLongerInlinesTheStack() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainSrc = try source("Sources/OneDayApp/ChatView.swift")
        let sendSrc = try source("Sources/OneDayApp/ChatView+SendAndOutbox.swift")
        let overlaysSrc = try source("Sources/OneDayApp/ChatView+OverlaysAndModifiers.swift")
        let headerSrc = try source("Sources/OneDayApp/ChatView+HeaderAndActions.swift")
        let src = mainSrc + "\n" + sendSrc + "\n" + overlaysSrc + "\n" + headerSrc
        XCTAssertFalse(
            src.contains("private var inputBar: some View"),
            "§373：inputBar 不许再作 ChatView 内联成员"
        )
        XCTAssertFalse(
            src.contains("private var composerCard: some View"),
            "§373：composerCard 不许再作 ChatView 内联成员"
        )
        XCTAssertTrue(
            src.contains("ChatBottomBarView("),
            "§373：ChatView 组装函数应构造 ChatBottomBarView"
        )
        XCTAssertTrue(
            src.contains("func chatSurfacePresentation"),
            "§373：chatSurface 链中段辅助函数应在位"
        )
        XCTAssertTrue(
            src.contains("func chatSurfaceLifecycle"),
            "§373：chatSurface 链尾段辅助函数应在位"
        )
    }
}
