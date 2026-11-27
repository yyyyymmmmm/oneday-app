import XCTest

/// 第 83 条命中域收口钉测（2026-11-15，全局标准审计
/// A 线 3-硬1–3-硬9）：九组漏网面按定版做法「视觉
/// 盘不变＋命中域外扩 44＋负内边距抵消布局」收口。
/// 判据＝源码钉测（照 HapticsMatrixTests 式）：逐面
/// 断言视觉帧原值还在、外扩链（minTapTarget 帧＋
/// Rectangle 命中形＋按视觉值算的负内边距抵消）在
/// 位、旧小命中形（30 圆／36 胶囊）已撤；根令牌视
/// 觉基准（buttonHeight 30／胶囊高 36／minTapTarget
/// 44）一并钉死，防借本包改视觉。
///
/// 行为 rig 撤销记（两轮 CI 实证）：曾试命中路由
/// rig（真窗口＋陷阱层＋hitTest）——单测宿主里
/// window.hitTest 只认平台视图（陷阱层与 .glass 的
/// 平台交互层），纯 SwiftUI 钮（.plain/.odPressable）
/// 连盘心都「落陷阱」，判据在该环境不成立（生产同
/// 式先例的命中行为由 0.23.0 轮真机验证背书，本包
/// 构造与先例逐项同构）。附带实测：.glass 钮平台
/// 玻璃交互层命中面 60×50、本已超 44——枢纽玻璃钮
/// 的外层链按构造声明 44、不依赖此平台宽容。
final class HitArea44Tests: XCTestCase {

    // MARK: - 源码钉测基建（HapticsMatrixTests 同式）

    private func sourcesRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: sources.path, isDirectory: &isDir
        ), isDir.boolValue else {
            throw XCTSkip("源码树在测试环境不可达，钉测跳过")
        }
        return sources
    }

    private func fileText(_ relative: String) throws -> String {
        let url = try sourcesRoot().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8)
        else { throw XCTSkip("\(relative) 不可达，钉测跳过") }
        return text
    }

    /// 锚点间切片（锚点缺失＝钉测对象被改动，直接判红）
    private func segment(
        _ text: String, from start: String, to end: String,
        file: StaticString = #filePath, line: UInt = #line
    ) -> String {
        guard let s = text.range(of: start) else {
            XCTFail("起始锚点缺失：\(start)", file: file, line: line)
            return ""
        }
        guard let e = text.range(
            of: end, range: s.upperBound..<text.endIndex
        ) else {
            XCTFail("结束锚点缺失：\(end)", file: file, line: line)
            return ""
        }
        return String(text[s.lowerBound..<e.upperBound])
    }

    private func assertChain(
        _ seg: String, visual: String, compensation: String,
        _ name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            seg.contains(visual),
            "\(name)：视觉帧原值应保留（\(visual)）",
            file: file, line: line
        )
        XCTAssertTrue(
            seg.contains("OneDayMetrics.minTapTarget"),
            "\(name)：外扩帧（minTapTarget）缺失",
            file: file, line: line
        )
        XCTAssertTrue(
            seg.contains(".contentShape(Rectangle())"),
            "\(name)：外层命中形（Rectangle）缺失",
            file: file, line: line
        )
        XCTAssertTrue(
            seg.contains(compensation),
            "\(name)：负内边距抵消缺失（\(compensation)）",
            file: file, line: line
        )
    }

    // MARK: - ① 逐面钉测

    /// 视觉基准钉死：根令牌与分段胶囊高不许借本包改动
    func testVisualBaselinesUntouched() throws {
        let layout = try fileText("OneDayCore/ComposerLayout.swift")
        XCTAssertTrue(
            layout.contains("buttonHeight: CGFloat = 30"),
            "输入舱视觉盘基准（buttonHeight 30）被改动"
        )
        let palette = try fileText("OneDayDesign/Palette.swift")
        XCTAssertTrue(
            palette.contains("hubSegCapsuleHeight: CGFloat = 36"),
            "枢纽分段胶囊视觉高（36）被改动"
        )
        XCTAssertTrue(
            palette.contains("minTapTarget: CGFloat = 44"),
            "命中域令牌（minTapTarget 44）被改动"
        )
    }

    /// 3-硬1 输入舱三钮（发送/停止变形键、麦克风、附件＋）
    func testComposerButtonsExpanded() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try fileText("OneDayApp/ChatView.swift")
        let sendChat = try fileText("OneDayApp/ChatView+SendAndOutbox.swift")
        let chat = mainChat + "\n" + sendChat
        let compensation =
            "ComposerLayout.buttonHeight) / 2"
        let send = segment(
            chat, from: "private var sendStopButton",
            to: "停止生成\" : \"发送\")"
        )
        assertChain(
            send, visual: "Palette.primaryPale, in: Circle())",
            compensation: compensation, "发送/停止键"
        )
        let mic = segment(
            chat, from: "private var micButton",
            to: ".accessibilityLabel(\"语音输入\")"
        )
        assertChain(
            mic, visual: "ComposerLayout.buttonHeight",
            compensation: compensation, "麦克风键"
        )
        XCTAssertFalse(
            mic.contains(".contentShape(Circle())"),
            "麦克风键：旧 30 圆命中形应被外层矩形取代"
        )
        let attach = segment(
            chat, from: "private var attachButton",
            to: ".accessibilityLabel(\"添加附件\")"
        )
        assertChain(
            attach, visual: "ComposerLayout.buttonHeight",
            compensation: compensation, "附件＋键"
        )
        XCTAssertFalse(
            attach.contains(".contentShape(Circle())"),
            "附件＋键：旧 30 圆命中形应被外层矩形取代"
        )
    }

    /// 3-硬2 听写条三键
    func testDictationBarButtonsExpanded() throws {
        let text = try fileText("OneDayApp/DictationViews.swift")
        let compensation =
            "ComposerLayout.buttonHeight) / 2"
        XCTAssertEqual(
            text.components(separatedBy: compensation).count - 1, 3,
            "听写条三键应各有一处外扩抵消"
        )
        let parts: [(String, String, String)] = [
            ("private var discardButton", "private var stopButton", "丢弃键"),
            ("private var stopButton", "private var sendButton", "停止键"),
            ("private var sendButton", "private var centerCluster", "发送键"),
        ]
        for (start, end, name) in parts {
            let seg = segment(text, from: start, to: end)
            assertChain(
                seg, visual: "ComposerLayout.buttonHeight",
                compensation: compensation, "听写条\(name)"
            )
            XCTAssertFalse(
                seg.contains(".contentShape(Circle())"),
                "听写条\(name)：旧 30 圆命中形应被外层矩形取代"
            )
        }
    }

    /// 3-硬6 听写失败条关闭钮
    func testDictationFailureCloseExpanded() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try fileText("OneDayApp/ChatView.swift")
        let overlaysChat = try fileText("OneDayApp/ChatView+OverlaysAndModifiers.swift")
        let chat = mainChat + "\n" + overlaysChat
        let seg = segment(
            chat, from: "dictation.clearFailure()",
            to: ".accessibilityLabel(\"关闭提示\")"
        )
        assertChain(
            seg, visual: ".frame(width: 24, height: 24)",
            compensation: "OneDayMetrics.minTapTarget - 24) / 2",
            "听写失败条关闭钮"
        )
    }

    /// 3-硬3 文件页头两钮
    func testFilesHeaderButtonsExpanded() throws {
        let files = try fileText("OneDayApp/FilesView.swift")
        let compensation = "OneDayMetrics.minTapTarget - 32) / 2"
        let newFolder = segment(
            files, from: "\"folder.badge.plus\"",
            to: ".accessibilityLabel(\"新建文件夹\")"
        )
        assertChain(
            newFolder, visual: ".frame(width: 32, height: 32)",
            compensation: compensation, "新建文件夹钮"
        )
        let sort = segment(
            files, from: "sortAscending.toggle()",
            to: "当前升序，点按切换为降序"
        )
        assertChain(
            sort, visual: ".frame(width: 32, height: 32)",
            compensation: compensation, "排序切换钮"
        )
    }

    /// 3-硬4 枢纽页头玻璃钮（分享两支＋关闭；编辑笔钮
    /// 基线已有外扩、不在本包范围）
    func testHubHeaderGlassButtonsExpanded() throws {
        let hub = try fileText("OneDayApp/AgentHubView.swift")
        let compensation = "OneDayMetrics.minTapTarget - 36) / 2"
        let share = segment(
            hub, from: "private func shareButton",
            to: "private func header"
        )
        XCTAssertEqual(
            share.components(separatedBy: compensation).count - 1, 2,
            "分享钮两支（名片图/文本回落）应各有一处外扩抵消"
        )
        XCTAssertTrue(
            share.contains(".frame(width: 36, height: 36)"),
            "分享钮：玻璃盘视觉帧（36）应保留"
        )
        let close = segment(
            hub, from: "Image(systemName: \"xmark\")",
            to: ".accessibilityLabel(\"关闭\")"
        )
        assertChain(
            close, visual: ".frame(width: 36, height: 36)",
            compensation: compensation, "枢纽关闭钮"
        )
    }

    /// 3-硬5 枢纽分段条段钮（只扩高、视觉胶囊 36 不变）
    func testHubSegmentHitHeightExpanded() throws {
        let hub = try fileText("OneDayApp/AgentHubView.swift")
        let seg = segment(
            hub, from: "private func segmentPicker",
            to: "OneDayMetrics.hubSegBarHeight"
        )
        XCTAssertTrue(
            seg.contains(".frame(height: OneDayMetrics.minTapTarget)"),
            "分段条：段钮命中高外扩（minTapTarget）缺失"
        )
        XCTAssertTrue(
            seg.contains("OneDayMetrics.hubSegCapsuleHeight) / 2"),
            "分段条：纵向负内边距抵消缺失"
        )
        XCTAssertFalse(
            seg.contains(".contentShape(Capsule())"),
            "分段条：旧 36 胶囊命中形应被外层矩形取代"
        )
    }

    /// 3-硬7 动态帖「来源」钮
    func testFeedSourceButtonExpanded() throws {
        let feed = try fileText("OneDayApp/FeedView.swift")
        let seg = segment(
            feed, from: "sourcesPost = post",
            to: ".accessibilityLabel(\"来源\")"
        )
        assertChain(
            seg, visual: "\"info.circle\"",
            compensation: "OneDayMetrics.minTapTarget - 15) / 2",
            "动态帖来源钮"
        )
    }

    /// 3-硬8 浏览器/电脑状态刷新钮（两面同款）
    func testStatusRefreshButtonsExpanded() throws {
        for file in [
            "OneDayApp/BrowserView.swift",
            "OneDayApp/ComputerView.swift",
        ] {
            let text = try fileText(file)
            let seg = segment(
                text, from: "\"arrow.clockwise\"",
                to: ".accessibilityLabel(\"刷新状态\")"
            )
            assertChain(
                seg, visual: "\"arrow.clockwise\"",
                compensation: "OneDayMetrics.minTapTarget - 14) / 2",
                "\(file) 刷新钮"
            )
        }
    }

    /// 3-硬9 交付物文档行 ⋮ 菜单
    func testDeliverableDocMenuExpanded() throws {
        let text = try fileText("OneDayApp/DeliverablesView.swift")
        let seg = segment(
            text, from: ".frame(width: 40, height: 40)",
            to: ".accessibilityLabel(\"更多操作\")"
        )
        assertChain(
            seg, visual: ".frame(width: 40, height: 40)",
            compensation: "OneDayMetrics.minTapTarget - 40) / 2",
            "交付物文档行 ⋮ 菜单"
        )
    }

}
