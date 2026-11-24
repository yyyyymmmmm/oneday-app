import SwiftUI

/// 空状态编排（台账 177，OB-U5；DESIGN §391）：空状态
/// 当一次编排过的转场做——图标、标题、说明、动作分阶
/// 段入场（阶段差 90ms、MotionTokens.entrance 收束），
/// 文案不同时在场；开启「减动效」时只保留淡入、去掉
/// 位移与阶段差（同拍全显）。形态与 ContentUnavail-
/// ableView 同位同职（图标＋标题＋说明＋可选动作），
/// 主面空态走本件；存量 ContentUnavailableView 逐面
/// 迁移，进度见 §391 登记。
public struct ODEmptyState<Actions: View>: View {
    private let title: String
    private let systemImage: String
    private let description: String?
    private let actions: Actions

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var appeared = false

    public init(
        _ title: String,
        systemImage: String,
        description: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    /// 阶段入场：delay 按阶段序递增（减动效恒 0），
    /// 位移只在非减动效且未入场时存在
    private func staged(
        _ phase: Int, content: some View
    ) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(
                MotionTokens.entrance.delay(
                    reduceMotion ? 0 : Double(phase) * 0.09
                ),
                value: appeared
            )
    }

    public var body: some View {
        VStack(spacing: OneDayMetrics.spacingS) {
            staged(0, content: Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true))
            staged(1, content: Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center))
            if let description {
                staged(2, content: Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center))
            }
            staged(3, content: actions
                .padding(.top, OneDayMetrics.spacingXS))
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }
}

extension ODEmptyState where Actions == EmptyView {
    public init(
        _ title: String,
        systemImage: String,
        description: String? = nil
    ) {
        self.init(
            title, systemImage: systemImage,
            description: description
        ) { EmptyView() }
    }
}
