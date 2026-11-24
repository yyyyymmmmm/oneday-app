import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §361（流畅度专项 S1／探活报告 H1）钉测：ChatEntry
/// 图片全集与远端路径的解码缓存（与 toolCard §135 同
/// 制：源数据本体为失效键、内容变即键变）。
/// ① 等价：三属性对修前无缓存算法（本文件参考实现逐
///    字复刻修前语义）在输入矩阵下逐值相等——行高
///    facet 摘要只消费这三属性的值，故属性等价即摘
///    要等价；
/// ② 失效：源字段变更后重解、新值生效；源不变重复
///    读恒同值（第二读走缓存命中路）；
/// ③ 摘要稳定：带图 user 行的 entryMemoKey 重复求值
///    逐字不变（缓存不扰动备忘键）；
/// ④ 量测（实验室口径、同机自校准）：800KB 图行重
///    复访问——修前原语（每趟全量 JSON 解码）对修后
///    （首趟入缓存、后续趟源比对），断言修后整段成
///    本显著低于修前；绝对值 print 留档，真机绝对值
///    以探活报告第四节补测为准。
@MainActor
final class ImageDecodeCacheS1Tests: XCTestCase {

    // MARK: - 参考实现（修前语义逐字复刻）

    private func referenceAllImageDatas(
        imageDatasData: Data?, imageData: Data?
    ) -> [Data] {
        if let imageDatasData,
           let decoded = try? JSONDecoder().decode(
               [Data].self, from: imageDatasData
           ), !decoded.isEmpty {
            return decoded
        }
        if let imageData { return [imageData] }
        return []
    }

    private func referencePaths(_ data: Data?) -> [String] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(
            [String].self, from: data
        )) ?? []
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        try! JSONEncoder().encode(value)
    }

    private func makeEntry() -> ChatEntry {
        ChatEntry(role: "user", content: "带图行", thread: nil)
    }

    // MARK: - ① allImageDatas 等价矩阵

    func testAllImageDatasMatchesReferenceAcrossMatrix() {
        let a = Data(repeating: 0xA1, count: 1_024)
        let b = Data(repeating: 0xB2, count: 2_048)
        let fallback = Data(repeating: 0xF0, count: 512)
        let corrupt = Data("not-json".utf8)
        let cases: [(Data?, Data?)] = [
            (nil, nil),
            (nil, fallback),
            (encode([a, b]), a),
            (encode([a]), fallback),
            (corrupt, fallback),
            (corrupt, nil),
            (encode([Data]()), fallback),
            (encode([Data]()), nil),
        ]
        for (index, pair) in cases.enumerated() {
            let entry = makeEntry()
            entry.imageDatasData = pair.0
            entry.imageData = pair.1
            let expected = referenceAllImageDatas(
                imageDatasData: pair.0, imageData: pair.1
            )
            XCTAssertEqual(
                entry.allImageDatas, expected,
                "用例 \(index) 首读须与修前算法逐值相等"
            )
            XCTAssertEqual(
                entry.allImageDatas, expected,
                "用例 \(index) 再读（缓存命中路）须逐值相等"
            )
        }
    }

    // MARK: - ② allImageDatas 失效口径

    func testAllImageDatasInvalidatesOnSourceChange() {
        let a = Data(repeating: 0xA1, count: 100)
        let b = Data(repeating: 0xB2, count: 200)
        let c = Data(repeating: 0xC3, count: 300)
        let entry = makeEntry()
        entry.imageDatasData = encode([a])
        entry.imageData = a
        XCTAssertEqual(entry.allImageDatas, [a])
        // 全集换内容 → 键变重解
        entry.imageDatasData = encode([b, c])
        XCTAssertEqual(entry.allImageDatas, [b, c])
        // 全集撤掉 → 回落单图
        entry.imageDatasData = nil
        XCTAssertEqual(entry.allImageDatas, [a])
        // 单图换内容 → 新值生效
        entry.imageData = c
        XCTAssertEqual(entry.allImageDatas, [c])
        // 全清 → 空集
        entry.imageData = nil
        XCTAssertEqual(entry.allImageDatas, [])
    }

    // MARK: - ①② 远端路径两属性等价＋失效

    func testRemotePathsMatchReferenceAndInvalidate() {
        let entry = makeEntry()
        let images = ["/data/a.png", "/data/b.png"]
        let files = ["/data/report.xlsx"]
        let corrupt = Data("nope".utf8)

        entry.remoteImagePathsData = nil
        entry.remoteFilePathsData = nil
        XCTAssertEqual(entry.remoteImagePaths, referencePaths(nil))
        XCTAssertEqual(entry.remoteFilePaths, referencePaths(nil))

        entry.remoteImagePathsData = encode(images)
        entry.remoteFilePathsData = encode(files)
        XCTAssertEqual(entry.remoteImagePaths, images)
        XCTAssertEqual(entry.remoteImagePaths, images)
        XCTAssertEqual(entry.remoteFilePaths, files)
        XCTAssertEqual(entry.remoteFilePaths, files)

        entry.remoteImagePathsData = corrupt
        entry.remoteFilePathsData = corrupt
        XCTAssertEqual(entry.remoteImagePaths, [])
        XCTAssertEqual(entry.remoteFilePaths, [])

        entry.remoteImagePathsData = encode(["/data/c.png"])
        XCTAssertEqual(entry.remoteImagePaths, ["/data/c.png"])
    }

    // MARK: - ③ facet 摘要（备忘键）稳定性

    private func makeComposer() -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ChatRowStateLedger(),
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    func testMemoKeyStableForImageRowAcrossPasses() {
        let composer = makeComposer()
        let entry = ChatEntry(
            role: "user", content: "看这张图", thread: nil,
            imageDatas: [Data(repeating: 0xD1, count: 4_096)],
            remoteFilePaths: ["/opt/data/report.xlsx"]
        )
        let first = composer.entryMemoKey(
            for: entry, dividerText: nil
        )
        for _ in 0..<5 {
            XCTAssertEqual(
                composer.entryMemoKey(for: entry, dividerText: nil),
                first,
                "同条目重复趟备忘键须逐字不变（缓存不扰动摘要）"
            )
        }
        // 有图行与无图行的键须可区分（li 段在场性）
        let plain = ChatEntry(
            role: "user", content: "看这张图", thread: nil
        )
        XCTAssertNotEqual(
            composer.entryMemoKey(for: plain, dividerText: nil),
            first
        )
    }

    // MARK: - ④ 量测：重复趟解码成本（同机自校准）

    func testRepeatedPassDecodeCostCollapses() {
        let big = Data(repeating: 0xC1, count: 800_000)
        let small = Data(repeating: 0xC2, count: 200_000)
        let entry = ChatEntry(
            role: "user", content: "带图行", thread: nil,
            imageDatas: [big, small]
        )
        let blob = try! XCTUnwrap(entry.imageDatasData)
        let passes = 20
        var sink = 0

        // 修前原语：每趟全量解码（修前 allImageDatas 算法本体）
        let beforeStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<passes {
            let decoded = try? JSONDecoder().decode(
                [Data].self, from: blob
            )
            sink += decoded?.count ?? 0
        }
        let beforeNs = DispatchTime.now().uptimeNanoseconds
            - beforeStart

        // 修后冷读：新条目首趟（一次真解码入缓存）
        let coldEntry = ChatEntry(
            role: "user", content: "带图行", thread: nil,
            imageDatas: [big, small]
        )
        let coldStart = DispatchTime.now().uptimeNanoseconds
        sink += coldEntry.allImageDatas.count
        let coldNs = DispatchTime.now().uptimeNanoseconds
            - coldStart

        // 修后稳态：同条目重复趟（源比对命中、零解码）
        _ = entry.allImageDatas
        let afterStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<passes {
            sink += entry.allImageDatas.count
        }
        let afterNs = DispatchTime.now().uptimeNanoseconds
            - afterStart

        XCTAssertGreaterThan(sink, 0)
        print(
            "S1 量测（实验室口径）：修前 \(passes) 趟全量解码 "
                + "\(beforeNs / 1_000)µs；修后冷读 1 趟 "
                + "\(coldNs / 1_000)µs；修后稳态 \(passes) 趟 "
                + "\(afterNs / 1_000)µs"
        )
        XCTAssertLessThan(
            afterNs, beforeNs / 3,
            "修后稳态 \(passes) 趟成本须显著低于修前全量解码"
                + "（修前 \(beforeNs)ns vs 修后 \(afterNs)ns）"
        )
    }
}
