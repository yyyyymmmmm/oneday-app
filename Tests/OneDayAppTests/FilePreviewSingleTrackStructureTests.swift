import XCTest
@testable import OneDayApp
import OneDayCore

/// §380 结构钉测：文件预览 QuickLook 单轨的形态
/// 把守——①§271 退役的自研阅读轨符号零回潮；
/// ②QLPreviewController 构造点只许两处（共用组
/// 件 QuickLookPreview＋例外 E2 设备工具呈现
/// 桥）；③盒文件预览资格门＋分享兜底在场（R1）；
/// ④设备工具 preview 资格门在场（R2）
final class FilePreviewSingleTrackStructureTests: XCTestCase {

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

    /// 代码行视图：剔除整行注释——历史 prose 提
    /// 及退役名不在禁列，禁的是代码本体回潮
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

    /// ①退役阅读轨符号零残留
    func testRetiredReaderSymbolsAbsentFromSources() throws {
        let banned = [
            "DocumentReaderView",
            "SpreadsheetReaderView",
            "BridgeSpreadsheet",
            "opensInReader",
            "isSpreadsheet",
        ]
        for url in allSourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = codeLines(text)
            for token in banned {
                XCTAssertFalse(
                    code.contains(token),
                    "\(url.lastPathComponent) 出现退役符号 \(token)"
                )
            }
        }
    }

    /// ②QLPreviewController 构造点只许两处文件
    func testQLPreviewControllerConstructionSitesAreOnlyTwo() throws {
        var sites: Set<String> = []
        for url in allSourceFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            if codeLines(text).contains("QLPreviewController()") {
                sites.insert(url.lastPathComponent)
            }
        }
        XCTAssertEqual(
            sites,
            ["RichContentViews.swift", "DeviceEverydayExecutors.swift"],
            "QL 构造点漂移：\(sites)"
        )
    }

    /// ③盒文件资格门＋分享兜底在场（R1）
    func testBoxPreviewHasQualificationGateAndShareFallback() throws {
        let text = try source("Sources/OneDayApp/BoxFilesView.swift")
        XCTAssertTrue(
            text.contains("item.canPreview"),
            "DataFilePreviewView 缺 QL 资格门"
        )
        XCTAssertTrue(
            text.contains("unsupportedData"),
            "DataFilePreviewView 缺不支持预览态"
        )
        XCTAssertTrue(
            text.contains("FileShareSheet"),
            "DataFilePreviewView 缺分享/保存兜底"
        )
    }

    /// ④设备工具 preview 资格门在场（R2）
    func testDevicePreviewHasQualificationGate() throws {
        let text = try source(
            "Sources/OneDayApp/DeviceEverydayExecutors.swift"
        )
        XCTAssertTrue(
            text.contains("QLPreviewController.canPreview"),
            "FilePresenceEngine.preview 缺 QL 资格门"
        )
    }
}
