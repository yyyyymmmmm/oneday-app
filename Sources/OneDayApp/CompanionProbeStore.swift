import Foundation
import OneDayCore

/// 伴生探测的执行与持有（本包，DESIGN §110）：登录
/// 成功后探一次、回前台节流再探；结果经 Core 的
/// CompanionProbeResolver 解析成设置页版本组的派生
/// 态，最近一次成功值落 UserDefaults 供离线时以
/// 「上次读到」形态露面。网络动作复用 Companion-
/// FrontClient.probeCompanion（/api/companion/info
/// 既有实现，不另起第二套请求）；本类只管时机、节
/// 流与缓存动作执行，派生口径全在 Core、不在这里重算。
@MainActor
@Observable
final class CompanionProbeStore {
    /// 当前派生态：冷启先由缓存记录派生（stale 形
    /// 态），本轮现读回来后替换
    private(set) var status: CompanionStatus?
    private var lastAttemptAt: Date?
    private var inFlight = false
    private let client = CompanionFrontClient()

    private static let cacheKey = "companionProbeRecord.v1"
    /// 回前台再探的节流间隔：距上次尝试不足此时长
    /// 直接跳过（登录后那次不受此限）
    static let foregroundRefreshInterval: TimeInterval = 60

    init() {
        if let record = Self.loadRecord() {
            status = .derive(
                cached: record, appVersion: Self.appVersion
            )
        }
    }

    static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? ""
    }

    /// 无条件探测（登录成功落点）：演示模式不探（假
    /// 客户端的世界里没有真伴生，探针走的是真网络
    /// 客户端、不许把演示态探成真结论）；未连接无
    /// config 时同样不探
    func probe(appState: AppState) async {
        guard !appState.isDemo, let config = appState.config,
              !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        lastAttemptAt = Date()
        let outcome = await client.probeCompanion(config: config)
        let resolution = CompanionProbeResolver.resolve(
            outcome: CompanionProbeOutcome(outcome),
            cached: Self.loadRecord(),
            appVersion: Self.appVersion, now: Date()
        )
        status = resolution.status
        switch resolution.cacheAction {
        case .persist(let record):
            Self.saveRecord(record)
        case .clear:
            Self.saveRecord(nil)
        case .keep:
            break
        }
    }

    /// 节流探测（回前台/冷启恢复/设置页打开）：距上
    /// 次尝试不足节流间隔跳过——回前台是高频事件，
    /// 不许每次亮屏都打一发
    func probeIfNeeded(appState: AppState) async {
        if let lastAttemptAt,
           Date().timeIntervalSince(lastAttemptAt)
            < Self.foregroundRefreshInterval {
            return
        }
        await probe(appState: appState)
    }

    // MARK: - 缓存落盘（UserDefaults JSON，只存事实）

    private static func loadRecord() -> CompanionProbeRecord? {
        guard let data = UserDefaults.standard.data(
            forKey: cacheKey
        ) else { return nil }
        return try? JSONDecoder().decode(
            CompanionProbeRecord.self, from: data
        )
    }

    private static func saveRecord(_ record: CompanionProbeRecord?) {
        if let record,
           let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
    }
}

/// App 层探测枚举（CompanionProbe，CompanionFront-
/// Client.probeCompanion 的结果）→ Core 解析口的
/// 1:1 映射：两边同构，映射在此一处，Core 不反向
/// 依赖 App 层类型
private extension CompanionProbeOutcome {
    init(_ probe: CompanionProbe) {
        switch probe {
        case .detected(let info): self = .detected(info)
        case .missing: self = .missing
        case .unreadable(let code): self = .unreadable(code)
        case .unreachable: self = .unreachable
        }
    }
}
