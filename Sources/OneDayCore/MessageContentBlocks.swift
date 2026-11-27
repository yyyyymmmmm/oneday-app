import Foundation

// MARK: - 结构化消息块协议（#34：兼容旧正则标记的双轨编解码器）

/// 标准化消息内容块：替代裸文本中的 `[[deliver:...]]`、`[[cloud:...]]`、
/// `MEDIA:` 等内联正则标记。新服务端可下发 JSON `content_blocks` 信封，
/// 旧历史消息自动走兼容解析器无损映射为同一套强类型块。
public enum MessageContentBlock: Codable, Equatable, Sendable {
    case text(String)
    case deliveredFile(id: String)
    case cloudComputer(CloudComputerTarget)
    case media(path: String)
    case vaultRequest(id: String, summary: String?)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, target, path, summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "delivered_file", "deliver":
            self = .deliveredFile(id: try container.decode(String.self, forKey: .id))
        case "cloud_computer", "cloud":
            self = .cloudComputer(try container.decode(CloudComputerTarget.self, forKey: .target))
        case "media":
            self = .media(path: try container.decode(String.self, forKey: .path))
        case "vault_request", "vreq":
            self = .vaultRequest(
                id: try container.decode(String.self, forKey: .id),
                summary: try container.decodeIfPresent(String.self, forKey: .summary)
            )
        default:
            let fallback = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(fallback)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .deliveredFile(let id):
            try container.encode("delivered_file", forKey: .type)
            try container.encode(id, forKey: .id)
        case .cloudComputer(let target):
            try container.encode("cloud_computer", forKey: .type)
            try container.encode(target, forKey: .target)
        case .media(let path):
            try container.encode("media", forKey: .type)
            try container.encode(path, forKey: .path)
        case .vaultRequest(let id, let summary):
            try container.encode("vault_request", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(summary, forKey: .summary)
        }
    }
}

/// 带服务端单调 `seq` 与幂等键 `client_msg_id` 的结构化消息信封。
public struct MessageContentEnvelope: Codable, Equatable, Sendable {
    public let version: Int
    public let seq: Int?
    public let clientMsgID: String?
    public let contentBlocks: [MessageContentBlock]

    public init(
        version: Int = 1,
        seq: Int? = nil,
        clientMsgID: String? = nil,
        contentBlocks: [MessageContentBlock]
    ) {
        self.version = version
        self.seq = seq
        self.clientMsgID = clientMsgID
        self.contentBlocks = contentBlocks
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case seq
        case clientMsgID = "client_msg_id"
        case contentBlocks = "content_blocks"
    }
}

/// 双轨消息块编解码器：
/// 1. 优先尝试解析 JSON `MessageContentEnvelope`（含 `content_blocks`）；
/// 2. 旧格式纯文本自动回落至兼容解析器，依次剥离 `[[deliver:...]]`、
///    云电脑直播链接（`CloudComputerMarker`）、`[[vreq:...]]` 与 `MEDIA:` 行。
public enum MessageBlockCodec {
    private static let deliverRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\[\[deliver:(dlv_[0-9a-f]{20})\]\]"#,
        options: []
    )
    private static let vaultReqRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\[\[vreq:([A-Za-z0-9_-]+)(?:\|([^\]]*))?\]\]"#,
        options: []
    )

    public static func encode(
        _ blocks: [MessageContentBlock],
        seq: Int? = nil,
        clientMsgID: String? = nil
    ) -> String? {
        let envelope = MessageContentEnvelope(
            version: 1,
            seq: seq,
            clientMsgID: clientMsgID,
            contentBlocks: blocks
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ raw: String) -> [MessageContentBlock] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1. 新协议 JSON 信封快路径
        if trimmed.hasPrefix("{"),
           trimmed.contains("\"content_blocks\""),
           let data = trimmed.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(MessageContentEnvelope.self, from: data) {
            return envelope.contentBlocks
        }

        // 2. 兼容解析器：剥离云电脑标记、文件交付标记、凭据请求标记与 MEDIA 行
        var working = raw
        var blocks: [MessageContentBlock] = []

        let cloudSplit = CloudComputerMarker.split(in: working)
        working = cloudSplit.text

        var deliveredIDs: [String] = []
        if let regex = deliverRegex {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    deliveredIDs.append(ns.substring(with: match.range(at: 1)))
                }
                working = (working as NSString).replacingCharacters(in: match.range, with: "")
            }
        }

        var vaultReqs: [(id: String, summary: String?)] = []
        if let regex = vaultReqRegex {
            let ns = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let id = ns.substring(with: match.range(at: 1))
                    let summary: String? = (match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound)
                        ? ns.substring(with: match.range(at: 2))
                        : nil
                    vaultReqs.append((id: id, summary: summary))
                }
                working = (working as NSString).replacingCharacters(in: match.range, with: "")
            }
        }

        var mediaPaths: [String] = []
        var textLines: [String] = []
        for line in working.components(separatedBy: "\n") {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("MEDIA:") {
                let path = String(stripped.dropFirst("MEDIA:".count))
                    .trimmingCharacters(in: .whitespaces)
                if !path.isEmpty {
                    mediaPaths.append(path)
                    continue
                }
            }
            textLines.append(line)
        }

        let cleanText = textLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanText.isEmpty {
            blocks.append(.text(cleanText))
        }
        for id in deliveredIDs.reversed() {
            blocks.append(.deliveredFile(id: id))
        }
        for target in cloudSplit.targets {
            blocks.append(.cloudComputer(target))
        }
        for path in mediaPaths {
            blocks.append(.media(path: path))
        }
        for req in vaultReqs.reversed() {
            blocks.append(.vaultRequest(id: req.id, summary: req.summary))
        }
        return blocks
    }
}
