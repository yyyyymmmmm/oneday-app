import Foundation

// MARK: - GET /api/profiles/{name}/soul（档案人设，需会话）

/// soul 回执文档（0.4.4 三期枢纽页身份段，数据设计
/// phase3-data-design §2）：OpenAPI 对 GET soul 的 200
/// 响应只给了空 schema，真实回执形状未冻结——本类型按
/// 宽容包络解码施工：顶层字符串直作正文；顶层对象按
/// content → soul → text 顺序取正文；日期依次认 ISO8601
/// 字符串、epoch 秒、epoch 毫秒；其余字段原样保留在
/// rawMetadata 供诊断、不上屏。三键皆无判解码失败，
/// 不许拿空正文冒充成功（正文为空字符串是合法状态，
/// 与「字段不存在」严格分开）。
/// 验收状态：宽容解码已按设计施工，真实回执 fixture
/// 未钉死前不得宣称 soul 已接通（见交付回执未冻结项）。
public struct ProfileSoulDocument: Decodable, Sendable, Equatable {
    /// 回执自带的 profile 名（只作一致性校验，不覆盖请求键）
    public let profileName: String?
    /// soul 正文（可为空字符串＝该档案尚无人设内容）
    public let content: String
    /// 更新时间（回执无此字段则 nil，卡面省略日期、不编造）
    public let updatedAt: Date?
    /// 正文键之外的原始字段（诊断用，不上屏）
    public let rawMetadata: [String: JSONValue]

    public init(
        profileName: String?, content: String,
        updatedAt: Date?, rawMetadata: [String: JSONValue]
    ) {
        self.profileName = profileName
        self.content = content
        self.updatedAt = updatedAt
        self.rawMetadata = rawMetadata
    }

    private static let contentKeys = ["content", "soul", "text"]
    private static let dateKeys = ["updated_at", "modified_at", "mtime"]
    private static let nameKeys = ["name", "profile"]

    public init(from decoder: Decoder) throws {
        // 形态一：顶层直接是正文字符串
        if let single = try? decoder.singleValueContainer(),
           let text = try? single.decode(String.self) {
            profileName = nil
            content = text
            updatedAt = nil
            rawMetadata = [:]
            return
        }
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: JSONValue].self)

        var body: String?
        for key in Self.contentKeys {
            if let value = object[key]?.stringValue {
                body = value
                break
            }
        }
        guard let resolvedBody = body else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "soul 回执无正文字段（content/soul/text 皆缺）"
            )
        }
        content = resolvedBody

        var name: String?
        for key in Self.nameKeys {
            if let value = object[key]?.stringValue, !value.isEmpty {
                name = value
                break
            }
        }
        profileName = name

        var date: Date?
        for key in Self.dateKeys {
            if let value = object[key] {
                date = Self.parseDate(value)
                if date != nil { break }
            }
        }
        updatedAt = date

        var metadata = object
        for key in Self.contentKeys { metadata.removeValue(forKey: key) }
        rawMetadata = metadata
    }

    /// 日期候选解析：ISO8601 字符串（普通/带小数秒）或
    /// epoch 数值（量级归一：>1e11 视为毫秒，与
    /// ServerSession 的既有归一口径一致）
    static func parseDate(_ value: JSONValue) -> Date? {
        switch value {
        case .string(let text):
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            return ISO8601DateFormatter().date(from: text)
        case .number(let epoch):
            return Date(
                timeIntervalSince1970: epoch > 1e11 ? epoch / 1000 : epoch
            )
        default:
            return nil
        }
    }
}

// MARK: - soul 正文分段（人设 / 风格）

/// soul 正文的结构映射结果（数据设计 §2.5）：只按标题
/// 结构切分、不做语义猜写。无已知标题时整篇归人设、
/// style 为 nil——禁止按段落数硬切一半冒充风格。
public struct SoulSections: Equatable, Sendable {
    public let persona: String?
    public let style: String?
    public let fullText: String

    public init(persona: String?, style: String?, fullText: String) {
        self.persona = persona
        self.style = style
        self.fullText = fullText
    }

    /// 屏上人设正文：人设区块为空时回落整篇，不显示空白区
    public var displayedPersona: String {
        if let persona, !persona.isEmpty { return persona }
        return fullText
    }
}

public enum SoulSectionParser {
    private static let personaTitles: Set<String> = [
        "人设", "身份", "角色", "自我定位",
        "identity", "persona", "about", "profile", "core identity",
    ]
    private static let styleTitles: Set<String> = [
        "风格", "语气", "表达", "沟通", "语言",
        "style", "tone", "voice", "communication",
    ]

    private enum Bucket {
        case persona, style
    }

    public static func parse(_ content: String) -> SoulSections {
        // 统一换行；连续 3 个以上空行压为 1 个空行
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        var collapsed: [String] = []
        var blankRun = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun > 1 { continue }
            } else {
                blankRun = 0
            }
            collapsed.append(line)
        }
        lines = collapsed

        var personaParts: [String] = []
        var styleParts: [String] = []
        var current: Bucket = .persona
        var sawKnownTitle = false

        for line in lines {
            if let title = headingTitle(line) {
                let key = normalizeTitle(title)
                if personaTitles.contains(key) {
                    current = .persona
                    sawKnownTitle = true
                    continue
                }
                if styleTitles.contains(key) {
                    current = .style
                    sawKnownTitle = true
                    continue
                }
                // 未知标题不丢弃：标题与正文并入当前区块
                append(line, to: current, persona: &personaParts, style: &styleParts)
                continue
            }
            append(line, to: current, persona: &personaParts, style: &styleParts)
        }

        let persona = joined(personaParts)
        let style = joined(styleParts)
        if !sawKnownTitle {
            // 无任何已知标题：整篇作为人设、风格省略
            return SoulSections(
                persona: normalized.trimmingCharacters(in: .whitespacesAndNewlines),
                style: nil,
                fullText: normalized
            )
        }
        return SoulSections(
            persona: persona,
            style: style,
            fullText: normalized
        )
    }

    private static func append(
        _ line: String, to bucket: Bucket,
        persona: inout [String], style: inout [String]
    ) {
        switch bucket {
        case .persona: persona.append(line)
        case .style: style.append(line)
        }
    }

    private static func joined(_ parts: [String]) -> String? {
        let text = parts.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// ATX 标题行（# ～ ######）→ 标题文本；非标题行 nil
    private static func headingTitle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var rest = trimmed
        var hashes = 0
        while rest.hasPrefix("#"), hashes < 6 {
            rest.removeFirst()
            hashes += 1
        }
        guard hashes >= 1, rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// 标题归一化：去首尾空格、去尾部标点、转小写
    private static func normalizeTitle(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: "：:。、．.·—-")
        while let last = text.unicodeScalars.last,
              trailingPunctuation.contains(last) {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
