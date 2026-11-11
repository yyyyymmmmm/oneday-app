import XCTest
@testable import OneDayCore

/// Store 加载态与错误映射共用定义钉测（§133，复杂
/// 度审计第 10 项）：KanbanStore／LedgerStore 自本
/// 包起共用 StoreLoadState——态形与两口映射（Hermes-
/// Error／OneDayBridgeError）在此钉死，防两 Store 再
/// 各长一套方言。
final class StoreLoadStateTests: XCTestCase {

    // MARK: - HermesError 映射

    func testHermesErrorMapsToFailedWithUserMessage() {
        let error = HermesError.unexpectedStatus(
            endpoint: "kanban", status: 500
        )
        XCTAssertEqual(
            StoreLoadState.failure(for: error),
            .failed(error.userMessage)
        )
    }

    func testHermesErrorTransientAlsoFailed() {
        let error = HermesError.transientNetwork
        XCTAssertEqual(
            StoreLoadState.failure(for: error),
            .failed(error.userMessage)
        )
    }

    // MARK: - 未连接统一落态

    func testNotConnectedIsFailedWithSharedCopy() {
        guard case .failed(let message) = StoreLoadState.notConnected
        else {
            return XCTFail("notConnected 应为 failed 态")
        }
        XCTAssertEqual(message, "尚未连接服务器。")
    }

    // MARK: - OneDayBridgeError 映射

    private func map(
        _ error: OneDayBridgeError
    ) -> StoreLoadState {
        StoreLoadState.from(
            bridgeError: error,
            unavailableMessage: { "不可用:\($0)" },
            recordGoneMessage: "记录已不在回落文案"
        )
    }

    func testBridgeKeyErrorsAreUnavailable() {
        for error in [OneDayBridgeError.noKey, .unauthorized,
                      .bridgeMissing] {
            guard case .unavailable(let message) = map(error)
            else {
                return XCTFail("\(error) 应归 unavailable")
            }
            XCTAssertEqual(message, "不可用:\(error)")
        }
    }

    func testBridgeRecordGoneIsFailedWithFallbackCopy() {
        XCTAssertEqual(
            map(.recordGone),
            .failed("记录已不在回落文案")
        )
    }

    func testBridgeFailedPassesMessageThrough() {
        XCTAssertEqual(
            map(.failed("桥侧人话")),
            .failed("桥侧人话")
        )
    }

    // MARK: - 态形

    func testUnavailableCarriesOptionalMessage() {
        XCTAssertEqual(
            StoreLoadState.unavailable(nil),
            StoreLoadState.unavailable(nil)
        )
        XCTAssertNotEqual(
            StoreLoadState.unavailable(nil),
            StoreLoadState.unavailable("说明")
        )
    }

    func testIsReadyOnlyForReady() {
        XCTAssertTrue(StoreLoadState.ready.isReady)
        XCTAssertFalse(StoreLoadState.loading.isReady)
        XCTAssertFalse(StoreLoadState.unavailable(nil).isReady)
        XCTAssertFalse(StoreLoadState.failed("x").isReady)
    }
}
