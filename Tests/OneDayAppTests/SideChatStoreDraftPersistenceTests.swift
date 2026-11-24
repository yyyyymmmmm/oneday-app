import XCTest
@testable import OneDayApp

/// §396 钉测（总表 151 定案）：草稿持久化口径
/// 把守——维持「草稿按线程落 UserDefaults、跨
/// 重启存续」（基础止血包 P3 按用户实报「切会
/// 话回来已输入文字丢失」修的保活口径；2026-
/// 11-23 裁定不学 OpenBot 纯内存草稿，见 DESIGN
/// §396.2）。任一断言红＝保活口径被改动，须先
/// 回 §396 裁定复核
@MainActor
final class SideChatStoreDraftPersistenceTests:
    XCTestCase
{
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName =
            "test.sidechats.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(
            forName: suiteName
        )
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// 跨实例读回＝跨重启语义：写入店关掉后，新
    /// 店从同一 UserDefaults 读回同一草稿
    func testDraftSurvivesAcrossStoreInstances() {
        let thread = UUID()
        let writer = SideChatStore(defaults: defaults)
        writer.setDraft("写了一半的回复", for: thread)
        let reader = SideChatStore(defaults: defaults)
        XCTAssertEqual(
            reader.draft(for: thread), "写了一半的回复"
        )
    }

    /// 空串即清键（发送后清草稿的落点）：清后新
    /// 实例读回 nil
    func testEmptyDraftClearsPersistedValue() {
        let thread = UUID()
        let writer = SideChatStore(defaults: defaults)
        writer.setDraft("待发草稿", for: thread)
        writer.setDraft("", for: thread)
        let reader = SideChatStore(defaults: defaults)
        XCTAssertNil(reader.draft(for: thread))
    }

    /// 草稿逐线程独立：A 线程的草稿不串到 B 线程
    func testDraftsArePerThread() {
        let threadA = UUID()
        let threadB = UUID()
        let store = SideChatStore(defaults: defaults)
        store.setDraft("甲线程草稿", for: threadA)
        XCTAssertEqual(
            store.draft(for: threadA), "甲线程草稿"
        )
        XCTAssertNil(store.draft(for: threadB))
    }

    /// 演示模式纯内存不落盘：persisted=false 的
    /// 店写草稿后，落盘店在同一档案读不到
    func testDemoModeStoreDoesNotPersist() {
        let thread = UUID()
        let memory = SideChatStore(persisted: false)
        memory.setDraft("演示草稿", for: thread)
        XCTAssertEqual(
            memory.draft(for: thread), "演示草稿"
        )
        let reader = SideChatStore(defaults: defaults)
        XCTAssertNil(reader.draft(for: thread))
    }
}
