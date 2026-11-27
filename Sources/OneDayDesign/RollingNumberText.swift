import OneDayCore
import SwiftUI

/// 总览数字：同值静态直出，真变才用 Timeline 插值；
/// 字体只消费 NumberText，不叠加 numericText 二次过渡。
public struct RollingNumberText: View {
    private let key: String
    private let value: Double
    private let font: Font
    private let weight: Font.Weight?
    private let format: (Double) -> String
    private let gate: RollingNumberGate
    private let duration: TimeInterval = 0.9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeKey: String?
    @State private var from: Double = 0
    @State private var target: Double = 0
    @State private var startedAt: Date?

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
        // 仅种首帧，后续输入由 onChange 驱动；同值重进不闪 0。
        switch gate.decision(key: key, value: value) {
        case .static(let settled):
            _target = State(initialValue: settled)
        case .roll(let previous, _):
            _target = State(initialValue: previous)
        }
    }

    public var body: some View {
        TimelineView(.animation(paused: startedAt == nil || reduceMotion)) { context in
            NumberText(
                format(reduceMotion ? value : displayedValue(at: context.date)),
                font: font, weight: weight
            )
                .onChange(of: context.date) { _, date in
                    if let startedAt, date.timeIntervalSince(startedAt) >= duration {
                        settle()
                    }
                }
        }
        .accessibilityLabel(format(value))
        .transaction { $0.animation = nil }
        .onAppear { update() }
        .onChange(of: key) { _, _ in update() }
        .onChange(of: value) { _, _ in update() }
        .onChange(of: reduceMotion) { _, _ in update() }
        .onDisappear {
            // 离面只在实际已到终点时落账；中断不预写目标值。
            if let startedAt, Date().timeIntervalSince(startedAt) >= duration {
                settle()
            } else {
                startedAt = nil
            }
        }
    }

    private func displayedValue(at date: Date) -> Double {
        guard let startedAt else { return target }
        let progress = min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
        let remainder = 1 - progress
        let eased = 1 - remainder * remainder * remainder
        return from + (target - from) * eased
    }

    private func update() {
        let now = Date()
        let continuing = activeKey == key && startedAt != nil
        let current = displayedValue(at: now)
        if continuing, target == value, !reduceMotion { return }
        activeKey = key
        if reduceMotion {
            target = value
            settle()
            return
        }
        let decision = gate.decision(key: key, value: value)
        switch decision {
        case .static(let settled) where !continuing:
            target = settled
            startedAt = nil
        default:
            let origin: Double
            if continuing {
                origin = current
            } else if case .roll(let previous, _) = decision {
                origin = previous
            } else {
                origin = value
            }
            from = origin
            target = value
            startedAt = origin == value ? nil : now
            if startedAt == nil { settle() }
        }
    }

    private func settle() {
        guard let activeKey else { return }
        startedAt = nil
        gate.settle(key: activeKey, value: target)
    }
}
