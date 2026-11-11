import OneDayCore
import XCTest

/// 贴底单一所有者（§132，DESIGN-V4 §132）：一次发
/// 送连发 3–5 次强制跳底是发送空屏的成因链之一——
/// 本组钉死收口契约：复贴全局只挂一笔、至多消费一
/// 次；同帧重复请求合并；过期代号不得消费新复贴；
/// 切线程作废一切在途状态
final class BottomStickTests: XCTestCase {

    func testFirstRequestPerformsWithGenerationOne() {
        var coordinator = BottomStickCoordinator()
        XCTAssertEqual(
            coordinator.requestStick(at: 100),
            .perform(generation: 1)
        )
        XCTAssertEqual(coordinator.generation, 1)
    }

    func testDuplicateWithinWindowCoalesces() {
        var coordinator = BottomStickCoordinator()
        _ = coordinator.requestStick(at: 100)
        // 合并窗内（<50ms）的第二路请求不再执行即时
        // 贴——落点由挂账复贴在 120ms 处校正
        XCTAssertEqual(
            coordinator.requestStick(at: 100.03), .coalesced
        )
        XCTAssertEqual(
            coordinator.requestStick(at: 100.049), .coalesced
        )
        // 合并请求不推进代号（不顶替挂账复贴）
        XCTAssertEqual(coordinator.generation, 1)
    }

    func testRequestAfterWindowPerformsAndSupersedes() {
        var coordinator = BottomStickCoordinator()
        _ = coordinator.requestStick(at: 100)
        XCTAssertEqual(
            coordinator.requestStick(at: 100.06),
            .perform(generation: 2)
        )
        // 旧代号的复贴已被顶替：过期消费拒绝
        XCTAssertFalse(coordinator.consumeRestick(generation: 1))
        // 新代号复贴可消费、且只此一次
        XCTAssertTrue(coordinator.consumeRestick(generation: 2))
        XCTAssertFalse(coordinator.consumeRestick(generation: 2))
    }

    func testRestickConsumedAtMostOnce() {
        var coordinator = BottomStickCoordinator()
        _ = coordinator.requestStick(at: 0)
        XCTAssertTrue(coordinator.consumeRestick(generation: 1))
        XCTAssertFalse(coordinator.consumeRestick(generation: 1))
    }

    func testCoalescedRequestKeepsArmedRestick() {
        var coordinator = BottomStickCoordinator()
        _ = coordinator.requestStick(at: 0)
        XCTAssertEqual(
            coordinator.requestStick(at: 0.02), .coalesced
        )
        // 合并后挂账复贴仍属第一代、可正常消费
        XCTAssertTrue(coordinator.consumeRestick(generation: 1))
    }

    func testPerformAfterRestickConsumedIsNotCoalesced() {
        var coordinator = BottomStickCoordinator()
        _ = coordinator.requestStick(at: 0)
        _ = coordinator.consumeRestick(generation: 1)
        // 复贴已消费、无挂账可依托：窗内新请求也必须
        // 执行即时贴，不许合并掉
        XCTAssertEqual(
            coordinator.requestStick(at: 0.02),
            .perform(generation: 2)
        )
    }

    func testInvalidateKillsPendingRestickAndWindow() {
        var coordinator = BottomStickCoordinator()
        _ = coordinator.requestStick(at: 0)
        coordinator.invalidate()
        // 在途复贴作废
        XCTAssertFalse(coordinator.consumeRestick(generation: 1))
        // 合并窗重置：紧接着的新请求立即执行
        guard case .perform = coordinator.requestStick(at: 0.01)
        else {
            return XCTFail("invalidate 后首请求应执行即时贴")
        }
    }
}
