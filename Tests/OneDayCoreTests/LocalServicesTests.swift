import XCTest
@testable import OneDayCore

/// 本机服务闸（0.29.0）：①名册完整（四条、序、字
/// 段齐）②探活结局→状态三路映射（成功/失败/钥匙
/// 未配——未配置不许探成异常）③状态文案单一映射
/// ④搜索覆盖本机四条（名称/说明/状态词）。
final class LocalServicesTests: XCTestCase {

    // MARK: - 名册完整性

    func testRosterIntegrity() {
        let roster = LocalServiceDirectory.roster
        XCTAssertEqual(roster.count, 4)
        XCTAssertEqual(
            roster.map(\.serviceID),
            [.hermes, .writeGate, .oneDayBridge, .overviewBridge],
            "名册序＝目录呈现序：本体→审批桥→目标点子→总览"
        )
        XCTAssertEqual(Set(roster.map(\.id)).count, roster.count, "id 唯一")
        for entry in roster {
            XCTAssertFalse(entry.name.isEmpty, entry.id)
            XCTAssertFalse(entry.blurb.isEmpty, entry.id)
            XCTAssertFalse(entry.iconAssetName.isEmpty, entry.id)
            // 0.36.0（宪法 §8＋S11）：证据行改用户语
            // 言——不许再出现接口方法名/端点行话
            XCTAssertFalse(entry.evidenceLine.isEmpty, entry.id)
            XCTAssertFalse(
                entry.evidenceLine.contains("GET"),
                "证据行不许写接口方法名：\(entry.id)"
            )
            XCTAssertFalse(
                entry.evidenceLine.contains("端点"),
                "证据行不许写端点行话：\(entry.id)"
            )
        }
        for id in LocalServiceID.allCases {
            XCTAssertEqual(
                LocalServiceDirectory.descriptor(id).serviceID, id
            )
        }
    }

    /// 图标真实化（0.36.3，用户加严 §4 执行口径）：
    /// 四件各有独立的定制图标面资产、不许共用一张、
    /// 不许回落裸 SF 符号命名
    func testIconAssetsAreDistinctPerService() {
        let names = LocalServiceDirectory.roster.map(\.iconAssetName)
        XCTAssertEqual(Set(names).count, names.count, "图标资产逐件独立")
        for name in names {
            XCTAssertTrue(name.hasPrefix("Local"), name)
        }
    }

    /// 电脑（Simular Box）是 MCP 在册连接、本组不
    /// 重复列——名册里不许出现它
    func testRosterExcludesBox() {
        for entry in LocalServiceDirectory.roster {
            XCTAssertFalse(entry.name.contains("Box"), entry.id)
            XCTAssertFalse(entry.name.contains("电脑"), entry.id)
        }
    }

    // MARK: - 结局→状态映射（三路）

    func testMappingSuccessToUp() {
        XCTAssertEqual(
            LocalServiceProbeMapping.state(from: .success(metric: nil)),
            .up(metric: nil)
        )
        XCTAssertEqual(
            LocalServiceProbeMapping.state(
                from: .success(metric: "记忆 1 · 技能 42")
            ),
            .up(metric: "记忆 1 · 技能 42")
        )
    }

    func testMappingFailureToDown() {
        XCTAssertEqual(
            LocalServiceProbeMapping.state(from: .failure("网络不可达")),
            .down(message: "网络不可达")
        )
    }

    /// 钥匙未配是独立一档——不许映射成异常（没发请
    /// 求与请求失败是两回事，混报即失真）
    func testMappingKeyNotConfiguredIsNotDown() {
        let state = LocalServiceProbeMapping.state(
            from: .keyNotConfigured
        )
        XCTAssertEqual(state, .notConfigured)
        XCTAssertNotEqual(state.statusLabel, "异常")
    }

    // MARK: - 状态文案单一映射

    func testStatusLabels() {
        XCTAssertEqual(LocalServiceProbeState.loading.statusLabel, "读取中")
        XCTAssertEqual(LocalServiceProbeState.up(metric: nil).statusLabel, "正常")
        XCTAssertEqual(
            LocalServiceProbeState.down(message: "x").statusLabel, "异常"
        )
        XCTAssertEqual(
            LocalServiceProbeState.notConfigured.statusLabel, "未配置"
        )
    }

    func testSublineJoinsMetricOnlyWhenPresent() {
        XCTAssertEqual(
            LocalServiceProbeState.up(metric: "目标 3 · 点子 5").subline,
            "正常 · 目标 3 · 点子 5"
        )
        XCTAssertEqual(LocalServiceProbeState.up(metric: nil).subline, "正常")
        XCTAssertEqual(
            LocalServiceProbeState.up(metric: "").subline, "正常",
            "空读数不许拼出空尾"
        )
        XCTAssertEqual(
            LocalServiceProbeState.down(message: "x").subline, "异常"
        )
    }

    // MARK: - 搜索覆盖本机四条

    private func allUp() -> [LocalServiceID: LocalServiceProbeState] {
        Dictionary(
            uniqueKeysWithValues: LocalServiceID.allCases.map {
                ($0, LocalServiceProbeState.up(metric: nil))
            }
        )
    }

    func testSearchByName() {
        let hits = LocalServiceProbeMapping.filtered(
            states: allUp(), query: "Hermes"
        )
        XCTAssertEqual(hits.map(\.serviceID), [.hermes])
        let hitsCN = LocalServiceProbeMapping.filtered(
            states: allUp(), query: "总览"
        )
        XCTAssertEqual(hitsCN.map(\.serviceID), [.overviewBridge])
    }

    func testSearchByBlurb() {
        let hits = LocalServiceProbeMapping.filtered(
            states: allUp(), query: "批准"
        )
        XCTAssertEqual(hits.map(\.serviceID), [.writeGate])
    }

    func testSearchByStatusWord() {
        var states = allUp()
        states[.writeGate] = .down(message: "网络不可达")
        states[.oneDayBridge] = .notConfigured
        let downHits = LocalServiceProbeMapping.filtered(
            states: states, query: "异常"
        )
        XCTAssertEqual(downHits.map(\.serviceID), [.writeGate])
        let unconfHits = LocalServiceProbeMapping.filtered(
            states: states, query: "未配置"
        )
        XCTAssertEqual(unconfHits.map(\.serviceID), [.oneDayBridge])
    }

    func testSearchEmptyQueryReturnsRoster() {
        let hits = LocalServiceProbeMapping.filtered(
            states: [:], query: "  "
        )
        XCTAssertEqual(hits.count, 4)
    }

    func testSearchNoMatch() {
        let hits = LocalServiceProbeMapping.filtered(
            states: allUp(), query: "zzzz"
        )
        XCTAssertTrue(hits.isEmpty)
    }
}
