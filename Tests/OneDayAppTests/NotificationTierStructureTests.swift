import XCTest
@testable import OneDayApp
import OneDayCore

/// §385 结构钉测（总表 162/163）：①授权铁律——本
/// 包新文件零 requestAuthorization（不新增任何权
/// 限请求路径，提醒只读真状态、活动只读同步可用
/// 性）；②隐私型面——实时活动属性源码不设正文/
/// 回复字段；③穿线在场（设置页四分类键与 Core 偏
/// 好口逐字同键、目录/路由/工程三处接线、ChatView
/// 三沿挂钩、桥店提醒消费点）
final class NotificationTierStructureTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    private let newFiles = [
        "Sources/OneDayCore/NotificationTier.swift",
        "Sources/OneDayCore/RunLiveActivityAttributes.swift",
        "Sources/OneDayApp/NotificationTierAlerter.swift",
        "Sources/OneDayApp/NotificationSettingsView.swift",
        "Sources/OneDayApp/RunLiveActivityCenter.swift",
        "Sources/OneDayWidgets/OneDayWidgets.swift",
    ]

    /// 授权铁律：已决定状态绝不重走异步请求回调——
    /// 本包不许新出现任何授权请求调用（提醒器只许
    /// 出现 currentState 只读口）
    func testNoNewAuthorizationRequestPath() throws {
        for file in newFiles {
            let text = try source(file)
            XCTAssertFalse(
                text.contains("requestAuthorization"),
                "\(file) 不许出现授权请求（§385 授权铁律）"
            )
        }
        let alerter = try source(
            "Sources/OneDayApp/NotificationTierAlerter.swift"
        )
        XCTAssertTrue(
            alerter.contains(
                "NotificationPermissionGate.currentState()"
            ),
            "提醒器投递前必须只读真状态过门"
        )
    }

    /// 隐私型面：内容态只有阶段＋阶段起始时刻，属
    /// 性只有任务名——源码层不许长出正文/回复字段
    func testLiveActivityAttributesCarryNoBodyFields() throws {
        let text = try source(
            "Sources/OneDayCore/RunLiveActivityAttributes.swift"
        )
        for banned in [
            "var body", "var text", "var reply",
            "var content: String", "var summary",
        ] {
            XCTAssertFalse(
                text.contains(banned),
                "实时活动属性不许带正文字段：\(banned)"
            )
        }
        XCTAssertTrue(text.contains("var taskName: String"))
        XCTAssertTrue(text.contains("var phase: Phase"))
        XCTAssertTrue(text.contains("var phaseStartedAt: Date"))
    }

    /// 设置页四分类键与 Core 偏好口逐字同键＋LA 总
    /// 开关键同键（改一处键名即在此翻红）；
    /// @MainActor：enabledKey 是中心（@MainActor 类）
    /// 的静态属性，非隔离 autoclosure 不许引用
    @MainActor
    func testSettingsKeysMatchCorePreferenceKeys() throws {
        let view = try source(
            "Sources/OneDayApp/NotificationSettingsView.swift"
        )
        for category in NotificationTier.Category.allCases {
            XCTAssertTrue(
                view.contains(
                    "\"\(category.preferenceKey)\""
                ),
                "设置页缺分类键 \(category.preferenceKey)"
            )
        }
        XCTAssertTrue(
            view.contains("RunLiveActivityCenter.enabledKey"),
            "设置页 LA 开关须引用中心同键常量"
        )
        XCTAssertEqual(
            RunLiveActivityCenter.enabledKey,
            "notify.liveActivity.enabled"
        )
    }

    /// 接线在场：目录条目、路由、工程三处
    func testSettingsAndProjectWiringPresent() throws {
        let catalog = try source(
            "Sources/OneDayCore/SettingsCatalog.swift"
        )
        XCTAssertTrue(catalog.contains("case notifications"))
        XCTAssertTrue(catalog.contains("id: \"notifications\""))
        let router = try source(
            "Sources/OneDayApp/AppRouter.swift"
        )
        XCTAssertTrue(router.contains("case notifications"))
        let settings = try source(
            "Sources/OneDayApp/SettingsView.swift"
        )
        XCTAssertTrue(
            settings.contains("NotificationSettingsView()")
        )
        let project = try source("Project.swift")
        XCTAssertTrue(
            project.contains("\"NSSupportsLiveActivities\": true")
        )
        XCTAssertTrue(project.contains("name: \"OneDayWidgets\""))
        XCTAssertTrue(
            project.contains("com.apple.widgetkit-extension")
        )
    }

    /// ChatView 三沿挂钩与桥店消费点在场
    func testRunAndAlertHooksPresent() throws {
        let chat = try source(
            "Sources/OneDayApp/ChatView.swift"
        )
        XCTAssertTrue(
            chat.contains("RunLiveActivityCenter.shared.begin("),
            "起跑沿须启动实时活动"
        )
        XCTAssertTrue(
            chat.contains("RunLiveActivityCenter.shared.end()"),
            "退出沿须收实时活动"
        )
        XCTAssertTrue(
            chat.contains(
                "RunLiveActivityCenter.shared.update("
            ),
            "流式上升沿须切生成中阶段"
        )
        let store = try source(
            "Sources/OneDayApp/OverviewBridgeStore.swift"
        )
        XCTAssertTrue(
            store.contains("NotificationTierAlerter.consume("),
            "桥店拉取成功后须消费分级提醒规划"
        )
    }

    /// 任务名截断口径：40 字封顶、空名回落 OneDay
    @MainActor
    func testTaskNameClipping() {
        let long = String(repeating: "题", count: 60)
        XCTAssertEqual(
            RunLiveActivityCenter.clippedTaskName(long).count,
            RunLiveActivityCenter.taskNameLimit
        )
        XCTAssertEqual(
            RunLiveActivityCenter.clippedTaskName("  "),
            "OneDay"
        )
        XCTAssertEqual(
            RunLiveActivityCenter.clippedTaskName(" 短题 "),
            "短题"
        )
    }

    /// 属性内容态可编解码往返（App 与扩展共用一型
    /// 的契约面）
    func testContentStateCodableRoundTrip() throws {
        let state = RunLiveActivityAttributes.ContentState(
            phase: .generating,
            phaseStartedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(
            RunLiveActivityAttributes.ContentState.self,
            from: data
        )
        XCTAssertEqual(decoded.phase, .generating)
        XCTAssertEqual(
            decoded.phaseStartedAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
