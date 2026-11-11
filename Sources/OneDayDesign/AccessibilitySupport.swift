import SwiftUI
import UIKit

// MARK: - 无障碍设计层支撑（0.43.0 无障碍专项）

public extension DynamicTypeSize {
    /// SwiftUI 字号档 → UIKit 内容大小档（0.43.0，
    /// A11Y-D1 量测贯穿）：发送舱量测在 Core/UIKit
    /// 侧计档，SwiftUI 侧从环境取档后经本映射交
    /// 接。十二档一一同名对应、由单测逐项钉死——
    /// 映射错一档，量测与排版就在该档脱钩（这正是
    /// D1 旧口径最怕的事），不许凭印象改
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

/// 行数上限的无障碍放宽（0.43.0，A11Y-D3）：标准
/// 档保持原行数（默认外观逐字不变），AX 档
/// （dynamicTypeSize.isAccessibilitySize）放宽到
/// 指定行——大字下宁可让行长高，也不截断要读的
/// 信息。只许用在「行题/副题/摘要」这类信息文本
/// 上；装饰与定版量测面（如发送舱）不走本口
private struct A11yLineLimitModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let standard: Int
    let accessibility: Int

    func body(content: Content) -> some View {
        content.lineLimit(
            dynamicTypeSize.isAccessibilitySize
                ? accessibility : standard
        )
    }
}

public extension View {
    /// 见 A11yLineLimitModifier：标准档 standard 行、
    /// AX 档 ax 行
    func a11yLineLimit(_ standard: Int, ax: Int) -> some View {
        modifier(
            A11yLineLimitModifier(standard: standard, accessibility: ax)
        )
    }
}
