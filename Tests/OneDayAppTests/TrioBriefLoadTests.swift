import OneDayCore
import XCTest
@testable import OneDayApp

/// §473 件一钉测：FeedStore.loadBrief 单读口——编辑
/// 器「打开必回读＋pending 轻轮询」的店侧落点。旧病
/// 是编辑器打开时 briefDoc 非空即跳过回读、打开期间
/// 无任何刷新路径，服务端润色写回永远进不了编辑器；
/// 本口必须每次调用都真拉、且新值整替存量。
@MainActor
final class TrioBriefLoadTests: XCTestCase {

    private func makeAppState() -> AppState {
        AppState(client: DemoHermesClient(), demoMode: .connected)
    }

    private func doc(
        _ text: String, polishState: String
    ) -> BridgeBriefDoc {
        BridgeBriefDoc(
            brief: text, interest: text,
            text: text, polished: polishState == "done",
            polishStateRaw: polishState
        )
    }

    func testLoadBriefFetchesAndReplacesEveryCall() async {
        let script = BridgeScript()
        let store = FeedStore(
            client: ScriptedBridgeClient(script: script)
        )
        let appState = makeAppState()

        script.feedBriefResult = doc("原文", polishState: "pending")
        await store.loadBrief(appState: appState)
        XCTAssertEqual(script.feedBriefCount, 1)
        XCTAssertEqual(store.briefDoc?.polishState, .pending)
        XCTAssertEqual(
            store.briefDoc.map(FeedBriefBoard.effectiveText), "原文"
        )

        // 轮询再读：服务端已写回专业稿——整替、不留旧值
        script.feedBriefResult = doc(
            "整理后的正式简报", polishState: "done"
        )
        await store.loadBrief(appState: appState)
        XCTAssertEqual(script.feedBriefCount, 2)
        XCTAssertEqual(store.briefDoc?.polishState, .done)
        XCTAssertEqual(
            store.briefDoc.map(FeedBriefBoard.effectiveText),
            "整理后的正式简报"
        )
    }

    func testLoadBriefFailureKeepsExistingDoc() async {
        let script = BridgeScript()
        let store = FeedStore(
            client: ScriptedBridgeClient(script: script)
        )
        let appState = makeAppState()

        script.feedBriefResult = doc("原文", polishState: "pending")
        await store.loadBrief(appState: appState)
        XCTAssertNotNil(store.briefDoc)

        // 脚本改回抛错：存量 briefDoc 保留、不被清成空
        script.feedBriefResult = nil
        await store.loadBrief(appState: appState)
        XCTAssertEqual(script.feedBriefCount, 2)
        XCTAssertEqual(
            store.briefDoc.map(FeedBriefBoard.effectiveText), "原文"
        )
    }
}
