import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 症二阶段二·动作级验证实验台入口（2026-11-12）
///
/// 宿主内自造 UIEvent 投递两轮实证到不了 SwiftUI
/// 按钮 machinery（诊断见 TAP-DISPATCH-DATA），动作
/// 级点按改走 XCUITest 系统级真实点按：本文件是被
/// 测装配——启动参数 -CapsuleTapHarness 直达，
/// -CapsuleArmC 选官方定式臂、缺省生产臂。装配深
/// 度照生产（根宿主→DrawerContainer→TabView→
/// safeAreaBar 顶栏面），呈现用探针替身（枢纽
/// cover／模型 sheet，不接生产呈现链）。
/// 发布构建 isEnabled 恒 false、装配代码只在
/// DEBUG 编译，正常启动路径零变化。
enum CapsuleTapHarness {
    static var isEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments
            .contains("-CapsuleTapHarness")
        #else
        return false
        #endif
    }

    static var usesOfficialArm: Bool {
        ProcessInfo.processInfo.arguments.contains("-CapsuleArmC")
    }
}

struct CapsuleTapHarnessRootView: View {
    var body: some View {
        #if DEBUG
        CapsuleHarnessAssemblyView()
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG

/// 探针存储：动作计数与呈现开关（XCUITest 侧只读
/// 界面元素，不读本对象——计数供装配内自洽，呈现
/// 以探针面实际升起为准）
private final class CapsuleHarnessStore: ObservableObject {
    @Published var showHubProbe = false
    @Published var showModelProbe = false
    @Published var calibrationOK = false

    func fireHub() { showHubProbe = true }
    func fireModel() { showModelProbe = true }
    func dismissProbes() {
        showHubProbe = false
        showModelProbe = false
    }
}

private struct CapsuleHarnessAssemblyView: View {
    @StateObject private var store = CapsuleHarnessStore()

    var body: some View {
        CapsuleHarnessContainer(store: store)
            .ignoresSafeArea()
    }
}

/// 容器装配：与阶段一/二宿主台同式（DrawerContai-
/// nerController 裸装、抽屉空、内容 TabView）
private struct CapsuleHarnessContainer: UIViewControllerRepresentable {
    let store: CapsuleHarnessStore

    func makeUIViewController(
        context: Context
    ) -> DrawerContainerController {
        let controller = DrawerContainerController()
        controller.drawerBuilder = { _ in AnyView(EmptyView()) }
        controller.contentRoot = AnyView(
            TabView {
                CapsuleHarnessSurface(store: store)
                    .tabItem { Label("聊天", systemImage: "message.fill") }
                Text("占位页")
                    .tabItem { Label("占位", systemImage: "folder") }
            }
        )
        return controller
    }

    func updateUIViewController(
        _ controller: DrawerContainerController, context: Context
    ) {}
}

/// 聊天面替身：ScrollView＋safeAreaBar 顶栏（左右
/// 玻璃圆钮＋胶囊居中），内容首行校准钮；呈现探针
/// 挂本面根（与生产今日同深度）
private struct CapsuleHarnessSurface: View {
    @ObservedObject var store: CapsuleHarnessStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Button("校准钮") { store.calibrationOK = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("harness.calibration")
                if store.calibrationOK {
                    Text("校准通过")
                        .accessibilityIdentifier("harness.calibrationOK")
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
                    armSlot
                        .layoutPriority(1)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("harness.capsule")
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
            probeView(title: "枢纽探针", identifier: "probe.hubCover")
        }
        .sheet(isPresented: $store.showModelProbe) {
            probeView(title: "模型探针", identifier: "probe.modelSheet")
        }
    }

    /// 胶囊槽：hug 住被测臂、无障碍容器标识供
    /// XCUITest 读帧（子钮保持独立元素）
    @ViewBuilder
    private var armSlot: some View {
        if CapsuleTapHarness.usesOfficialArm {
            CapsuleHarnessOfficialArm(store: store)
        } else {
            IdentityCapsuleView(
                avatar: Image(systemName: "person.circle.fill"),
                displayName: "Hermes",
                statusWord: "在线",
                statusColor: .green,
                avatarPointSize: 28,
                modelTriggerLabel: "deepseek-flash",
                modelAccessibilityLabel: "当前模型 deepseek-flash，切换模型",
                onOpenHub: { store.fireHub() },
                onOpenModelPicker: { store.fireModel() }
            )
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

    private func probeView(title: String, identifier: String) -> some View {
        ZStack {
            Palette.pageBG.ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier(identifier)
                Button("关闭探针") { store.dismissProbes() }
                    .accessibilityIdentifier("probe.dismiss")
            }
        }
    }
}

/// C 臂：官方定式（GlassEffectContainer＋两钮各自
/// 交互玻璃＋glassEffectUnion 同 id、无 .odPres-
/// sable），内容度量与阶段一恒同；两钮带标识供
/// XCUITest 读帧
private struct CapsuleHarnessOfficialArm: View {
    @ObservedObject var store: CapsuleHarnessStore
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
                hubLabelContent(showName: showName)
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
            .accessibilityIdentifier("harness.hubButton")

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 0.5, height: 18)

            Button {
                store.fireModel()
            } label: {
                modelLabelContent
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectUnion(id: "identity-capsule", namespace: glassUnion)
            .accessibilityIdentifier("harness.modelButton")
        }
        .padding(.horizontal, OneDayMetrics.spacingSM)
        .padding(.vertical, 7)
    }

    private func hubLabelContent(showName: Bool) -> some View {
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

    private var modelLabelContent: some View {
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
}

#endif
