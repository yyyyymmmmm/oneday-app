import XCTest
@testable import OneDayCore

/// 活头像状态机/分类/目录裁决钉测（§479）：状态只
/// 认事件、不认计时猜测；瞬时窗与睡眠全走注入时钟。
final class LivingAvatarTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - 工具族分类

    func testFamilyClassifier() {
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "write_file"), .write)
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "patch"), .write)
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "read_file"), .search)
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "web_search"), .search)
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "terminal"), .execute)
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "execute_code"), .execute)
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "delegate_task"), .delegate)
        // 映射缺失/语义含混一律 general，不硬猜
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "memory"), .general)
        XCTAssertEqual(
            LivingToolFamilyClassifier.classify(
                toolName: "no_such_tool"), .general)
    }

    // MARK: - 状态机主链

    func testRunLifecycleStates() {
        var machine = LivingAvatarStateMachine(startedAt: t0)
        XCTAssertEqual(machine.state(at: t0), .idle)
        machine.handle(.runStarted, at: t0)
        XCTAssertEqual(machine.state(at: t0), .thinking)
        machine.handle(.toolStarted(.write), at: t0 + 1)
        XCTAssertEqual(
            machine.state(at: t0 + 1), .working(.write))
        machine.handle(
            .toolCompleted(family: .write, failed: false), at: t0 + 2)
        XCTAssertEqual(machine.state(at: t0 + 2), .thinking)
        machine.handle(.textDelta, at: t0 + 3)
        XCTAssertEqual(machine.state(at: t0 + 3), .speaking)
        // 工具再起：说话让位干活
        machine.handle(.toolStarted(.search), at: t0 + 4)
        XCTAssertEqual(
            machine.state(at: t0 + 4), .working(.search))
        machine.handle(
            .toolCompleted(family: .search, failed: false),
            at: t0 + 5)
        machine.handle(.terminalCompleted, at: t0 + 6)
        XCTAssertEqual(machine.state(at: t0 + 6), .done)
        // 完成是瞬时态：呈示窗过后回空闲
        XCTAssertEqual(machine.state(at: t0 + 9), .idle)
    }

    func testToolFailureBlockedThenSuperseded() {
        var machine = LivingAvatarStateMachine(startedAt: t0)
        machine.handle(.runStarted, at: t0)
        machine.handle(.toolStarted(.execute), at: t0)
        machine.handle(
            .toolCompleted(family: .execute, failed: true), at: t0 + 1)
        XCTAssertEqual(machine.state(at: t0 + 1), .blocked)
        // run 续走（新工具起）：错态即清、不许还挂着
        machine.handle(.toolStarted(.search), at: t0 + 2)
        XCTAssertEqual(
            machine.state(at: t0 + 2), .working(.search))
    }

    func testRunFailureBlockedWindow() {
        var machine = LivingAvatarStateMachine(startedAt: t0)
        machine.handle(.runStarted, at: t0)
        machine.handle(.terminalFailed, at: t0 + 1)
        XCTAssertEqual(machine.state(at: t0 + 1), .blocked)
        XCTAssertEqual(machine.state(at: t0 + 10), .blocked)
        XCTAssertEqual(machine.state(at: t0 + 11.1), .idle)
        // 新 run 即清
        var second = LivingAvatarStateMachine(startedAt: t0)
        second.handle(.runStarted, at: t0)
        second.handle(.terminalFailed, at: t0 + 1)
        second.handle(.runStarted, at: t0 + 2)
        XCTAssertEqual(second.state(at: t0 + 2), .thinking)
    }

    func testCancelledAndStreamLostAreNotFailures() {
        var machine = LivingAvatarStateMachine(startedAt: t0)
        machine.handle(.runStarted, at: t0)
        machine.handle(.terminalCancelled, at: t0 + 1)
        XCTAssertEqual(machine.state(at: t0 + 1), .idle)

        var lost = LivingAvatarStateMachine(startedAt: t0)
        lost.handle(.runStarted, at: t0)
        lost.handle(.toolStarted(.general), at: t0)
        lost.handle(.streamLost, at: t0 + 1)
        XCTAssertEqual(lost.state(at: t0 + 1), .idle)
    }

    func testSleepAndWake() {
        var machine = LivingAvatarStateMachine(startedAt: t0)
        XCTAssertEqual(machine.state(at: t0 + 1799), .idle)
        XCTAssertEqual(machine.state(at: t0 + 1800), .asleep)
        // 无 run 的交互唤醒：醒来瞬时态，窗过回空闲
        machine.handle(.interaction, at: t0 + 1800)
        XCTAssertEqual(machine.state(at: t0 + 1800), .waking)
        XCTAssertEqual(machine.state(at: t0 + 1803), .idle)

        // 睡着时直接来新 run：运行态压过醒来、不拖活
        var second = LivingAvatarStateMachine(startedAt: t0)
        second.handle(.runStarted, at: t0 + 1800)
        XCTAssertEqual(
            second.state(at: t0 + 1800), .thinking)
    }

    func testNextTransitionDate() {
        var machine = LivingAvatarStateMachine(startedAt: t0)
        // 未活动：下一个时间点＝入睡时刻
        XCTAssertEqual(
            machine.nextTransitionDate(after: t0),
            t0 + 1800)
        machine.handle(.runStarted, at: t0)
        machine.handle(.terminalCompleted, at: t0 + 5)
        XCTAssertEqual(
            machine.nextTransitionDate(after: t0 + 5),
            t0 + 5 + LivingAvatarStateMachine.doneWindow)
    }

    // MARK: - 目录裁决（fixture 与生产 manifest 同形）

    private func makeCatalog() -> LivingAvatarCatalog {
        let json = """
        {
          "schema": "living-avatar-clips/1",
          "bound_avatar": {"id": "av_bound", "kind": "image"},
          "states": {
            "S1_idle": {
              "file": "idle.mp4", "dark": "idle-dark.mp4"
            },
            "S4_working_general": {
              "file": "working.mp4",
              "dark": "working-dark.mp4"
            },
            "S4_working_write": {
              "file": "making_something.mp4",
              "dark": "making_something-dark.mp4"
            },
            "S6_done": {
              "file": "milestone_level_up.mp4",
              "dark": "milestone_level_up-dark.mp4"
            },
            "S9_asleep_neighbor": {
              "file": null, "dark": "waking-dark.mp4"
            },
            "connecting": {
              "file": "idle.mp4", "dark": "idle-dark.mp4",
              "call": {
                "light": "idle-call-light.mp4",
                "dark": "idle-call-dark.mp4"
              }
            }
          }
        }
        """
        let catalog = LivingAvatarCatalog(
            manifestData: Data(json.utf8))
        XCTAssertNotNil(catalog)
        return catalog!
    }

    func testCatalogResolution() {
        let catalog = makeCatalog()
        let bound = "av_bound"
        XCTAssertEqual(
            catalog.resolve(
                state: .idle, appearance: .light,
                currentAvatarItemID: bound),
            .clip(fileName: "idle.mp4", transient: false))
        XCTAssertEqual(
            catalog.resolve(
                state: .idle, appearance: .dark,
                currentAvatarItemID: bound),
            .clip(fileName: "idle-dark.mp4", transient: false))
        XCTAssertEqual(
            catalog.resolve(
                state: .working(.write), appearance: .dark,
                currentAvatarItemID: bound),
            .clip(
                fileName: "making_something-dark.mp4",
                transient: false))
        // 无专属变体的族落通用
        XCTAssertEqual(
            catalog.resolve(
                state: .working(.search), appearance: .light,
                currentAvatarItemID: bound),
            .clip(fileName: "working.mp4", transient: false))
        XCTAssertEqual(
            catalog.resolve(
                state: .working(.delegate),
                appearance: .light,
                currentAvatarItemID: bound),
            .clip(fileName: "working.mp4", transient: false))
        XCTAssertEqual(
            catalog.resolve(
                state: .done, appearance: .light,
                currentAvatarItemID: bound),
            .clip(
                fileName: "milestone_level_up.mp4",
                transient: true))
        // 思考/说话无专属片段：落 S1 兜底
        XCTAssertEqual(
            catalog.resolve(
                state: .thinking, appearance: .light,
                currentAvatarItemID: bound),
            .clip(fileName: "idle.mp4", transient: false))
        XCTAssertEqual(
            catalog.resolve(
                state: .speaking, appearance: .dark,
                currentAvatarItemID: bound),
            .clip(fileName: "idle-dark.mp4", transient: false))
    }

    func testCatalogFallbacks() {
        let catalog = makeCatalog()
        let bound = "av_bound"
        // 醒来仅深色：浅色回落静态、不拿深色片凑
        XCTAssertEqual(
            catalog.resolve(
                state: .waking, appearance: .dark,
                currentAvatarItemID: bound),
            .clip(fileName: "waking-dark.mp4", transient: true))
        XCTAssertEqual(
            catalog.resolve(
                state: .waking, appearance: .light,
                currentAvatarItemID: bound),
            .staticImage(.appearanceMissing))
        // 出错/睡着：静态（兜底表 §479.5）
        XCTAssertEqual(
            catalog.resolve(
                state: .blocked, appearance: .dark,
                currentAvatarItemID: bound),
            .staticImage(.noClipForState))
        XCTAssertEqual(
            catalog.resolve(
                state: .asleep, appearance: .dark,
                currentAvatarItemID: bound),
            .staticImage(.noClipForState))
        // 绑定不符：整套静态（换图即 stale）
        XCTAssertEqual(
            catalog.resolve(
                state: .idle, appearance: .light,
                currentAvatarItemID: "av_other"),
            .staticImage(.avatarMismatch))
        XCTAssertEqual(
            catalog.resolve(
                state: .idle, appearance: .light,
                currentAvatarItemID: nil),
            .staticImage(.avatarMismatch))
        // 通话空闲位仅目录在册
        XCTAssertEqual(
            catalog.callIdleClip(appearance: .light),
            "idle-call-light.mp4")
        XCTAssertEqual(
            catalog.callIdleClip(appearance: .dark),
            "idle-call-dark.mp4")
        // 坏数据：目录不出（调用方按 catalogMissing 全静态）
        XCTAssertNil(
            LivingAvatarCatalog(manifestData: Data("[]".utf8)))
    }
}
