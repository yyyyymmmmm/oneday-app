import XCTest
@testable import OneDayApp

/// §489 结构钉测（HIG 合规批 A）：四项小改的回潮
/// 把守——①FeedView 帖子展开动画只许走 MotionTokens
/// .resolved 出口（禁字面曲线回潮）；②可调 sheet 两
/// 面（模型选择／点子详情）抓手在场；③fileicon 退役
/// 资产与死件 FileIconImageView 不许回仓；④App 图
/// 标深色／着色变体登记在册（appearances 双值齐全）
final class HigBatchA483Tests: XCTestCase {

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

    /// 代码行视图：剔除整行注释（/// 与 //）——历史
    /// prose 提及不在禁列，禁的是代码本体（§381 先例）
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

    // MARK: - ① P1-01 动画收编

    func testFeedViewAnimationGoesThroughResolvedOutlet() throws {
        let code = codeLines(try source(
            "Sources/OneDayApp/FeedView.swift"
        ))
        XCTAssertTrue(
            code.contains("MotionTokens.resolved("),
            "§489：FeedView 动画必须经 resolved 出口（Reduce Motion 降级）"
        )
        XCTAssertTrue(
            code.contains("MotionTokens.swap"),
            "§489：帖子展开收编 swap 档"
        )
        XCTAssertFalse(
            code.contains("easeInOut(duration"),
            "§489：FeedView 不许再有字面 easeInOut 曲线"
        )
        XCTAssertFalse(
            code.contains("withAnimation(."),
            "§489：FeedView 不许再有字面 withAnimation 曲线"
        )
    }

    // MARK: - ② P1-02 可调 sheet 抓手

    func testResizableSheetsHaveGrabbers() throws {
        let picker = codeLines(try source(
            "Sources/OneDayApp/ChatModelPickerView.swift"
        ))
        XCTAssertTrue(
            picker.contains(".presentationDragIndicator(.visible)"),
            "§489：模型选择 sheet（.medium/.large 可调）必须带抓手"
        )
        let ideas = codeLines(try source(
            "Sources/OneDayApp/IdeasView.swift"
        ))
        XCTAssertTrue(
            ideas.contains(".presentationDragIndicator(.visible)"),
            "§489：点子详情 sheet（§470 双档可调）必须带抓手"
        )
    }

    // MARK: - ③ P2-05 退役资产与死件

    func testRetiredFileiconAssetsStayDeleted() throws {
        let assets = repoRoot().appendingPathComponent(
            "App/Resources/Assets.xcassets"
        )
        let entries = try FileManager.default
            .contentsOfDirectory(atPath: assets.path)
        XCTAssertFalse(
            entries.contains { $0.hasPrefix("fileicon-") },
            "§489：fileicon 退役 PNG 套不许回仓（渲染已由 FileTypeIconView 程序绘制接管）"
        )
        let files = codeLines(try source(
            "Sources/OneDayApp/FilesView.swift"
        ))
        XCTAssertFalse(
            files.contains("struct FileIconImageView"),
            "§489：死件 FileIconImageView（零调用点）不许回潮"
        )
    }

    // MARK: - ④ P2-04 App 图标变体

    func testAppIconHasDarkAndTintedAppearances() throws {
        let jsonText = try source(
            "App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
        )
        let data = Data(jsonText.utf8)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        let images = try XCTUnwrap(root["images"] as? [[String: Any]])
        var values = Set<String>()
        for image in images {
            guard let appearances =
                image["appearances"] as? [[String: Any]] else {
                continue
            }
            for appearance in appearances {
                if let value = appearance["value"] as? String {
                    values.insert(value)
                }
                // 引用的变体文件必须真在盘上
                if let filename = image["filename"] as? String {
                    let url = repoRoot().appendingPathComponent(
                        "App/Resources/Assets.xcassets/AppIcon.appiconset/\(filename)"
                    )
                    XCTAssertTrue(
                        FileManager.default.fileExists(
                            atPath: url.path
                        ),
                        "§489：变体文件缺失 \(filename)"
                    )
                }
            }
        }
        XCTAssertTrue(
            values.contains("dark"),
            "§489：App 图标必须登记深色变体"
        )
        XCTAssertTrue(
            values.contains("tinted"),
            "§489：App 图标必须登记着色变体"
        )
    }
}
