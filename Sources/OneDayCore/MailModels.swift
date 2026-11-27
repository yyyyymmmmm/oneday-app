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

/// Mail draft model (server CAPABILITIES #TBD).
public struct MailDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let to: String
    public let subject: String
    public let bodyText: String
    public let status: String
    public let approvalRef: String?
    public let sendError: String?
    public let createdAt: Int64
    public let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, to, subject, status
        case bodyText = "body_text"
        case approvalRef = "approval_ref"
        case sendError = "send_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct MailDraftsResponse: Decodable, Sendable {
    public let data: [MailDraft]
}

public struct CreateDraftRequest: Encodable, Sendable {
    public let to: String
    public let subject: String
    public let bodyText: String

    public init(to: String, subject: String, bodyText: String) {
        self.to = to
        self.subject = subject
        self.bodyText = bodyText
    }

    enum CodingKeys: String, CodingKey {
        case to, subject
        case bodyText = "body_text"
    }
}

public struct SendDraftRequest: Encodable, Sendable {
    public let approvalRef: String

    public init(approvalRef: String) {
        self.approvalRef = approvalRef
    }

    enum CodingKeys: String, CodingKey {
        case approvalRef = "approval_ref"
    }
}
