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
                tabSymbol("bubble.left.and.bubble.right")
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
                tabSymbol("chart.line.uptrend.xyaxis")
                    .accessibilityLabel("总览")
                    .accessibilityIdentifier("tab.overview")
            }
            .tag(MainTab.overview)

            FilesView()
                .tabItem {
                    tabSymbol("folder")
                        .accessibilityLabel("文件")
                        .accessibilityIdentifier("tab.files")
                }
                .tag(MainTab.files)

            SettingsView()
                .tabItem {
                    // 0.2.5：gearshape 是实心剪影、无更细的同义
                    // 齿轮符号，换线条体的滑杆组（偏好设置字形）
                    tabSymbol("slider.horizontal.3")
                        .accessibilityLabel("设置")
                        .accessibilityIdentifier("tab.settings")
                }
                .tag(MainTab.settings)
        }
        .tint(Palette.ink)
    }

    /// 0.2.6 检查项 C＋底栏图标再小一号：tab 图标改预渲染
    /// UIImage——以 SymbolConfiguration(pointSize: 21,
    /// weight: .regular) 在生成时就把字形烘焙死。
    /// 核查结论（真机 0.2.5 截图 folder 与选中态聊天仍读作
    /// 实心黑块）：SwiftUI 的 .symbolVariant(.none) 没有锁住
    /// 底栏渲染——UITabBar 在选中态仍按自己的规则换 .fill
    /// 变体、且 tab 图标点数不受 SwiftUI font/配置控制
    /// （系统默认约 26–28pt 视觉）。预渲染位图没有变体可
    /// 换：两态同一张线条字形，根除 fill 切换；点数 21 落
    /// 在用户直令的 20–22 目标带内，点击热区是 tab 条目
    /// 本身、不随字形缩小。位图按 alpha 模板渲染，.tint
    /// 墨色照常生效。
    /// 0.2.7 按官方口径再校准（DESIGN-V4 §11.0）：定案标准
    /// 改为「字形墨迹高 23–25pt」——HIG《Tab bars》指向的
    /// Apple Design Resources 字形规格约 25pt。实测 SF 符号
    /// 在底栏的墨迹系统性大于 config 点数且逐字形不同，故
    /// 逐字形反推 config 并两轮实测收敛：config 21 时双气
    /// 泡 ≈37pt（系数 ≈1.8）、folder ≈28pt（≈1.35）；首轮
    /// 校准（双气泡 14/folder 17）后 CI 同法复量仍 ≈27pt
    /// （实测系数 1.9/1.6），再收一档定案：双气泡 12、其余
    /// 15，墨迹落 23–24pt。字形烘焙进固定 44×44pt 透明画
    /// 布居中绘制：四个条目位图同尺寸，系统排版基准一致、
    /// 只缩墨迹不动槽位与热区；烘焙图须显式
    /// .alwaysTemplate（渲染器产物默认 original，tint 会
    /// 失效）。
    private func tabSymbol(_ name: String) -> Image {
        let pointSize: CGFloat =
            name == "bubble.left.and.bubble.right" ? 12 : 15
        let configuration = UIImage.SymbolConfiguration(
            pointSize: pointSize, weight: .regular
        )
        let glyph = UIImage(systemName: name, withConfiguration: configuration)
            ?? UIImage()
        let canvas = CGSize(width: 44, height: 44)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let baked = UIGraphicsImageRenderer(size: canvas, format: format)
            .image { _ in
                glyph.draw(at: CGPoint(
                    x: (canvas.width - glyph.size.width) / 2,
                    y: (canvas.height - glyph.size.height) / 2
                ))
            }
            .withRenderingMode(.alwaysTemplate)
        return Image(uiImage: baked)
    }
}
