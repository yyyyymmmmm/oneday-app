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
    // §449.8 定因补键：服务端回执实际用 camelCase
    // updatedAt（epoch 秒、SOUL 文件 mtime 或末写胜
    // 台账时刻——companion identity_bridge 同口径实
    // 证），旧表只有 snake_case 三键、日期恒解不出
    // nil（SOUL 卡日期永不显的真因）；宽容口径不变、
    // 候选键补全 camelCase 两键
    private static let dateKeys = [
        "updated_at", "updatedAt", "modified_at", "modifiedAt", "mtime",
    ]
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
            if let title = headingTitle(of: line) {
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
            // §449.8 平文标题：服务端 SOUL 的实际形态
            // 是无 ATX 的独立标题行（如「风格口径
            // （…）」）＋子弹列——旧解析只认 ATX、整
            // 篇落 persona、风格永不分出（身份段整篇
            // 直倒的定因）。归一键命中已知标题（等值
            // 或前缀）才切桶并消费该行；认不出按正文
            // 行处理（与未知 ATX 同纪律）
            if let key = plainHeadingKey(of: line) {
                if personaTitles.contains(key)
                    || personaTitles.contains(where: { key.hasPrefix($0) }) {
                    current = .persona
                    sawKnownTitle = true
                    continue
                }
                if styleTitles.contains(key)
                    || styleTitles.contains(where: { key.hasPrefix($0) }) {
                    current = .style
                    sawKnownTitle = true
                    continue
                }
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

    /// 平文标题行的归一键（§449.8）：认定从严——
    /// 短行（2–40 字）、无句读（。！？；）、不以子
    /// 弹/标题符起头、不以逗顿结尾；尾部括号注（全
    /// 角/半角）先剥再归一。返回 nil ＝不是标题行。
    /// 正文整句多带句号、天然出局；宁可漏认、不可
    /// 把正文行错当标题吞掉
    static func plainHeadingKey(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.count <= 40 else { return nil }
        guard !trimmed.hasPrefix("-"), !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("•"), !trimmed.hasPrefix("*")
        else { return nil }
        let sentenceMarks: [Character] = ["。", "！", "？", "；"]
        guard !trimmed.contains(where: { sentenceMarks.contains($0) })
        else { return nil }
        guard !trimmed.hasSuffix("，"), !trimmed.hasSuffix("、")
        else { return nil }
        var core = trimmed
        if core.hasSuffix("）"), let open = core.lastIndex(of: "（") {
            core = String(core[..<open])
        } else if core.hasSuffix(")"), let open = core.lastIndex(of: "(") {
            core = String(core[..<open])
        }
        let key = normalizeTitle(core)
        return key.isEmpty ? nil : key
    }

    /// ATX 标题行（# ～ ######）→ 标题文本；非标题行 nil。
    /// §218 起呈现提炼器共用同一口径，故开放（internal
    /// 以上）——标题认定全仓一处，不许各写一份。
    public static func headingTitle(of line: String) -> String? {
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

    /// 标题归一化：去首尾空格、去尾部标点、转小写。
    /// §253 起呈现提炼层（SoulDistillation）共用同一
    /// 口径，故开放为 internal——标题归一全仓一处。
    static func normalizeTitle(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: "：:。、．.·—-")
        while let last = text.unicodeScalars.last,
              trailingPunctuation.contains(last) {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

// MARK: - soul 保存回读比对（§155 HUB-1，规格 §2.7 环 4）

/// 保存后的确认口径：提交内容与保存后重新取回的内容，
/// 去掉首尾空白后逐字相等，才算确认存好。规范化只动
/// 首尾空白（含换行），正文内部一字不让——服务端若动
/// 了正文内部（改字、重排），比对必不等、按未确认处
/// 理，不许放宽成「差不多」就报成功。
public enum SoulSaveVerification {
    public static func isConfirmed(submitted: String, fetched: String) -> Bool {
        normalized(submitted) == normalized(fetched)
    }

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - soul 屏上呈现提炼（§218 枢纽身份段视觉重做）

/// 身份段屏上呈现：把解析后的分段清成可读散文段落。
/// 提炼分两层：结构层（§218）按空行分段、剥 ATX 标
/// 题的 `#` 脚手架、摘除与显示名同文的名标题段；真
/// 提炼层（§253）把系统提示词段整段收起——身份段只
/// 呈人设本体（SoulDistillation 按标题结构分段裁
/// 决，只认结构、不做语义猜写，与 SoulSectionParser
/// 同纪律）。正文一字不改写、不翻译、不增删；原始
/// 全文的入口仍在 SOUL 卡详情与编辑面，本提炼只管
/// 身份段呈现。
public struct SoulPresentation: Equatable, Sendable {
    /// 人设散文段落（简介区，灰字呈现）
    public let introParagraphs: [String]
    /// 风格段落（风格区，黑字呈现；无风格块时为空）
    public let styleParagraphs: [String]
    /// 本次被真提炼层收起的系统提示词段数（呈现层可
    /// 据此给出去处注记；全文在 SOUL 卡与编辑面）
    public let withheldSegmentCount: Int

    public init(
        introParagraphs: [String], styleParagraphs: [String],
        withheldSegmentCount: Int = 0
    ) {
        self.introParagraphs = introParagraphs
        self.styleParagraphs = styleParagraphs
        self.withheldSegmentCount = withheldSegmentCount
    }

    public var isEmpty: Bool {
        introParagraphs.isEmpty && styleParagraphs.isEmpty
    }
}

public enum SoulPresentationBuilder {
    public static func build(
        from sections: SoulSections, displayName: String
    ) -> SoulPresentation {
        // 真提炼层（§253）：人设正文先过系统段收起，
        // 只把人设本体交给结构层分段呈现；风格块是
        // 呈现本体、不在收起面
        let distilled = SoulDistillation.visibleText(
            from: sections.displayedPersona
        )
        let allIntro = paragraphs(
            from: distilled.text,
            displayName: displayName, dropNameHeading: true
        )
        let style = paragraphs(
            from: sections.style ?? "",
            displayName: displayName, dropNameHeading: false
        )
        // §477 摘要化（2026-11-24 全抄参照身份页）：
        // 简介区只呈摘要级——身份首段＋气质摘要（合
        // 计约 5–6 行封顶的呈现量），人设其余段落撤
        // 出本页：全文仍在 SOUL 卡详情与编辑面（读
        // soulDocument.content 原文、零丢失），本页
        // 只管摘要呈现、与参照同构（参照灰字摘要同
        // 样只是其人设首段＋气质）。提炼层（SoulDis-
        // tillation）口径不动：收起裁决仍在那一层，
        // 本处只收呈现量
        // §477 内部注记过滤（P3-2 防复发口径）：协
        // 作对齐注记（如「（与主线三狗共用一份，
        // 2026-11-24 对齐）」）是内部标记、不上呈
        // 现面——先在提炼出口统一剥离（摘要与风格
        // 两区同过，只剥括号注记组本身、正文一字不
        // 动），再取首段作摘要，防首段恰为纯注记时
        // 摘要落空
        let cleanIntro = allIntro
            .map(strippingInternalNotes)
            .filter { !$0.isEmpty }
        let cleanStyle = style
            .map(strippingInternalNotes)
            .filter { !$0.isEmpty }
        // 摘要首段＝首个正文段：独占一段的纯标题行
        // （文档名/节题，如「# SOUL.md」孤行、节题孤
        // 行）是结构脚手架、不是身份内容，跳过不取
        // （与名标题摘除同理）；标题与正文同段时整段
        // 照取（一字不动）
        let atxTitles = Set(
            distilled.text.components(separatedBy: "\n")
                .compactMap {
                    SoulSectionParser.headingTitle(of: $0)
                }
        )
        var intro: [String] = []
        if let first = cleanIntro.first(where: {
            !isHeadingOnly($0, atxTitles: atxTitles)
        }) {
            intro = [first]
        }
        // §449.8 气质摘要（对 Muse 呈现结构）：风
        // 格块中带「气质／Vibe」标签的条目，其内容
        // 提作简介区末段灰字摘要——Muse 的灰字摘
        // 要与其「风格」节同文同源，此处同法；风格
        // 块内原文保留不动、只多呈一处摘要，无此
        // 标签不强凑
        if let temperament = temperamentSummary(in: cleanStyle),
           !intro.contains(temperament) {
            intro.append(temperament)
        }
        return SoulPresentation(
            introParagraphs: intro,
            styleParagraphs: cleanStyle,
            withheldSegmentCount: distilled.withheldCount
        )
    }

    /// 纯标题段判定（§477）：整段只有一行、且该行是
    /// ATX 节题（在提炼文本里以标题行出现过）或平文
    /// 节题（plainHeadingKey 命中）——只认结构、不
    /// 猜语义（与本文件提炼纪律同款）
    static func isHeadingOnly(
        _ paragraph: String, atxTitles: Set<String>
    ) -> Bool {
        guard !paragraph.contains("\n") else { return false }
        let line = paragraph.trimmingCharacters(in: .whitespaces)
        if atxTitles.contains(line) { return true }
        return SoulSectionParser.plainHeadingKey(of: line) != nil
    }

    /// 内部注记剥离（§477）：括号组（全角／半角）内
    /// 容命中任一标记即整组剥除——含 ISO 日期
    /// （yyyy-MM-dd）、或「共用一份」字样。这类注记
    /// 是写作时的协作对齐标记（写进 SOUL 标题/正文
    /// 的括号注），不是人设内容；判定只认括号组＋
    /// 标记两条件，不做语义猜写（与本文件提炼纪律
    /// 同款）。剥后折叠多余空白；整段只剩注记时返
    /// 回空串、由调用方弃段
    static func strippingInternalNotes(_ paragraph: String) -> String {
        let pattern = "（[^（）]*）|\\([^()]*\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { return paragraph }
        let range = NSRange(
            paragraph.startIndex..., in: paragraph
        )
        var result = paragraph
        // 自后向前替换，避免 range 漂移
        let matches = regex.matches(in: paragraph, range: range)
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result)
            else { continue }
            let inner = String(result[matchRange])
            let hasDate = inner.range(
                of: "\\d{4}-\\d{2}-\\d{2}",
                options: .regularExpression
            ) != nil
            if hasDate || inner.contains("共用一份") {
                result.removeSubrange(matchRange)
            }
        }
        return result
            .split(whereSeparator: { $0 == " " || $0 == "　" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 子弹行 → 条目文本（剥 `- `/`• ` 标记）；非子
    /// 弹行返回 nil（§449.8）
    static func bulletText(of trimmedLine: String) -> String? {
        for marker in ["- ", "• "] {
            if trimmedLine.hasPrefix(marker) {
                let text = trimmedLine.dropFirst(marker.count)
                    .trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : text
            }
        }
        return nil
    }

    /// 行组中 index 之后的第一个非空行（修剪形）
    static func nextNonEmptyLine(
        in lines: [String], after index: Int
    ) -> String? {
        guard index + 1 < lines.count else { return nil }
        for line in lines[(index + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// 风格段落中「气质：…／Vibe: …」标签条的内容
    /// （§449.8 气质摘要的来源；无此条返回 nil）
    static func temperamentSummary(in styleParagraphs: [String]) -> String? {
        for paragraph in styleParagraphs {
            for label in ["气质", "Vibe", "vibe"] {
                for separator in ["：", ":"] {
                    if paragraph.hasPrefix(label + separator) {
                        let rest = paragraph
                            .dropFirst(label.count + separator.count)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !rest.isEmpty { return rest }
                    }
                }
            }
        }
        return nil
    }

    /// 一段文本 → 呈现段落：空行分段；段内 ATX 标题行
    /// 剥 `#` 只留标题文本；首段若是纯标题且与显示名
    /// 同文则整段摘除（仅人设区、dropNameHeading 时）
    static func paragraphs(
        from text: String, displayName: String, dropNameHeading: Bool
    ) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var blocks: [[String]] = []
        var current: [String] = []
        let allLines = normalized.components(separatedBy: "\n")
        for (index, line) in allLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
                continue
            }
            // §449.8 子弹成段：子弹行自成一段（剥
            // `- `/`• ` 标记），续行（无标记）并入本
            // 条——服务端 SOUL 的子弹列由此成散文流
            // （对 Muse 呈现），不再带标记直倒
            if let bullet = bulletText(of: trimmed) {
                if !current.isEmpty {
                    blocks.append(current)
                }
                current = [bullet]
                continue
            }
            // §449.8 未知平文标题（其后紧跟子弹时）自
            // 成一段作节题呈现，不与子弹粘连；ATX 行
            // 维持旧口径（段内剥 #、与正文同段）
            if SoulSectionParser.plainHeadingKey(of: line) != nil,
               let next = nextNonEmptyLine(in: allLines, after: index),
               bulletText(of: next) != nil {
                if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
                blocks.append([line])
                continue
            }
            current.append(line)
        }
        if !current.isEmpty { blocks.append(current) }

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        for (index, rawBlock) in blocks.enumerated() {
            var block = rawBlock
            // 名标题摘除：首段首行若是与显示名同文的标题
            // 行，整行摘掉（名已在段头大字呈现）；它若独
            // 占一段，摘后整段为空、自然消失。与正文同
            // 段时只摘这一行、正文一字不动
            if dropNameHeading, index == 0, !name.isEmpty,
               let first = block.first,
               SoulSectionParser.headingTitle(of: first) == name {
                block.removeFirst()
                if block.isEmpty { continue }
            }
            // 段内逐行剥标题脚手架：标题行只留标题文本
            let cleanedLines = block.map { line -> String in
                SoulSectionParser.headingTitle(of: line) ?? line
            }
            let cleaned = cleanedLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty { continue }
            result.append(cleaned)
        }
        return result
    }
}

// MARK: - soul 真提炼层（§253 身份段：系统提示词段收起）

/// 真提炼层（2026-11-14 立项，.48 身份包）：SOUL 里
/// 混着两类段——人设本体（它是谁、与用户是什么关
/// 系、还不知道什么）与系统提示词段（怎么工作、守
/// 则、伤疤教训、安全边界这类给智能体自己的操作规
/// 程）。身份段是给人看的「它是谁」，只呈人设本体；
/// 系统段整段收起，原文一字不动地留在 SOUL 卡详情
/// 与编辑面（「原文进编辑」）。
///
/// 裁决只认结构（与 SoulSectionParser 同纪律，不做
/// 语义猜写）：按 ATX 标题切段，标题归一后命中系统
/// 段标题表即收起；无标题的前言段与未登记标题段一
/// 律保留（宁可多呈、不可错藏人设本体）。兜底：收
/// 起后正文为空（整篇都是系统段）时整篇回落原文呈
/// 现——身份段不许被提炼成空白。
public enum SoulDistillation {
    public struct Result: Equatable, Sendable {
        /// 可见正文（人设本体，段落原文）
        public let text: String
        /// 被收起的系统段数
        public let withheldCount: Int

        public init(text: String, withheldCount: Int) {
            self.text = text
            self.withheldCount = withheldCount
        }
    }

    /// 系统提示词段标题表（归一形：小写、去尾标点，
    /// 与 SoulSectionParser.normalizeTitle 同口径）。
    /// 来源：现行 SOUL 的规程性章节（我怎么工作/学
    /// 到的伤疤）、Hermes 缺省 SOUL 模板的指令性章
    /// 节（Boundaries/Continuity）与通用规程词。只
    /// 收「给智能体的操作规程」类；Core Truths/Vibe
    /// 这类本体自述不在表内（风格另有风格块承接）。
    static let systemTitles: Set<String> = [
        // 中文：工作与规则
        "我怎么工作", "怎么工作", "工作方式", "工作守则",
        "行为准则", "行为规则", "工作原则", "判断步骤",
        "操作规程", "运行规则", "学习循环", "房间规则",
        "记忆规则", "安全守则", "安全", "红线", "边界",
        "工具", "工具使用", "指令", "系统提示词",
        "注意事项", "约束",
        // 中文：教训类（以规则形态沉淀的操作经验）
        "我学到的伤疤", "学到的伤疤", "教训", "经验教训",
        // English: working rules & instructions
        "how i work", "how you work", "working rules",
        "guidelines", "rules", "instructions",
        "operating principles", "safety", "safety rules",
        "boundaries", "red lines", "tools", "tool usage",
        "memory rules", "continuity", "workflow",
        "operations", "system prompt", "lessons",
        "lessons learned",
    ]

    public static func visibleText(from personaText: String) -> Result {
        let normalized = personaText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // 按标题切段：标题行起新段；首个标题前的行是
        // 前言段（无标题、恒可见）
        var segments: [(title: String?, lines: [String])] = []
        var currentTitle: String? = nil
        var currentLines: [String] = []
        var started = false
        for line in normalized.components(separatedBy: "\n") {
            if let title = SoulSectionParser.headingTitle(of: line) {
                if started || !currentLines.isEmpty {
                    segments.append((currentTitle, currentLines))
                }
                started = true
                currentTitle = title
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }
        if started || !currentLines.isEmpty {
            segments.append((currentTitle, currentLines))
        }

        var visible: [String] = []
        var withheld = 0
        for segment in segments {
            if let title = segment.title,
               systemTitles.contains(
                   SoulSectionParser.normalizeTitle(title)
               ) {
                withheld += 1
                continue
            }
            visible.append(contentsOf: segment.lines)
        }
        let text = visible.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 兜底：全篇皆系统段时回落原文，身份段不空白
        if text.isEmpty {
            return Result(
                text: normalized.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                withheldCount: 0
            )
        }
        return Result(text: text, withheldCount: withheld)
    }
}
