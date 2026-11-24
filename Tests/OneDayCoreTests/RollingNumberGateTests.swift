import XCTest
@testable import OneDayCore

final class RollingNumberGateTests: XCTestCase {
    func testFirstValueRollsFromZero() {
        withDefaults { defaults in
            let gate = RollingNumberGate(defaults: defaults)
            XCTAssertEqual(gate.decision(key: "tokens", value: 42), .roll(from: 0, to: 42))
            XCTAssertEqual(gate.decision(key: "zero", value: 0), .roll(from: 0, to: 0))
        }
    }

    func testSettledSameValueIsStaticAndChangedValueRollsFromPrevious() {
        withDefaults { defaults in
            let gate = RollingNumberGate(defaults: defaults)
            gate.settle(key: "tokens", value: 42)
            XCTAssertEqual(gate.decision(key: "tokens", value: 42), .static(42))
            XCTAssertEqual(gate.decision(key: "tokens", value: 65), .roll(from: 42, to: 65))
            // 决策不是落定；滚中再问仍从最后落定的 42 起算。
            XCTAssertEqual(gate.decision(key: "tokens", value: 70), .roll(from: 42, to: 70))
            gate.settle(key: "tokens", value: 70)
            XCTAssertEqual(gate.decision(key: "tokens", value: 70), .static(70))
        }
    }

    func testDifferentKeysDoNotInterfere() {
        withDefaults { defaults in
            let gate = RollingNumberGate(defaults: defaults)
            gate.settle(key: "tokens", value: 42)
            gate.settle(key: "sessions", value: 3)
            XCTAssertEqual(gate.decision(key: "tokens", value: 50), .roll(from: 42, to: 50))
            XCTAssertEqual(gate.decision(key: "sessions", value: 3), .static(3))
            XCTAssertEqual(gate.decision(key: "cron", value: 2), .roll(from: 0, to: 2))
        }
    }

    func testInjectedDefaultsPersistsOnlySettledValuesAcrossInstances() {
        withDefaults { defaults in
            let first = RollingNumberGate(defaults: defaults)
            _ = first.decision(key: "tokens", value: 99)
            XCTAssertEqual(
                RollingNumberGate(defaults: defaults).decision(key: "tokens", value: 99),
                .roll(from: 0, to: 99)
            )
            first.settle(key: "tokens", value: 99)
            let restored = RollingNumberGate(defaults: defaults)
            XCTAssertEqual(restored.decision(key: "tokens", value: 99), .static(99))
            XCTAssertEqual(restored.decision(key: "tokens", value: 12), .roll(from: 99, to: 12))
            restored.settle(key: "tokens", value: 0)
            XCTAssertEqual(
                RollingNumberGate(defaults: defaults).decision(key: "tokens", value: 0), .static(0)
            )
        }
    }

    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suite = "RollingNumberGateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        test(defaults)
    }
}
