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
    /// 共用件落点数与 §431 落码清单一致（45 起、随版本增至 47；§476 组版改钉：§470 网关页新增「用量」行用共用件 +1，46→47，归因亲验；§493 改钉：StatusView 整页退役 −3，47→44，归因亲验；§503 改钉：外观页 Menu 行共用件 menuRowLabel 新增一落点 +1，44→45，归因亲验）
    func testAccessoryChevronsUnifiedIntoComponent() throws {
        let all = try allSourceText()
        // 2026-11-25 三轮合并改钉（归因亲验）：1954e437 的
        // GoalDetailView 改版在「进展对话」行直写一处 chevron.right，1→2
        XCTAssertEqual(
            count(of: "Image(systemName: \"chevron.right\")", in: all), 2)
        XCTAssertEqual(
            count(of: "Image(systemName: \"chevron.up.chevron.down\")", in: all), 0)
        // 2026-11-25 合并改钉（归因亲验）：all-8-issues 波次
        // 改版四面收编直写行——外观页 −2、CronViews −2、
        // CronBlueprintViews −1、EnvVarsView −1，45→39
        // 2026-11-25 二轮合并改钉（归因亲验）：e66acd1d 设置
        // 大改版再收两处——GatewayView −1、ServerDetailView −1，39→37
        // 2026-11-25 三轮合并改钉（归因亲验）：1954e437 P1 页
        // 原生 List/Form 化再收六处——GoalDetailView −3、
        // SkillsViews −2、SkillHubViews −1，37→31
        XCTAssertEqual(count(of: "DisclosureChevron(", in: all), 31)
    }

    /// 外观页触点逐点在位（§503 后：主题/模式/形象
    /// 大小三 selection＋形象 impact 沿旧；背景/强调/
    /// 文字/圆角四新点随 §503 分区同落；语言触点随
    /// 语言节迁 LanguageSettingsView、由下一用例钉）
    func testAppearanceHapticPointsPresent() throws {
        let appearance = try fileText("OneDayApp/AppearanceView.swift")
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: chatThemeID)"))
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: appearanceModeRaw)"))
        // 2026-11-25 合并改钉（归因亲验）：all-8-issues 波次
        // 外观页明示移除「虚拟形象大小」与「气泡圆角」两微调
        // 项，avatarSizeRaw／bubbleStyleRaw／avatarMenuTap-
        // Count 三触点随项退役；余下五点在位不变
        XCTAssertFalse(appearance.contains("avatarSizeRaw"))
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: chatBackgroundRaw)"))
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: accentOverrideRaw)"))
        XCTAssertTrue(appearance.contains(
            ".sensoryFeedback(.selection, trigger: chatTextSizeRaw)"))
        XCTAssertFalse(appearance.contains("bubbleStyleRaw"))
        XCTAssertFalse(appearance.contains("appLanguageRaw"))
    }

    /// §503：语言触点随语言节迁出——新页在位、外观
    /// 页不再有语言写口
    func testLanguageHapticPointMoved503() throws {
        let language = try fileText("OneDayApp/LanguageSettingsView.swift")
        XCTAssertTrue(language.contains(
            ".sensoryFeedback(.selection, trigger: appLanguageRaw)"))
        XCTAssertTrue(language.contains("LanguageStorageKeys.appLanguage"))
    }
}
