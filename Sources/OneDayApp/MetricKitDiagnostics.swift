import Foundation
import MetricKit
import os

/// 苹果原生 MetricKit 性能与崩溃诊断采集器（零第三方依赖、不外传任何用户内容）：
/// 订阅系统下发的 `MXMetricPayload` 与 `MXDiagnosticPayload`（崩溃、卡顿、CPU/内存异常），
/// 记录到系统 Unified Logging 并持久化最近一份摘要供诊断页查看。
final class MetricKitDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitDiagnostics()

    private let logger = Logger(
        subsystem: "site.didichou.oneday",
        category: "MetricKit"
    )
    private let lock = NSLock()
    private var started = false

    private override init() {
        super.init()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        logger.info("MetricKit subscriber registered")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard started else { return }
        started = false
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        logger.info("Received \(payloads.count, privacy: .public) MetricKit metric payload(s)")
        persistLatestSummary(kind: "metrics", payloads: payloads.map { $0.jsonRepresentation() })
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        logger.warning("Received \(payloads.count, privacy: .public) MetricKit diagnostic payload(s)")
        persistLatestSummary(kind: "diagnostics", payloads: payloads.map { $0.jsonRepresentation() })
    }

    private func persistLatestSummary(kind: String, payloads: [Data]) {
        guard let latest = payloads.last,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let dir = caches.appendingPathComponent("OneDayMetricKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("latest-\(kind).json")
        try? latest.write(to: target, options: .atomic)
    }
}
