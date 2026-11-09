import OneDayCore
import XCTest

/// 0.3.8 显示映射组：模型显示名（第 6 条）、档案名翻译
/// （第 7 条）、日志三行解析（补遗审计结构）、抽屉底条
/// 钉底几何（第 22 条）、统一行规格与字重增补（补遗）。
final class DisplayMappingTests: XCTestCase {
    // MARK: - 模型显示名（第 6 条）

    func testModelDisplayNames() {
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: "deepseek-flash"),
            "DeepSeek Flash"
        )
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: "deepseek-v4-pro"),
            "DeepSeek V4 Pro"
        )
        XCTAssertEqual(
            ModelDisplayNames.displayName(
                for: "Qwen/Qwen3-30B-A3B-Instruct-2507-FP8"
            ),
            "Qwen3-30B"
        )
        // 服务端别名映射到规范显示名
        XCTAssertEqual(
            ModelDisplayNames.displayName(for: "deepseek-chat"),
            "DeepSeek Flash"
        )
        // 网关别名与未知 id 不给假名：nil → 身份位兜底
        XCTAssertNil(ModelDisplayNames.displayName(for: "hermes-agent"))
        XCTAssertNil(ModelDisplayNames.displayName(for: "some-unknown-x"))
        XCTAssertNil(ModelDisplayNames.displayName(for: nil))
        XCTAssertEqual(
            ModelDisplayNames.identityLabel(for: "hermes-agent"),
            "服务端默认"
        )
        XCTAssertEqual(
            ModelDisplayNames.identityLabel(for: nil), "服务端默认"
        )
    }

    // MARK: - 档案名（第 7 条）

    func testProfileName() {
        XCTAssertEqual(ServerLabels.profileName("default"), "默认档案")
        XCTAssertEqual(ServerLabels.profileName(nil), "默认档案")
        XCTAssertEqual(ServerLabels.profileName("work"), "work")
    }

    // MARK: - 日志三行（补遗：人话动作＋说明＋级别·时间）

    func testLogDisplayParsesFullLine() {
        let entry = LogDisplay.parse(
            "2026-11-09T03:12:44.123+08:00 INFO gateway.run: Gateway started. Listening on port 8642"
        )
        XCTAssertEqual(entry.headline, "Gateway started")
        XCTAssertEqual(entry.detail, "Listening on port 8642")
        XCTAssertTrue(entry.meta.contains("信息"))
        XCTAssertTrue(entry.meta.contains("03:12:44"))
        XCTAssertTrue(entry.meta.contains("gateway.run"))
    }

    func testLogDisplayErrorAndBareLines() {
        let error = LogDisplay.parse("ERROR Connection refused")
        XCTAssertEqual(error.headline, "Connection refused")
        XCTAssertEqual(error.meta, "错误")
        let bare = LogDisplay.parse("网关已启动")
        XCTAssertEqual(bare.headline, "网关已启动")
        XCTAssertNil(bare.detail)
        XCTAssertEqual(bare.meta, "日志")
    }

    // MARK: - 抽屉底条钉底（第 22 条）

    func testDrawerBottomBarGeometry() {
        XCTAssertEqual(
            DrawerGeometry.bottomBarBottomPadding(safeAreaBottom: 34), 38
        )
        // 852pt 屏＋安全区 34：条中心 92.5%（Muse 实测
        // 同值；0.3.7 旧形态 77.5%）
        let fraction = DrawerGeometry.bottomBarCenterFraction(
            screenHeight: 852, safeAreaBottom: 34
        )
        XCTAssertEqual(fraction, 0.925, accuracy: 0.002)
    }

    // MARK: - 统一行规格与字重增补（补遗）

    func testListRowSpecFrozen() {
        XCTAssertEqual(ListRowSpec.iconSlotWidth, 28)
        XCTAssertEqual(ListRowSpec.minHeight, 56)
        XCTAssertEqual(ListRowSpec.sessionRowMinHeight, 57)
        XCTAssertEqual(ListRowSpec.titleSize, 17)
        XCTAssertEqual(ListRowSpec.subtitleSize, 13)
    }

    func testLocalThreadSubtitle() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 12
        ))!
        let updated = cal.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 9, minute: 41
        ))!
        XCTAssertEqual(
            LocalThreadSubtitle.text(
                updatedAt: updated, messageCount: 12,
                now: now, calendar: cal
            ),
            "今天 09:41 · 12 条"
        )
        XCTAssertEqual(
            LocalThreadSubtitle.text(
                updatedAt: updated, messageCount: 0,
                now: now, calendar: cal
            ),
            "今天 09:41"
        )
    }
}
