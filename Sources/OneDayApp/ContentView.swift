import OneDayCore
import OneDayDesign
import SwiftUI

/// 底部四格（聊天／总览／文件／设置；IA 不动）。
/// 0.2.4：底栏回归 SwiftUI 原生 TabView——iOS 26 由系统亲自
/// 渲染 Liquid Glass：材质折光、边缘高光、滚动收起、键盘
/// 联动全走系统。0.2.2 的自绘贴底栏、0.2.3 的自绘玻璃悬浮
/// 栏，连同键盘通知监听、frame 级下沿预留、opacity 页切换
/// 一并删除，不在自绘件上打补丁。
/// 只要图标不要文字：tabItem 只放线条图标（系统 image-only
/// 条目形态），名称只进无障碍标签；选中着色走系统 tint 通道。
/// 0.2.3 的自绘浅灰胶囊＋4pt 微点没有系统挂钩，按「冲突时
/// 系统优先」撤销，取舍在案（DESIGN-V4 §8）。
/// 0.2.5 图标瘦身＋tint 改墨（DESIGN-V4 §9）：0.2.4 的图标
/// 在真机上呈实心粗 glyph、选中染腾讯蓝，与 Muse 的细
/// 线条＋墨色选中两路。两处根因与修法：①SF Symbols 带
/// 变体的符号（如双气泡、folder）在选中态会被系统自动换
/// 成 .fill 变体——四枚图标一律选线条版并加
/// .symbolVariant(.none) 锁死基础（线条）变体，.fill 全面
/// 禁用，设置格的 gearshape 是实心剪影且无更细的同义符号，
/// 换线条体的 slider.horizontal.3（系统偏好设置的标准
/// 线条字形）；②.tint 由 Palette.primary 改 Palette.ink，
/// 选中态呈「墨色线条图标＋系统浅灰选择胶囊」。腾讯蓝自
/// 此只留在发送键、链接等内容强调位，不再染底栏。页面内
/// 强调色全部显式引用 Palette 令牌（全仓核查：.tint 仅此
/// 一处），改 tint 不误伤各页。
/// 0.3.1 底栏再定案（DESIGN-V4 §16）：用户点名照搬
/// 礼记做法——结构换 Tab(value:)＋Label(标题,
/// systemImage:) 系统直渲，零尺寸配置、零预渲染
/// （0.2.9 的烘焙定标、同日先行的配置定标均作废）。
/// 0.2.4 的「只要图标不要文字」同步作废：标题随
/// Label 进栏、由系统排布（礼记同款）。
/// 0.2.5 的「.fill 全面禁用」就此反转：未选线条体、
/// 选中切官方 .fill 成对变体（chart 与 slider 无
/// fill、同名），选中 .bounce 一次（Reduce Motion
/// 系统自动抑制）。符号名对的单一事实源在
/// OneDayCore.TabBarSymbols，单测钉死。
/// 层级与避让全部服从系统默认：聊天抽屉（页内覆盖层）打开
/// 时底栏按系统层级浮于其上；键盘弹起时由系统处理；各页
/// 滚动内容经系统安全区延伸到底栏之下，从玻璃背后流过。
/// 深链口径不变：AgentRoute / SettingsRoute 落点仍是设置格；
/// 聊天第一格默认落点。
/// 0.3.6 立宪再定案（DESIGN-V4 §21.3/§22，Muse 实测
/// 基线）：结构仍是原生 TabView＋Tab(value:)（IA 与数
/// 据逻辑零动），形态按基线换：去文字标签（回到 0.2.4
/// 的 image-only 条目形态）、字形配置 22、tint 回墨、
/// 选中只靠系统浅灰胶囊垫、fill 成对撤销。0.3.1 的
/// 「照搬礼记」与 0.3.3 的「选中必须蓝」均被基线取
/// 代，对账在 §21.5。系统悬浮大胶囊（iOS 26 原生栏）
/// 即基线的「悬浮大胶囊」落点，不自绘栏体。
/// 0.3.8 自绘定案（fixlist 第 1/2/3 条，用户裁决）：真
/// 机实测推翻 0.3.6 的系统落点——原生栏图标渲染仍实心
/// （墨迹密度 44.6%/49.0%）、选中垫为系统几何约栏宽
/// 1/4 且无代码落点（0.3.7 卡 19 纠正 3 如实留痕）。
/// 本轮按用户裁决替换呈现层：TabView 结构/selection/
/// 深链口径全不动，原生栏经 toolbarVisibility 隐藏，
/// 悬浮其上的是 FloatingTabBar（白浮纸大胶囊、选中垫
/// 由 TabBarLayout 构造收窄贴合字形、图标 outline 直
/// 渲）；抽屉打开（appState.drawerPresented）时底栏隐
/// 藏让位（第 3 条，抽屉底条落进原栏坑位、第 22 条）。
/// 0.2.4 的自绘止损沿革就此由用户裁决正式推翻（当年
/// 止损针对的是「在自绘件上打补丁」，本轮是整层替换
/// ＋几何由 Core 令牌构造决定，与当年情形不同）。
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case overview
        case files
        case settings
    }

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: MainTab = .chat

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                Tab(value: MainTab.chat) {
                    ChatView(
                        onOpenServerSession: { id in
                            appState.pendingAgentRoute = .serverSessionDetail(id)
                            selection = .settings
                        },
                        onSelectTab: { selection = $0 }
                    )
                    .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    tabLabel(TabBarSymbols.chat, tab: .chat)
                }

                Tab(value: MainTab.overview) {
                    OverviewView(
                        onOpenAgent: { route in
                            appState.pendingAgentRoute = route
                            selection = .settings
                        },
                        onOpenSettings: { route in
                            appState.pendingSettingsRoute = route
                            selection = .settings
                        },
                        onOpenChat: { selection = .chat }
                    )
                    .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    tabLabel(TabBarSymbols.overview, tab: .overview)
                }

                Tab(value: MainTab.files) {
                    FilesView()
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    tabLabel(TabBarSymbols.files, tab: .files)
                }

                Tab(value: MainTab.settings) {
                    SettingsView()
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    tabLabel(TabBarSymbols.settings, tab: .settings)
                }
            }
            // tint 墨口径沿 0.3.6 立宪（各页功能位显式引用
            // Palette，本处只兜系统残余着色）
            .tint(Palette.ink)
            // 条 3（§14）未带权文字的降档通道：暗色环境下根
            // fontWeight 降一档（regular→light），未显式带权
            // 的 Text 全量继承；带权字体走 TypeScale 的
            // (for:) 变体（VisualWeight 映射）。UIKit 文本
            // 视图（输入框正文）不在此环境内、不受影响
            .fontWeight(colorScheme == .dark ? .light : .regular)

            // 自绘底栏（第 2 条）：抽屉打开时隐藏（第 3 条）
            if !appState.drawerPresented {
                FloatingTabBar(
                    items: TabBarSymbols.all.map {
                        .init(id: $0.id, title: $0.title, symbol: $0.normal)
                    },
                    selectedID: selectedTabID
                ) { id in
                    if let tab = tab(forID: id) { selection = tab }
                }
                .padding(.horizontal, TabBarLayout.horizontalMargin)
                .safeAreaPadding(.bottom, TabBarLayout.bottomMargin)
                .zIndex(10)
                .transition(
                    .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .animation(
            MotionTokens.resolved(
                MotionTokens.swap, reduceMotion: reduceMotion
            ),
            value: appState.drawerPresented
        )
    }

    private var selectedTabID: String {
        switch selection {
        case .chat: return TabBarSymbols.chat.id
        case .overview: return TabBarSymbols.overview.id
        case .files: return TabBarSymbols.files.id
        case .settings: return TabBarSymbols.settings.id
        }
    }

    private func tab(forID id: String) -> MainTab? {
        switch id {
        case TabBarSymbols.chat.id: return .chat
        case TabBarSymbols.overview.id: return .overview
        case TabBarSymbols.files.id: return .files
        case TabBarSymbols.settings.id: return .settings
        default: return nil
        }
    }

    /// 底栏标签（原生栏隐藏后的 VO 元数据载体）：0.3.8
    /// 自绘栏接管呈现后，Tab 的 label 不再渲染，本函数
    /// 只保留符号/标题/标识的既有口径（自绘栏的按钮标
    /// 签由 FloatingTabBar 用同一 TabBarSymbols 表出）。
    /// 字形恒线条体、尺寸 22，选中不切 .fill、不变色不
    /// 加粗（选中信号由自绘浅灰胶囊垫承载）。
    private func tabLabel(_ pair: TabSymbolPair, tab: MainTab) -> some View {
        Image(systemName: pair.normal)
            .font(.system(size: OneDayMetrics.tabGlyph))
            .symbolEffect(.bounce, value: selection == tab)
            .accessibilityLabel(pair.title)
            .accessibilityIdentifier("tab.\(pair.id)")
    }
}
