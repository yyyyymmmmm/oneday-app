import XCTest
@testable import OneDayApp
import OneDayCore

/// §457 结构钉测：聊天空态收口——中央招呼块
/// （头像＋「和 %@ 聊聊」标题＋「记录只存这台
/// 手机」说明文）整块退役，空态只剩 §455 建
/// 议行一族。①招呼块的视图/行键/量测函数在
/// 生产源码（代码行，整行注释除外）零残留；
/// ②两句招呼文案在生产源码零残留；③建议行
/// （empty-suggestions）仍在场、仍是空态构成
final class EmptyStateTrim457StructureTests: XCTestCase {

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

    /// 代码行视图：剔除整行注释（与 §379 同口径）
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
        for dir in [
            "Sources/OneDayApp", "Sources/OneDayCore",
            "Sources/OneDayDesign",
        ] {
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

    func testGreetingBlockTokensAbsentFromProductionCode()
        throws
    {
        let banned = [
            "emptyStateHero", "\"empty-hero\"",
            "emptyHeroHeight",
            "和 %@ 聊聊", "记录只存这台手机",
        ]
        let files = allSourceFiles()
        XCTAssertFalse(files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = codeLines(text)
            for token in banned {
                XCTAssertFalse(
                    code.contains(token),
                    "\(url.lastPathComponent) 不应再出现 \(token)"
                )
            }
        }
    }

    func testSuggestionsRemainTheEmptyStateContent()
        throws
    {
        let chatView = try codeLines(
            source("Sources/OneDayApp/ChatView.swift")
        )
        XCTAssertTrue(
            chatView.contains("\"empty-suggestions\""),
            "空态建议行应在场"
        )
        XCTAssertTrue(
            chatView.contains("emptyStateSuggestions"),
            "空态建议视图应在场"
        )
    }
}
