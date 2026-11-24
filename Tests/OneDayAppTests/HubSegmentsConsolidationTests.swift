import Combine
import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §434 枢纽五格注册表＋全页 push 呈现的装配门
/// （本文件前身为 §217 收段＋sheet 卡片式门，呈现
/// 与格集口径均由 §434 覆盖，逐项改写如下）：
/// ①格集由注册表裁决：裸装配（无回读、无 Box
///   钥）时可见段恒为锚格序首工作＋含身份、恒不
///   含邮箱（mail 位未广告）；格集全量裁决矩阵
///   在 Core HubSegmentRegistryTests 钉死；
/// ②通知落点改道：原指向任务/审核/监测三撤段的
///   落点全部落工作段（AgentHubView.segment
///   (for:) 纯映射）；
/// ③分段条量测钉（§222 值不变）；
/// ④呈现探针：中枢经 fullScreenCover 卡片呈现
///   （§502）——本 rig 内机制面硬断言＝开启后
///   presentedViewController 物化且样式为
///   .fullScreen（非 sheet 卡）；全页帧/底栏覆
///   盖归真 App UITests（HubCardPresentati-
///   onUITests）与真机（rig≠真机一贯口径）。
final class HubSegmentsConsolidationTests: XCTestCase {

    // MARK: - ① 注册表锚格

    func testAvailableSegmentsStartWithAnchors() {
        let segments = AgentHubView().availableSegments
        XCTAssertEqual(
            segments.first, .work,
            "格集序首恒为工作格（参照胶囊序）：\(segments)"
        )
        XCTAssertTrue(
            segments.contains(.identity),
            "身份锚格恒在：\(segments)"
        )
        XCTAssertFalse(
            segments.contains(.mail),
            "邮箱格在 mail 位未广告时不许长出：\(segments)"
        )
        XCTAssertFalse(
            segments.contains(.audit),
            "无回读活证时审核格不长（注册表纪律）：\(segments)"
        )
    }

    /// 注册表初值输入：Box 在位只认钥匙串真状态、
    /// 其余回读旗恒 false（回读后由 refreshSeg-
    /// mentInputs 刷新）
    func testInitialSegmentInputsAreHonest() {
        let inputs = AgentHubView.initialSegmentInputs()
        XCTAssertTrue(inputs.connected)
        XCTAssertFalse(inputs.grantsReadbackOK)
        XCTAssertFalse(inputs.approvalsReadbackOK)
        XCTAssertFalse(inputs.mailAdvertised)
        XCTAssertEqual(
            inputs.boxConfigured,
            KeychainStore.read(account: "box.mcp.key") != nil
        )
    }

    // MARK: - §222 分段条量测钉

    /// §222（枢纽页对 Muse 重建）：自绘胶囊条的三
    /// 个量测值钉死（对基准真机图：条高 48／选中胶
    /// 囊 36／图标 22），且条高不低于命中下限、胶囊
    /// 恒纳于条内——防后续顺手改值把对齐量测改没
    func testHubSegmentBarMetricsMatchParitySpec() {
        XCTAssertEqual(OneDayMetrics.hubSegBarHeight, 48)
        XCTAssertEqual(OneDayMetrics.hubSegCapsuleHeight, 36)
        XCTAssertEqual(OneDayMetrics.hubSegGlyphSize, 22)
        XCTAssertGreaterThanOrEqual(
            OneDayMetrics.hubSegBarHeight,
            OneDayMetrics.minTapTarget
        )
        XCTAssertLessThan(
            OneDayMetrics.hubSegCapsuleHeight,
            OneDayMetrics.hubSegBarHeight
        )
    }

    // MARK: - ② 落点改道

    func testRetiredSegmentDestinationsRerouteToWork() {
        XCTAssertEqual(
            AgentHubView.segment(for: .approvalDecision(id: "rec-1")),
            .work
        )
        XCTAssertEqual(
            AgentHubView.segment(for: .approvalHome),
            .work
        )
        XCTAssertEqual(
            AgentHubView.segment(
                for: .monitorChange(monitorID: "mon-1", changeID: "chg-1")
            ),
            .work
        )
        XCTAssertEqual(
            AgentHubView.segment(for: .monitorsHome),
            .work
        )
    }

    // MARK: - ④ 全页呈现探针（§502 改钉）

    /// 呈现装配台：与 ChatView 同一呈现构造
    /// （fullScreenCover＋HubCardHost 卡片宿主，
    /// §502；旧 push＋zoom＋hubFullPageChrome 装
    /// 配随 §434 呈现退役，改钉归因见 DESIGN §502）
    private struct HubCardHarness: View {
        @ObservedObject var box: HubPresentationProbeBox

        var body: some View {
            Color.clear
                .fullScreenCover(isPresented: $box.presented) {
                    HubCardHost(
                        onDismissed: { box.presented = false }
                    ) { _ in
                        AgentHubView()
                    }
                }
        }
    }


    @MainActor
    func testHubCardPresentationIsFullScreenNotSheet() throws {
        let appState = AppState()
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        let box = HubPresentationProbeBox()
        let host = UIHostingController(
            rootView: HubCardHarness(box: box)
                .environment(appState)
                .modelContainer(container)
        )
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        spin(seconds: 0.6)

        // 本 rig 的信号边界（§434 探针三轮诊断实
        // 测沿用）：无场景裸 UIWindow 里 SwiftUI 内
        // 容不物化，帧级断言不成立；但模态呈现在本
        // rig 会物化出 presentedViewController
        // （§217 旧探针实证）。§502 口径：中枢是
        // fullScreenCover 全屏覆盖（非 sheet 卡）——
        // 可判别断言＝开启后 presentedViewControl-
        // ler 物化且 modalPresentationStyle 为
        // .fullScreen（sheet 卡为 .pageSheet 等、
        // 不许命中）；关闭后 presented 归 nil
        box.presented = true
        var sawFullScreenCover = false
        let presentDeadline = Date().addingTimeInterval(8)
        while Date() < presentDeadline {
            if let presented = host.presentedViewController {
                // SwiftUI fullScreenCover 的呈现样式
                // 实测为 .overFullScreen（rawValue 5，
                // 底层留场正合 §502 背板透出所需）或
                // .fullScreen——同属全屏覆盖族；sheet
                // 卡为 .pageSheet/.formSheet，不许命中
                XCTAssertTrue(
                    presented.modalPresentationStyle == .fullScreen
                        || presented.modalPresentationStyle
                            == .overFullScreen,
                    "中枢须是全屏覆盖、不许是 sheet 卡形态"
                        + "（实测 rawValue "
                        + "\(presented.modalPresentationStyle.rawValue)）"
                )
                sawFullScreenCover = true
                break
            }
            spin(seconds: 0.016)
        }
        XCTAssertTrue(
            sawFullScreenCover,
            "fullScreenCover 未在本 rig 物化出呈现控制器"
        )
        box.presented = false
        let dismissDeadline = Date().addingTimeInterval(8)
        var dismissed = false
        while Date() < dismissDeadline {
            if host.presentedViewController == nil {
                dismissed = true
                break
            }
            spin(seconds: 0.016)
        }
        XCTAssertTrue(dismissed, "关闭后呈现控制器未退场")
    }

    private func spin(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }
}

/// 呈现开关探针盒（测试与装配台之间传呈现意图）
final class HubPresentationProbeBox: ObservableObject {
    @Published var presented = false
}
