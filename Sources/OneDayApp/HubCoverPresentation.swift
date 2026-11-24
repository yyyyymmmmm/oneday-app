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
    /// 开中枢：卡片口径走无动画事务置位（入场弹
    /// 簧由 HubCardHost 自理）
    static func present(
        _ isPresented: Binding<Bool>, reduceMotion: Bool
    ) {
        if HubCardPolicy.decide(reduceMotion: reduceMotion)
            == .card {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isPresented.wrappedValue = true
            }
        } else {
            isPresented.wrappedValue = true
        }
    }

    /// 关中枢落账：飞出动画已在 HubCardHost 内走
    /// 完，无动画事务落位防系统退场转场二次抢镜
    static func dismiss(_ isPresented: Binding<Bool>) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresented.wrappedValue = false
        }
    }
}

/// 标准中枢 cover 修饰位：四格各挂一处，呈现宿
/// 主与聊天页同一 HubCardHost（同一呈现宿主）
struct HubCoverModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            if HubCardPolicy.decide(
                reduceMotion: reduceMotion
            ) == .card {
                HubCardHost(
                    onDismissed: {
                        HubCoverPresenter.dismiss($isPresented)
                    }
                ) { requestClose in
                    AgentHubView(onCardClose: requestClose)
                }
            } else {
                AgentHubView()
            }
        }
    }
}

extension View {
    /// 中枢 cover 呈现（H2 收编单源）：非聊天宿主
    /// 开中枢只许走本修饰位＋HubCoverPresenter
    /// .present 置位，不许再 push 入中枢
    func hubCover(isPresented: Binding<Bool>) -> some View {
        modifier(HubCoverModifier(isPresented: isPresented))
    }
}
