import XCTest

/// §431（2026-11-24 主题对位包）源码钉：行尾披露箭头
/// 收口与外观页触感落点。渲染模式与声明式触感在运
/// 行时无可观测输出，按 HapticsMatrixTests 同法以源
/// 码扫描钉死；源码在测试环境不可达时整套跳过，呈
/// 现与手感终验归真机门（见 DESIGN §431）。
final class ThemeAlign431Tests: XCTestCase {

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
            throw XCTSkip("源码树在测试环境不可达，断言跳过")
        }
        return sources
    }

    private func allSourceText() throws -> String {
        let sources = try sourcesRoot()
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        )
        var chunks: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(
                      contentsOf: url, encoding: .utf8
                  )
            else { continue }
            chunks.append(text)
        }
        guard !chunks.isEmpty else {
            throw XCTSkip("未读到任何源码文件，断言跳过")
        }
        return chunks.joined(separator: "\n")
    }

    private func fileText(_ relative: String) throws -> String {
        let url = try sourcesRoot().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8)
        else { throw XCTSkip("\(relative) 不可达，断言跳过") }
        return text
    }

    private func count(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// 共用件本体必须带参照口径：hierarchical 渲染＋
    /// 系统次级色（采样实证：参照展开箭头渲染
    /// #87878A≈secondaryLabel，见 §431）
    func testDisclosureChevronCarriesReferenceRendering() throws {
        let components = try fileText("OneDayDesign/Components.swift")
        XCTAssertTrue(components.contains("public struct DisclosureChevron"))
        XCTAssertTrue(components.contains(".symbolRenderingMode(.hierarchical)"))
        XCTAssertTrue(components.contains(".foregroundStyle(.secondary)"))
    }

    /// 全仓行尾附件箭头收口：字面量直写只许剩
    /// ChatView 强调色链接箭头一处（Palette.primary、
    /// 非披露附件，§431 登记不收）；上下双箭直写零；
    /// 共用件落点数与 §431 落码清单一致（45 起、随版本增至 47；§476 组版改钉：§470 网关页新增「用量」行用共用件 +1，46→47，归因亲验；§493 改钉：StatusView 整页退役 −3，47→44，归因亲验）
    func testAccessoryChevronsUnifiedIntoComponent() throws {
        let all = try allSourceText()
        XCTAssertEqual(
            count(of: "Image(systemName: \"chevron.right\")", in: all), 1)
        XCTAssertEqual(
            count(of: "Image(systemName: \"chevron.up.chevron.down\")", in: all), 0)
        XCTAssertEqual(count(of: "DisclosureChevron(", in: all), 44)
    }

    /// 外观页五触点逐点在位（四 selection＋一 impact）
    func testAppearanceHapticPointsPresent() throws {
        let appearance = try fileText("OneDayApp/AppearanceView.swift")
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: chatThemeID)"))
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: appearanceModeRaw)"))
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: appLanguageRaw)"))
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: avatarSizeRaw)"))
        XCTAssertTrue(appearance.contains(
            ".impact(weight: .light), trigger: avatarMenuTapCount"))
    }
}
