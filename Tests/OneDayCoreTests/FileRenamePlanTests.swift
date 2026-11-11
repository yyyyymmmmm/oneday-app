import Foundation
import XCTest
@testable import OneDayCore

/// 改名判定（§131，D8）：新名规整/扩展名保持/目标
/// 路径/组合链上限/同名冲突。执行链在宿主，本表只
/// 钉判定——尤其「超上限不许搬」「冲突不许覆盖」。
final class FileRenamePlanTests: XCTestCase {
    func testNormalizedNameTrims() {
        XCTAssertEqual(
            FileRenamePlan.normalizedName("  新报告.pdf "), "新报告.pdf"
        )
    }

    func testNormalizedNameRejectsIllegal() {
        XCTAssertNil(FileRenamePlan.normalizedName(""))
        XCTAssertNil(FileRenamePlan.normalizedName("   "))
        XCTAssertNil(FileRenamePlan.normalizedName("."))
        XCTAssertNil(FileRenamePlan.normalizedName(".."))
        XCTAssertNil(FileRenamePlan.normalizedName("a/b.md"))
        XCTAssertNil(FileRenamePlan.normalizedName("a\\b.md"))
        XCTAssertNil(FileRenamePlan.normalizedName("a\nb.md"))
    }

    func testKeepsExtension() {
        XCTAssertTrue(
            FileRenamePlan.keepsExtension(
                oldName: "报告.pdf", newName: "月报.PDF"
            )
        )
        XCTAssertFalse(
            FileRenamePlan.keepsExtension(
                oldName: "报告.pdf", newName: "月报.docx"
            )
        )
        XCTAssertFalse(
            FileRenamePlan.keepsExtension(
                oldName: "报告.pdf", newName: "月报"
            )
        )
    }

    func testTargetPathSameDirectory() {
        XCTAssertEqual(
            FileRenamePlan.targetPath(
                currentPath: "/opt/data/cache/documents/报告.pdf",
                newName: "月报.pdf"
            ),
            "/opt/data/cache/documents/月报.pdf"
        )
    }

    func testChainAllowedFollowsUploadLimit() {
        XCTAssertTrue(FileRenamePlan.isChainAllowed(byteCount: 1024))
        XCTAssertFalse(FileRenamePlan.isChainAllowed(byteCount: 0))
        XCTAssertFalse(
            FileRenamePlan.isChainAllowed(
                byteCount: FileBrowserLogic.uploadByteLimit + 1
            )
        )
    }

    func testConflicts() {
        let siblings = ["/opt/data/a.md", "/opt/data/b.md"]
        XCTAssertTrue(
            FileRenamePlan.conflicts(
                targetPath: "/opt/data/b.md",
                currentPath: "/opt/data/a.md",
                siblingPaths: siblings
            )
        )
        XCTAssertFalse(
            FileRenamePlan.conflicts(
                targetPath: "/opt/data/c.md",
                currentPath: "/opt/data/a.md",
                siblingPaths: siblings
            )
        )
        // 改回自己原名不算冲突
        XCTAssertFalse(
            FileRenamePlan.conflicts(
                targetPath: "/opt/data/a.md",
                currentPath: "/opt/data/a.md",
                siblingPaths: siblings
            )
        )
    }
}
