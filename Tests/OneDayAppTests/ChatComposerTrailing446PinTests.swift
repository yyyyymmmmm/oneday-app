import XCTest

/// §446 源码钉（照 HitArea44Tests／HapticsMatrixTests
/// 式）：发送舱右端单槽位不变量。背景：§419 双钮态
/// .stopAndSend 在 ComposerBarLayout 的 30pt 槽位
/// 里塞 62pt 双钮（stopMiniButton 30＋spacing 2＋
/// 发送圆盘 30），布局按槽位右锚放置，溢出部分被
/// 推出胶囊与屏幕——0.50.105 真机 verdict 实证：
/// 生成中输入「测试2」，停止钮在槽位、发送钮只剩
/// 半个挂在屏外，点不到、无从入队。挂载环境测不
/// 到 SwiftUI 钮帧（§419 钉头注既有口径），故以
/// 源码钉把守结构面：右端任何状态只许一颗钮、双
/// 钮件不许复活；行为面（四象限判定）由
/// OneDayCoreTests MotionGateTests 把守，真机面
/// 列 §446 真机门。
final class ChatComposerTrailing446PinTests: XCTestCase {

    // MARK: - 源码钉测基建（HitArea44Tests 同式）

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

    // MARK: - 钉一：Core 状态机单槽化＋判定序内容优先

    func testCoreTrailingStateSingleSlot() throws {
        let core = try fileText(
            "OneDayCore/ComposerTrailingState.swift"
        )
        XCTAssertFalse(
            core.contains("stopAndSend"),
            "§446：双钮态 .stopAndSend 必须退役"
                + "（双钮溢出槽位、发送钮被挤出屏幕）"
        )
        let body = segment(
            core, from: "-> ComposerTrailingState {",
            to: "public var isDiscKey"
        )
        let canSendAt = try XCTUnwrap(
            body.range(of: "canSend"), "resolve 本体须读 canSend"
        )
        let streamingAt = try XCTUnwrap(
            body.range(of: "isStreaming"), "resolve 本体须读 isStreaming"
        )
        XCTAssertTrue(
            canSendAt.lowerBound < streamingAt.lowerBound,
            "§446：resolve 判定序必须内容优先"
                + "（canSend 先于 isStreaming）"
        )
    }

    // MARK: - 钉二：ChatView 右端单槽渲染

    func testTrailingControlRendersSingleButton() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try fileText("OneDayApp/ChatView.swift")
        let sendChat = try fileText("OneDayApp/ChatView+SendAndOutbox.swift")
        let chat = mainChat + "\n" + sendChat
        XCTAssertFalse(
            chat.contains("stopMiniButton"),
            "§446：停止小钮 stopMiniButton 必须删除"
                + "（双钮同排是溢出源头）"
        )
        let trailing = segment(
            chat, from: "private var trailingControl",
            to: "private var sendStopButton"
        )
        XCTAssertFalse(
            trailing.contains("HStack"),
            "§446：右端槽位只许单钮，不许 HStack 并排双钮"
        )
        XCTAssertTrue(trailing.contains("sendStopButton"))
        XCTAssertTrue(trailing.contains("micButton"))
    }

    // MARK: - 钉三：圆盘键点按分流（停／发两路俱在）

    /// .stop 态走 requestRunStop 真取消；其余圆盘态
    /// （含流式有字的 .send）走 send()——后者即
    /// §419 入队口（账本在席分支落位待发）
    func testDiscTapRoutesStopOrSend() throws {
        // #37 模块化拆分后 ChatView 分布在多个文件，合并读取
        let mainChat = try fileText("OneDayApp/ChatView.swift")
        let sendChat = try fileText("OneDayApp/ChatView+SendAndOutbox.swift")
        let chat = mainChat + "\n" + sendChat
        let disc = segment(
            chat, from: "private var sendStopButton",
            to: "private var micButton"
        )
        XCTAssertTrue(disc.contains("trailingState == .stop"))
        XCTAssertTrue(disc.contains("requestRunStop()"))
        XCTAssertTrue(disc.contains("send()"))
    }
}
