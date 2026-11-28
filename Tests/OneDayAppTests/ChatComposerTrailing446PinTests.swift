import OneDayCore
import XCTest

final class ChatComposerTrailing446PinTests: XCTestCase {
    func testDraftRoutesToSendEvenWhileStreaming() {
        for isStreaming in [false, true] {
            assertDiscAction(isStreaming: isStreaming, canSend: true, expected: ["send"])
        }
    }

    func testEmptyComposerStopsOnlyWhileStreaming() {
        assertDiscAction(isStreaming: true, canSend: false, expected: ["stop"])
        assertDiscAction(isStreaming: false, canSend: false, expected: [])
    }

    private func assertDiscAction(
        isStreaming: Bool, canSend: Bool, expected: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var actions: [String] = []
        ComposerTrailingState.resolve(isStreaming: isStreaming, canSend: canSend)
            .activateDisc(
                onSend: { actions.append("send") },
                onStop: { actions.append("stop") }
            )
        XCTAssertEqual(actions, expected, file: file, line: line)
    }
}
