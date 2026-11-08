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
struct ContentView: View {
    enum MainTab: Hashable {
        case chat
        case overview
        case files
        case settings
    }

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: MainTab = .chat

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: MainTab.chat) {
                ChatView(
                    onOpenServerSession: { id in
                        appState.pendingAgentRoute = .serverSessionDetail(id)
                        selection = .settings
                    },
                    onSelectTab: { selection = $0 }
                )
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
            } label: {
                // 0.2.5 选型沿革：原 gauge.with.dots.needle.
                // 33percent 是带实心圆点的粗字形，换细线条
                // 的趋势线图（该符号无 .fill 对，选中同名）
                tabLabel(TabBarSymbols.overview, tab: .overview)
            }

            Tab(value: MainTab.files) {
                FilesView()
            } label: {
                tabLabel(TabBarSymbols.files, tab: .files)
            }

            Tab(value: MainTab.settings) {
                SettingsView()
            } label: {
                // 0.2.5 选型沿革：gearshape 是实心剪影、无更
                // 细的同义齿轮符号，换线条体的滑杆组（偏好
                // 设置字形；该符号无 .fill 对，选中同名）
                tabLabel(TabBarSymbols.settings, tab: .settings)
            }
        }
        // 0.3.6 立宪（DESIGN-V4 §21.3/§22）：tint 撤销蓝
        // 色、改回 Palette.ink——用户按 Muse 实测基线改
        // 判：选中＝系统浅灰小胶囊垫＋墨色字形，文字不变
        // 色不加粗不上蓝；蓝只留功能位（发送键/链接等）。
        // 此令推翻 0.3.3「.tint(Palette.primary) 随主题」
        // （真机对比礼记的当场改判再被基线改判，§21.5 对
        // 账）。0.2.5 的系统口径在此复用：tint 墨 → 选中
        // 呈墨色线条字形＋系统浅灰选择胶囊（#E3E3E5 系、
        // 色值由系统按 tint 派生）。
        .tint(Palette.ink)
        // 条 3（§14）未带权文字的降档通道：暗色环境下根
        // fontWeight 降一档（regular→light），未显式带权
        // 的 Text 全量继承；带权字体走 TypeScale 的
        // (for:) 变体（VisualWeight 映射）。UIKit 文本
        // 视图（输入框正文）不在此环境内、不受影响
        .fontWeight(colorScheme == .dark ? .light : .regular)
    }

    /// 底栏标签（0.3.6 立宪形态，DESIGN-V4 §21.3）：
    /// 去文字标签——只交字形（Image-only 系统条目形
    /// 态，名称只进无障碍标签）；字形恒线条体、尺寸
    /// 配置 22（OneDayMetrics.tabGlyph，基线带 21–
    /// 22），选中不切 .fill、不变色不加粗（选中信号
    /// 只由系统浅灰胶囊垫承载，见 body 的 tint 注）。
    /// 符号源仍是 OneDayCore.TabBarSymbols 恒取
    /// normal（线条体）一侧；选中 .bounce 保留（系统
    /// 在 Reduce Motion 时自动抑制）。0.3.1 的 Label
    /// 带字＋fill 成对就此被立宪取代（§21.5 对账）。
    private func tabLabel(_ pair: TabSymbolPair, tab: MainTab) -> some View {
        Image(systemName: pair.normal)
            .font(.system(size: OneDayMetrics.tabGlyph))
            .symbolEffect(.bounce, value: selection == tab)
            .accessibilityLabel(pair.title)
            .accessibilityIdentifier("tab.\(pair.id)")
    }
}
