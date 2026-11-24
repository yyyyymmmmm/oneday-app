import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §351 探针（诊断用、只打印不设卡顿断言）：量动画
/// 期间三件事——①内容宿主子树 layoutSubviews 次数
/// （逐帧布局的直接证据）②CADisplayLink 帧间隔分
/// 布（死帧）③clip/内容宿主 presentation 帧的逐帧
/// 变化（几何是否逐帧被改）。刚体断言在
/// DrawerRigidBodyTests，本组只出量测数字供前后对比
@MainActor
final class DrawerMotionProbeTests: XCTestCase {
    private var window: UIWindow!
    private var controller: DrawerContainerController!
    private var layoutCounter: LayoutCounter!

    override func setUp() async throws {
        try await super.setUp()
        layoutCounter = LayoutCounter()
        controller = DrawerContainerController()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    /// 负载装配（放测试体内：setUp 里 spin/重内容装
    /// 配与既有套件口径不一致、会把 setUp 拖超时）
    private func installLoad() {
        let counter = layoutCounter!
        controller.contentRoot = AnyView(
            List(0..<120) { index in
                Text("行 \(index) 内容负载行")
            }
            .overlay {
                LayoutCountingRepresentable(counter: counter)
            }
        )
        controller.drawerBuilder = { _ in
            AnyView(
                List(0..<60) { index in
                    Text("抽屉行 \(index)")
                }
            )
        }
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.8)
    }

    override func tearDown() async throws {
        window.isHidden = true
        window = nil
        controller = nil
        layoutCounter = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    private var foreground: UIView { controller.view.subviews[1] }
    private var clipView: UIView { foreground.subviews[1] }
    private var contentView: UIView { clipView.subviews[0] }

    func testProbeOpenCloseHitchProfile() {
        installLoad()
        print(
            "PROBE contentFrame="
            + "\(contentView.frame)"
            + " clipFrame=\(clipView.frame)"
        )
        let sampler = FrameSampler(
            foreground: foreground, clip: clipView, content: contentView
        )
        for round in 1...3 {
            layoutCounter.reset()
            sampler.start()
            controller.setDrawer(true, animated: true)
            spinRunLoop(seconds: 1.1)
            sampler.stop()
            print(
                "PROBE open#\(round): layouts="
                + "\(layoutCounter.count) maxGapMs="
                + "\(sampler.maxGapMs) gapsOver25ms="
                + "\(sampler.gapsOver25ms) fgTx=\(sampler.distinctFgTx) presNonNil=\(sampler.presNonNil) clipPresFrames="
                + "\(sampler.distinctClipFrames) contentPresFrames="
                + "\(sampler.distinctContentFrames) samples="
                + "\(sampler.samples)"
            )
            layoutCounter.reset()
            sampler.start()
            controller.setDrawer(false, animated: true)
            spinRunLoop(seconds: 1.1)
            sampler.stop()
            print(
                "PROBE close#\(round): layouts="
                + "\(layoutCounter.count) maxGapMs="
                + "\(sampler.maxGapMs) gapsOver25ms="
                + "\(sampler.gapsOver25ms) fgTx=\(sampler.distinctFgTx) presNonNil=\(sampler.presNonNil) clipPresFrames="
                + "\(sampler.distinctClipFrames) contentPresFrames="
                + "\(sampler.distinctContentFrames) samples="
                + "\(sampler.samples)"
            )
        }
    }
}

/// 内容子树布局计数（UIView.layoutSubviews 覆写计数）
final class LayoutCounter {
    var count = 0
    func reset() { count = 0 }
}

private final class LayoutCountingView: UIView {
    var counter: LayoutCounter?
    override func layoutSubviews() {
        super.layoutSubviews()
        counter?.count += 1
    }
}

private struct LayoutCountingRepresentable: UIViewRepresentable {
    let counter: LayoutCounter
    func makeUIView(context: Context) -> LayoutCountingView {
        let view = LayoutCountingView()
        view.counter = counter
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: LayoutCountingView, context: Context) {}
}

/// 逐帧采样：displaylink 间隔＋两层 presentation 帧集合
private final class FrameSampler: NSObject {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private(set) var maxGapMs: Double = 0
    private(set) var gapsOver25ms = 0
    private(set) var samples = 0
    private var clipFrames = Set<String>()
    private var contentFrames = Set<String>()
    private var fgTxValues = Set<String>()
    private(set) var presNonNil = 0
    var distinctClipFrames: Int { clipFrames.count }
    var distinctContentFrames: Int { contentFrames.count }
    var distinctFgTx: Int { fgTxValues.count }
    private weak var foreground: UIView?
    private weak var clip: UIView?
    private weak var content: UIView?

    init(foreground: UIView, clip: UIView, content: UIView) {
        self.foreground = foreground
        self.clip = clip
        self.content = content
    }

    func start() {
        maxGapMs = 0
        gapsOver25ms = 0
        samples = 0
        clipFrames = []
        contentFrames = []
        fgTxValues = []
        presNonNil = 0
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp > 0 {
            let gap = (link.timestamp - lastTimestamp) * 1000
            if gap > maxGapMs { maxGapMs = gap }
            if gap > 25 { gapsOver25ms += 1 }
        }
        lastTimestamp = link.timestamp
        samples += 1
        if let tx = foreground?.layer.presentation()?.transform.m41 {
            presNonNil += 1
            fgTxValues.insert(String(format: "%.1f", tx))
        }
        if let frame = clip?.layer.presentation()?.frame {
            clipFrames.insert(
                "\(Int(frame.minX)),\(Int(frame.minY)),"
                + "\(Int(frame.width)),\(Int(frame.height))"
            )
        }
        if let frame = content?.layer.presentation()?.frame {
            contentFrames.insert(
                "\(Int(frame.minX)),\(Int(frame.minY)),"
                + "\(Int(frame.width)),\(Int(frame.height))"
            )
        }
    }
}
