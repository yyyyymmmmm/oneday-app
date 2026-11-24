import XCTest
@testable import OneDayApp
import OneDayCore

/// §374.9 结构钉测：旧承载退役的形态把守——
/// ①gen3/legacy/ComposerGuideHost 三承载的机
/// 构符号在生产源码（代码行，整行注释除外）零
/// 残留、两承载文件不存在、Core 文件已改名；
/// ②跟随链单源：贴底/落定链同名函数在 ChatView
/// 只剩一份定义、chatSurface 只剩原生面单路；
/// ③共用件迁移在场（布局/回调/锚存取/点空白
/// delegate 在 ChatNativeList、舱卡帧键在
/// ChatBottomBarViews）
final class ChatSwapStep6StructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    /// 代码行视图：剔除整行注释（/// 与 //）——
    /// 历史 prose 提及退役名不在禁列，禁的是代
    /// 码本体（类型/属性/函数/开关）回潮
    private func codeLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(
                    in: .whitespaces
                )
                return !t.hasPrefix("///") && !t.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    private func allSourceFiles() -> [URL] {
        var urls: [URL] = []
        for dir in ["Sources/OneDayApp", "Sources/OneDayCore"] {
            let base = repoRoot().appendingPathComponent(dir)
            guard let en = FileManager.default.enumerator(
                at: base,
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let url as URL in en
            where url.pathExtension == "swift" {
                urls.append(url)
            }
        }
        return urls
    }

    /// 禁词普查：三承载机构符号零残留
    func testRetiredCarrierSymbolsAbsentFromSources() throws {
        let banned = [
            "ChatListCarrierView",
            "ChatListCarrierViewController",
            "ChatListCarrierHandle",
            "ChatListCarrierCallbacks",
            "ChatCarrierRow",
            "ChatCarrierLayout",
            "ChatCarrierFeature",
            "ChatCarrierBlankTapDelegate",
            "ChatNativeListFeature",
            "ComposerGuideHost",
            "ComposerGuideHostController",
            "ComposerPassthroughView",
            "gen3CarrierEnabled",
            "nativeListEnabled",
            "carrierListSurface",
            "legacyListSurface",
            "carrierRows",
            "composerBottomSpace",
            "listViewportHeight",
            "keyboardAnchorPending",
            "keyboardFrameSettled",
        ]
        let files = allSourceFiles()
        XCTAssertGreaterThan(
            files.count, 100,
            "源码文件数下限（防普查空过）"
        )
        for url in files {
            let text = try String(
                contentsOf: url, encoding: .utf8
            )
            let code = codeLines(text)
            for token in banned {
                XCTAssertFalse(
                    code.contains(token),
                    "\(url.lastPathComponent) 残留退役符号 \(token)"
                )
            }
        }
        // 文件级存废：两承载文件不存在、Core 已改名
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(
            atPath: repoRoot().appendingPathComponent(
                "Sources/OneDayApp/ChatListCarrier.swift"
            ).path
        ))
        XCTAssertFalse(fm.fileExists(
            atPath: repoRoot().appendingPathComponent(
                "Sources/OneDayApp/ComposerGuideHost.swift"
            ).path
        ))
        XCTAssertTrue(fm.fileExists(
            atPath: repoRoot().appendingPathComponent(
                "Sources/OneDayCore/ChatListCore.swift"
            ).path
        ))
        XCTAssertFalse(fm.fileExists(
            atPath: repoRoot().appendingPathComponent(
                "Sources/OneDayCore/ChatListCarrierCore.swift"
            ).path
        ))
    }

    /// 跟随链单源：同名链函数只剩一份定义、
    /// chatSurface 单路原生面（§409 步 B：
    /// settleStreamFollow 随流式跟随退役出列）
    func testFollowChainSingleSourceInChatView() throws {
        let chatView = codeLines(
            try source("Sources/OneDayApp/ChatView.swift")
        )
        for name in [
            "func scrollToBottom(",
            "func performScrollToBottom(",
            "func evaluateSettleOnEvent(",
            "func evaluateSettleFallback(",
            "func handleSettleStep(",
        ] {
            let count = chatView.components(
                separatedBy: name
            ).count - 1
            XCTAssertEqual(
                count, 1,
                "跟随链函数 \(name) 须单源（实测 \(count) 份）"
            )
        }
        XCTAssertTrue(
            chatView.contains("nativeListSurface"),
            "chatSurface 须出原生面"
        )
        // 键盘解析点在原生控制器在场（§302 收口点）
        let nativeList = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        XCTAssertTrue(
            nativeList.contains("onKeyboardFrameChange"),
            "原生面键盘解析点须在场"
        )
    }

    /// 共用件迁移在场
    func testMigratedSharedTypesPresent() throws {
        let nativeList = try source(
            "Sources/OneDayApp/ChatNativeList.swift"
        )
        for token in [
            "struct ChatNativeLayout",
            "struct ChatNativeListCallbacks",
            "enum ChatListAnchorStore",
            "class ChatNativeBlankTapDelegate",
        ] {
            XCTAssertTrue(
                nativeList.contains(token),
                "迁入件缺席：\(token)"
            )
        }
        let bottomBar = try source(
            "Sources/OneDayApp/ChatBottomBarViews.swift"
        )
        XCTAssertTrue(
            bottomBar.contains("struct ComposerCardFrameKey"),
            "ComposerCardFrameKey 须迁入 ChatBottomBarViews"
        )
        let core = try source(
            "Sources/OneDayCore/ChatListCore.swift"
        )
        XCTAssertTrue(core.contains("ChatListAnchor"))
        XCTAssertFalse(core.contains("ChatCarrierFeature"))
        XCTAssertFalse(core.contains("ChatNativeListFeature"))
    }
}
