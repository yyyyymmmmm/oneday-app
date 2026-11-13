import Foundation

/// 助手气泡派生扫描的打包产出（§199）：一次全文扫
/// 描链的全部派生物——交付标记拆分、MEDIA 拆分、
/// 裸路径内联图候选、独立成行路径集。原消费方
/// （ChatView 气泡 body）逐项取用，与旧逐遍现算的
/// 五个调用点一一对应、语义逐字不变
public struct AssistantTextScans: Equatable, Sendable {
    public let delivery: DeliveryMarkerSplit
    public let media: MediaMarkerSplit
    public let inlineCandidates: [FileRefDetector.InlineImageRef]
    /// detectStandaloneAnchored 的路径集（出现序去
    /// 重；旧消费方取 Set，此处保序不影响其语义）
    public let standalonePaths: [String]

    public init(
        delivery: DeliveryMarkerSplit,
        media: MediaMarkerSplit,
        inlineCandidates: [FileRefDetector.InlineImageRef],
        standalonePaths: [String]
    ) {
        self.delivery = delivery
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
            let media = MediaMarker.split(in: delivery.text)
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

    // MARK: - 验收读面（与 MarkdownParseMetrics 同口径）

    public struct Metrics: Equatable {
        public var scanHits: Int
        public var scanMisses: Int
        public var stripHits: Int
        public var stripMisses: Int
        public var plainHits: Int
        public var plainMisses: Int
    }

    public static func metrics() -> Metrics {
        let scans = scansBox.metrics()
        let strip = strippedBox.metrics()
        let plain = plainBox.metrics()
        return Metrics(
            scanHits: scans.hits, scanMisses: scans.misses,
            stripHits: strip.hits, stripMisses: strip.misses,
            plainHits: plain.hits, plainMisses: plain.misses
        )
    }

    public static func resetMetrics() {
        scansBox.resetMetrics()
        strippedBox.resetMetrics()
        plainBox.resetMetrics()
    }

    public static func removeAll() {
        scansBox.removeAll()
        strippedBox.removeAll()
        plainBox.removeAll()
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
