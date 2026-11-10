import OneDayCore
import XCTest

/// 听写 tap 喂入盒（0.36.11，DESIGN-V4 §76）：本盒的
/// 全部意义就是「在实时音频线程被调用」——结构钉子：
/// nonisolated 终类、状态只经锁盒。本组测试以真机闪
/// 退的同形调用面（任意后台队列并发调用、detached
/// 任务调用）行使它：盒若带任何 actor 隔离，这组调
/// 用形态正是入口断言的触发面，测试层先于真机暴露。
final class DictationTapFeedBoxTests: XCTestCase {

    /// 并发队列 256 次喂入：计数一笔不差、末帧电平可读
    func testIngestFromConcurrentQueues() {
        let box = DictationAudioFeedBox()
        DispatchQueue.concurrentPerform(iterations: 256) { index in
            box.ingest(samples: [Float(index % 5) * 0.1, -0.2, 0.05])
            _ = box.latestRMS
        }
        XCTAssertEqual(box.ingestedBufferCount, 256)
        XCTAssertGreaterThanOrEqual(box.latestRMS, 0)
    }

    /// detached 任务（无任何 actor 上下文）里喂入大声
    /// 样本：RMS 应为 1.0（±1.0 满幅方波）
    func testIngestFromDetachedTask() async {
        let box = DictationAudioFeedBox()
        await Task.detached {
            box.ingest(samples: [1.0, -1.0, 1.0, -1.0])
        }.value
        XCTAssertEqual(box.ingestedBufferCount, 1)
        XCTAssertEqual(box.latestRMS, 1.0, accuracy: 0.0001)
    }

    /// 空样本喂入不崩、电平归零、计数照记
    func testIngestEmptySamples() {
        let box = DictationAudioFeedBox()
        box.ingest(samples: [])
        XCTAssertEqual(box.ingestedBufferCount, 1)
        XCTAssertEqual(box.latestRMS, 0)
    }

    /// reset 后电平与计数双清
    func testResetClearsState() {
        let box = DictationAudioFeedBox()
        box.ingest(samples: [0.5, -0.5])
        box.reset()
        XCTAssertEqual(box.latestRMS, 0)
        XCTAssertEqual(box.ingestedBufferCount, 0)
    }
}
