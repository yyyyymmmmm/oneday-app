import XCTest
@testable import OneDayCore

/// 文件页菜单选项模型钉测（样式二期 S2-04/S2-05）：
/// 两页的单选菜单改系统 Picker 承载后，勾由系统按
/// selection 绘制——本组钉的是喂给 Picker 的选择口
/// 径：文件页 v2 的落盘原值经 resolved 解析（命中回
/// 本身、未知/空/缺失回落默认档），任一输入下解析
/// 结果恒是清单内恰一项（恰一勾、不错挂，同
/// ModelMenuSelection 口径）；服务器文件页的选项集
/// 本身（次序/文案/rawValue）在此钉住，视图层
/// Picker 直接消费 allCases，不许另立清单。
final class LibraryMenuResolutionTests: XCTestCase {

    // MARK: - 显示模式（S2-04 组1）

    func testDisplayModeResolvedRoundTrips() {
        for mode in LibraryDisplayMode.allCases {
            XCTAssertEqual(
                LibraryDisplayMode.resolved(rawValue: mode.rawValue),
                mode
            )
        }
    }

    func testDisplayModeResolvedFallback() {
        XCTAssertEqual(
            LibraryDisplayMode.resolved(rawValue: nil), .list
        )
        XCTAssertEqual(
            LibraryDisplayMode.resolved(rawValue: ""), .list
        )
        XCTAssertEqual(
            LibraryDisplayMode.resolved(rawValue: "mosaic"), .list
        )
    }

    // MARK: - 资料库排序（S2-04 组2）

    func testLibrarySortResolvedRoundTrips() {
        for option in LibrarySort.allCases {
            XCTAssertEqual(
                LibrarySort.resolved(rawValue: option.rawValue),
                option
            )
        }
    }

    func testLibrarySortResolvedFallback() {
        XCTAssertEqual(
            LibrarySort.resolved(rawValue: nil), .lastOpened
        )
        XCTAssertEqual(
            LibrarySort.resolved(rawValue: ""), .lastOpened
        )
        XCTAssertEqual(
            LibrarySort.resolved(rawValue: "bySize"), .lastOpened
        )
    }

    /// 恰一勾不变量：任意落盘原值（含损坏值）解析后
    /// 恒命中清单内恰一项——菜单不可能零勾或双勾
    func testResolvedAlwaysExactlyOneCheck() {
        let raws: [String?] = [
            nil, "", "list", "grid", "lastOpened",
            "lastModified", "title", "bogus",
        ]
        for raw in raws {
            let mode = LibraryDisplayMode.resolved(rawValue: raw)
            XCTAssertEqual(
                LibraryDisplayMode.allCases
                    .filter { $0 == mode }.count,
                1
            )
            let option = LibrarySort.resolved(rawValue: raw)
            XCTAssertEqual(
                LibrarySort.allCases
                    .filter { $0 == option }.count,
                1
            )
        }
    }

    // MARK: - 服务器文件页排序选项集（S2-05）

    func testServerSortKeyOptionModel() {
        XCTAssertEqual(
            FileBrowserLogic.SortKey.allCases,
            [.name, .modified, .size]
        )
        XCTAssertEqual(
            FileBrowserLogic.SortKey.allCases.map(\.label),
            ["名称", "修改时间", "大小"]
        )
        // rawValue 互不相同：Picker 的 tag 不许撞
        XCTAssertEqual(
            Set(FileBrowserLogic.SortKey.allCases.map(\.rawValue))
                .count,
            FileBrowserLogic.SortKey.allCases.count
        )
    }
}
