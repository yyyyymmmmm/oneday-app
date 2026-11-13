import Combine
import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §208 枢纽收段＋卡片式呈现的装配门：
/// ①分段集合恰为四段且顺序对（活动/定时/浏览器/
///   身份）——七段时代的 UI 回归门在 UITests 侧同
///   步改口径，本门在单元层钉死集合本体；
/// ②通知落点改道：原指向任务/审核/监测三撤段的落
///   点全部落活动段（AgentHubView.segment(for:) 纯
///   映射）；
/// ③转场帧级自查（可测面）：枢纽以系统 sheet 大
///   detent 呈现——非全屏硬顶、落定留边、圆角容器
///   在场、呈现/关闭全程有帧位移（非硬切）。录屏
///   级的逐帧形态比对归真机待验（报告 §真机待验）。
final class HubSegmentsConsolidationTests: XCTestCase {

    // MARK: - ① 分段集合

    func testSegmentsAreExactlyFourInOrder() {
        XCTAssertEqual(
            HubSegment.allCases,
            [.activity, .cron, .browser, .identity]
        )
        XCTAssertEqual(
            HubSegment.allCases.map(\.title),
            ["活动", "定时", "浏览器", "身份"]
        )
        XCTAssertEqual(
            HubSegment.allCases.map(\.systemImage),
            ["list.bullet", "clock", "display", "touchid"]
        )
    }

    func testAvailableSegmentsPerMode() {
        XCTAssertEqual(
            AgentHubView(mode: .sheet).availableSegments,
            [.activity, .cron, .browser, .identity]
        )
        XCTAssertEqual(
            AgentHubView(mode: .activity).availableSegments,
            [.activity]
        )
    }

    // MARK: - ② 落点改道

    func testRetiredSegmentDestinationsRerouteToActivity() {
        XCTAssertEqual(
            AgentHubView.segment(for: .approvalDecision(id: "rec-1")),
            .activity
        )
        XCTAssertEqual(
            AgentHubView.segment(for: .approvalHome),
            .activity
        )
        XCTAssertEqual(
            AgentHubView.segment(
                for: .monitorChange(monitorID: "mon-1", changeID: "chg-1")
            ),
            .activity
        )
        XCTAssertEqual(
            AgentHubView.segment(for: .monitorsHome),
            .activity
        )
    }

    // MARK: - ③ 卡片式呈现探针

    /// 呈现装配台：与 ChatView 同一修饰符
    /// （hubSheetPresentation）把枢纽挂在 .sheet 上
    private struct HubSheetHarness: View {
        @ObservedObject var box: HubPresentationProbeBox
        var body: some View {
            Color.clear
                .sheet(isPresented: $box.presented) {
                    AgentHubView(mode: .sheet)
                        .hubSheetPresentation()
                }
        }
    }

    @MainActor
    func testHubSheetPresentationIsCardStyleWithMotion() throws {
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
            rootView: HubSheetHarness(box: box)
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

        // 打开：采样呈现全程的被呈视图帧位（minY）
        box.presented = true
        var presentMinYs: [CGFloat] = []
        var presentedVC: UIViewController?
        let presentDeadline = Date().addingTimeInterval(8)
        while Date() < presentDeadline {
            if let vc = host.presentedViewController {
                presentedVC = vc
                presentMinYs.append(
                    vc.view.convert(vc.view.bounds, to: window).minY
                )
                if vc.view.bounds.height > 0,
                   presentMinYs.count > 30,
                   let last = presentMinYs.last,
                   abs(last - (presentMinYs.suffix(5).first ?? last)) < 0.5 {
                    break // 落定（近 5 帧不动）
                }
            }
            spin(seconds: 0.016)
        }
        let presented = try XCTUnwrap(
            presentedVC, "枢纽 sheet 未在限时内呈现"
        )

        // 不是全屏硬顶：呈现样式非 fullScreen、sheet
        // 控制器在位且含 .large detent
        XCTAssertNotEqual(
            presented.modalPresentationStyle, .fullScreen,
            "枢纽不许再走 fullScreenCover 式全屏呈现"
        )
        let sheet = try XCTUnwrap(
            presented.sheetPresentationController,
            "枢纽呈现缺 sheet 控制器（非卡片式呈现）"
        )
        XCTAssertEqual(
            sheet.detents.count, 1,
            "枢纽 sheet 应只有 .large 一个 detent：\(sheet.detents)"
        )
        XCTAssertEqual(
            sheet.selectedDetentIdentifier, .large,
            "枢纽 sheet 落定 detent 应为 .large"
        )

        // 落定形态：被呈视图在窗口内留顶边（卡片浮
        // 起而非贴满）、且祖先链上有圆角容器
        let settled = presented.view.convert(
            presented.view.bounds, to: window
        )
        XCTAssertGreaterThan(
            settled.minY, 0.5,
            "落定帧应留顶边（卡片形态），实测 minY=\(settled.minY)"
        )
        XCTAssertLessThanOrEqual(settled.maxY, window.bounds.height + 0.5)
        var cornerFound = false
        var cursor: UIView? = presented.view
        while let view = cursor {
            if view.layer.cornerRadius >= 8,
               view.layer.maskedCorners.contains(.layerMinXMinYCorner) {
                cornerFound = true
                break
            }
            cursor = view.superview
        }
        XCTAssertTrue(
            cornerFound, "被呈视图祖先链上无圆角容器（卡片圆角不在场）"
        )

        // 关闭：反向位移采样（回缩下滑＝minY 增大）
        box.presented = false
        var dismissMinYs: [CGFloat] = []
        let dismissDeadline = Date().addingTimeInterval(8)
        while Date() < dismissDeadline {
            if let vc = host.presentedViewController {
                dismissMinYs.append(
                    vc.view.convert(vc.view.bounds, to: window).minY
                )
            } else {
                break
            }
            spin(seconds: 0.016)
        }
        XCTAssertNil(
            host.presentedViewController, "枢纽 sheet 未在限时内关闭"
        )

        // 非硬切证据：呈现或关闭任一程出现 >24pt 的
        // 帧位移（卡从下方升起/回缩下滑的轨迹）；全
        // 程样本打进日志供帧级对账
        let presentTravel = (presentMinYs.max() ?? 0)
            - (presentMinYs.min() ?? 0)
        let dismissTravel = (dismissMinYs.max() ?? 0)
            - (dismissMinYs.min() ?? 0)
        print(
            "HUB-SHEET-PROBE presentSamples=\(presentMinYs.count) "
                + "presentTravel=\(presentTravel) "
                + "dismissSamples=\(dismissMinYs.count) "
                + "dismissTravel=\(dismissTravel) "
                + "settled=\(settled)"
        )
        XCTAssertTrue(
            presentTravel > 24 || dismissTravel > 24,
            "呈现/关闭全程无帧位移（硬切嫌疑）：presentTravel="
                + "\(presentTravel) dismissTravel=\(dismissTravel)"
        )
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
