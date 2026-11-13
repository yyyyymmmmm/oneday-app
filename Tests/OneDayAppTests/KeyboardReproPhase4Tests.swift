import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 键盘真崩配方实验（四期：套件形状复刻）——纯实验代码。
/// 三期定案：所有单格在干净进程隔离跑全部存活（E09/F01/G01 各
/// 15/15、落定阶梯 H01–H04 全存活）——单格构形不是配方本体，
/// 差异在进程史：套件内死亡恒发生在「先前测试装配过生产
/// RootView 并经 XCTest tearDown 拆除」之后的第一批异容器 save。
/// 本组以「成对测试方法」复刻套件形状（方法按字母序执行）：
///   K0：a 在一测内装配 RootView ×5（E10 剂量）→ b 只做种子写
///   K1：a 装配 RootView ×1 → b 只做种子写
///   K2：a 装配 RootView ×2 → b 只做种子写
///   K3：a 只装配最小探针（对照）→ b 只做种子写
/// b 方法除种子写外什么都不做（与解耦组死亡点同形）；a 的拆
/// 除走 XCTest tearDown（window 置 nil），不在方法内手动拆。
@MainActor
final class KeyboardReproPhase4Tests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow?

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func mark(_ cell: String, _ iter: Int) {
        let line = "\(cell) iter=\(iter) ok\n"
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("repro-progress.txt")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    private func assembleRootOnce() throws {
        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        let container = try makeContainer()
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        let w = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        w.rootViewController = host
        w.makeKeyAndVisible()
        w.layoutIfNeeded()
        window = w
        spinRunLoop(seconds: 2.0)
        window?.layoutIfNeeded()
    }

    private func seedOnly(_ cell: String) throws {
        for i in 1...5 {
            let c = try makeContainer()
            let thread = ChatThread()
            thread.title = "旁聊种子"
            c.mainContext.insert(thread)
            try c.mainContext.save()
            mark(cell, i)
        }
    }

    private struct ProbePlain: View {
        @Query private var threads: [ChatThread]
        var body: some View { Text("n=\(threads.count)") }
    }

    // MARK: - K0：a 剂量 ×5

    func testK0_a_assembleRootViewTimes5() throws {
        for _ in 1...5 {
            try assembleRootOnce()
            window?.rootViewController = nil
            window?.isHidden = true
            window = nil
        }
        try assembleRootOnce()
    }

    func testK0_b_seedOnly() throws { try seedOnly("K0B") }

    // MARK: - K1：a 剂量 ×1

    func testK1_a_assembleRootViewOnce() throws {
        try assembleRootOnce()
    }

    func testK1_b_seedOnly() throws { try seedOnly("K1B") }

    // MARK: - K2：a 剂量 ×2

    func testK2_a_assembleRootViewTwice() throws {
        try assembleRootOnce()
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try assembleRootOnce()
    }

    func testK2_b_seedOnly() throws { try seedOnly("K2B") }

    // MARK: - K3：a 最小探针对照

    func testK3_a_assembleProbeOnce() throws {
        let container = try makeContainer()
        let host = UIHostingController(
            rootView: ProbePlain().modelContainer(container)
        )
        let w = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        w.rootViewController = host
        w.makeKeyAndVisible()
        w.layoutIfNeeded()
        window = w
        spinRunLoop(seconds: 1.0)
    }

    func testK3_b_seedOnly() throws { try seedOnly("K3B") }
}
