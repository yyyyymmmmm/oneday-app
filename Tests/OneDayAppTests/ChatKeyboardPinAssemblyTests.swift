import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §426 缺陷三装配钉：键盘事务贴底跟随——贴底意图
/// 须在键盘开始动之前捕获、事务全程末行完整可见；
/// 离底时键盘升起不许动用户位置。参照对照（用户
/// 双视频）：参照应用键盘起→内容同步上移稳落最新；
/// OneDay 旧链＝键盘不置任何钉底意图、量测在落定
/// 拍一次跳到终值、后续判定按新几何恒读「不在底」
/// →永不重钉、用户须手拉。
@MainActor
final class ChatKeyboardPinAssemblyTests: XCTestCase {
    private var window: UIWindow!
    private var controller: ChatRootViewController!
    private var handle: ChatNativeListHandle!
    private var ids: [UUID] = []

    private let windowHeight: CGFloat = 874
    private let keyboardHeight: CGFloat = 340

    override func tearDown() {
        window?.isHidden = true
        window = nil
        controller = nil
        handle = nil
        super.tearDown()
    }

    private func assemble() {
        let win = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: windowHeight)
        )
        let root = UIViewController()
        win.rootViewController = root
        win.makeKeyAndVisible()
        let listHandle = ChatNativeListHandle()
        let list = ChatRootViewController()
        list.handle = listHandle
        list.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        listHandle.controller = list
        root.addChild(list)
        list.view.frame = root.view.bounds
        root.view.addSubview(list.view)
        list.didMove(toParent: root)
        root.view.layoutIfNeeded()
        window = win
        controller = list
        handle = listHandle
    }

    private func apply(_ rows: [ChatNativeRow]) {
        controller?.apply(
            rows: rows,
            layout: ChatNativeLayout(
                horizontalPadding: OneDayMetrics.pageGutter,
                topPadding: OneDayMetrics.spacingM,
                bottomPadding: 8,
                rowSpacing: OneDayMetrics.spacingL,
                arrowTrailing: OneDayMetrics.spacingM,
                arrowGapAboveComposer: 8,
                arrowSize: OneDayMetrics.minTapTarget
            ),
            topInset: 122,
            bottomMargin: 0,
            composerView: AnyView(
                Rectangle()
                    .fill(Color.gray)
                    .frame(height: 54)
            ),
            arrowView: AnyView(Color.clear)
        )
        window?.layoutIfNeeded()
    }

    private func drain(_ seconds: TimeInterval) {
        let exp = expectation(description: "drain \(seconds)")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 10)
        window?.layoutIfNeeded()
    }

    private func makeRows(count: Int) -> [ChatNativeRow] {
        if ids.count != count {
            ids = (0..<count).map { _ in UUID() }
        }
        return (0..<count).map { index in
            ChatNativeRow(
                key: "r\(index)", entryID: ids[index],
                revision: ChatNativeRowRevision(
                    parts: [.text("row \(index)")]
                ),
                height: 60,
                makeView: {
                    AnyView(
                        Text("row")
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    )
                }
            )
        }
    }

    /// 装配＋落底＋意图消费殆尽（第二遍同批重喂不
    /// 再置冷开意图、留足落定拍把首轮意图按判据消
    /// 费）——键盘钉测的前置必须是「在底且无在途
    /// 意图」，与真机「停在底部读消息后点输入框」
    /// 同态
    private func assemblePinnedAndSettled() {
        assemble()
        let rows = makeRows(count: 40)
        apply(rows)
        drain(1.0)
        apply(rows)
        drain(0.8)
        XCTAssertTrue(
            handle.contentEndVisible,
            "前置：在底末行应完整可见"
        )
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 1,
            "前置：距底应≈0，实 \(handle.latestDistance)"
        )
    }

    private func postKeyboardShow(
        height: CGFloat, duration: Double = 0.25
    ) {
        let frame = CGRect(
            x: 0, y: windowHeight - height,
            width: 402, height: height
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: frame),
                UIResponder.keyboardAnimationDurationUserInfoKey:
                    duration,
                UIResponder.keyboardAnimationCurveUserInfoKey: 7,
            ]
        )
    }

    private func postKeyboardHide(duration: Double = 0.25) {
        let frame = CGRect(
            x: 0, y: windowHeight, width: 402, height: keyboardHeight
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    NSValue(cgRect: frame),
                UIResponder.keyboardAnimationDurationUserInfoKey:
                    duration,
                UIResponder.keyboardAnimationCurveUserInfoKey: 7,
            ]
        )
    }

    /// 贴底→键盘起→末行完整可见零手拉（终态断言）
    func testKeyboardShowAtBottomLandsOnLatest() {
        assemblePinnedAndSettled()
        let insetBefore = handle.bottomInset
        postKeyboardShow(height: keyboardHeight)
        drain(0.7)
        XCTAssertTrue(
            handle.contentEndVisible,
            "键盘起后末行应完整可见（旧链缺陷：距底≈键盘高、末行被顶出视口）"
        )
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 1,
            "键盘起后距底应≈0，实 \(handle.latestDistance)"
        )
        XCTAssertEqual(
            handle.bottomInset - insetBefore, keyboardHeight,
            accuracy: 1.5,
            "底部留位增量应恰＝键盘高"
        )
        // 收起回落同守：在底者回到在底
        postKeyboardHide()
        drain(0.7)
        XCTAssertTrue(handle.contentEndVisible)
        XCTAssertLessThanOrEqual(handle.latestDistance, 1)
    }

    /// 中途帧（§438 改钉）：键盘动画全程末行与舱
    /// 同程跟随——呈现层间距（舱呈现顶−末行屏幕
    /// 底）恒≈静息值：末行不被盖（间距不为负）、
    /// 也不抢跑（间距不胀）。§426 旧钉断言「中途
    /// 帧留位一步到位」钉的正是抢跑机制本身（内
    /// 容单帧瞬移、舱独行，用户视频实证），改钉理
    /// 由见 kb-smooth-spec §438 三章；旧测的深层
    /// 意图（末行完整可见、无被盖中间态）在新不
    /// 变量下更强地成立
    func testKeyboardShowMidAnimationTailAlreadyVisible() {
        assemblePinnedAndSettled()
        let restGap = presentationGap()
        XCTAssertNotNil(restGap, "前置：呈现层采样应可得")
        postKeyboardShow(height: keyboardHeight, duration: 0.6)
        for sample in 1...3 {
            drain(0.15)
            guard let gap = presentationGap() else {
                XCTFail("中途帧样本 \(sample)：呈现层采样不可得")
                continue
            }
            XCTAssertEqual(
                gap, restGap ?? 8, accuracy: 10,
                "中途帧样本 \(sample)：末行应与舱同程（间距守恒），"
                    + "实间距 \(gap)、静息 \(restGap ?? -1)"
            )
            XCTAssertGreaterThanOrEqual(
                gap, -1,
                "中途帧样本 \(sample)：末行不许被舱盖住，实间距 \(gap)"
            )
        }
        drain(0.6)
        XCTAssertTrue(handle.contentEndVisible)
        XCTAssertLessThanOrEqual(handle.latestDistance, 1)
    }

    /// 离底→键盘起→位置不动（不许把人拽回底部）
    func testKeyboardShowAwayFromBottomLeavesPosition() {
        assemblePinnedAndSettled()
        let pinnedOffset = controller.collectionView.contentOffset.y
        let target = pinnedOffset - 400
        controller.collectionView.setContentOffset(
            CGPoint(x: 0, y: target), animated: false
        )
        drain(0.5)
        XCTAssertFalse(
            handle.contentEndVisible,
            "前置：上翻 400 后末行不应完整可见"
        )
        XCTAssertEqual(
            controller.collectionView.contentOffset.y, target,
            accuracy: 1
        )
        postKeyboardShow(height: keyboardHeight)
        drain(0.7)
        XCTAssertEqual(
            controller.collectionView.contentOffset.y, target,
            accuracy: 1,
            "离底时键盘升起不许动用户位置"
        )
        XCTAssertFalse(handle.contentEndVisible)
    }

    /// §438 合侧：在底→升起→收起全程同程跟随、
    /// 终点精确回静息（旧链收起无专属回钉：落偏
    /// 靠事后偶然收敛，用户视频合后 +149px 不归
    /// 位；裸装配无坞、竞速不复现，本测守终态与
    /// 中途间距不劣化，生产几何差集见图内说明）
    func testKeyboardHideFollowsAndReturnsToRest() {
        assemblePinnedAndSettled()
        let restInset = handle.bottomInset
        postKeyboardShow(height: keyboardHeight)
        drain(0.7)
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 1,
            "前置：键盘态应在底，实 \(handle.latestDistance)"
        )
        let restGap = presentationGap()
        XCTAssertNotNil(restGap, "前置：呈现层采样应可得")
        postKeyboardHide(duration: 0.6)
        for sample in 1...3 {
            drain(0.15)
            guard let gap = presentationGap() else {
                XCTFail("合侧中途样本 \(sample)：呈现层采样不可得")
                continue
            }
            XCTAssertEqual(
                gap, restGap ?? 8, accuracy: 10,
                "合侧中途样本 \(sample)：末行应与舱同程，"
                    + "实间距 \(gap)、静息 \(restGap ?? -1)"
            )
        }
        drain(0.6)
        XCTAssertTrue(
            handle.contentEndVisible,
            "收起后末行应完整可见"
        )
        XCTAssertLessThanOrEqual(
            handle.latestDistance, 1,
            "收起后应精确归位在底，实 \(handle.latestDistance)"
        )
        XCTAssertEqual(
            handle.bottomInset, restInset, accuracy: 1.5,
            "收起后留位应回静息值"
        )
    }

    /// §438 呈现层间距采样：舱呈现顶 − 末行屏幕
    /// 底（窗口系）。在底静息时恒＝底 padding；
    /// 内容与舱同事务跟随则动画全程守恒，内容抢
    /// 跑/脱钉时中途帧显著偏离
    private func presentationGap() -> CGFloat? {
        guard let cv = controller?.collectionView,
              let hostView = controller?.composerHost?.view,
              let hostSuperview = hostView.superview,
              let tailBottom = cv.visibleCells
                .map({ $0.frame.maxY }).max()
        else { return nil }
        let presOffsetY = cv.layer.presentation()?
            .bounds.origin.y ?? cv.contentOffset.y
        let cvWindowTop = cv.superview?
            .convert(
                CGPoint(x: 0, y: cv.frame.minY), to: nil
            ).y ?? 0
        let tailScreenBottom = cvWindowTop + tailBottom
            - presOffsetY
        let presFrame = hostView.layer.presentation()?
            .frame ?? hostView.frame
        let composerWindowTop = hostSuperview.convert(
            CGPoint(x: 0, y: presFrame.minY), to: nil
        ).y
        return composerWindowTop - tailScreenBottom
    }
}
