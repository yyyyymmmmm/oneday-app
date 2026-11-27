import XCTest
@testable import OneDayCore

/// §434 分格注册表钉测：格集只由真回读输入决定
/// （有真能力才长格），顺序恒为参照胶囊序。
final class HubSegmentRegistryTests: XCTestCase {

    private func inputs(
        connected: Bool = true,
        grants: Bool = false,
        approvals: Bool = false,
        box: Bool = false,
        mail: Bool = false
    ) -> HubSegmentInputs {
        HubSegmentInputs(
            connected: connected,
            grantsReadbackOK: grants,
            approvalsReadbackOK: approvals,
            boxConfigured: box,
            mailDataSourceAvailable: mail
        )
    }

    func testDisconnectedGrowsNothing() {
        XCTAssertEqual(
            HubSegmentRegistry.resolve(.disconnected), []
        )
        XCTAssertEqual(
            HubSegmentRegistry.resolve(
                inputs(connected: false, grants: true, box: true, mail: true)
            ),
            []
        )
    }

    func testAnchorsOnlyWhenBareConnected() {
        XCTAssertEqual(
            HubSegmentRegistry.resolve(inputs()),
            [.work, .identity]
        )
    }

    func testAuditGrowsOnEitherReadback() {
        XCTAssertEqual(
            HubSegmentRegistry.resolve(inputs(grants: true)),
            [.work, .audit, .identity]
        )
        XCTAssertEqual(
            HubSegmentRegistry.resolve(inputs(approvals: true)),
            [.work, .audit, .identity]
        )
    }

    func testComputerGrowsOnBoxConfigured() {
        XCTAssertEqual(
            HubSegmentRegistry.resolve(inputs(box: true)),
            [.work, .computer, .identity]
        )
    }

    func testMailGrowsOnlyWhenDataSourceIsAvailable() {
        XCTAssertEqual(
            HubSegmentRegistry.resolve(inputs(mail: true)),
            [.work, .identity, .mail]
        )
    }

    func testFullHouseInReferenceOrder() {
        XCTAssertEqual(
            HubSegmentRegistry.resolve(
                inputs(grants: true, approvals: true, box: true, mail: true)
            ),
            [.work, .audit, .computer, .identity, .mail]
        )
    }

    func testDescriptorMetadata() {
        XCTAssertEqual(
            HubSegmentID.allCases.map(\.title),
            ["工作", "审核", "电脑", "身份", "邮箱"]
        )
        XCTAssertEqual(
            HubSegmentID.allCases.map(\.systemImage),
            ["list.bullet", "shield", "display", "touchid", "envelope"]
        )
    }
}
