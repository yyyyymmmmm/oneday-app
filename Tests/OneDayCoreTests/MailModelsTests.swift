import XCTest
@testable import OneDayCore

final class MailModelsTests: XCTestCase {
    func testMailGatewayListAndDetailPayloadDecode() throws {
        let payload = #"""
        {
          "total": 1,
          "data": [{
            "account_id": "mail_123",
            "folder": "INBOX",
            "uid": 42,
            "message_id": "<m1@example.org>",
            "from": "sender@example.org",
            "to": "reader@example.org",
            "subject": "Status",
            "date": 1795780800,
            "seen": false,
            "snippet": "All good",
            "body_text": "All good",
            "attachments": [{
              "filename": "report.txt",
              "size": 12,
              "content_type": "text/plain"
            }]
          }]
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(
            MailMessagesResponse.self, from: payload
        )
        let message = try XCTUnwrap(response.data.first)
        XCTAssertEqual(response.total, 1)
        XCTAssertEqual(message.id, "mail_123:INBOX:42")
        XCTAssertEqual(message.bodyText, "All good")
        XCTAssertEqual(message.attachments.first?.contentType, "text/plain")
    }
}
