import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §185 步骤二结构取证探针：文件页（DeliverablesView）根为
/// VStack（身份头＋分段＋滚动面），其滚动面帧是否止于底
/// 安全区、内容能否流到浮动底坞之下，代码静态读法定不
/// 死——本探针在真实 UIWindow＋UIHostingController 里量
/// 三种结构的 UIScrollView 帧（换算到窗口坐标）与
/// adjustedContentInset，宿主 additionalSafeAreaInsets
/// 设 top=59／bottom=83 模拟顶栏带与浮动底坞。
/// 帧值只打日志（BGP-PROBE 前缀）不作断言，结论由主线
/// 读 CI 日志裁决；探针去留另行决定。
@MainActor
final class ShellBgStructureProbeTests: XCTestCase {

    private func settle(_ window: UIWindow) async {
        window.layoutIfNeeded()
        let exp = expectation(description: "layout settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 2)
        window.layoutIfNeeded()
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    private func measure<Content: View>(
        label: String, @ViewBuilder content: () -> Content
    ) async throws {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 852)
        )
        let hosting = UIHostingController(rootView: content())
        hosting.additionalSafeAreaInsets = UIEdgeInsets(
            top: 59, left: 0, bottom: 83, right: 0
        )
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        await settle(window)

        let sv = findScrollView(in: hosting.view)
        XCTAssertNotNil(sv, "\(label): UIScrollView not found")
        guard let sv else { return }
        // 帧必须换算到窗口坐标——sv.frame 是父视图坐标，
        // 直接与 windowH 比即 v1 仪表错误（见胶囊扫描教训）
        let rect = sv.convert(sv.bounds, to: window)
        print(
            "BGP-PROBE \(label) frameTop=\(rect.minY) "
                + "frameBottom=\(rect.maxY) windowH=\(window.frame.height) "
                + "adjInsetTop=\(sv.adjustedContentInset.top) "
                + "adjInsetBottom=\(sv.adjustedContentInset.bottom)"
        )
    }

    private func rows(_ prefix: String) -> some View {
        VStack(spacing: 8) {
            ForEach(0..<40, id: \.self) { i in
                Text("\(prefix) line \(i)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.2))
            }
        }
        .padding()
    }

    /// 模式 A（对照）：ScrollView 直接作根
    func testProbeScrollViewAsRoot() async throws {
        try await measure(label: "A") {
            ScrollView { rows("A") }
        }
    }

    /// 模式 B（文件页形态）：VStack｛固定高头部; 固定高
    /// 分段行; ScrollView｝
    func testProbeVStackWithScrollView() async throws {
        try await measure(label: "B") {
            VStack(spacing: 0) {
                Text("Header")
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.blue.opacity(0.3))
                HStack { Text("Seg 1"); Text("Seg 2") }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.green.opacity(0.3))
                ScrollView { rows("B") }
            }
        }
    }

    /// 模式 C（动态/点子页形态）：List 作根
    func testProbeListAsRoot() async throws {
        try await measure(label: "C") {
            List {
                ForEach(0..<40, id: \.self) { i in
                    Text("C item \(i)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .listStyle(.plain)
        }
    }
}
