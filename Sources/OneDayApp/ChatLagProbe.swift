import Foundation
import os

/// 卡顿取证探针（2026-11-20 卡顿修复包）：全面对比
/// 报告（chat-lag-full-comparison-20261120）第四节
/// 取证单的落点——signpost（Instruments 时间线）＋
/// 计数盒（回读）双写，沿 ChatDiagTrace／合成器
/// rowComputationBox 的既有口径：生产路径只记账、
/// 无行为影响；汇总每 600 趟喂入经 ChatDiagTrace
/// 留痕一次，0.50.74 真机跑完经诊断面回读出数。
/// 记账面：①每趟喂入（nativeRows）耗时＋构建/复
/// 用行数，流式期单列（发布拍主线程劳动≈帧时压
/// 力的代理读数，真 CADisplayLink 帧分布不在本
/// 包）；②托管行构建（makeView 闭包求值）耗时；
/// ③远端图解码耗时（已移出主 actor，记的是解码
/// 本体时长、供与旧主线程占用对账）
enum ChatLagProbe {
    private static let signposter = OSSignposter(
        subsystem: "site.didichou.oneday",
        category: "chat-lag"
    )

    struct FeedPassToken {
        let start: ContinuousClock.Instant
        let state: OSSignpostIntervalState
    }

    static func beginFeedPass() -> FeedPassToken {
        FeedPassToken(
            start: .now,
            state: signposter.beginInterval("feed-pass")
        )
    }

    static func endFeedPass(
        _ token: FeedPassToken,
        built: Int, reused: Int, streaming: Bool
    ) {
        signposter.endInterval("feed-pass", token.state)
        box.noteFeed(
            duration: token.start.duration(to: .now),
            built: built, reused: reused,
            streaming: streaming
        )
    }

    /// 托管行构建计时：闭包由 UIHostingConfigura-
    /// tion 在框架求值时调用，本口只包计时、不改
    /// 求值时机与产物
    static func measureHostingBuild<T>(
        _ build: () -> T
    ) -> T {
        let state = signposter.beginInterval(
            "hosting-build"
        )
        let start = ContinuousClock.now
        let value = build()
        signposter.endInterval("hosting-build", state)
        box.noteHosting(
            duration: start.duration(to: .now)
        )
        return value
    }

    static func noteDecode(duration: Duration) {
        box.noteDecode(duration: duration)
    }

    /// 回读汇总（一行）：诊断面与测试共用
    static func summaryLine() -> String {
        box.summaryLine()
    }

    /// 测试读口：清账
    static func reset() {
        box.reset()
    }

    static func milliseconds(
        _ duration: Duration
    ) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1e15
    }

    private static let box = ChatLagProbeBox()
}

/// 探针计数盒（锁盒，与合成器 rowComputationBox
/// 同式）：计数只增、汇总读时成行
private final class ChatLagProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var feedPasses = 0
    private var feedBuilt = 0
    private var feedReused = 0
    private var feedTotalMs = 0.0
    private var feedMaxMs = 0.0
    private var streamPasses = 0
    private var streamTotalMs = 0.0
    private var streamMaxMs = 0.0
    private var streamOver8 = 0
    private var hostingBuilds = 0
    private var hostingTotalMs = 0.0
    private var hostingMaxMs = 0.0
    private var decodeCount = 0
    private var decodeTotalMs = 0.0
    private var decodeMaxMs = 0.0

    func noteFeed(
        duration: Duration, built: Int, reused: Int,
        streaming: Bool
    ) {
        let ms = ChatLagProbe.milliseconds(duration)
        lock.lock()
        feedPasses += 1
        feedBuilt += built
        feedReused += reused
        feedTotalMs += ms
        feedMaxMs = max(feedMaxMs, ms)
        if streaming {
            streamPasses += 1
            streamTotalMs += ms
            streamMaxMs = max(streamMaxMs, ms)
            if ms > 8 { streamOver8 += 1 }
        }
        let shouldFlush = feedPasses % 600 == 0
        lock.unlock()
        if shouldFlush {
            ChatDiagTrace.record(
                "lagprobe \(summaryLine())"
            )
        }
    }

    func noteHosting(duration: Duration) {
        let ms = ChatLagProbe.milliseconds(duration)
        lock.lock()
        hostingBuilds += 1
        hostingTotalMs += ms
        hostingMaxMs = max(hostingMaxMs, ms)
        lock.unlock()
    }

    func noteDecode(duration: Duration) {
        let ms = ChatLagProbe.milliseconds(duration)
        lock.lock()
        decodeCount += 1
        decodeTotalMs += ms
        decodeMaxMs = max(decodeMaxMs, ms)
        lock.unlock()
    }

    func summaryLine() -> String {
        lock.lock()
        defer { lock.unlock() }
        func avg(_ total: Double, _ count: Int) -> Double {
            count > 0 ? total / Double(count) : 0
        }
        return String(
            format: "feed %d趟 建%d 复用%d 均%.2fms 峰%.1fms"
                + "｜流式 %d趟 均%.2fms 峰%.1fms 超8ms %d"
                + "｜托管建 %d次 均%.2fms 峰%.1fms"
                + "｜解码 %d次 均%.1fms 峰%.1fms",
            feedPasses, feedBuilt, feedReused,
            avg(feedTotalMs, feedPasses), feedMaxMs,
            streamPasses,
            avg(streamTotalMs, streamPasses), streamMaxMs,
            streamOver8,
            hostingBuilds,
            avg(hostingTotalMs, hostingBuilds),
            hostingMaxMs,
            decodeCount,
            avg(decodeTotalMs, decodeCount), decodeMaxMs
        )
    }

    func reset() {
        lock.lock()
        feedPasses = 0
        feedBuilt = 0
        feedReused = 0
        feedTotalMs = 0
        feedMaxMs = 0
        streamPasses = 0
        streamTotalMs = 0
        streamMaxMs = 0
        streamOver8 = 0
        hostingBuilds = 0
        hostingTotalMs = 0
        hostingMaxMs = 0
        decodeCount = 0
        decodeTotalMs = 0
        decodeMaxMs = 0
        lock.unlock()
    }
}
