import OneDayCore
import SwiftUI

/// 总览数字：基于系统原生 `.contentTransition(.numericText())` 实现平滑数字滚动；
/// 配合 RollingNumberGate 保证同值重进不闪 0，减少动态效果时直出终值。
public struct RollingNumberText: View {
    private let key: String
    private let value: Double
    private let font: Font
    private let weight: Font.Weight?
    private let format: (Double) -> String
    private let gate: RollingNumberGate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedValue: Double

    public init(
        key: String,
        value: Double,
        font: Font = .body,
        weight: Font.Weight? = nil,
        gate: RollingNumberGate = .shared,
        format: @escaping (Double) -> String
    ) {
        self.key = key
        self.value = value
        self.font = font
        self.weight = weight
        self.gate = gate
        self.format = format
        switch gate.decision(key: key, value: value) {
        case .static(let settled):
            _displayedValue = State(initialValue: settled)
        case .roll(let previous, _):
            _displayedValue = State(initialValue: previous)
        }
    }

    public var body: some View {
        NumberText(
            format(reduceMotion ? value : displayedValue),
            font: font,
            weight: weight
        )
        .contentTransition(.numericText(value: displayedValue))
        .accessibilityLabel(format(value))
        .onAppear { syncValue() }
        .onChange(of: key) { _, _ in syncValue() }
        .onChange(of: value) { _, _ in syncValue() }
        .onChange(of: reduceMotion) { _, _ in syncValue() }
    }

    private func syncValue() {
        if reduceMotion {
            displayedValue = value
            gate.settle(key: key, value: value)
            return
        }
        switch gate.decision(key: key, value: value) {
        case .static(let settled):
            displayedValue = settled
        case .roll(let previous, let target):
            if displayedValue != previous && displayedValue != target {
                displayedValue = previous
            }
            withAnimation(.snappy(duration: 0.45)) {
                displayedValue = target
            }
            gate.settle(key: key, value: target)
        }
    }
}
