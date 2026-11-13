import OneDayCore
import XCTest

/// 分区折叠与服务商可见性治理（§158）：折叠账编解
/// 码与判定、内置行分拣（含默认升主列）、隐藏过滤
/// （含默认组结构闸）、恢复名单
final class SectionCollapseTests: XCTestCase {

    // MARK: - 折叠账

    func testCollapseFallsBackToDefaultWhenKeyMissing() {
        XCTAssertFalse(SectionCollapseState.isCollapsed(
            key: "a", in: [:], defaultCollapsed: false))
        XCTAssertTrue(SectionCollapseState.isCollapsed(
            key: "a", in: [:], defaultCollapsed: true))
    }

    func testCollapseToggleRoundTrip() {
        var store = SectionCollapseState.toggled(
            key: "a", in: [:], defaultCollapsed: false)
        XCTAssertTrue(SectionCollapseState.isCollapsed(
            key: "a", in: store, defaultCollapsed: false))
        store = SectionCollapseState.toggled(
            key: "a", in: store, defaultCollapsed: false)
        XCTAssertFalse(SectionCollapseState.isCollapsed(
            key: "a", in: store, defaultCollapsed: false))
    }

    func testCollapseEncodeDecodeRoundTripAndGarbage() {
        let data = SectionCollapseState.encode(["a": true, "b": false])
        XCTAssertEqual(
            SectionCollapseState.decode(data), ["a": true, "b": false])
        XCTAssertEqual(
            SectionCollapseState.decode(Data("junk".utf8)), [:])
        XCTAssertEqual(SectionCollapseState.decode(nil), [:])
    }

    func testDrawerSectionKeysAreDistinct() {
        let keys = [
            DrawerSectionKey.navigation,
            DrawerSectionKey.channels,
            DrawerSectionKey.sideChats,
            DrawerSectionKey.manage,
        ]
        XCTAssertEqual(Set(keys).count, 4)
        XCTAssertEqual(
            DrawerSectionKey.key(forSearching: true),
            DrawerSectionKey.sideChats)
    }

    // MARK: - 显隐账（§198）

    func testVisibilityDefaultsToVisibleWhenKeyMissing() {
        let keys = [
            DrawerSectionKey.navigation,
            DrawerSectionKey.channels,
            DrawerSectionKey.sideChats,
            DrawerSectionKey.manage,
        ]
        for key in keys {
            XCTAssertTrue(
                SectionVisibilityState.isVisible(key: key, in: [:]),
                key)
        }
    }

    func testVisibilityToggleAndSetting() {
        var store = SectionVisibilityState.toggled(
            key: DrawerSectionKey.channels, in: [:])
        XCTAssertFalse(SectionVisibilityState.isVisible(
            key: DrawerSectionKey.channels, in: store))
        store = SectionVisibilityState.toggled(
            key: DrawerSectionKey.channels, in: store)
        XCTAssertTrue(SectionVisibilityState.isVisible(
            key: DrawerSectionKey.channels, in: store))
        // 直置同值不翻转（分区管理面选择器口径：选的
        // 就是目标态，不经切换推导）
        store = SectionVisibilityState.setting(
            key: DrawerSectionKey.channels, visible: false, in: store)
        store = SectionVisibilityState.setting(
            key: DrawerSectionKey.channels, visible: false, in: store)
        XCTAssertFalse(SectionVisibilityState.isVisible(
            key: DrawerSectionKey.channels, in: store))
    }

    func testVisibilityEncodeDecodeRoundTripAndGarbage() {
        let data = SectionVisibilityState.encode(
            [DrawerSectionKey.manage: false])
        XCTAssertEqual(
            SectionVisibilityState.decode(data),
            [DrawerSectionKey.manage: false])
        XCTAssertEqual(
            SectionVisibilityState.decode(Data("junk".utf8)), [:])
        XCTAssertEqual(SectionVisibilityState.decode(nil), [:])
    }

    // MARK: - 四区渲染合成（§198 显隐账；频道内容闸
    // 于 2026-11-13 频道扩展一期退役——清单恒显）

    func testDrawerSectionGatesDefaultAllPresent() {
        let gates = DrawerSectionGates.resolve(visibility: [:])
        XCTAssertEqual(
            gates,
            DrawerSectionGates(
                navigation: true, channels: true,
                manage: true, sideChats: true))
    }

    func testDrawerSectionGatesChannelsAlwaysListed() {
        // 恒显口径：频道区不再有成员内容闸——账面显
        // 示即在场（未配对行/冻结行靠它才有地方站）
        let gates = DrawerSectionGates.resolve(visibility: [:])
        XCTAssertTrue(gates.channels)
        XCTAssertTrue(gates.navigation)
        XCTAssertTrue(gates.manage)
        XCTAssertTrue(gates.sideChats)
    }

    func testDrawerSectionGatesChannelsHiddenByLedgerOnly() {
        // 整区退场只剩一条路：用户在分区管理里隐藏
        let gates = DrawerSectionGates.resolve(
            visibility: [DrawerSectionKey.channels: false])
        XCTAssertFalse(gates.channels)
    }

    func testDrawerSectionGatesEachEntryIndependent() {
        // 四条目各自独立：导航账隐藏不连带管理行（管
        // 理行显隐只由自家账管，§198 规格 §2.2 第 6 条）
        let gates = DrawerSectionGates.resolve(
            visibility: [
                DrawerSectionKey.navigation: false,
                DrawerSectionKey.sideChats: false,
            ])
        XCTAssertFalse(gates.navigation)
        XCTAssertFalse(gates.sideChats)
        XCTAssertTrue(gates.manage)
        XCTAssertTrue(gates.channels)
        let manageOff = DrawerSectionGates.resolve(
            visibility: [DrawerSectionKey.manage: false])
        XCTAssertFalse(manageOff.manage)
        XCTAssertTrue(manageOff.navigation)
    }

    // MARK: - 分组样本（生产定型：网关组＋具名组＋两家内置行）

    private func groups() -> [ChatModelGroup] {
        [
            ChatModelGroup(title: "默认服务商", choices: [
                ChatModelChoice(model: "deepseek-flash", providerField: "custom"),
            ]),
            ChatModelGroup(title: "Ailey", choices: [
                ChatModelChoice(model: "gpt-5.6", providerField: "custom:ailey"),
            ]),
            ChatModelGroup(title: "nous", choices: [
                ChatModelChoice(model: "nous-1", providerField: nil),
            ]),
            ChatModelGroup(title: "deepseek", choices: [
                ChatModelChoice(model: "deepseek-chat", providerField: nil),
            ]),
        ]
    }

    func testBuiltinDetectionByStructure() {
        let g = groups()
        XCTAssertFalse(ProviderGroupVisibility.isBuiltinGroup(g[0]))
        XCTAssertFalse(ProviderGroupVisibility.isBuiltinGroup(g[1]))
        XCTAssertTrue(ProviderGroupVisibility.isBuiltinGroup(g[2]))
        XCTAssertTrue(ProviderGroupVisibility.isBuiltinGroup(g[3]))
    }

    func testPartitionMovesBuiltinsOutKeepsOrder() {
        let parts = ProviderGroupVisibility.partition(groups())
        XCTAssertEqual(parts.main.map(\.title), ["默认服务商", "Ailey"])
        XCTAssertEqual(parts.builtin.map(\.title), ["nous", "deepseek"])
    }

    func testBuiltinGroupContainingDefaultStaysInMain() {
        var g = groups()
        g[2] = ChatModelGroup(title: "nous", choices: [
            ChatModelChoice(
                model: "nous-1", providerField: nil, isDefault: true),
        ])
        let parts = ProviderGroupVisibility.partition(g)
        XCTAssertEqual(
            parts.main.map(\.title), ["默认服务商", "Ailey", "nous"])
        XCTAssertEqual(parts.builtin.map(\.title), ["deepseek"])
    }

    func testBucketGroupMergesBuiltins() {
        let parts = ProviderGroupVisibility.partition(groups())
        let bucket = ProviderGroupVisibility.bucketGroup(parts.builtin)
        XCTAssertEqual(bucket?.title, "未配置的服务商")
        XCTAssertEqual(
            bucket?.choices.map(\.model), ["nous-1", "deepseek-chat"])
        XCTAssertNil(ProviderGroupVisibility.bucketGroup([]))
    }

    // MARK: - 隐藏名单

    func testGroupKeys() {
        let g = groups()
        XCTAssertEqual(
            ProviderGroupVisibility.groupKey(for: g[0]), "gateway")
        XCTAssertNil(ProviderGroupVisibility.groupKey(for: g[1]))
        XCTAssertEqual(
            ProviderGroupVisibility.groupKey(for: g[2]), "builtin:nous")
        XCTAssertEqual(
            ProviderGroupVisibility.groupKey(for: g[3]), "builtin:deepseek")
    }

    func testVisibleGroupsFiltersHidden() {
        let visible = ProviderGroupVisibility.visibleGroups(
            groups(), hidden: ["gateway", "builtin:nous"])
        XCTAssertEqual(visible.map(\.title), ["Ailey", "deepseek"])
    }

    func testVisibleGroupsNeverHidesDefaultCarrier() {
        var g = groups()
        g[2] = ChatModelGroup(title: "nous", choices: [
            ChatModelChoice(
                model: "nous-1", providerField: nil, isDefault: true),
        ])
        let visible = ProviderGroupVisibility.visibleGroups(
            g, hidden: ["builtin:nous"])
        XCTAssertTrue(visible.contains { $0.title == "nous" })
    }

    func testHiddenEncodeDecodeAndEntries() {
        let data = ProviderGroupVisibility.encodeHidden(
            ["gateway", "builtin:nous"])
        XCTAssertEqual(
            ProviderGroupVisibility.decodeHidden(data),
            ["gateway", "builtin:nous"])
        XCTAssertEqual(
            ProviderGroupVisibility.decodeHidden(Data("x".utf8)), [])
        let entries = ProviderGroupVisibility.hiddenEntries(
            in: groups(), hidden: ["builtin:nous", "builtin:ghost"])
        XCTAssertEqual(entries.map(\.title), ["nous"])
        XCTAssertEqual(entries.map(\.key), ["builtin:nous"])
    }

    func testDefaultCollapsedPolicy() {
        XCTAssertTrue(ProviderGroupVisibility.defaultCollapsed(
            isBuiltinBucket: true))
        XCTAssertFalse(ProviderGroupVisibility.defaultCollapsed(
            isBuiltinBucket: false))
    }
}
