import XCTest
@testable import OneDayCore

/// 抽屉底条搜索状态政策闸（§162，抽屉呈现第二
/// 批）：搜索态判定与关抽屉复位两条逐项钉——判
/// 定口径与 0.18.0 沿革一致（修剪后非空），复位
/// 只在开→关一沿触发、重开恒默认态。
final class DrawerSearchPolicyTests: XCTestCase {

    // 判定：空串与纯空白都不是搜索态；实词（含中
    // 文）修剪后非空即搜索态
    func testIsSearching() {
        XCTAssertFalse(DrawerSearchPolicy.isSearching(query: ""))
        XCTAssertFalse(DrawerSearchPolicy.isSearching(query: "   "))
        XCTAssertTrue(DrawerSearchPolicy.isSearching(query: "婚礼"))
        XCTAssertTrue(DrawerSearchPolicy.isSearching(query: " abc "))
    }

    // 规范化：首尾空白修剪、词内不动
    func testNormalizedQuery() {
        XCTAssertEqual(DrawerSearchPolicy.normalizedQuery("  a b "), "a b")
        XCTAssertEqual(DrawerSearchPolicy.normalizedQuery(""), "")
    }

    // 复位沿：只开→关触发；关→开、同态保持不触发
    func testShouldResetQueryOnlyOnDismissEdge() {
        XCTAssertTrue(DrawerSearchPolicy.shouldResetQuery(
            wasPresented: true, isPresented: false
        ))
        XCTAssertFalse(DrawerSearchPolicy.shouldResetQuery(
            wasPresented: false, isPresented: true
        ))
        XCTAssertFalse(DrawerSearchPolicy.shouldResetQuery(
            wasPresented: true, isPresented: true
        ))
        XCTAssertFalse(DrawerSearchPolicy.shouldResetQuery(
            wasPresented: false, isPresented: false
        ))
    }

    // 复位闭环：视图侧复位动作＝触发沿成立时把词
    // 置空——任意起始词经此动作后必出搜索态，重
    // 开抽屉呈全量名单由此构造保证
    func testResetAlwaysLeavesSearchState() {
        for start in ["x", " 婚礼 ", "a b"] {
            var query = start
            XCTAssertTrue(DrawerSearchPolicy.isSearching(query: query))
            if DrawerSearchPolicy.shouldResetQuery(
                wasPresented: true, isPresented: false
            ) {
                query = ""
            }
            XCTAssertFalse(DrawerSearchPolicy.isSearching(query: query))
        }
    }
}
