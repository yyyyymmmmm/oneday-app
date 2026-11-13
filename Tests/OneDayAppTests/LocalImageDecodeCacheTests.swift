import UIKit
import XCTest
@testable import OneDayApp

/// §199：本地图解码缓存——同（条目，图序，数据）
/// 第二遍零重解码、异键各自解码、坏图不入缓存
final class LocalImageDecodeCacheTests: XCTestCase {

    func testSecondLookupDoesNotRedecode() {
        var decodes = 0
        let cache = LocalImageDecodeCache(decode: { _ in
            decodes += 1
            return UIImage()
        })
        let entryID = UUID()
        let data = Data([0x1, 0x2, 0x3])

        let first = cache.image(entryID: entryID, index: 0, data: data)
        let second = cache.image(entryID: entryID, index: 0, data: data)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "命中应直取同一已解码图")
        XCTAssertEqual(decodes, 1, "同键第二遍不许重解码")
        XCTAssertEqual(cache.decodeCount, 1)

        // 图序不同＝另一张图，各自解码
        _ = cache.image(entryID: entryID, index: 1, data: data)
        XCTAssertEqual(decodes, 2)
        // 条目不同＝各自解码
        _ = cache.image(entryID: UUID(), index: 0, data: data)
        XCTAssertEqual(decodes, 3)
    }

    func testFailedDecodeIsNotCached() {
        var decodes = 0
        let cache = LocalImageDecodeCache(decode: { _ in
            decodes += 1
            return nil
        })
        let entryID = UUID()
        let data = Data([0x9])
        XCTAssertNil(cache.image(entryID: entryID, index: 0, data: data))
        XCTAssertNil(cache.image(entryID: entryID, index: 0, data: data))
        XCTAssertEqual(decodes, 2, "坏图不入缓存、逐遍重试（旧口径）")
    }
}
