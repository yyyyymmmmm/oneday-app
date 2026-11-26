import Foundation
import MetricKit
import OneDayCore

/// 崩溃与诊断采集端（DESIGN §384／总表 131 G-14）
///
/// 平台通道＝MetricKit：系统把本 App 的崩溃/卡死/
/// CPU/磁盘写诊断在事后（通常下次启动后）以
/// MXDiagnosticPayload 投递，本件只做「载荷→白名
/// 单字段→过隐私门→落 CrashReportStore」一件事。
/// iOS 沙箱内 App 读不到自家 .ips 原文，MetricKit
/// 载荷即其平台等价物（§241.4 的 CI 侧 .ips 提取
/// 只覆盖 CI 崩溃、与本运行时通道分工不同）。
/// 上报面：本机落盘即终点——服务端崩溃端点未立
/// （只登记不动生产），报告经报告面的系统分享由
/// 用户手动外发，不自动上传。
final class CrashDiagnosticsCollector: NSObject, MXMetricManagerSubscriber,
    @unchecked Sendable
{
    static let shared = CrashDiagnosticsCollector()

    private let stateLock = NSLock()
    private var isSubscribed = false

    private override init() { super.init() }

    /// 启动口（OneDayApp.init 调用）：开关开才订阅。
    func startIfEnabled() {
        setEnabled(CrashCollectionFeature.isEnabled())
    }

    /// 静默自动上报本机未上报的崩溃记录至 `POST /v1/diagnostics/crash-reports`（仅上报已过隐私门的记录）。
    /// 返回本次服务端接受条数；已上报过的 ID 记入 UserDefaults 避免重复提交。
    @MainActor
    @discardableResult
    func uploadPendingIfNeeded(appState: AppState) async -> Int {
        guard CrashCollectionFeature.isEnabled(),
              !appState.isDemo,
              let config = appState.config,
              let apiKey = appState.apiKey
        else { return 0 }
        let uploadedKey = "oneday.crash.uploadedRecordIDs"
        var uploaded = Set(UserDefaults.standard.stringArray(forKey: uploadedKey) ?? [])
        let pending = CrashReportStore.shared.all().filter { !uploaded.contains($0.id.uuidString) }
        guard !pending.isEmpty else { return 0 }
        do {
            let receipt = try await appState.client.uploadCrashReports(
                config: config, apiKey: apiKey, reports: pending
            )
            for item in pending {
                uploaded.insert(item.id.uuidString)
            }
            if uploaded.count > 200 {
                uploaded = Set(uploaded.prefix(200))
            }
            UserDefaults.standard.set(Array(uploaded), forKey: uploadedKey)
            return receipt.accepted
        } catch {
            return 0
        }
    }

    /// 开关翻转即时生效（关于页内部实验节 Toggle 的
    /// onChange 直达）：开＝订阅、关＝摘除。
    func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if enabled, !isSubscribed {
            MXMetricManager.shared.add(self)
            isSubscribed = true
        } else if !enabled, isSubscribed {
            MXMetricManager.shared.remove(self)
            isSubscribed = false
        }
    }

    // MARK: - MXMetricManagerSubscriber

    /// 系统性能指标回报（MetricKit 官方通道）：记录冷启动耗时、滚动卡顿率（Hitch Time Ratio）
    /// 与内存峰值，替代手搓常驻帧率探针；同时预留外部 APM（如 Sentry）转发钩子。
    func didReceive(_ payloads: [MXMetricPayload]) {
        var summaries: [String] = []
        for payload in payloads {
            var parts: [String] = []
            if let launch = payload.applicationLaunchMetrics?.histogrammedTimeToFirstDraw {
                let buckets = launch.bucketEnumerator.allObjects.compactMap { $0 as? MXHistogramBucket<UnitDuration> }
                if let first = buckets.first {
                    let ms = first.bucketStart.converted(to: .milliseconds).value
                    parts.append(String(format: "firstDraw≈%.0fms", ms))
                }
            }
            if let anim = payload.animationMetrics {
                let ratio = anim.scrollHitchTimeRatio.value
                parts.append(String(format: "hitchRatio=%.2fms/s", ratio))
            }
            if let mem = payload.memoryMetrics {
                let peakMB = mem.peakMemoryUsage.converted(to: .megabytes).value
                parts.append(String(format: "peakMem=%.1fMB", peakMB))
            }
            if !parts.isEmpty {
                summaries.append(parts.joined(separator: " | "))
            }
        }
        if !summaries.isEmpty {
            let line = summaries.joined(separator: " ; ")
            UserDefaults.standard.set(line, forKey: "oneday.metrickit.lastMetricSummary")
            ChatDiagTrace.record("MetricKit: \(line)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var records: [CrashReportRecord] = []
        for payload in payloads {
            let when = payload.timeStampEnd
            for diagnostic in payload.crashDiagnostics ?? [] {
                records.append(Self.record(from: diagnostic, when: when))
            }
            for diagnostic in payload.hangDiagnostics ?? [] {
                records.append(CrashReportRecord.make(
                    capturedAt: when,
                    kind: .hang,
                    terminationCode: "持续 \(Self.seconds(diagnostic.hangDuration)) 秒",
                    appVersion: Self.appVersion,
                    osVersion: Self.osVersion,
                    faultingTopSymbols: Self.topSymbols(
                        from: diagnostic.callStackTree
                    )
                ))
            }
            for diagnostic in payload.cpuExceptionDiagnostics ?? [] {
                records.append(CrashReportRecord.make(
                    capturedAt: when,
                    kind: .cpuException,
                    terminationCode: "累计 CPU \(Self.seconds(diagnostic.totalCPUTime)) 秒",
                    appVersion: Self.appVersion,
                    osVersion: Self.osVersion,
                    faultingTopSymbols: Self.topSymbols(
                        from: diagnostic.callStackTree
                    )
                ))
            }
            for diagnostic in payload.diskWriteExceptionDiagnostics ?? [] {
                records.append(CrashReportRecord.make(
                    capturedAt: when,
                    kind: .diskWriteException,
                    terminationCode: "写入 \(Int(diagnostic.totalWritesCaused.converted(to: .bytes).value)) 字节",
                    appVersion: Self.appVersion,
                    osVersion: Self.osVersion,
                    faultingTopSymbols: Self.topSymbols(
                        from: diagnostic.callStackTree
                    )
                ))
            }
        }
        if !records.isEmpty {
            CrashReportStore.shared.append(records)
        }
    }

    // MARK: - 载荷映射（白名单字段，原文不落盘）

    private static func record(
        from diagnostic: MXCrashDiagnostic, when: Date
    ) -> CrashReportRecord {
        // 终止原因原文形如「Namespace SIGNAL, Code
        // 0x…」——拆命名空间与码两字段，地址随码串
        // 进 Core 后由隐私门抹除。
        var namespace: String?
        var code: String?
        if let reason = diagnostic.terminationReason {
            let parts = reason
                .replacingOccurrences(of: "Namespace ", with: "")
                .split(separator: ",", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            namespace = parts.first
            if parts.count > 1 {
                code = parts[1]
                    .replacingOccurrences(of: "Code ", with: "")
            }
        }
        return CrashReportRecord.make(
            capturedAt: when,
            kind: .crash,
            exceptionType: diagnostic.exceptionType.map {
                Self.exceptionName(for: $0.intValue)
            },
            exceptionSignal: diagnostic.signal.map {
                Self.signalName(for: $0.intValue)
            },
            terminationNamespace: namespace,
            terminationCode: code ?? diagnostic.exceptionCode.map { "\($0.intValue)" },
            appVersion: appVersion,
            osVersion: osVersion,
            faultingTopSymbols: topSymbols(from: diagnostic.callStackTree)
        )
    }

    /// 调用栈 JSON 白名单走读：只取符号名（无符号
    /// 名时退二进制名）——binaryUUID/地址/偏移字段
    /// 一律不读。上限由 Core 隐私门截 8。
    private static func topSymbols(from tree: MXCallStackTree) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(
            with: tree.jsonRepresentation()
        ) as? [String: Any],
              let stacks = object["callStacks"] as? [[String: Any]],
              let first = stacks.first,
              let roots = first["callStackRootFrames"] as? [[String: Any]]
        else { return [] }
        var symbols: [String] = []
        func walk(_ frame: [String: Any]) {
            if let symbol = frame["symbolName"] as? String,
               !symbol.isEmpty {
                symbols.append(symbol)
            } else if let binary = frame["binaryName"] as? String,
                      !binary.isEmpty {
                symbols.append(binary)
            }
            if let subs = frame["subFrames"] as? [[String: Any]] {
                for sub in subs { walk(sub) }
            }
        }
        for root in roots { walk(root) }
        return symbols
    }

    private static func seconds(
        _ measurement: Measurement<UnitDuration>
    ) -> String {
        String(format: "%.1f", measurement.converted(to: .seconds).value)
    }

    // MARK: - 码表与版本

    private static func exceptionName(for raw: Int) -> String {
        let names: [Int: String] = [
            1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION",
            3: "EXC_ARITHMETIC", 4: "EXC_EMULATION",
            5: "EXC_SOFTWARE", 6: "EXC_BREAKPOINT",
            7: "EXC_SYSCALL", 8: "EXC_RPC_ALERT",
            9: "EXC_CRASH", 10: "EXC_RESOURCE",
            11: "EXC_GUARD", 12: "EXC_CORPSE_NOTIFY",
        ]
        if let name = names[raw] { return "\(name) (\(raw))" }
        return "EXC_\(raw)"
    }

    private static func signalName(for raw: Int) -> String {
        let names: [Int: String] = [
            4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT",
            7: "SIGEMT", 8: "SIGFPE", 10: "SIGBUS",
            11: "SIGSEGV", 12: "SIGSYS",
        ]
        if let name = names[raw] { return "\(name) (\(raw))" }
        return "SIG_\(raw)"
    }

    private static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return nil
        }
    }

    private static var osVersion: String? {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
