import Foundation
import XCTest
@testable import OneDayCore

/// 置顶集纯值表（§127，D8）：切换/改名跟随/删除清
/// 理/序列化往返。语义钉死：纯客户端整理集，不携
/// 带任何服务端状态。
final class FilePinSetTests: XCTestCase {
    func testToggleRoundtrip() {
        var set = FilePinSet()
        XCTAssertFalse(set.contains(path: "/opt/data/a.md"))
        XCTAssertTrue(set.toggle(path: "/opt/data/a.md"))
        XCTAssertTrue(set.contains(path: "/opt/data/a.md"))
        XCTAssertFalse(set.toggle(path: "/opt/data/a.md"))
        XCTAssertFalse(set.contains(path: "/opt/data/a.md"))
    }

    func testSetPinnedIdempotent() {
        var set = FilePinSet()
        set.setPinned(true, path: "/opt/data/a.md")
        set.setPinned(true, path: "/opt/data/a.md")
        XCTAssertEqual(set.paths, ["/opt/data/a.md"])
        set.setPinned(false, path: "/opt/data/a.md")
        set.setPinned(false, path: "/opt/data/a.md")
        XCTAssertTrue(set.paths.isEmpty)
    }

    func testRenamedFollowsNewPath() {
        var set = FilePinSet(paths: ["/opt/data/旧.md", "/opt/data/b.md"])
        set.renamed(from: "/opt/data/旧.md", to: "/opt/data/新.md")
        XCTAssertEqual(
            set.paths, ["/opt/data/新.md", "/opt/data/b.md"]
        )
    }

    func testRenamedUnpinnedPathNoChange() {
        var set = FilePinSet(paths: ["/opt/data/b.md"])
        set.renamed(from: "/opt/data/x.md", to: "/opt/data/y.md")
        XCTAssertEqual(set.paths, ["/opt/data/b.md"])
    }

    func testRenamedSamePathNoChange() {
        var set = FilePinSet(paths: ["/opt/data/a.md"])
        set.renamed(from: "/opt/data/a.md", to: "/opt/data/a.md")
        XCTAssertEqual(set.paths, ["/opt/data/a.md"])
    }

    func testRemovedClearsPin() {
        var set = FilePinSet(paths: ["/opt/data/a.md"])
        set.removed(path: "/opt/data/a.md")
        XCTAssertTrue(set.paths.isEmpty)
    }

    func testSerializeRoundtrip() {
        let set = FilePinSet(paths: ["/opt/data/b.md", "/opt/data/a.md"])
        XCTAssertEqual(FilePinSet.deserialize(set.serialized()), set)
    }

    func testDeserializeGarbageFallsBackEmpty() {
        XCTAssertEqual(
            FilePinSet.deserialize(Data("junk".utf8)), FilePinSet()
        )
        XCTAssertEqual(FilePinSet.deserialize(nil), FilePinSet())
    }
}
