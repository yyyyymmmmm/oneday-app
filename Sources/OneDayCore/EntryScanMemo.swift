import Foundation

/// 助手气泡派生扫描的打包产出（§199）：一次全文扫
/// 描链的全部派生物——交付标记拆分、凭据请求标记拆分、MEDIA 拆分、
/// 裸路径内联图候选、独立成行路径集。原消费方
/// （ChatView 气泡 body）逐项取用，与旧逐遍现算的
/// 五个调用点一一对应、语义逐字不变
public struct AssistantTextScans: Equatable, Sendable {
    public let delivery: DeliveryMarkerSplit
    public let vaultRequest: VaultRequestMarkerSplit
    public let cloudComputer: CloudComputerMarkerSplit
    public let media: MediaMarkerSplit
    public let inlineCandidates: [FileRefDetector.InlineImageRef]
    /// detectStandaloneAnchored 的路径集（出现序去
    /// 重；旧消费方取 Set，此处保序不影响其语义）
    public let standalonePaths: [String]

    public init(
        delivery: DeliveryMarkerSplit,
        vaultRequest: VaultRequestMarkerSplit,
        cloudComputer: CloudComputerMarkerSplit = CloudComputerMarkerSplit(text: "", targets: []),
        media: MediaMarkerSplit,
        inlineCandidates: [FileRefDetector.InlineImageRef],
        standalonePaths: [String]
    ) {
        self.delivery = delivery
        self.vaultRequest = vaultRequest
        self.cloudComputer = cloudComputer
        self.media = media
        self.inlineCandidates = inlineCandidates
        self.standalonePaths = standalonePaths
    }
}

/// §199（2026-11-13）条目级派生扫描记忆盒
///
/// 出处与定因：一层审计（chat-page-bigfactory-
/// audit-20261113.md §2.2）——助手气泡每遍 body 对
/// 正文裸奔五组全文扫描（DeliveryMarker.split、
/// MediaMarker.split、FileRefDetector.inlineImage-
/// Candidates／detectStandaloneAnchored／stripping-
/// StandaloneLines），无任何按条目缓存；滚动逐帧
/// 全页重跑时按帧计费，是滑动卡的主体成本。对照
/// 组 MarkdownParser／InlineRunBuilder 早有 Core 级
/// 备忘（§167），唯独这组派生扫描裸奔，本盒补齐。
///
/// 纪律：
/// - 键＝条目 id × 内容哈希（FNV-1a 64 位＋字节数
///   双因子），内容不变恒命中、内容一变（流式增
///   长/编辑）自动失效，不设显式失效路；
/// - 五组扫描全是纯函数（同入参恒同出参），记忆
///   化不改变任何输出；stripping 的入参除正文外
///   还有「摘行集」——它由 App 层存在性判定派生
///   （会随后到元数据翻转），故摘行结果单独一盒、
///   键里并入摘行集签名，存在性一变即重算，语义
///   与旧逐遍现算恒等；
/// - plainText（长按菜单文本口径）同属每遍现算的
///   全文派生（施工图包 1 ②并列），同盒治理；
/// - 计数（命中/未命中）即验收代理指标，与
///   MarkdownParseMetrics 同口径：同内容第二遍起
///   未命中不增长（EntryScanMemoTests 断言）。
public enum EntryScanMemo {
    private static let scansBox =
        ParseMemoBox<AssistantTextScans>(capacity: 256)
    private static let strippedBox =
        ParseMemoBox<String>(capacity: 256)
    private static let plainBox =
        ParseMemoBox<String>(capacity: 256)
    private static let facetBox =
        ParseMemoBox<[String]>(capacity: 256)

    /// 五组扫描中的四组打包（摘行一组入参含 App
    /// 层存在性派生量，走 displayText 单独一盒）
    public static func scans(
        entryID: UUID,
        content: String,
        remoteImagePaths: [String]
    ) -> AssistantTextScans {
        let key = "scan|\(entryID.uuidString)"
            + "|\(content.count)|\(contentHash(content))"
            + "|\(contentHash(remoteImagePaths.joined(separator: "\u{1}")))"
        return scansBox.value(for: key) {
            let delivery = DeliveryMarker.split(in: content)
            let vaultRequest = VaultRequestMarker.split(in: delivery.text)
            let cloudComputer = CloudComputerMarker.split(in: vaultRequest.text)
            let media = MediaMarker.split(in: cloudComputer.text)
            let inline = FileRefDetector.inlineImageCandidates(
                in: media.text,
                excluding: remoteImagePaths + media.imagePaths
            )
            var seen = Set<String>()
            var standalone: [String] = []
            for ref in FileRefDetector.detectStandaloneAnchored(
                in: media.text
            ) where seen.insert(ref.path).inserted {
                standalone.append(ref.path)
            }
            return AssistantTextScans(
                delivery: delivery,
                vaultRequest: vaultRequest,
                cloudComputer: cloudComputer,
                media: media,
                inlineCandidates: inline,
                standalonePaths: standalone
            )
        }
    }

    /// 摘行（第五组扫描）：正文＝MEDIA 拆分后的文
    /// 本，摘行集由消费方按存在性确证派生——签名
    /// 入键，集合一变即失效重算
    public static func displayText(
        entryID: UUID,
        mediaText: String,
        stripPaths: Set<String>
    ) -> String {
        let signature = contentHash(
            stripPaths.sorted().joined(separator: "\u{1}")
        )
        let key = "strip|\(entryID.uuidString)"
            + "|\(mediaText.count)|\(contentHash(mediaText))"
            + "|\(signature)"
        return strippedBox.value(for: key) {
            FileRefDetector.strippingStandaloneLines(
                in: mediaText, paths: stripPaths
            )
        }
    }

    /// 长按菜单的纯文本口径（助手消息剥 Markdown）
    public static func plainText(
        entryID: UUID, content: String
    ) -> String {
        let key = "plain|\(entryID.uuidString)"
            + "|\(content.count)|\(contentHash(content))"
        return plainBox.value(for: key) {
            MessagePlainText.make(from: content)
        }
    }

    /// facet 路径集（§333，待办 143 根治）：整行
    /// 备忘键的 facet 摘要（App 层 ChatNativeRow-
    /// Height.entryFacetDigest）需要的助手行文件
    /// 路径全集——MEDIA 图＋行内候选＋独立成行＋
    /// 整条消息路径＋组合排除口径锚定探测五源并
    /// 集。此前消费方在每趟行键组装时对正文现算
    /// 后两源（wholeMessagePath 与组合排除口径的
    /// detectStandaloneAnchored 不在 scans 的备
    /// 忘口径内），长会话每趟 body 求值全表重扫，
    /// 是量测台（§331）落成后滚动热路径上残余的
    /// 主线程同步全扫。本盒把并集本身收进条目级
    /// 备忘：键与 scans 同式（条目 id×内容哈希×
    /// 远端图集哈希），内容不变恒命中、第二趟起
    /// 零重扫；产出与逐遍现算逐字相等（EntryScan-
    /// MemoTests 对拍钉住）
    public static func facetPaths(
        entryID: UUID,
        content: String,
        remoteImagePaths: [String]
    ) -> [String] {
        let key = "facet|\(entryID.uuidString)"
            + "|\(content.count)|\(contentHash(content))"
            + "|\(contentHash(remoteImagePaths.joined(separator: "\u{1}")))"
        return facetBox.value(for: key) {
            let scans = scans(
                entryID: entryID, content: content,
                remoteImagePaths: remoteImagePaths
            )
            var paths = Set<String>()
            paths.formUnion(scans.media.imagePaths)
            paths.formUnion(
                scans.inlineCandidates.map(\.path)
            )
            paths.formUnion(scans.standalonePaths)
            let wholePathRef = FileRefDetector
                .wholeMessagePath(in: scans.media.text)
            if let wholePathRef {
                paths.insert(wholePathRef.path)
            }
            let fileRefs = FileRefDetector
                .detectStandaloneAnchored(
                    in: content,
                    excluding: remoteImagePaths
                        + scans.media.imagePaths
                        + scans.inlineCandidates
                            .map(\.path)
                        + (wholePathRef.map { [$0.path] }
                            ?? [])
                )
            paths.formUnion(fileRefs.map(\.path))
            return paths.sorted()
        }
    }

    // MARK: - 验收读面（与 MarkdownParseMetrics 同口径）

    public struct Metrics: Equatable {
        public var scanHits: Int
        public var scanMisses: Int
        public var stripHits: Int
        public var stripMisses: Int
        public var plainHits: Int
        public var plainMisses: Int
        public var facetHits: Int
        public var facetMisses: Int
    }

    public static func metrics() -> Metrics {
        let scans = scansBox.metrics()
        let strip = strippedBox.metrics()
        let plain = plainBox.metrics()
        let facet = facetBox.metrics()
        return Metrics(
            scanHits: scans.hits, scanMisses: scans.misses,
            stripHits: strip.hits, stripMisses: strip.misses,
            plainHits: plain.hits, plainMisses: plain.misses,
            facetHits: facet.hits, facetMisses: facet.misses
        )
    }

    public static func resetMetrics() {
        scansBox.resetMetrics()
        strippedBox.resetMetrics()
        plainBox.resetMetrics()
        facetBox.resetMetrics()
    }

    public static func removeAll() {
        scansBox.removeAll()
        strippedBox.removeAll()
        plainBox.removeAll()
        facetBox.removeAll()
    }

    /// FNV-1a 64 位（确定性、无随机种子）：只作缓
    /// 存键因子——与条目 id、字节数三重合围，碰撞
    /// 需同条目同长度同哈希三重巧合，不作任何安
    /// 全/正确性判定用途
    private static func contentHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}

// MARK: - 标准结构化消息块协议（移植自 refactor/standard-architecture Phase 3.2）

/// 结构化消息块：将正文、文件交付卡、凭据请求卡、云电脑实时卡、内联图片与独立文件引用
/// 统一表达为类型安全的 JSON Block 数组，双轨向后兼容老文本标记，供 iOS 与 macOS 双端共用。
public enum MessageContentBlock: Equatable, Sendable, Codable {
    case text(String)
    case delivery(id: String)
    case vaultRequest(id: String)
    case cloudComputer(CloudComputerTarget)
    case mediaImage(path: String)
    case fileRef(path: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, cloudComputer, path
    }

    private enum BlockType: String, Codable {
        case text
        case delivery
        case vaultRequest = "vault_request"
        case cloudComputer = "cloud_computer"
        case mediaImage = "media_image"
        case fileRef = "file_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BlockType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .delivery:
            self = .delivery(id: try container.decode(String.self, forKey: .id))
        case .vaultRequest:
            self = .vaultRequest(id: try container.decode(String.self, forKey: .id))
        case .cloudComputer:
            self = .cloudComputer(try container.decode(CloudComputerTarget.self, forKey: .cloudComputer))
        case .mediaImage:
            self = .mediaImage(path: try container.decode(String.self, forKey: .path))
        case .fileRef:
            self = .fileRef(path: try container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(BlockType.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .delivery(let id):
            try container.encode(BlockType.delivery, forKey: .type)
            try container.encode(id, forKey: .id)
        case .vaultRequest(let id):
            try container.encode(BlockType.vaultRequest, forKey: .type)
            try container.encode(id, forKey: .id)
        case .cloudComputer(let target):
            try container.encode(BlockType.cloudComputer, forKey: .type)
            try container.encode(target, forKey: .cloudComputer)
        case .mediaImage(let path):
            try container.encode(BlockType.mediaImage, forKey: .type)
            try container.encode(path, forKey: .path)
        case .fileRef(let path):
            try container.encode(BlockType.fileRef, forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }
}

public struct MessageContentEnvelope: Equatable, Sendable, Codable {
    public let v: Int
    public let blocks: [MessageContentBlock]

    public init(v: Int = 1, blocks: [MessageContentBlock]) {
        self.v = v
        self.blocks = blocks
    }
}

public enum MessageBlockCodec {
    private static let envelopePrefix = "{\"v\":1,\"blocks\":"

    /// 双轨解码：优先识别结构化 JSON Envelope，否则兼容降级走 EntryScanMemo 解析老文本标记。
    public static func decode(
        entryID: UUID,
        content: String,
        remoteImagePaths: [String] = []
    ) -> [MessageContentBlock] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(envelopePrefix),
           let data = trimmed.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(MessageContentEnvelope.self, from: data) {
            return envelope.blocks
        }
        let scans = EntryScanMemo.scans(
            entryID: entryID,
            content: content,
            remoteImagePaths: remoteImagePaths
        )
        var blocks: [MessageContentBlock] = []
        if !scans.media.text.isEmpty {
            blocks.append(.text(scans.media.text))
        }
        for id in scans.delivery.deliveryIDs {
            blocks.append(.delivery(id: id))
        }
        for id in scans.vaultRequest.requestIDs {
            blocks.append(.vaultRequest(id: id))
        }
        for target in scans.cloudComputer.targets {
            blocks.append(.cloudComputer(target))
        }
        for path in scans.media.imagePaths {
            blocks.append(.mediaImage(path: path))
        }
        for path in scans.standalonePaths {
            blocks.append(.fileRef(path: path))
        }
        return blocks
    }

    /// 编码为标准结构化 JSON Envelope（供新消息写入与测试使用）。
    public static func encode(_ blocks: [MessageContentBlock]) -> String? {
        let envelope = MessageContentEnvelope(v: 1, blocks: blocks)
        guard let data = try? JSONEncoder().encode(envelope) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
