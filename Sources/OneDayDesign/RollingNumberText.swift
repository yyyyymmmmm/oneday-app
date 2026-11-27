import OneDayCore
import SwiftUI

/// 总览数字：使用 iOS 17+ / macOS 14+ 原生 `.contentTransition(.numericText())`
/// 驱动数字平滑滚动，同值静态直出，尊重 Reduce Motion。
public struct RollingNumberText: View {
    private let key: String
    private let value: Double
    private let font: Font
    private let weight: Font.Weight?
    private let format: (Double) -> String
    private let gate: RollingNumberGate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Double

    public init(
        key: String, value: Double, font: Font = .body,
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
            _displayed = State(initialValue: settled)
        case .roll(let previous, _):
            _displayed = State(initialValue: previous)
        }
    }

    public var body: some View {
        NumberText(format(reduceMotion ? value : displayed), font: font, weight: weight)
            .contentTransition(.numericText(value: reduceMotion ? value : displayed))
            .accessibilityLabel(format(value))
            .onAppear { sync() }
            .onChange(of: key) { _, _ in sync() }
            .onChange(of: value) { _, _ in sync() }
            .onChange(of: reduceMotion) { _, _ in sync() }
    }

    private func sync() {
        if reduceMotion {
            displayed = value
            gate.settle(key: key, value: value)
            return
        }
        let decision = gate.decision(key: key, value: value)
        switch decision {
        case .static(let settled):
            displayed = settled
        case .roll:
            withAnimation(.snappy(duration: 0.45)) {
                displayed = value
            }
            gate.settle(key: key, value: value)
        }
    }
}
