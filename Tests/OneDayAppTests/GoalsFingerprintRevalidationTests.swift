import OneDayCore
import XCTest
@testable import OneDayApp

/// G-3a（2026-11-24）目标在面指纹重验钉测：指纹没变
/// ＝名单与条目零扰动；指纹变了＝名单换新＋已打开详
/// 情的目标回拉条目流（智能体新记的进展不用退出重
/// 进就能看见，靠的就是这一条）
@MainActor
final class GoalsFingerprintRevalidationTests: XCTestCase {

    private func makeAppState() -> AppState {
        AppState(client: DemoHermesClient(), demoMode: .connected)
    }

    private func goal(fp: String, title: String = "目标") -> BridgeGoal {
        BridgeGoal(
            id: "g_1", title: title, note: "",
            entriesFingerprint: fp, createdAt: 1, updatedAt: 2
        )
    }

    private func entry(id: String, body: String) -> BridgeGoalEntry {
        BridgeGoalEntry(
            id: id, goalId: "g_1", body: body,
            source: .agent, createdAt: 5
        )
    }

    func testRevalidateWithSameFingerprintKeepsEverything() async {
        let script = BridgeScript()
        script.goalsList = [goal(fp: "fp-a")]
        let store = GoalsStore(client: ScriptedBridgeClient(script: script))
        let appState = makeAppState()
        await store.load(appState: appState)
        XCTAssertEqual(store.loadState, .ready)
        XCTAssertEqual(store.goalFingerprints["g_1"], "fp-a")

        await store.revalidateFingerprints(appState: appState)
        // 拉了一遍列表做比对，但名单原样、没有条目回拉
        XCTAssertEqual(script.goalsCount, 2)
        XCTAssertEqual(script.goalEntriesCount, 0)
        XCTAssertEqual(store.goal(id: "g_1")?.title, "目标")
    }

    func testRevalidateWithChangedFingerprintReloadsAndRefetchesOpenedDetail() async {
        let script = BridgeScript()
        script.goalsList = [goal(fp: "fp-a")]
        script.entriesByGoal["g_1"] = [entry(id: "e_1", body: "第一条")]
        let store = GoalsStore(client: ScriptedBridgeClient(script: script))
        let appState = makeAppState()
        await store.load(appState: appState)
        await store.loadDetail(appState: appState, goalID: "g_1")
        XCTAssertEqual(store.entriesByGoal["g_1"]?.map(\.id), ["e_1"])
        let entriesFetchesBefore = script.goalEntriesCount

        // 服务端新记一条：指纹变、条目多一条
        script.goalsList = [goal(fp: "fp-b", title: "目标·新")]
        script.entriesByGoal["g_1"] = [
            entry(id: "e_1", body: "第一条"),
            entry(id: "e_2", body: "智能体新记的"),
        ]
        await store.revalidateFingerprints(appState: appState)

        XCTAssertEqual(store.goal(id: "g_1")?.title, "目标·新")
        XCTAssertEqual(store.goalFingerprints["g_1"], "fp-b")
        XCTAssertEqual(
            store.entriesByGoal["g_1"]?.map(\.id), ["e_1", "e_2"]
        )
        XCTAssertGreaterThan(script.goalEntriesCount, entriesFetchesBefore)
    }
}
