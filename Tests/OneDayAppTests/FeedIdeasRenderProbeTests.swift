import OneDayCore
import SwiftUI
import UIKit
import XCTest

@testable import OneDayApp

/// §486 渲染/托管探针（改前无此件）：
/// ①演示模式下动态页无帖数据（未连接态），行内新件
/// FeedLinkPreviewCard 无法在整机面上验——以 Image-
/// Renderer 离屏渲染两形态（带路径/根路径）落 PNG。
/// ②页头滚动行为同理无真列表可滚——以托管副本验机
/// 制：真 ContentPageHeader＋与 FeedView 同式的几何
/// 归一化公式（offset＋顶 inset），断言静止偏移≈0、
/// 滚过旧收起阈值 24 后偏移实达（滚动真发生）。
/// §498 翻案：§486.4 的整簇收起废止——副本不再有
/// collapsed 状态可断，改断「簇恒在」：两帧（静止/
/// 滚后）落盘供墨迹比对，滚后帧页头区须与静止帧同
/// 位同形（组版/真机帧同口径复核）。
final class FeedIdeasRenderProbeTests: XCTestCase {

    func testPostGalleryOpensSelectedImageInPostOrder() throws {
        let first = try XCTUnwrap(URL(string: "https://example.com/first.jpg"))
        let second = try XCTUnwrap(URL(string: "https://example.com/second.jpg"))
        let images = [first.absoluteString, "", first.absoluteString, second.absoluteString]
            .map { BridgeFeedImage(url: $0, sourceUrl: "") }

        let session = try XCTUnwrap(ImageViewerSession(
            feedImages: images, selectedURL: second, previewLongEdge: 1600
        ))
        XCTAssertEqual(session.initialIndex, 1)
        XCTAssertEqual(session.items.map(\.source), [
            .publicURL(first, previewLongEdge: 1600),
            .publicURL(second, previewLongEdge: 1600),
        ])
    }

    @MainActor
    func testRenderLinkPreviewCards() throws {
        let cases: [(String, BridgeFeedLink)] = [
            ("linkcard-path", BridgeFeedLink(
                title: "GitHub trending this week",
                url: "https://githubtrending.today/weekly"
            )),
            ("linkcard-root", BridgeFeedLink(
                title: "octo/hello：打招呼仓库",
                url: "https://github.com/octo/hello"
            )),
        ]
        for (name, link) in cases {
            let view = FeedLinkPreviewCard(link: link)
                .frame(width: 310)
                .padding(20)
                .background(Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            let data = try XCTUnwrap(image.pngData())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(name).png")
            try data.write(to: url)
            print("RENDERED \(name) size=\(image.size) -> \(url.path)")
        }
    }

    // MARK: - 页头恒常驻托管副本（§498）

    private final class ScrollFlag {
        var restOffset: CGFloat?
        var maxOffset: CGFloat = 0
    }

    private struct PinnedHeaderReplica: View {
        let flag: ScrollFlag

        var body: some View {
            VStack(spacing: 0) {
                ContentPageHeader(
                    onOpenHub: {}
                ) {
                    PageHeaderCircleButton(
                        symbol: "slider.horizontal.3",
                        label: "编辑简报"
                    ) {}
                }
                ScrollViewReader { proxy in
                    List {
                        ForEach(0..<40, id: \.self) { i in
                            Text("行 \(i)").id(i)
                        }
                    }
                    .listStyle(.plain)
                    .onScrollGeometryChange(
                        for: CGFloat.self
                    ) { geometry in
                        geometry.contentOffset.y
                            + geometry.contentInsets.top
                    } action: { _, newValue in
                        if flag.restOffset == nil {
                            flag.restOffset = newValue
                        }
                        flag.maxOffset = max(flag.maxOffset, newValue)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 1.2
                        ) {
                            proxy.scrollTo(39, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testHeaderStaysPinnedReplica() async throws {
        let flag = ScrollFlag()
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(
            rootView: PinnedHeaderReplica(flag: flag)
                .environment(AppState())
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await Task.sleep(for: .milliseconds(700))
        try capture(host.view, name: "header-rest")
        // 等滚动实达旧收起阈值之上（上限 6 秒轮询）
        var waited = 0
        while flag.maxOffset <= 24, waited < 60 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        try await Task.sleep(for: .milliseconds(600))
        try capture(host.view, name: "header-scrolled")
        print(
            "PINNED restOffset=\(flag.restOffset ?? -999) "
                + "maxOffset=\(flag.maxOffset)"
        )
        XCTAssertGreaterThan(
            flag.maxOffset, 24,
            "滚动须实达旧收起阈值之上（否则恒在断言无据）"
        )
        if let rest = flag.restOffset {
            XCTAssertLessThan(
                abs(rest), 1.5,
                "静止归一化偏移应≈0，实得 \(rest)"
            )
        }
    }

    @MainActor
    private func capture(_ view: UIView, name: String) throws {
        let renderer = UIGraphicsImageRenderer(
            bounds: view.bounds
        )
        let image = renderer.image { _ in
            view.drawHierarchy(
                in: view.bounds, afterScreenUpdates: true
            )
        }
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("CAPTURED \(name) -> \(url.path)")
    }
}
