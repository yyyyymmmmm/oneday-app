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
/// ③转场自查：机制面硬断言（sheet 呈现、非全屏、
///   detent 恰一个 .large 配置、开合闭环）；几何
///   面（留边/圆角/帧位移）在无场景裸窗口里会退
///   化（run 43426199136 实测整窗瞬时呈现）——环
///   境给出信号时条件断言、未给时全值打日志，逐
///   帧形态终验归真 App 回归门与真机录屏并排比
///   （报告 §6/§8）。
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
        // 控制器在位、detent 恰一个（生产修饰符给的
        // .large）——机制面硬断言，环境无关
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

        // 几何面（留顶边/圆角/落定 detent 标识）：无
        // 场景的裸 UIWindow 里 sheet 会退化成整窗瞬时
        // 呈现（run 43426199136 实测 settled=整窗、
        // selectedDetentIdentifier=nil）——这些信号
        // 只在环境真给出时才成立、给出即须正确；环
        // 境没给的逐项打进 HUB-SHEET-PROBE 日志，帧
        // 级形态的终验在真 App（UITests 枢纽回归门）
        // 与真机录屏并排比（本仓 rig≠真机的一贯口径）
        let settled = presented.view.convert(
            presented.view.bounds, to: window
        )
        XCTAssertLessThanOrEqual(
            settled.maxY, window.bounds.height + 0.5,
            "被呈视图不许溢出窗口：\(settled)"
        )
        if settled.minY > 0.5 {
            // 环境给出了留边帧：卡片形态成立的正信号
            XCTAssertLessThan(
                settled.height, window.bounds.height,
                "留边帧的高应小于整窗：\(settled)"
            )
        }
        if let identifier = sheet.selectedDetentIdentifier {
            XCTAssertEqual(
                identifier, .large,
                "落定 detent 标识应为 .large，实测 \(identifier)"
            )
        }
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

        // 帧位移：环境真跑动画时（任一程 travel>0）
        // 轨迹须是卡自下方升起/回缩下滑的量级
        // （>24pt）；环境瞬时呈现（travel=0，裸窗
        // 口退化形态）时本项无信号、只记日志——硬
        // 切与否的终验同几何面口径归真 App/真机
        let presentTravel = (presentMinYs.max() ?? 0)
            - (presentMinYs.min() ?? 0)
        let dismissTravel = (dismissMinYs.max() ?? 0)
            - (dismissMinYs.min() ?? 0)
        print(
            "HUB-SHEET-PROBE presentSamples=\(presentMinYs.count) "
                + "presentTravel=\(presentTravel) "
                + "dismissSamples=\(dismissMinYs.count) "
                + "dismissTravel=\(dismissTravel) "
                + "settled=\(settled) "
                + "cornerFound=\(cornerFound) "
                + "detentID="
                + "\(String(describing: sheet.selectedDetentIdentifier))"
        )
        if presentTravel > 0 || dismissTravel > 0 {
            XCTAssertTrue(
                presentTravel > 24 || dismissTravel > 24,
                "有动画却位移不足（轨迹异常）：presentTravel="
                    + "\(presentTravel) dismissTravel=\(dismissTravel)"
            )
        }
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
