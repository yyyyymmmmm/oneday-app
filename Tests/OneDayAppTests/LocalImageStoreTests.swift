import UIKit
import XCTest
@testable import OneDayApp

/// §418（前身 §199 LocalImageDecodeCacheTests，断言
/// 口径不变、观测点换 LocalImageStore）：本地图解码
/// 口——同（条目，图序，数据）第二遍零重解码、异键
/// 各自解码、坏图不入缓存。解码产物现入 Nuke 本地
/// 管线缓存（合成键），身份断言（===）验缓存直取同
/// 一已解码图。
final class LocalImageStoreTests: XCTestCase {

    func testSecondLookupDoesNotRedecode() {
        var decodes = 0
        let store = LocalImageStore(decode: { _ in
            decodes += 1
            return UIImage()
        })
        let entryID = UUID()
        let data = Data([0x1, 0x2, 0x3])

        let first = store.image(entryID: entryID, index: 0, data: data)
        let second = store.image(entryID: entryID, index: 0, data: data)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "命中应直取同一已解码图")
        XCTAssertEqual(decodes, 1, "同键第二遍不许重解码")
        XCTAssertEqual(store.decodeCount, 1)

        // 图序不同＝另一张图，各自解码
        _ = store.image(entryID: entryID, index: 1, data: data)
        XCTAssertEqual(decodes, 2)
        // 条目不同＝各自解码
        _ = store.image(entryID: UUID(), index: 0, data: data)
        XCTAssertEqual(decodes, 3)
    }

    func testFailedDecodeIsNotCached() {
        var decodes = 0
        let store = LocalImageStore(decode: { _ in
            decodes += 1
            return nil
        })
        let entryID = UUID()
        let data = Data([0x9])
        XCTAssertNil(store.image(entryID: entryID, index: 0, data: data))
        XCTAssertNil(store.image(entryID: entryID, index: 0, data: data))
        XCTAssertEqual(decodes, 2, "坏图不入缓存、逐遍重试（旧口径）")
    }
}
