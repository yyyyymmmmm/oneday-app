import OneDayCore
import SwiftUI

/// 中枢 cover 呈现（H2 收编，呈现与导航手势审计
/// 2026-11-24 问题二；用户 2026-11-24 拍板）：中
/// 枢自全部入口一律 cover 呈现——动态/点子/目
/// 标/文件四格原 push 入中枢（与各自页栈形成嵌
/// 套双栈、右滑返回无仲裁）整路退役，与聊天页入
/// 口同形态：fullScreenCover＋HubCardHost 卡片
/// 宿主（Reduce Motion 走标准 cover），呈现/关
/// 闭的无动画事务与 ChatView 的 presentHub/dis-
/// missHubWithoutAnimation 同口径（卡片口径下防
/// 系统 cover 转场与宿主入场弹簧双写）。
/// 聊天页宿主带模型入口与审批回调注入、构造点
/// 在 ChatView.hubCover，不走本件；本件只承载无
/// 注入的标准中枢（四格现行构造即无注入，行为
/// 不变）。通知落点与聚焦字段的消费在 AgentHub-
/// View 本体内、与呈现形态无关，收编不丢落点。
enum HubCoverPresenter {
    /// 开中枢：走 iOS 原生 Sheet 呈现（系统 120fps 合成自带底层缩放压暗）
    static func present(
        _ isPresented: Binding<Bool>, reduceMotion: Bool
    ) {
        isPresented.wrappedValue = true
    }

    /// 关中枢
    static func dismiss(_ isPresented: Binding<Bool>) {
        isPresented.wrappedValue = false
    }
}

/// 标准中枢 fullScreenCover 修饰位（2026-11-27 改全屏呈现，皇上亲令）
struct HubCoverModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            AgentHubView()
        }
    }
}

extension View {
    /// 中枢全屏呈现（2026-11-27 改 fullScreenCover，皇上亲令）
    func hubCover(isPresented: Binding<Bool>) -> some View {
        modifier(HubCoverModifier(isPresented: isPresented))
    }
}
