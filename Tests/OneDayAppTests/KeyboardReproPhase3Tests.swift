import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 键盘真崩配方实验（三期：落定窗口阶梯）——纯实验代码。
/// 二期疑点：E09（落定 1s）必杀、F04（落定 5s）15/15 存活——
/// 受害观察面的「可被击杀窗口」可能在首轮求值后的一段时间窗内。
/// 本组在同一类内阶梯化落定时长（0.5/2/3/8s），其余与 E09 全同
/// （存活纯 @Query 探针＠A＋异容器 B 种子写），每格 5 迭代落标记。
/// 隔离单测（E09/F01/G01 原格单独成 run）由 CI 派发侧控制，
/// 不在本文件。
@MainActor
final class KeyboardReproPhase3Tests: XCTestCase {

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

    private struct ProbePlain: View {
        @Query private var threads: [ChatThread]
        var body: some View { Text("n=\(threads.count)") }
    }

    private func ladder(_ cell: String, settle: TimeInterval) throws {
        for i in 1...5 {
            let a = try makeContainer()
            let host = UIHostingController(
                rootView: ProbePlain().modelContainer(a)
            )
            let w = DeviceWindow(
                frame: CGRect(x: 0, y: 0, width: 402, height: 874)
            )
            w.rootViewController = host
            w.makeKeyAndVisible()
            w.layoutIfNeeded()
            window = w
            spinRunLoop(seconds: settle)
            let b = try makeContainer()
            let thread = ChatThread()
            thread.title = "旁聊种子"
            b.mainContext.insert(thread)
            try b.mainContext.save()
            mark(cell, i)
            window?.rootViewController = nil
            window?.isHidden = true
            window = nil
        }
    }

    func testH01_settle0_5() throws { try ladder("H01", settle: 0.5) }
    func testH02_settle2() throws { try ladder("H02", settle: 2.0) }
    func testH03_settle3() throws { try ladder("H03", settle: 3.0) }
    func testH04_settle8() throws { try ladder("H04", settle: 8.0) }
}
