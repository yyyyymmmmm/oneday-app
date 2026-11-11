import XCTest
@testable import OneDayCore

/// 服务健康统一派生钉测（复杂化全清·第 9 项）：三套
/// 探测（伴生/本地服务/提供商）＋ /health 的原始结果
/// 入同一词表的映射逐项钉死；本地服务状态词与伴生
/// serviceHealth 只许与词表同源，不许各面自拼。
final class ServiceHealthTests: XCTestCase {

    private let zhHans = Locale(identifier: "zh-Hans")

    private func info(
        hermesUp: Bool? = true,
        modules: [String: CompanionModuleInfo] = [:]
    ) -> CompanionInfo {
        CompanionInfo(
            companionVersion: "1.0.7", apiLevel: 1,
            minAppVersion: nil, hermesUp: hermesUp,
            modules: modules, generatedAt: nil
        )
    }

    private func module(
        _ state: String, degraded: Bool? = nil
    ) -> CompanionModuleInfo {
        CompanionModuleInfo(
            state: state, detail: nil, degraded: degraded
        )
    }

    // MARK: - 词表

    func testLabelsCoverAllCases() {
        let cases: [ServiceHealth] = [
            .checking, .up, .degraded, .down,
            .absent, .notConfigured, .unknown, .stale,
        ]
        let labels = cases.map { $0.label(locale: zhHans) }
        XCTAssertEqual(Set(labels).count, cases.count, "八档词两两不重")
        XCTAssertEqual(
            labels,
            ["读取中", "正常", "降级运行", "异常",
             "未检测到", "未配置", "暂时读不到", "上次读到"]
        )
    }

    // MARK: - 本地服务入表

    func testLocalMapping() {
        XCTAssertEqual(
            ServiceHealth.from(local: .loading), .checking)
        XCTAssertEqual(
            ServiceHealth.from(local: .up(metric: nil)), .up)
        XCTAssertEqual(
            ServiceHealth.from(local: .up(metric: "版本 0.23.0")), .up)
        XCTAssertEqual(
            ServiceHealth.from(local: .down(message: "x")), .down)
        XCTAssertEqual(
            ServiceHealth.from(local: .notConfigured), .notConfigured)
    }

    /// 本地服务状态词与词表单一出处：statusLabel 必须
    /// 逐档等于 ServiceHealth 的 label，不许回潮自拼
    func testLocalStatusLabelComesFromSharedTable() {
        let states: [LocalServiceProbeState] = [
            .loading, .up(metric: nil),
            .down(message: "x"), .notConfigured,
        ]
        for state in states {
            XCTAssertEqual(
                state.statusLabel,
                ServiceHealth.from(local: state).label(locale: zhHans),
                "\(state)"
            )
        }
    }

    // MARK: - 伴生入表

    func testCompanionPresentHealthyIsUp() {
        let status = CompanionStatus.derive(
            info: info(modules: ["box": module("up")]),
            appVersion: "0.50.3", probedAt: Date()
        )
        XCTAssertEqual(status.serviceHealth, .up)
        XCTAssertEqual(ServiceHealth.from(companion: status), .up)
    }

    func testCompanionDegradedOnlyIsDegraded() {
        let status = CompanionStatus.derive(
            info: info(modules: [
                "box": module("up"),
                "oneday": module("degraded"),
            ]),
            appVersion: "0.50.3", probedAt: Date()
        )
        XCTAssertEqual(status.serviceHealth, .degraded)
    }

    func testCompanionImpairedIsDown() {
        let status = CompanionStatus.derive(
            info: info(modules: [
                "box": module("up"),
                "oneday": module("down"),
            ]),
            appVersion: "0.50.3", probedAt: Date()
        )
        XCTAssertEqual(status.serviceHealth, .down)
    }

    func testCompanionHermesDownIsDown() {
        let status = CompanionStatus.derive(
            info: info(hermesUp: false, modules: ["box": module("up")]),
            appVersion: "0.50.3", probedAt: Date()
        )
        XCTAssertEqual(status.serviceHealth, .down)
    }

    func testCompanionStaleCacheIsStale() {
        let record = CompanionProbeRecord(
            info: info(modules: ["box": module("up")]),
            probedAt: Date()
        )
        let status = CompanionStatus.derive(
            cached: record, appVersion: "0.50.3"
        )
        XCTAssertTrue(status.isStale)
        XCTAssertEqual(status.serviceHealth, .stale)
    }

    func testCompanionAbsentAndUnknown() {
        XCTAssertEqual(
            CompanionStatus.absent(probedAt: Date()).serviceHealth,
            .absent
        )
        XCTAssertEqual(
            CompanionStatus.unknown(probedAt: nil).serviceHealth,
            .unknown
        )
    }

    // MARK: - /health 入表

    func testHealthMapping() {
        let ok = HealthResponse(
            status: "ok", platform: "hermes-agent", version: "0.23.0"
        )
        XCTAssertEqual(ServiceHealth.from(health: ok), .up)
        let bad = HealthResponse(
            status: "error", platform: nil, version: nil
        )
        XCTAssertEqual(ServiceHealth.from(health: bad), .down)
    }

    // MARK: - 提供商结局入表

    func testProviderOutcomeMapping() {
        XCTAssertEqual(
            ProviderConnectionOutcome.connected(modelCount: 3)
                .serviceHealth,
            .up
        )
        XCTAssertEqual(
            ProviderConnectionOutcome.connectedNoCatalog.serviceHealth,
            .degraded
        )
        XCTAssertEqual(
            ProviderConnectionOutcome.failed(message: "x").serviceHealth,
            .down
        )
    }
}
