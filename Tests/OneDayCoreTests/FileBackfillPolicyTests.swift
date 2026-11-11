import Foundation
import XCTest
@testable import OneDayCore

/// 大小回读口径（复杂度清理后单试口径，审计第 6
/// 项）：旧 3 试＋1.5s/4s 退避＋同目录冷却整套退
/// 役——一次露面只查一趟、失败不记账、下次露面再
/// 查。钉死单试形状防宿主把计时重试偷偷加回来。
final class FileBackfillPolicyTests: XCTestCase {
    func testMaxAttemptsPerAppearanceIsOne() {
        XCTAssertEqual(FileBackfillPolicy.maxAttemptsPerAppearance, 1)
    }

    func testAppearanceBudgetIsExactlyTheFirstTry() {
        // 宿主 ensureSize 以 0..<maxAttemptsPerAppearance
        // 为回读趟数：预算必须恰好一趟——首试之外不
        // 许再有任何一趟（无退避、无冷却后重试）
        XCTAssertEqual(
            Array(0..<FileBackfillPolicy.maxAttemptsPerAppearance),
            [0]
        )
    }
}
