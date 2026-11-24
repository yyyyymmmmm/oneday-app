import XCTest
@testable import OneDayApp

/// §430（量测包 3，工单单执行者纪律）夹具：
/// 同一工单任一时刻只许一个执行者——量测台队列
/// 与 measureNow 直执互斥。
///
/// 场景 A（并发重叠）：工单已被队列执行、闭包被
/// 栅栏堵在执行中途时，measureNow 不许把同一闭
/// 包在主线程再跑一次（旧码：第二执行者进入、
/// 双执行同刻重叠——204455.ips 崩②的高度疑似
/// 土壤）；新码：measureNow 回 nil（无确定高、
/// 等 finish 的高度-only 修正）、全程只执行一次。
/// 场景 B（排队抢先）：工单已投队列但排在积压
/// 后未执行时，measureNow 认领同步量出；队列随
/// 后不许重复执行同一工单（旧码：队列再跑一次、
/// 执行计数 2）。
/// 场景 C（(a)/(b) 定夺数据，非红绿门）：积压
/// 队列下目标行的就绪延迟——纯 (a) 等队列轮到
/// vs (b) measureNow 同步认领，两数打印供 §430
/// 定夺记账。
@MainActor
final class RowMeasureSingleExec430Tests: XCTestCase {

    /// 执行记账盒：全部读写走锁口（不重蹈
    /// DeskTests 脚手架「锁写＋裸读」的 TSan
    /// access race 覆辙）
    private final class ExecutionLedger: @unchecked Sendable {
        private let lock = NSLock()
        private var entries = 0
        private var current = 0
        private var maxConcurrent = 0

        func enter() {
            lock.lock()
            entries += 1
            current += 1
            maxConcurrent = max(maxConcurrent, current)
            lock.unlock()
        }

        func exit() {
            lock.lock()
            current -= 1
            lock.unlock()
        }

        func entriesSnapshot() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }

        func maxConcurrentSnapshot() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return maxConcurrent
        }
    }

    /// 真挂起轮询（Task.sleep 让出 MainActor，
    /// 不许同步自旋——失败包 drain 钉教训）
    private func waitUntil(
        timeout: TimeInterval,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(
                nanoseconds: 20_000_000
            )
        }
        return condition()
    }

    // MARK: - 场景 A：队列执行中，measureNow 不许重入

    func testSingleExec_queueExecuting_measureNowDoesNotReenter() async {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "se430-a-\(suffix)"
        let rowKey = "se430-a-row-\(suffix)"
        let ledger = ExecutionLedger()
        let gate = DispatchSemaphore(value: 0)
        let job = ChatNativeRowMeasureJob(
            memoKey: memoKey, rowKey: rowKey
        ) {
            ledger.enter()
            // 栅栏堵住执行者：放行前一直「执行中」
            _ = gate.wait(timeout: .now() + 10)
            ledger.exit()
            return 88
        }
        desk.collect(job)
        desk.flushCollected()
        let entered = await waitUntil(timeout: 5) {
            ledger.entriesSnapshot() >= 1
        }
        XCTAssertTrue(
            entered, "队列侧工单须先进入执行（栅栏堵住中）"
        )
        // 放行兜底：0.6s 后连发两记 signal——旧码
        // 下两个执行者各需一记放行才不至久冻主线
        // 程；新码下多余 signal 只是滞留计数、无害
        DispatchQueue.global().asyncAfter(
            deadline: .now() + 0.6
        ) {
            gate.signal()
            gate.signal()
        }
        let measured = desk.measureNow(rowKey: rowKey)
        XCTAssertNil(
            measured,
            "工单正在队列执行时 measureNow 不许直执同一"
                + "闭包——回 nil 等 finish 的高度-only 修正"
        )
        XCTAssertEqual(
            ledger.entriesSnapshot(), 1,
            "同一工单只许一个执行者进入"
        )
        XCTAssertEqual(
            ledger.maxConcurrentSnapshot(), 1,
            "同一工单不许双执行者同刻重叠"
        )
        // 放行队列那份并等对账完成
        gate.signal()
        let filled = await waitUntil(timeout: 5) {
            ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: memoKey) == 88
        }
        XCTAssertTrue(filled, "队列执行完须回填缓存")
        let hit = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(hit.height, 88)
        XCTAssertTrue(hit.isExact)
        XCTAssertEqual(
            ledger.entriesSnapshot(), 1,
            "全程只许执行一次"
        )
    }

    // MARK: - 场景 B：排队未执行，measureNow 抢先、队列不重复跑

    func testSingleExec_queuedJob_measureNowPreempts_queueDoesNotRerun() async {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        // 堵队列的慢单（栅栏堵住串行队列队首）
        let blockerLedger = ExecutionLedger()
        let blockerGate = DispatchSemaphore(value: 0)
        let blocker = ChatNativeRowMeasureJob(
            memoKey: "se430-b-block-\(suffix)",
            rowKey: "se430-b-block-row-\(suffix)"
        ) {
            blockerLedger.enter()
            _ = blockerGate.wait(timeout: .now() + 10)
            blockerLedger.exit()
            return 66
        }
        desk.collect(blocker)
        desk.flushCollected()
        let blockerIn = await waitUntil(timeout: 5) {
            blockerLedger.entriesSnapshot() >= 1
        }
        XCTAssertTrue(blockerIn, "慢单须先占住队列")
        // 目标单：投递入队——在飞，但排在慢单后未执行
        let ledger = ExecutionLedger()
        let memoKey = "se430-b-\(suffix)"
        let rowKey = "se430-b-row-\(suffix)"
        let target = ChatNativeRowMeasureJob(
            memoKey: memoKey, rowKey: rowKey
        ) {
            ledger.enter()
            ledger.exit()
            return 88
        }
        desk.collect(target)
        desk.flushCollected()
        // 就地量测抢先：同步认领量出确定高
        let measured = desk.measureNow(rowKey: rowKey)
        XCTAssertEqual(
            measured, 88,
            "排队未执行的工单 measureNow 须同步量出确定高"
        )
        XCTAssertEqual(ledger.entriesSnapshot(), 1)
        // 放行慢单，等队列把目标单那份处理完（新
        // 码＝认领失败、复用缓存对账，不再进闭包；
        // 旧码＝再跑一次，计数变 2）
        blockerGate.signal()
        try? await Task.sleep(
            nanoseconds: 1_500_000_000
        )
        XCTAssertEqual(
            ledger.entriesSnapshot(), 1,
            "队列不许重复执行已被 measureNow 量完的工单"
        )
        XCTAssertEqual(
            ledger.maxConcurrentSnapshot(), 1
        )
        XCTAssertEqual(
            ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: memoKey),
            88
        )
    }

    // MARK: - 场景 C：(a)/(b) 就绪延迟定夺数据（非红绿门）

    func testSingleExec_decisionData_backlogLatency() async {
        // 积压构造：24 个各耗 25ms 的桩单占住串行
        // 队列，目标单排队尾。注意投单口径＝逆序
        // （最新先量）：collect 序的最后一单最先投
        // 递——目标单须最先 collect 才排在投递序
        // 的队尾（首轮夹具把此序弄反，(a) 量到队
        // 首延迟、(b) 撞上队列已认领目标单回 nil，
        // 均为夹具构造误、非生产面问题）
        func makeBackloggedDesk(
            suffix: String
        ) -> (
            desk: ChatNativeRowMeasureDesk,
            targetMemo: String, targetRow: String
        ) {
            let desk = ChatNativeRowMeasureDesk()
            let targetMemo = "se430-c-target-\(suffix)"
            let targetRow = "se430-c-target-row-\(suffix)"
            desk.collect(
                ChatNativeRowMeasureJob(
                    memoKey: targetMemo, rowKey: targetRow
                ) {
                    // 单行量测耗时桩（毫秒级，与真实
                    // 单行量测同量级）
                    usleep(5_000)
                    return 88
                }
            )
            for index in 0..<24 {
                desk.collect(
                    ChatNativeRowMeasureJob(
                        memoKey: "se430-c-stub-\(index)-\(suffix)",
                        rowKey: "se430-c-stub-row-\(index)-\(suffix)"
                    ) {
                        usleep(25_000)
                        return 100
                    }
                )
            }
            desk.flushCollected()
            return (desk, targetMemo, targetRow)
        }

        // (a) 纯等待：不调 measureNow，等队列轮到
        // 目标单回填缓存的时刻
        let a = makeBackloggedDesk(
            suffix: "a-\(UUID().uuidString)"
        )
        let startA = Date()
        let readyA = await waitUntil(timeout: 10) {
            ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: a.targetMemo) != nil
        }
        let latencyA = Date().timeIntervalSince(startA)
        XCTAssertTrue(readyA, "(a) 目标行须最终经队列就绪")

        // (b) 认领：同积压下 measureNow 同步就绪
        let b = makeBackloggedDesk(
            suffix: "b-\(UUID().uuidString)"
        )
        let startB = Date()
        let measuredB = b.desk.measureNow(
            rowKey: b.targetRow
        )
        let latencyB = Date().timeIntervalSince(startB)
        XCTAssertEqual(measuredB, 88)

        print(
            "SE430-DECISION (a)纯等待就绪延迟="
                + "\(String(format: "%.3f", latencyA))s "
                + "(b)认领同步就绪延迟="
                + "\(String(format: "%.3f", latencyB))s"
        )
        XCTAssertLessThan(
            latencyB, latencyA,
            "(b) 认领同步就绪须快于 (a) 等队列轮到"
        )
    }
}
