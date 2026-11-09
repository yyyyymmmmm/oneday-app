import OneDayCore
import OneDayDesign
import SwiftUI

/// 底部四格（聊天／总览／文件／设置；IA 不动）。
/// 底栏沿革：0.2.4 回归原生 TabView → 0.3.1 换 Tab(value:)
/// ＋Label 直渲 → 0.3.8 按当时裁决隐藏原生栏、叠自绘
/// FloatingTabBar → **0.4.0 拆自绘、回原生（审计 §3.2）**：
/// 自绘前提「原生选中垫宽约 98pt 改不了」已被 Muse 本体
/// 截图证伪（它用的就是 iOS 26 原生玻璃坞）；本版删四处
/// .toolbarVisibility(.hidden)、删覆盖层与 FloatingTabBar
/// 本体、删 TabBarLayout，呈现全交系统——Liquid Glass 坞、
/// 选中态、滚动最小化、键盘联动都是系统行为（WWDC25-323）。
/// 符号源仍是 OneDayCore.TabBarSymbols（原生 Tab 的 Label
/// 直接取用，§1.2 #28 数据保留）；Label 标题随栏进系统
/// 排布（0.3.1 礼记同款口径）。
/// 抽屉与底栏的关系：0.4.0 曾按 §3.2 推荐案「不为抽屉
/// 态隐藏底栏」，0.4.1 被用户真机点名推翻——抽屉打开
/// 时底栏隐藏（ChatView 侧 toolbarVisibility 绑定
/// drawerOpen），面板底条落真底边。
/// 0.4.1 底栏向 Muse 本体靠（用户点名，全用原生件）：
/// ①图标锁 outline——符号表 selected≡normal 之外，
/// Label 字形再加 .symbolVariant(.none)，堵系统在选中
/// 态自动换 .fill 变体的通道（0.2.5 时代实证）；②根
/// .tint 由系统默认蓝改 .primary 单色（去蓝；连带页面
/// 残余强调位一并单色化——发送键/光标/主按钮，全仓
/// Palette.primary* 引用共 7 处、均为框架强调位，与
/// 「框架无色」基线同向，§26 在案）；③开
/// .tabBarMinimizeBehavior(.onScrollDown) 滚动收起
/// （样板里底坞收成一颗胶囊即此原生行为）。标签在展
/// 开态保留属原生形态、不处理。
/// 深链口径：AgentRoute / SettingsRoute 落点仍是设置格；
/// 服务端会话续聊（§3.4）经 pendingChatSessionID 切聊天格。
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case overview
        case files
        case settings
    }

    @Environment(AppState.self) private var appState
    @State private var selection: MainTab = .chat

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: MainTab.chat) {
                ChatView(
                    onOpenServerSession: { id in
                        // 0.4.0（§3.4）：服务端会话改道
                        // 聊天页续聊，不再送设置格只读详情
                        appState.pendingChatSessionID = id
                    },
                    onSelectTab: { selection = $0 }
                )
            } label: {
                tabLabel(TabBarSymbols.chat)
            }

            Tab(value: MainTab.overview) {
                OverviewView(
                    onOpenAgent: { route in
                        appState.pendingAgentRoute = route
                        selection = .settings
                    },
                    onOpenChatSession: { id in
                        appState.pendingChatSessionID = id
                    },
                    onOpenSettings: { route in
                        appState.pendingSettingsRoute = route
                        selection = .settings
                    },
                    onOpenChat: { selection = .chat }
                )
            } label: {
                tabLabel(TabBarSymbols.overview)
            }

            Tab(value: MainTab.files) {
                FilesView()
            } label: {
                tabLabel(TabBarSymbols.files)
            }

            Tab(value: MainTab.settings) {
                SettingsView()
            } label: {
                tabLabel(TabBarSymbols.settings)
            }
        }
        // 0.4.0（审计 §1.1）：根 .tint(Palette.ink) 与暗色
        // 字重降档 hack 一并删除——tint 回系统默认（强调
        // 色由系统/用户系统设置决定），字重不再做环境级
        // 覆写（正文字重回归语义样式自带，批次 4 收口）
        // 0.4.1（用户点名）：tint 改系统主色单色 .primary
        // （去蓝，见文件头 0.4.1 注）；滚动收起走系统
        // tabBarMinimizeBehavior（.onScrollDown）
        .tint(.primary)
        .tabBarMinimizeBehavior(.onScrollDown)
        // 0.4.0（§3.4）：任一入口置位待续聊会话 → 切聊天格
        // （ChatView 侧消费导入；已在聊天格时 onChange 同样
        // 触发、由 ChatView 直接消费）
        .onChange(of: appState.pendingChatSessionID) { _, id in
            if id != nil { selection = .chat }
        }
    }

    /// 底栏标签（0.4.1）：标题随 Label 进栏（原生形态），
    /// 字形锁 outline——.symbolVariant(.none) 禁系统在
    /// 选中态自动替换 .fill 变体（符号表本身 selected≡
    /// normal 是第一道锁、此处是呈现侧第二道锁）
    private func tabLabel(_ pair: TabSymbolPair) -> some View {
        Label {
            Text(pair.title)
        } icon: {
            Image(systemName: pair.normal)
                .symbolVariant(.none)
        }
    }
}
