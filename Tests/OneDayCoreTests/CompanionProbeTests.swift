import XCTest
@testable import OneDayCore

/// 伴生探测契约钉测（DESIGN §110）：派生口径逐项
/// 钉死——版本串形态/比较、模块健康（状态词表据伴
/// 生 front aggregate()/probe_module() 实产）、
/// presence 三档、缓存回落与缓存动作、App 升级门、
/// 设置行文案（钉 zh-Hans locale，断言不随运行环
/// 境语言漂移；无目录宿主时 L10n 回落简体源串）。
final class CompanionProbeTests: XCTestCase {

    private let zhHans = Locale(identifier: "zh-Hans")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func info(
        version: String? = "1.0.7", apiLevel: Int? = 1,
        minApp: String? = "0.37.0", hermesUp: Bool? = true,
        modules: [String: CompanionModuleInfo] = [:]
    ) -> CompanionInfo {
        CompanionInfo(
            companionVersion: version, apiLevel: apiLevel,
            minAppVersion: minApp, hermesUp: hermesUp,
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

    private func allUp() -> [String: CompanionModuleInfo] {
        [
            "writeGate": module("up"), "overview": module("up"),
            "box": module("up"), "oneday": module("up", degraded: false),
            "device": module("up"),
        ]
    }

    // MARK: - 版本串形态

    func testVersionFormWellFormed() {
        XCTAssertTrue(CompanionVersionForm.isWellFormed("1.0.7"))
        XCTAssertTrue(CompanionVersionForm.isWellFormed("0.37.0"))
        XCTAssertTrue(CompanionVersionForm.isWellFormed("v1.0.7"))
        XCTAssertTrue(CompanionVersionForm.isWellFormed(" 1.0.7 "))
    }

    func testVersionFormMalformed() {
        // 两段式/四段式/后缀/非数字/空——一律格式异常
        XCTAssertFalse(CompanionVersionForm.isWellFormed("1.0"))
        XCTAssertFalse(CompanionVersionForm.isWellFormed("1.0.7.1"))
        XCTAssertFalse(CompanionVersionForm.isWellFormed("1.0.7-beta"))
        XCTAssertFalse(CompanionVersionForm.isWellFormed("dev"))
        XCTAssertFalse(CompanionVersionForm.isWellFormed("1.x.0"))
        XCTAssertFalse(CompanionVersionForm.isWellFormed(""))
        XCTAssertFalse(CompanionVersionForm.isWellFormed(nil))
    }

    func testVersionCompareNumericOrder() {
        // 数值序不是字面序：1.10.0 必须大于 1.9.0
        XCTAssertEqual(
            CompanionVersionForm.compare("1.10.0", "1.9.0"),
            .orderedDescending
        )
        XCTAssertEqual(
            CompanionVersionForm.compare("0.36.0", "0.37.0"),
            .orderedAscending
        )
        XCTAssertEqual(
            CompanionVersionForm.compare("0.37.0", "0.37.0"),
            .orderedSame
        )
        XCTAssertEqual(
            CompanionVersionForm.compare("v1.0.7", "1.0.7"),
            .orderedSame
        )
    }

    func testVersionCompareMalformedGivesNoConclusion() {
        XCTAssertNil(CompanionVersionForm.compare("1.0", "0.37.0"))
        XCTAssertNil(CompanionVersionForm.compare("0.36.0", "dev"))
    }

    // MARK: - 模块健康派生

    func testHealthAllUp() {
        let health = CompanionModuleHealth.derive(modules: allUp())
        XCTAssertTrue(health.isHealthy)
        XCTAssertTrue(health.degradedModules.isEmpty)
        XCTAssertTrue(health.impairedModules.isEmpty)
        XCTAssertTrue(health.disabledModules.isEmpty)
    }

    func testHealthDegradedByStateAndByFlag() {
        var modules = allUp()
        modules["box"] = module("degraded")
        modules["oneday"] = module("up", degraded: true)
        let health = CompanionModuleHealth.derive(modules: modules)
        XCTAssertFalse(health.isHealthy)
        // 定序：box 在 oneday 之前
        XCTAssertEqual(health.degradedModules, ["box", "oneday"])
        XCTAssertTrue(health.impairedModules.isEmpty)
    }

    func testHealthImpairedStates() {
        // down/crash-loop/unknown 与未见过的状态词都按
        // 不可用处理（不往好处猜）
        var modules = allUp()
        modules["device"] = module("down")
        modules["writeGate"] = module("crash-loop")
        modules["overview"] = module("unknown")
        modules["box"] = module("some-future-state")
        let health = CompanionModuleHealth.derive(modules: modules)
        XCTAssertEqual(
            health.impairedModules,
            ["writeGate", "overview", "box", "device"]
        )
        XCTAssertTrue(health.degradedModules.isEmpty)
    }

    func testHealthDisabledIsNotAnomaly() {
        var modules = allUp()
        modules["box"] = module("disabled")
        let health = CompanionModuleHealth.derive(modules: modules)
        XCTAssertTrue(health.isHealthy)
        XCTAssertEqual(health.disabledModules, ["box"])
    }

    func testHealthMissingModuleMakesNoClaim() {
        // info 里缺席的模块不入任何名单
        let health = CompanionModuleHealth.derive(
            modules: ["oneday": module("up", degraded: false)]
        )
        XCTAssertTrue(health.isHealthy)
        XCTAssertTrue(health.disabledModules.isEmpty)
    }

    func testHealthUnknownModuleIDsSortAfterKnown() {
        let health = CompanionModuleHealth.derive(modules: [
            "zzz-custom": module("down"),
            "device": module("down"),
            "aaa-custom": module("down"),
        ])
        XCTAssertEqual(
            health.impairedModules,
            ["device", "aaa-custom", "zzz-custom"]
        )
    }

    func testModuleDisplayName() {
        XCTAssertEqual(
            CompanionModuleHealth.displayName("oneday", locale: zhHans),
            "目标点子"
        )
        XCTAssertEqual(
            CompanionModuleHealth.displayName("writeGate", locale: zhHans),
            "审批"
        )
        // 未识 id 原样回本身（服务端自报名册键、照显不编）
        XCTAssertEqual(
            CompanionModuleHealth.displayName("custom-x", locale: zhHans),
            "custom-x"
        )
    }

    // MARK: - 现读派生

    func testDeriveDetectedHealthy() {
        let status = CompanionStatus.derive(
            info: info(modules: allUp()),
            appVersion: "0.42.0", probedAt: now
        )
        XCTAssertEqual(status.presence, .present)
        XCTAssertEqual(status.version, "1.0.7")
        XCTAssertTrue(status.versionWellFormed)
        XCTAssertEqual(status.health?.isHealthy, true)
        XCTAssertEqual(status.hermesUp, true)
        XCTAssertNil(status.appUpdateRequired)
        XCTAssertFalse(status.isStale)
        XCTAssertEqual(status.probedAt, now)
    }

    func testDeriveDetectedMissingFields() {
        // info 字段缺失：版本为空→nil、wellFormed 假；
        // minApp/hermesUp 缺→不给结论、不臆断
        let status = CompanionStatus.derive(
            info: info(
                version: nil, apiLevel: nil, minApp: nil,
                hermesUp: nil, modules: [:]
            ),
            appVersion: "0.42.0", probedAt: now
        )
        XCTAssertEqual(status.presence, .present)
        XCTAssertNil(status.version)
        XCTAssertFalse(status.versionWellFormed)
        XCTAssertNil(status.hermesUp)
        XCTAssertNil(status.appUpdateRequired)
        // 模块空表：无异常可报（缺席不下结论）
        XCTAssertEqual(status.health?.isHealthy, true)
    }

    func testDeriveDetectedBlankVersionIsNil() {
        let status = CompanionStatus.derive(
            info: info(version: "  "),
            appVersion: "0.42.0", probedAt: now
        )
        XCTAssertNil(status.version)
        XCTAssertEqual(
            status.versionText(locale: zhHans), "版本未知"
        )
    }

    func testDeriveDetectedMalformedVersionKeptVerbatim() {
        // 格式异常：原文照存照显（服务器自报），只标
        // wellFormed 假、不参与升级门比较
        let status = CompanionStatus.derive(
            info: info(version: "1.1-beta", minApp: "0.37.0"),
            appVersion: "0.36.0", probedAt: now
        )
        XCTAssertEqual(status.version, "1.1-beta")
        XCTAssertFalse(status.versionWellFormed)
        XCTAssertEqual(
            status.versionText(locale: zhHans), "v1.1-beta"
        )
    }

    // MARK: - App 升级门

    func testUpdateGateStrictlyGreater() {
        let older = CompanionStatus.derive(
            info: info(minApp: "0.37.0"),
            appVersion: "0.36.0", probedAt: now
        )
        XCTAssertEqual(older.appUpdateRequired, "0.37.0")
        // 相等不算需要升级
        let equal = CompanionStatus.derive(
            info: info(minApp: "0.37.0"),
            appVersion: "0.37.0", probedAt: now
        )
        XCTAssertNil(equal.appUpdateRequired)
        let newer = CompanionStatus.derive(
            info: info(minApp: "0.37.0"),
            appVersion: "0.42.0", probedAt: now
        )
        XCTAssertNil(newer.appUpdateRequired)
    }

    func testUpdateGateMalformedMinGivesNoConclusion() {
        let status = CompanionStatus.derive(
            info: info(minApp: "latest"),
            appVersion: "0.36.0", probedAt: now
        )
        XCTAssertNil(status.appUpdateRequired)
    }

    // MARK: - 解析（结果×缓存）

    func testResolveDetectedPersists() {
        let resolution = CompanionProbeResolver.resolve(
            outcome: .detected(info(modules: allUp())),
            cached: nil, appVersion: "0.42.0", now: now
        )
        XCTAssertEqual(resolution.status.presence, .present)
        XCTAssertFalse(resolution.status.isStale)
        guard case .persist(let record) = resolution.cacheAction
        else {
            return XCTFail("detected 应落盘新记录")
        }
        XCTAssertEqual(record.companionVersion, "1.0.7")
        XCTAssertEqual(record.probedAt, now)
    }

    func testResolveMissingClearsCache() {
        let cached = CompanionProbeRecord(
            info: info(), probedAt: now.addingTimeInterval(-3600)
        )
        let resolution = CompanionProbeResolver.resolve(
            outcome: .missing, cached: cached,
            appVersion: "0.42.0", now: now
        )
        XCTAssertEqual(resolution.status.presence, .absent)
        XCTAssertEqual(resolution.cacheAction, .clear)
    }

    func testResolveUnreachableFallsBackToCacheAsStale() {
        let cached = CompanionProbeRecord(
            info: info(modules: ["device": module("down")]),
            probedAt: now.addingTimeInterval(-3600)
        )
        for outcome in [CompanionProbeOutcome.unreachable,
                        .unreadable(401)] {
            let resolution = CompanionProbeResolver.resolve(
                outcome: outcome, cached: cached,
                appVersion: "0.42.0", now: now
            )
            XCTAssertEqual(resolution.status.presence, .present)
            XCTAssertTrue(resolution.status.isStale)
            XCTAssertEqual(resolution.status.version, "1.0.7")
            // 缓存状态不带健康结论——哪怕记录里有模块
            // 处于 down，也不许拿旧健康冒充现况
            XCTAssertNil(resolution.status.health)
            XCTAssertEqual(
                resolution.status.probedAt,
                now.addingTimeInterval(-3600)
            )
            XCTAssertEqual(resolution.cacheAction, .keep)
        }
    }

    func testResolveUnreachableWithoutCacheIsUnknown() {
        let resolution = CompanionProbeResolver.resolve(
            outcome: .unreachable, cached: nil,
            appVersion: "0.42.0", now: now
        )
        XCTAssertEqual(resolution.status.presence, .unknown)
        XCTAssertNil(resolution.status.version)
        XCTAssertEqual(resolution.cacheAction, .keep)
    }

    // MARK: - 缓存记录互转

    func testRecordRoundTripsThroughInfoAndJSON() throws {
        let original = info(
            modules: ["oneday": module("degraded", degraded: true)]
        )
        let record = CompanionProbeRecord(
            info: original, probedAt: now
        )
        XCTAssertEqual(record.info, original)

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(
            CompanionProbeRecord.self, from: data
        )
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.probedAt, now)
    }

    // MARK: - 呈现文案（zh-Hans 钉死）

    func testLineHealthy() {
        let status = CompanionStatus.derive(
            info: info(modules: allUp()),
            appVersion: "0.42.0", probedAt: now
        )
        XCTAssertEqual(
            status.settingsLine(now: now, locale: zhHans),
            "v1.0.7 · 运行正常"
        )
        XCTAssertNil(status.footerNote(locale: zhHans))
    }

    func testLineAnomalies() {
        var modules = allUp()
        modules["box"] = module("degraded")
        modules["oneday"] = module("down")
        let status = CompanionStatus.derive(
            info: info(modules: modules),
            appVersion: "0.42.0", probedAt: now
        )
        XCTAssertEqual(
            status.settingsLine(now: now, locale: zhHans),
            "v1.0.7 · 云电脑降级运行；目标点子暂时不可用"
        )
    }

    func testLineHermesDownAppended() {
        let status = CompanionStatus.derive(
            info: info(hermesUp: false, modules: allUp()),
            appVersion: "0.42.0", probedAt: now
        )
        XCTAssertEqual(
            status.settingsLine(now: now, locale: zhHans),
            "v1.0.7 · 运行正常；Hermes 暂时联系不上"
        )
    }

    func testLineStaleShowsLastReadWithoutHealth() {
        let record = CompanionProbeRecord(
            info: info(modules: ["device": module("down")]),
            probedAt: now.addingTimeInterval(-3 * 3600)
        )
        let status = CompanionStatus.derive(
            cached: record, appVersion: "0.42.0"
        )
        let line = status.settingsLine(now: now, locale: zhHans)
        XCTAssertTrue(line.hasPrefix("v1.0.7 · 上次读到 "))
        // stale 行绝不带健康结论（记录里 device 是 down）
        XCTAssertFalse(line.contains("不可用"))
        XCTAssertFalse(line.contains("运行正常"))
    }

    func testLineAbsentAndUnknown() {
        XCTAssertEqual(
            CompanionStatus.absent(probedAt: now)
                .settingsLine(now: now, locale: zhHans),
            "未检测到"
        )
        XCTAssertEqual(
            CompanionStatus.unknown(probedAt: now)
                .settingsLine(now: now, locale: zhHans),
            "暂时读不到"
        )
    }

    func testFooterNoteAbsentIsActionable() {
        let note = CompanionStatus.absent(probedAt: now)
            .footerNote(locale: zhHans)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("未检测到伴生服务") == true)
        XCTAssertTrue(note?.contains("确认伴生服务已经启动") == true)
    }

    func testFooterNoteUpdateRequired() {
        let status = CompanionStatus.derive(
            info: info(minApp: "0.37.0"),
            appVersion: "0.36.0", probedAt: now
        )
        XCTAssertEqual(
            status.footerNote(locale: zhHans),
            "请把 App 升级到 0.37.0 版，伴生服务才能正常配合工作。"
        )
    }

    func testFooterNoteUnknownStaysSilent() {
        // 读不到不吓人：unknown 不出脚注
        XCTAssertNil(
            CompanionStatus.unknown(probedAt: now)
                .footerNote(locale: zhHans)
        )
    }
}
