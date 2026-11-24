import OneDayCore
import XCTest

/// 台账 174/175/179 Core 钉测（DESIGN §391）：例程关
/// 系图组装、更新说明表、聊天个性化默认值与读口。
final class OBBundleCoreTests: XCTestCase {

    private func job(_ json: String) throws -> CronJob {
        try JSONDecoder().decode(CronJob.self, from: Data(json.utf8))
    }

    // MARK: - 174 例程关系图

    func testGraphGroupsPlatformTargetsByPlatform() throws {
        let jobs = try [
            job(#"{"id":"a","name":"早报","deliver":"telegram:111"}"#),
            job(#"{"id":"b","name":"晚报","deliver":"telegram:222"}"#),
            job(#"{"id":"c","name":"提醒","deliver":"origin"}"#),
        ]
        let graph = CronRelationGraph.build(jobs: jobs)
        XCTAssertEqual(graph.edges.count, 3)
        let telegram = graph.targets.first {
            $0.id == "deliver:platform:telegram"
        }
        XCTAssertEqual(telegram?.label, "telegram 对话")
        XCTAssertEqual(telegram?.jobIDs, ["a", "b"])
        // 任务数多者排首
        XCTAssertEqual(graph.targets.first?.id, telegram?.id)
        let origin = graph.targets.first {
            $0.id == "deliver:origin"
        }
        XCTAssertEqual(origin?.label, "原对话")
        XCTAssertEqual(origin?.jobIDs, ["c"])
    }

    func testGraphUnspecifiedDeliverBucket() throws {
        let jobs = try [
            job(#"{"id":"a","name":"无投递"}"#),
            job(#"{"id":"b","name":"本地","deliver":"local"}"#),
        ]
        let graph = CronRelationGraph.build(jobs: jobs)
        let unspecified = graph.targets.first {
            $0.id == CronRelationGraph.unspecifiedTargetID
        }
        XCTAssertEqual(
            unspecified?.label,
            CronRelationGraph.unspecifiedTargetLabel
        )
        XCTAssertEqual(unspecified?.jobIDs, ["a"])
        let local = graph.targets.first { $0.id == "deliver:local" }
        XCTAssertEqual(local?.label, "不投递")
    }

    func testGraphEmptyJobs() {
        let graph = CronRelationGraph.build(jobs: [])
        XCTAssertTrue(graph.targets.isEmpty)
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func testGraphEveryJobHasExactlyOneEdge() throws {
        let jobs = try [
            job(#"{"id":"a","deliver":"log"}"#),
            job(#"{"id":"b","deliver":"log"}"#),
            job(#"{"id":"c","deliver":"weixin:9"}"#),
        ]
        let graph = CronRelationGraph.build(jobs: jobs)
        XCTAssertEqual(
            graph.edges.map(\.jobID).sorted(), ["a", "b", "c"]
        )
        // 目标内成员与边集一致
        for target in graph.targets {
            let edgeJobs = graph.edges
                .filter { $0.targetID == target.id }
                .map(\.jobID)
            XCTAssertEqual(edgeJobs, target.jobIDs)
        }
    }

    // MARK: - 175 更新说明

    func testReleaseNotesCurrentFirst() {
        let entries = ReleaseNotes.entries(currentVersion: "0.50.97")
        XCTAssertEqual(entries.first?.version, "0.50.97")
        XCTAssertEqual(entries.count, ReleaseNotes.entries.count)
    }

    func testReleaseNotesUnknownVersionReturnsTable() {
        let entries = ReleaseNotes.entries(currentVersion: "9.9.9")
        XCTAssertEqual(entries, ReleaseNotes.entries)
        XCTAssertNil(ReleaseNotes.entry(forVersion: "9.9.9"))
    }

    func testReleaseNotesContentSanity() {
        XCTAssertFalse(ReleaseNotes.entries.isEmpty)
        for entry in ReleaseNotes.entries {
            XCTAssertFalse(entry.version.isEmpty)
            XCTAssertFalse(entry.highlights.isEmpty)
            XCTAssertTrue(
                entry.highlights.allSatisfy { !$0.isEmpty }
            )
        }
        // 表序新→旧（版本号字符串序在本表范围内成立）
        let versions = ReleaseNotes.entries.map(\.version)
        XCTAssertEqual(versions, versions.sorted(by: >))
    }

    // MARK: - 179 个性化默认值与读口

    private func freshDefaults() -> UserDefaults {
        let suite = "ob-bundle-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testPersonalizationDefaultsAreHouseStyle() {
        let defaults = freshDefaults()
        XCTAssertEqual(
            AppearancePreferences.bubbleStyle(in: defaults),
            .standard
        )
        XCTAssertEqual(
            AppearancePreferences.backgroundStyle(in: defaults),
            .standard
        )
        // 定版三角逐值＝旧常量（22/22/7），未设置呈现零变化
        let style = ChatBubbleStyle.standard
        XCTAssertEqual(style.bubbleCorner, 22)
        XCTAssertEqual(style.assistantBubbleCorner, 22)
        XCTAssertEqual(style.bubbleTailCorner, 7)
    }

    func testPersonalizationRoundtripAndDirtyFallback() {
        let defaults = freshDefaults()
        AppearancePreferences.setBubbleStyle(
            .rounded, in: defaults
        )
        AppearancePreferences.setBackgroundStyle(
            .slate, in: defaults
        )
        XCTAssertEqual(
            AppearancePreferences.bubbleStyle(in: defaults),
            .rounded
        )
        XCTAssertEqual(
            AppearancePreferences.backgroundStyle(in: defaults),
            .slate
        )
        XCTAssertEqual(ChatBubbleStyle.rounded.bubbleCorner, 28)
        XCTAssertEqual(ChatBubbleStyle.squared.bubbleCorner, 12)
        // 脏值回定版
        defaults.set(
            "bogus", forKey: AppearanceStorageKeys.chatBubbleStyle
        )
        defaults.set(
            "bogus", forKey: AppearanceStorageKeys.chatBackground
        )
        XCTAssertEqual(
            AppearancePreferences.bubbleStyle(in: defaults),
            .standard
        )
        XCTAssertEqual(
            AppearancePreferences.backgroundStyle(in: defaults),
            .standard
        )
    }

    func testPersonalizationKeysAreDistinct() {
        let keys = [
            AppearanceStorageKeys.chatBubbleStyle,
            AppearanceStorageKeys.chatBackground,
            AppearanceStorageKeys.chatTheme,
            AppearanceStorageKeys.avatarSize,
            AppearanceStorageKeys.appearanceMode,
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
