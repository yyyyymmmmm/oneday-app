import OneDayDesign
import SwiftUI

/// 身份胶囊（§434 立于 ChatView 页头内、§449 抽为
/// 独立件供顶带复刻 rig 同件复用）：居中身份区的
/// 下件——名（.headline）＋状态词（.caption）两行
/// 装 44 高玻璃胶囊，压大头像下沿（重叠 ≈8 由宿
/// 主 ZStack 的头像底距 36 构成）。点按开枢纽
/// （与头像同路、单义）；§449 起长按菜单下沉一
/// 级挂「在对话中查找」（第 1 条安置：Telegram 点
/// 名展开页头／WhatsApp 点名进信息页把会话内查
/// 找挂身份面下沉一级同式，见 DESIGN §449.1），
/// VoiceOver 自定义动作同达。在线状态不在本件呈
/// 现（§449 去重：全簇只留头像角点一处）
/// §474（用户 2026-11-24 10:16 亲令）：第二行只许
/// 是工作状态（AppState.liveActivityPhrase 单源，
/// 与中枢状态行同词）；连接状态词（在线／联系不
/// 上／待审批）一律不进本件——无活动时第二行不
/// 呈现（回落留空，参照 Muse 空闲态查不到原文
/// 不自创词），不拿连接词垫底
struct HubIdentityCapsule: View {
    var displayName: String
    var statusWord: String?
    var onOpenHub: () -> Void
    /// 「在对话中查找」是聊天页专属下沉动作（§449.1）：
    /// §486 起本件被内容页页头簇（ContentPageHeader）
    /// 复用，那些页面没有会话内查找——改可选，nil 时
    /// 长按菜单只留「打开枢纽」、不挂 VO 自定义动作；
    /// 聊天页传闭包、行为一字不变
    var onFindInConversation: (() -> Void)? = nil

    var body: some View {
        // VO 自定义动作只在宿主真有此动作时才挂（nil
        // 时不许留一个按了没反应的空动作）：两分支共
        // 用 capsuleButton 本体、只差这一条修饰
        if let onFindInConversation {
            capsuleButton
                .accessibilityAction(named: "在对话中查找") {
                    onFindInConversation()
                }
        } else {
            capsuleButton
        }
    }

    private var capsuleButton: some View {
        Button {
            onOpenHub()
        } label: {
            VStack(spacing: OneDayMetrics.spacingMicro) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let statusWord, !statusWord.isEmpty {
                    Text(statusWord)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingSM)
            .frame(height: OneDayMetrics.minTapTarget)
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.odPressable)
        .accessibilityLabel(
            statusWord.map { "\(displayName)，\($0)，打开枢纽" }
                ?? "\(displayName)，打开枢纽"
        )
        .accessibilityIdentifier("topbar.identityCapsule")
        .contextMenu {
            Button {
                onOpenHub()
            } label: {
                Label("打开枢纽", systemImage: "person.crop.circle")
            }
            if let onFindInConversation {
                Button {
                    onFindInConversation()
                } label: {
                    Label("在对话中查找", systemImage: "magnifyingglass")
                }
            }
        }
    }
}
