import XCTest
@testable import OneDayCore

/// 页签落点闸（0.30.0，用户 12:56 录屏讲解 Muse 模
/// 型「页签不与主线同步、点页签回上次对话」）：Chat-
/// LandingResolution 三场景钉死——①进程内当前线程仍
/// 在（页签切走再切回）保持不动②冷启恢复上次线程
/// ③上次线程已不存在回主线；外加无落点与当前失效的
/// 边界。
final class ChatLandingTests: XCTestCase {

    private let main = UUID()
    private let sideA = UUID()
    private let sideB = UUID()
    private let ghost = UUID()

    private var all: [UUID] { [main, sideA, sideB] }

    // MARK: - 场景一：页签切换保持

    func testCurrentThreadKeptAcrossTabReturn() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: sideA, lastThreadID: sideA,
                existingIDs: all, mainThreadID: main
            ),
            .keep(sideA)
        )
    }

    /// 当前线程优先于上次记录（两者不一致时——如刚经
    /// 抽屉切线程、落盘回调尚未跑完的一拍）以当前为准
    func testCurrentWinsOverLastRecord() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: sideB, lastThreadID: sideA,
                existingIDs: all, mainThreadID: main
            ),
            .keep(sideB)
        )
    }

    // MARK: - 场景二：冷启恢复上次线程

    func testColdStartRestoresLastSideThread() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: nil, lastThreadID: sideB,
                existingIDs: all, mainThreadID: main
            ),
            .restore(sideB)
        )
    }

    func testColdStartRestoresMainWhenMainWasLast() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: nil, lastThreadID: main,
                existingIDs: all, mainThreadID: main
            ),
            .restore(main)
        )
    }

    /// 当前 id 已失效（指向已删线程）时不许粘死在它
    /// 身上——落到上次记录继续解析
    func testStaleCurrentFallsThroughToLast() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: ghost, lastThreadID: sideA,
                existingIDs: all, mainThreadID: main
            ),
            .restore(sideA)
        )
    }

    // MARK: - 场景三：上次线程不存在回主线

    func testDeletedLastThreadFallsBackToMain() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: nil, lastThreadID: ghost,
                existingIDs: all, mainThreadID: main
            ),
            .main(main)
        )
    }

    func testNoRecordFallsBackToMain() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: nil, lastThreadID: nil,
                existingIDs: all, mainThreadID: main
            ),
            .main(main)
        )
    }

    // MARK: - 无落点边界

    func testEmptyListHasNoLanding() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: nil, lastThreadID: sideA,
                existingIDs: [], mainThreadID: main
            ),
            .none
        )
    }

    func testMissingMainHasNoLanding() {
        XCTAssertEqual(
            ChatLandingResolution.landing(
                currentID: nil, lastThreadID: nil,
                existingIDs: [sideA], mainThreadID: main
            ),
            .none
        )
    }
}
