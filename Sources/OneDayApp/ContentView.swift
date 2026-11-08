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
/// 层级与避让全部服从系统默认：聊天抽屉（页内覆盖层）打开
/// 时底栏按系统层级浮于其上；键盘弹起时由系统处理；各页
/// 滚动内容经系统安全区延伸到底栏之下，从玻璃背后流过。
/// 深链口径不变：AgentRoute / SettingsRoute 落点仍是设置格；
/// 聊天第一格默认落点。
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
            ChatView(
                onOpenSettings: { selection = .settings },
                onOpenServerSession: { id in
                    appState.pendingAgentRoute = .serverSessionDetail(id)
                    selection = .settings
                }
            )
            .tabItem {
                Image(systemName: "bubble.left.and.bubble.right")
                    .symbolVariant(.none)
                    .accessibilityLabel("聊天")
                    .accessibilityIdentifier("tab.chat")
            }
            .tag(MainTab.chat)

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
            .tabItem {
                // 0.2.5：原 gauge.with.dots.needle.33percent 是
                // 带实心圆点的粗字形，换细线条的趋势线图
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .symbolVariant(.none)
                    .accessibilityLabel("总览")
                    .accessibilityIdentifier("tab.overview")
            }
            .tag(MainTab.overview)

            FilesView()
                .tabItem {
                    Image(systemName: "folder")
                        .symbolVariant(.none)
                        .accessibilityLabel("文件")
                        .accessibilityIdentifier("tab.files")
                }
                .tag(MainTab.files)

            SettingsView()
                .tabItem {
                    // 0.2.5：gearshape 是实心剪影、无更细的同义
                    // 齿轮符号，换线条体的滑杆组（偏好设置字形）
                    Image(systemName: "slider.horizontal.3")
                        .symbolVariant(.none)
                        .accessibilityLabel("设置")
                        .accessibilityIdentifier("tab.settings")
                }
                .tag(MainTab.settings)
        }
        .tint(Palette.ink)
    }
}
