import Foundation

/// Mail gateway list/detail read models (server CAPABILITIES #66).
public struct MailMessage: Decodable, Equatable, Identifiable, Sendable {
    public struct Attachment: Decodable, Equatable, Sendable {
        public let filename: String
        public let size: Int
        public let contentType: String

        enum CodingKeys: String, CodingKey {
            case filename, size
            case contentType = "content_type"
        }
    }

    public let accountID: String
    public let folder: String
    public let uid: Int
    public let messageID: String?
    public let from: String
    public let to: String
    public let subject: String
    public let date: Int64
    public let seen: Bool
    public let snippet: String
    public let bodyText: String?
    public let attachments: [Attachment]

    public var id: String { "\(accountID):\(folder):\(uid)" }

    enum CodingKeys: String, CodingKey {
        case folder, uid, from, to, subject, date, seen, snippet, attachments
        case accountID = "account_id"
        case messageID = "message_id"
        case bodyText = "body_text"
    }
}

public struct MailMessagesResponse: Decodable, Sendable {
    public let total: Int
    public let data: [MailMessage]
}
