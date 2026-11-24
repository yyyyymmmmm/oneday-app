import XCTest
@testable import OneDayApp
import OneDayCore

/// §379 结构钉测：PressFeedbackModifier 组件
/// 治理的形态把守——①自研按压修饰两令牌在生
/// 产源码（代码行，整行注释除外）零残留；
/// ②其按下感知本体 DragGesture(minimumDi-
/// stance: 0) 全仓零残留（§363 定案的杀滚动
/// hazard 不许以任何新壳回潮）；③迁移目标
/// PressableButtonStyle／.odPressable 在场
final class ChatPressFeedbackRetireStructureTests: XCTestCase {

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
    /// 历史 prose 提及不在禁列，禁的是代码本体
    /// 回潮（与 §374.9 结构钉测同口径）
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

    func testRetiredPressFeedbackTokensAbsentFromProductionCode()
        throws
    {
        let banned = [
            "PressFeedbackModifier", "odPressFeedback",
            "DragGesture(minimumDistance: 0",
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

    func testPressableButtonStyleRemainsTheSinglePressCarrier()
        throws
    {
        let components = try codeLines(
            source("Sources/OneDayDesign/Components.swift")
        )
        XCTAssertTrue(
            components.contains("struct PressableButtonStyle"),
            "平台 Button 形态的按压承载应在场"
        )
        XCTAssertTrue(
            components.contains("static var odPressable"),
            ".odPressable 入口应在场"
        )
    }
}
