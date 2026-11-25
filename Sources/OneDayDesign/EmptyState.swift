import OneDayCore
import SwiftUI

/// 空状态组件（全面原生统一）：直接委托系统原生
/// `ContentUnavailableView`，保持所有业务页与设计
/// 层空态视觉一致、字体与图标随 Dynamic Type 自动适配。
public struct ODEmptyState<Actions: View>: View {
    private let title: String
    private let systemImage: String
    private let description: String?
    private let actions: Actions

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

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            actions
        }
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
