import XCTest
@testable import OneDayApp
import OneDayCore

/// §393（台账 165）结构钉测：智能体成包三件的形
/// 态把守——防回退成 P10「只展示路径/只收手填路
/// 径」的伪成包：①导出面有真下载落库＋分享 ②导
/// 入面选包走 DocumentPickerView（.fileImporter
/// 退役口径不复活）、选中即真解包读清单 ③装包链
/// 在宿主（上传→回读→导入）且本地包库文件在场
final class ProfilePackageStructureTests: XCTestCase {

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

    /// 代码行视图：剔除整行注释（同 §374.9 口径）
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

    func testExportSheetDownloadsAndShares() throws {
        let code = codeLines(
            try source("Sources/OneDayApp/ProfilesView.swift")
        )
        XCTAssertTrue(
            code.contains("client.fileData("),
            "导出面须经文件面 download 端点取包字节"
        )
        XCTAssertTrue(
            code.contains("AgentPackageLibrary.save("),
            "下载的包须落本地包库"
        )
        XCTAssertTrue(
            code.contains("ShareLink(item: downloadedURL)"),
            "落库后须给系统分享/存文件出口"
        )
    }

    func testImportSheetRealPackageFlow() throws {
        let code = codeLines(
            try source("Sources/OneDayApp/ProfilesView.swift")
        )
        XCTAssertTrue(
            code.contains("DocumentPickerView("),
            "选包须走 DocumentPickerView 状态旗路"
        )
        XCTAssertFalse(
            code.contains(".fileImporter"),
            ".fileImporter 已退役（§317），不许复活"
        )
        XCTAssertTrue(
            code.contains("ProfilePackage.manifest(tarGz:"),
            "选中包须真解包读清单，不许只靠文件名猜"
        )
        XCTAssertTrue(
            code.contains("ProfilePackage.importNameVerdict("),
            "导入名须过 Core 校验（default/同名先拦）"
        )
    }

    func testInstallChainLivesInHost() throws {
        let code = codeLines(
            try source("Sources/OneDayApp/ProfilesView.swift")
        )
        XCTAssertTrue(
            code.contains("func installLocalPackage("),
            "装包链（上传→回读→导入）须在宿主在场"
        )
        XCTAssertTrue(
            code.contains("client.uploadFile("),
            "装包上传走文件面既有端点"
        )
        XCTAssertTrue(
            code.contains("client.importProfile("),
            "装包末段走既有导入端点"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repoRoot().appendingPathComponent(
                    "Sources/OneDayApp/AgentPackageLibrary.swift"
                ).path
            ),
            "本地包库文件须在场"
        )
    }
}
