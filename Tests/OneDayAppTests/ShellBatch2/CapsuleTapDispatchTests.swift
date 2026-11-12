import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 症二阶段二·胶囊动作级点按派发验证（2026-11-12）
///
/// 背景：阶段一 hitTest 结构扫描（HIT-SCAN-DATA）只
/// 给结构量——③官方定式的 union 玻璃面在胶囊中带跨
/// 两钮、结构门未过；但「面跨域」不等于「点下去必派
/// 错」，动作归属 hitTest 给不出。本组补动作级证据：
/// 在与阶段一相同的真实容器层级（DrawerContainer
/// 裸装→TabView→safeAreaBar 顶栏）内，用合成 UIEvent
/// 触摸序列（began/ended 经 UIWindow.sendEvent 走真
/// 实派发链：hitTest→响应链→手势/按钮 machinery）
/// 逐点点按，以探针记录每次点按**实际升起哪一面**
/// （枢纽 cover 探针／模型 sheet 探针，本组替身呈
/// 现、不接生产呈现链）。
///
/// 触摸合成：UITouch 私有状态经运行时 ivar 存在性
/// 校验后 KVC 写入（缺失的键跳过、不硬写），事件经
/// UIEvent 子类携带同一 touch 对象分两阶段投递。
/// 通道是否可信由校准点判定（见下），不预设可信。
///
/// 点位与判定（预注册、跑前写死）：
/// - 校准点：内容区一只普通 SwiftUI 钮——它不响＝
///   点按合成通道未通、本组数据整体作废（仪表门，
///   与派发结论分开记）。
/// - 域内点：落点在某钮帧内（x 向内缩 ≥2pt）、胶囊
///   中带行（midY）——必须只触发该钮、只升该面；
///   触发对侧或无触发＝派错。
/// - 缘带点：胶囊上/下缘带（minY+2／maxY−2）、x 在
///   某钮 x 域内——升对侧的面或不升都可记，升错侧
///   ＝派错（误开症状的高发带）。
/// - 缝点/衬垫带点：两钮间缝（分隔线 ±3/±6，按实
///   测帧归类）与胶囊上方衬垫带（minY−5）——只记
///   录，无预设对错（缝本身不是任一钮的领地）。
///
/// 两臂：P＝生产 IdentityCapsuleView 本体（现行形
/// 态，只记录——它是正在发货的形态，动作数据本身
/// 即结论；其钮帧以 C 臂同内容实测帧的相对偏移移
/// 植，中心点自证放置）；C＝官方定式复刻（玻璃逐
/// 钮＋union 同 id、无 .odPressable）——阶段二门
/// 只绑 C：域内点全对＋缘带点零派错才放行重建。
@MainActor
final class CapsuleTapDispatchTests: XCTestCase {

    // MARK: - 探针存储

    final class TapProbeStore: ObservableObject {
        @Published var showHubProbe = false
        @Published var showModelProbe = false
        var hubActions = 0
        var modelActions = 0
        var hubAppeared = false
        var modelAppeared = false
        var calibrationActions = 0

        func fireHub() {
            hubActions += 1
            showHubProbe = true
        }

        func fireModel() {
            modelActions += 1
            showModelProbe = true
        }

        func reset() {
            showHubProbe = false
            showModelProbe = false
            hubActions = 0
            modelActions = 0
            hubAppeared = false
            modelAppeared = false
        }
    }

    // MARK: - 帧捕获

    private final class TapFrameBox {
        var capsuleFrame: CGRect?
        var hubFrame: CGRect?
        var modelFrame: CGRect?
        var calibrationFrame: CGRect?
    }

    private struct TapCapsuleFrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    private struct TapHubFrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    private struct TapModelFrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    private struct TapCalibrationFrameKey: PreferenceKey {
        static var defaultValue: CGRect? { nil }
        static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
            value = nextValue() ?? value
        }
    }

    private static func frameCapture<Key: PreferenceKey>(
        _ key: Key.Type
    ) -> some View where Key.Value == CGRect? {
        GeometryReader { proxy in
            Color.clear.preference(
                key: Key.self,
                value: proxy.frame(in: .global)
            )
        }
    }

    // MARK: - 脚手架（层级同阶段一扫描）

    private final class StatusBarWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: StatusBarWindow!
    private var controller: DrawerContainerController!
    /// 投递通道（校准段探明后固定）：window 直投／
    /// UIApplication 转投
    private var deliveryPath = "window"
    /// 诊断：touch 上实际写成功的 ivar 名
    private var touchKeysSet: [String] = []

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        controller = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    /// 聊天面替身：装配照阶段一（左右玻璃圆钮＋胶囊
    /// 居中＋safeAreaBar 顶栏）；内容首行放校准钮；
    /// 呈现探针挂在本面根（与生产今日同深度：模型
    /// sheet／枢纽 cover 都自 ChatView 链升起）
    private struct TapSurfaceStandIn<Arm: View>: View {
        let box: TapFrameBox
        @ObservedObject var store: TapProbeStore
        @ViewBuilder var arm: () -> Arm

        var body: some View {
            ScrollView {
                LazyVStack(spacing: 12) {
                    Button("校准钮") {
                        store.calibrationActions += 1
                    }
                    .buttonStyle(.bordered)
                    .background {
                        CapsuleTapDispatchTests.frameCapture(
                            TapCalibrationFrameKey.self
                        )
                    }
                    ForEach(0..<40, id: \.self) { index in
                        Text("消息行 \(index)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 20)
            }
            .safeAreaBar(edge: .top) {
                VStack(spacing: OneDayMetrics.rowInnerGap) {
                    HStack(alignment: .center, spacing: OneDayMetrics.spacingS) {
                        sideButton("line.3.horizontal")
                        Spacer()
                        arm()
                            .layoutPriority(1)
                            .background {
                                CapsuleTapDispatchTests.frameCapture(
                                    TapCapsuleFrameKey.self
                                )
                            }
                        Spacer()
                        sideButton("bell")
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingS)
                .padding(.bottom, OneDayMetrics.spacingS)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .fullScreenCover(isPresented: $store.showHubProbe) {
                probeView(title: "枢纽探针") { store.hubAppeared = true }
            }
            .sheet(isPresented: $store.showModelProbe) {
                probeView(title: "模型探针") { store.modelAppeared = true }
            }
            .onPreferenceChange(TapCapsuleFrameKey.self) { value in
                box.capsuleFrame = value ?? box.capsuleFrame
            }
            .onPreferenceChange(TapHubFrameKey.self) { value in
                box.hubFrame = value ?? box.hubFrame
            }
            .onPreferenceChange(TapModelFrameKey.self) { value in
                box.modelFrame = value ?? box.modelFrame
            }
            .onPreferenceChange(TapCalibrationFrameKey.self) { value in
                box.calibrationFrame = value ?? box.calibrationFrame
            }
        }

        private func sideButton(_ symbol: String) -> some View {
            Button {
            } label: {
                Image(systemName: symbol)
                    .font(.system(
                        size: HeaderButtonSpec.glyphPointSize,
                        weight: .regular
                    ))
                    .foregroundStyle(Palette.ink)
                    .frame(
                        width: HeaderButtonSpec.diameter,
                        height: HeaderButtonSpec.diameter
                    )
                    .glassEffect(.regular, in: Circle())
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
        }

        private func probeView(
            title: String, onAppear: @escaping () -> Void
        ) -> some View {
            ZStack {
                Palette.pageBG.ignoresSafeArea()
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Palette.ink)
            }
            .onAppear(perform: onAppear)
        }
    }

    // MARK: - 两臂（内容度量与阶段一恒同）

    private static func hubLabelContent(showName: Bool) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Circle()
                .fill(.blue.gradient)
                .frame(width: 28, height: 28)
            if showName {
                Text("Hermes")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: OneDayMetrics.iconTextGap) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("在线")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .contentShape(Rectangle())
    }

    private static var modelLabelContent: some View {
        HStack(spacing: OneDayMetrics.stackGap) {
            Text("deepseek-flash")
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Palette.inkSecondary)
        }
        .contentShape(Rectangle())
    }

    private static var hairline: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 0.5, height: 18)
    }

    /// C 臂：官方定式复刻（同阶段一 OfficialPatternArm
    /// ＋探针动作＋钮帧捕获）
    private struct OfficialPatternTapArm: View {
        let store: TapProbeStore
        @Namespace private var glassUnion

        var body: some View {
            GlassEffectContainer {
                ViewThatFits(in: .horizontal) {
                    row(showName: true)
                    row(showName: false)
                }
            }
        }

        private func row(showName: Bool) -> some View {
            HStack(spacing: OneDayMetrics.spacingS) {
                Button {
                    store.fireHub()
                } label: {
                    CapsuleTapDispatchTests.hubLabelContent(
                        showName: showName
                    )
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
                .background {
                    CapsuleTapDispatchTests.frameCapture(TapHubFrameKey.self)
                }

                CapsuleTapDispatchTests.hairline

                Button {
                    store.fireModel()
                } label: {
                    CapsuleTapDispatchTests.modelLabelContent
                }
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
                .background {
                    CapsuleTapDispatchTests.frameCapture(TapModelFrameKey.self)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .padding(.vertical, 7)
        }
    }

    // MARK: - 装配

    private func mount<Arm: View>(
        arm: Arm, box: TapFrameBox, store: TapProbeStore
    ) {
        controller = DrawerContainerController()
        controller.drawerBuilder = { _ in AnyView(EmptyView()) }
        let root = TabView {
            TapSurfaceStandIn(box: box, store: store) { arm }
                .tabItem { Label("聊天", systemImage: "message.fill") }
            Text("占位页")
                .tabItem { Label("占位", systemImage: "folder") }
        }
        controller.contentRoot = AnyView(root)
        window = StatusBarWindow(
            frame: CGRect(x: 0, y: 0, width: 393, height: 852)
        )
        // iOS 26 场景制：无 windowScene 的窗口不进事件
        // 路由（阶段一纯 hitTest 几何不受影响、事件投
        // 递则会被静默丢弃）——挂宿主 App 的活动场景
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        spinRunLoop(seconds: 0.8)
        controller.view.layoutIfNeeded()
    }

    private func unmount() {
        window?.isHidden = true
        window = nil
        controller = nil
    }

    // MARK: - 合成点按（UIEvent 经 window 投递）

    private final class SyntheticTouchesEvent: UIEvent {
        private let held: Set<UITouch>
        private let stamp: TimeInterval

        init(touches: Set<UITouch>, timestamp: TimeInterval) {
            held = touches
            stamp = timestamp
            super.init()
            // UIKit 内部多处直读事件的 _touches 集合而非
            // 访问器——覆盖方法之外把内部集合也写上
            // （ivar 存在才写，口径同 touch 侧）
            if CapsuleTapDispatchTests.ivarExists("_touches", on: self) {
                setValue(held, forKey: "_touches")
            }
            if CapsuleTapDispatchTests.ivarExists("_timestamp", on: self) {
                setValue(stamp, forKey: "_timestamp")
            }
            if CapsuleTapDispatchTests.ivarExists("_type", on: self) {
                setValue(UIEvent.EventType.touches.rawValue, forKey: "_type")
            }
            if CapsuleTapDispatchTests.ivarExists("_subtype", on: self) {
                setValue(UIEvent.EventSubtype.none.rawValue, forKey: "_subtype")
            }
        }

        override var type: UIEvent.EventType { .touches }
        override var subtype: UIEvent.EventSubtype { .none }
        override var timestamp: TimeInterval { stamp }
        override var allTouches: Set<UITouch>? { held }
        override func touches(for window: UIWindow) -> Set<UITouch>? { held }
        override func touches(for view: UIView) -> Set<UITouch>? { held }
        override func touches(
            for gestureRecognizer: UIGestureRecognizer
        ) -> Set<UITouch>? { held }
    }

    private static func ivarExists(_ name: String, on object: AnyObject) -> Bool {
        var cls: AnyClass? = type(of: object)
        while let current = cls {
            var count: UInt32 = 0
            if let ivars = class_copyIvarList(current, &count) {
                for index in 0..<Int(count) {
                    if let ivarName = ivar_getName(ivars[index]),
                       String(cString: ivarName) == name {
                        free(ivars)
                        return true
                    }
                }
                free(ivars)
            }
            cls = class_getSuperclass(current)
        }
        return false
    }

    private func setTouchValue(_ touch: UITouch, _ key: String, _ value: Any) {
        if Self.ivarExists(key, on: touch) {
            touch.setValue(value, forKey: key)
            touchKeysSet.append(key)
        }
    }

    private func send(_ event: UIEvent) {
        if deliveryPath == "app" {
            UIApplication.shared.sendEvent(event)
        } else {
            window.sendEvent(event)
        }
    }

    private func makeTouch(at point: CGPoint, phase: UITouch.Phase) -> UITouch {
        let touch = UITouch()
        setTouchValue(touch, "_window", window as Any)
        if let target = window.hitTest(point, with: nil) {
            setTouchValue(touch, "_view", target)
        }
        setTouchValue(touch, "_phase", phase.rawValue)
        setTouchValue(touch, "_tapCount", 1)
        let location = NSValue(cgPoint: point)
        setTouchValue(touch, "_locationInWindow", location)
        setTouchValue(touch, "_previousLocationInWindow", location)
        setTouchValue(touch, "_absoluteLocationInWindow", location)
        setTouchValue(
            touch, "_timestamp", ProcessInfo.processInfo.systemUptime
        )
        return touch
    }

    /// 一次完整点按：began 投递→短停→同 touch 改
    /// ended 投递→等动作与呈现落定
    private func deliverTap(at point: CGPoint) {
        let touch = makeTouch(at: point, phase: .began)
        let beganEvent = SyntheticTouchesEvent(
            touches: [touch],
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        setTouchValue(touch, "_event", beganEvent)
        send(beganEvent)
        spinRunLoop(seconds: 0.12)
        setTouchValue(touch, "_phase", UITouch.Phase.ended.rawValue)
        setTouchValue(
            touch, "_timestamp", ProcessInfo.processInfo.systemUptime
        )
        let endedEvent = SyntheticTouchesEvent(
            touches: [touch],
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        setTouchValue(touch, "_event", endedEvent)
        send(endedEvent)
        spinRunLoop(seconds: 0.7)
    }

    // MARK: - 点位计划与判定

    private enum Zone {
        case domainHub, domainModel, edgeHub, edgeModel, record
    }

    private struct TapPoint {
        var name: String
        var point: CGPoint
        var zone: Zone
    }

    private struct TapOutcome {
        var name: String
        var point: CGPoint
        var zone: Zone
        var fired: String
        var presented: String
        var wrong: Bool
    }

    private func fmt(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(
            format: "(%.0f,%.0f %.0f×%.0f)",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    private func planPoints(
        capsule: CGRect, hub: CGRect, model: CGRect
    ) -> [TapPoint] {
        let divider = (hub.maxX + model.minX) / 2
        let midY = capsule.midY
        var points: [TapPoint] = [
            TapPoint(
                name: "HUB-C", point: CGPoint(x: hub.midX, y: midY),
                zone: .domainHub
            ),
            TapPoint(
                name: "MOD-C", point: CGPoint(x: model.midX, y: midY),
                zone: .domainModel
            ),
            TapPoint(
                name: "HUB-IN", point: CGPoint(x: hub.maxX - 6, y: midY),
                zone: .domainHub
            ),
            TapPoint(
                name: "MOD-IN", point: CGPoint(x: model.minX + 6, y: midY),
                zone: .domainModel
            ),
            TapPoint(
                name: "HUB-T",
                point: CGPoint(x: hub.midX, y: capsule.minY + 2),
                zone: .edgeHub
            ),
            TapPoint(
                name: "MOD-T",
                point: CGPoint(x: model.midX, y: capsule.minY + 2),
                zone: .edgeModel
            ),
            TapPoint(
                name: "HUB-B",
                point: CGPoint(x: hub.midX, y: capsule.maxY - 2),
                zone: .edgeHub
            ),
            TapPoint(
                name: "MOD-B",
                point: CGPoint(x: model.midX, y: capsule.maxY - 2),
                zone: .edgeModel
            ),
        ]
        // 缝点：按实测帧归类——落进某钮帧（内缩 2pt）
        // 的按域内点判，落在开缝里的只记录
        for (label, x) in [
            ("GAP-3L", divider - 3), ("GAP-3R", divider + 3),
            ("GAP-6L", divider - 6), ("GAP-6R", divider + 6),
        ] {
            let zone: Zone
            if x >= hub.minX + 2, x <= hub.maxX - 2 {
                zone = .domainHub
            } else if x >= model.minX + 2, x <= model.maxX - 2 {
                zone = .domainModel
            } else {
                zone = .record
            }
            points.append(TapPoint(
                name: label, point: CGPoint(x: x, y: midY), zone: zone
            ))
        }
        points.append(TapPoint(
            name: "TOP-DIV",
            point: CGPoint(x: divider, y: capsule.minY + 2),
            zone: .record
        ))
        points.append(TapPoint(
            name: "PAD-H",
            point: CGPoint(x: hub.midX, y: capsule.minY - 5),
            zone: .record
        ))
        points.append(TapPoint(
            name: "PAD-M",
            point: CGPoint(x: model.midX, y: capsule.minY - 5),
            zone: .record
        ))
        return points
    }

    private func runArm(
        armName: String,
        box: TapFrameBox,
        store: TapProbeStore,
        hubFrame: CGRect,
        modelFrame: CGRect
    ) throws -> (report: String, violations: [String]) {
        let capsule = try XCTUnwrap(box.capsuleFrame, "胶囊帧未量得")
        XCTAssertGreaterThan(capsule.width, 150, "胶囊应为全量档宽")
        let calibration = try XCTUnwrap(
            box.calibrationFrame, "校准钮帧未量得"
        )

        var lines: [String] = []
        lines.append(
            "arm=\(armName) capsule=\(fmt(capsule)) hub=\(fmt(hubFrame)) "
                + "model=\(fmt(modelFrame))"
        )

        // 仪表门：校准钮先响，通道不通则整组作废
        store.reset()
        store.calibrationActions = 0
        let calibPoint = CGPoint(x: calibration.midX, y: calibration.midY)
        // 诊断：场景/焦点/坐标回读/命中视图/已写 ivar
        let probeTouch = makeTouch(at: calibPoint, phase: .began)
        let diagLoc = probeTouch.location(in: window)
        let diagHit = window.hitTest(calibPoint, with: nil)
        lines.append(
            "arm=\(armName) diag scene=\(window.windowScene != nil) "
                + "key=\(window.isKeyWindow) "
                + "touchLoc=(\(Int(diagLoc.x)),\(Int(diagLoc.y))) "
                + "hit=\(diagHit.map { String(describing: type(of: $0)) } ?? "nil") "
                + "touchKeys=\(touchKeysSet.joined(separator: ","))"
        )
        deliverTap(at: calibPoint)
        if store.calibrationActions == 0 {
            // 第二通道：UIApplication 转投（诊断用，
            // 通道定下后其余点位只走该通道）
            deliveryPath = "app"
            deliverTap(at: calibPoint)
        }
        let calibrated = store.calibrationActions > 0
        lines.append(
            "arm=\(armName) calibration fired=\(store.calibrationActions) "
                + "ok=\(calibrated) path=\(deliveryPath)"
        )
        guard calibrated else {
            lines.append("arm=\(armName) VERDICT=INSTRUMENT-FAIL")
            return (lines.joined(separator: "\n"), ["仪表门未过"])
        }

        var violations: [String] = []
        for tap in planPoints(
            capsule: capsule, hub: hubFrame, model: modelFrame
        ) {
            store.reset()
            spinRunLoop(seconds: 0.45)
            deliverTap(at: tap.point)
            let fired: String
            switch (store.hubActions, store.modelActions) {
            case (1, 0): fired = "hub"
            case (0, 1): fired = "model"
            case (0, 0): fired = "none"
            default:
                fired = "multi(h:\(store.hubActions),m:\(store.modelActions))"
            }
            let presented = store.hubAppeared
                ? "cover"
                : store.modelAppeared ? "sheet" : "-"
            var wrong = false
            switch tap.zone {
            case .domainHub:
                wrong = fired != "hub"
            case .domainModel:
                wrong = fired != "model"
            case .edgeHub:
                wrong = fired == "model" || fired.hasPrefix("multi")
            case .edgeModel:
                wrong = fired == "hub" || fired.hasPrefix("multi")
            case .record:
                wrong = false
            }
            if wrong {
                violations.append(
                    "\(tap.name)@(\(Int(tap.point.x)),\(Int(tap.point.y))) "
                        + "fired=\(fired)"
                )
            }
            lines.append(
                "arm=\(armName) tap=\(tap.name) "
                    + "at=(\(Int(tap.point.x)),\(Int(tap.point.y))) "
                    + "zone=\(tap.zone) fired=\(fired) "
                    + "presented=\(presented) wrong=\(wrong)"
            )
        }
        lines.append(
            "arm=\(armName) violations=\(violations.count) "
                + violations.joined(separator: "; ")
        )
        lines.append(
            "arm=\(armName) VERDICT="
                + (violations.isEmpty ? "PASS" : "FAIL")
        )
        return (lines.joined(separator: "\n"), violations)
    }

    private func emit(_ report: String) {
        print("CAPSULE-TAP-BEGIN")
        print(report)
        print("CAPSULE-TAP-END")
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 两臂执行

    /// C 臂（官方定式复刻）——阶段二门：域内点全对
    /// ＋缘带点零派错才放行生产重建
    func testTapDispatch_OfficialPattern_StageGate() throws {
        let box = TapFrameBox()
        let store = TapProbeStore()
        mount(
            arm: OfficialPatternTapArm(store: store),
            box: box, store: store
        )
        let hub = try XCTUnwrap(box.hubFrame, "C 臂枢纽帧未量得")
        let model = try XCTUnwrap(box.modelFrame, "C 臂模型帧未量得")
        let result = try runArm(
            armName: "C-official", box: box, store: store,
            hubFrame: hub, modelFrame: model
        )
        emit(result.report)
        XCTAssertTrue(
            result.violations.isEmpty,
            "官方定式动作级派发有误：\(result.violations.joined(separator: "; "))"
        )
    }

    /// P 臂（生产 IdentityCapsuleView 现行形态）——
    /// 只记录：钮帧以 C 臂同内容实测帧的相对偏移移
    /// 植（内容度量恒同、行构成同构）；P 臂中心点
    /// 的实际触发即放置自证，结果全量落盘供裁决
    func testTapDispatch_CurrentProductionForm_Record() throws {
        // 先以 C 臂量同内容帧偏移
        let measureBox = TapFrameBox()
        let measureStore = TapProbeStore()
        mount(
            arm: OfficialPatternTapArm(store: measureStore),
            box: measureBox, store: measureStore
        )
        let refCapsule = try XCTUnwrap(
            measureBox.capsuleFrame, "参照胶囊帧未量得"
        )
        let refHub = try XCTUnwrap(measureBox.hubFrame, "参照枢纽帧未量得")
        let refModel = try XCTUnwrap(
            measureBox.modelFrame, "参照模型帧未量得"
        )
        unmount()

        let box = TapFrameBox()
        let store = TapProbeStore()
        mount(
            arm: IdentityCapsuleView(
                avatar: Image(systemName: "person.circle.fill"),
                displayName: "Hermes",
                statusWord: "在线",
                statusColor: .green,
                avatarPointSize: 28,
                modelTriggerLabel: "deepseek-flash",
                modelAccessibilityLabel: "当前模型 deepseek-flash，切换模型",
                onOpenHub: { store.fireHub() },
                onOpenModelPicker: { store.fireModel() }
            ),
            box: box, store: store
        )
        let capsule = try XCTUnwrap(box.capsuleFrame, "生产胶囊帧未量得")
        let hub = CGRect(
            x: capsule.minX + (refHub.minX - refCapsule.minX),
            y: capsule.minY + (refHub.minY - refCapsule.minY),
            width: refHub.width, height: refHub.height
        )
        let model = CGRect(
            x: capsule.minX + (refModel.minX - refCapsule.minX),
            y: capsule.minY + (refModel.minY - refCapsule.minY),
            width: refModel.width, height: refModel.height
        )
        let result = try runArm(
            armName: "P-current", box: box, store: store,
            hubFrame: hub, modelFrame: model
        )
        emit(result.report)
    }
}
