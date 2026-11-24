import OneDayCore
import OneDayDesign
import SwiftUI

/// NEW 未读分界线（台账 148，学 OpenBot 的
/// UnreadLineRow 交互形态、视觉走自家定版）：发丝
/// 线＋居中徽标＋发丝线，立在第一条未读消息上方
/// （锚解析在 Core UnreadDivider、水位在 Thread-
/// ReadMarkStore）。
///
/// 入场节拍对 OB 原值：徽标先到（200ms easeOut、
/// 透明 0→1＋缩放 0.9→1），线自徽标向两侧长出
/// （340ms easeOut、延迟 60ms、scaleX 锚在徽标
/// 侧）；只演一次——已演由 ChatRowStateLedger 记
/// 账（arrived 入参），滚动重建后直接静态呈现；
/// Reduce Motion 时恒静态（OB 同口径）。行高由
/// 徽标单行决定，与高度合成侧的分界槽逐值同高
/// （ChatNativeRowHeightComposer 的 showsUnread-
/// Divider 槽）。
struct ChatUnreadDividerView: View {
    /// 本锚是否已演过入场（账本派生；true＝静态）
    let arrived: Bool
    /// 首次呈现后回记账本（只演一次的记账口）
    let onArrive: () -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var shown: Bool

    init(arrived: Bool, onArrive: @escaping () -> Void) {
        self.arrived = arrived
        self.onArrive = onArrive
        _shown = State(initialValue: arrived)
    }

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            line(anchor: .trailing)
            Text(L10n.string("新消息"))
                .font(.meta)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.primary)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.9)
                .animation(
                    .easeOut(duration: 0.2), value: shown
                )
            line(anchor: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("以下为新消息"))
        .onAppear {
            if !shown {
                if reduceMotion {
                    shown = true
                } else {
                    // 线的延迟/时长在各自 animation
                    // 上，徽标与线共用 shown 一拍起步
                    shown = true
                }
            }
            onArrive()
        }
    }

    /// 两侧发丝线：自徽标侧向外长出（左线锚右缘、
    /// 右线锚左缘——徽标在中间，两线都从贴徽标的
    /// 一端生长）
    private func line(anchor: UnitPoint) -> some View {
        Rectangle()
            .fill(Palette.primary.opacity(0.45))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .opacity(shown ? 1 : 0)
            .scaleEffect(
                x: shown ? 1 : 0, y: 1, anchor: anchor
            )
            .animation(
                .easeOut(duration: 0.34).delay(0.06),
                value: shown
            )
    }
}
