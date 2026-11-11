import CoreFoundation
import Foundation

/// 待发文件接入预检（0.36.31 件三，诊断 file-picker-
/// batch-diagnosis-20261111 次节口径）：文件入条前
/// 的纯判定与文案拼装——先查大小（fileSize）再读数
/// 据，超限不整份读入；被拒文件汇总点名，不再逐个
/// 写 notice 互相覆盖、只剩最后一个名。网络与文件
/// 读取动作在 App 层，本枚举只管判定与拼装。
public enum FileIntake {
    /// App 侧单文件大小闸（字节）：与服务端托管上
    /// 传契约对齐（file-upload-contract-20261111：
    /// POST /api/files/upload 解码后上限 100 MiB）；
    /// 0.36.29 前为 20MB，选大文件（安装包级）必撞
    /// 闸、且旧链先整份读入才判，本轮改预检＋对齐
    public static let maxFileBytes = 100 * 1024 * 1024

    /// 大小预检判定：App 层先以 resourceValues 取
    /// fileSize 问本函数，`.tooLarge` 直接拒收免读；
    /// `.unknownSize`（取不到大小）放行读入、读后以
    /// `isOversized` 对实字节二次判，不许因查不到
    /// 大小就拒人
    public enum SizeVerdict: Equatable, Sendable {
        case acceptable
        case tooLarge
        case unknownSize
    }

    public static func sizeVerdict(declaredSize: Int?) -> SizeVerdict {
        guard let declaredSize else { return .unknownSize }
        return declaredSize > maxFileBytes ? .tooLarge : .acceptable
    }

    /// 实读字节的超限判（预检 `.unknownSize` 的兜底
    /// 二次判，与预检同闸值）
    public static func isOversized(byteCount: Int) -> Bool {
        byteCount > maxFileBytes
    }

    // MARK: - 文本编码转码（0.46.1 扩围 C）

    /// 文本类扩展名集：与网关按文本内联的口径对齐
    /// （context_references 的 _TEXT_EXTENSIONS＋常
    /// 见文本格式）——只有这些扩展名才谈编码转换，
    /// 二进制格式（zip/docx/图片）一律不碰
    public static let textExtensions: Set<String> = [
        "txt", "md", "csv", "json", "xml", "html", "htm",
        "log", "py", "js", "ts", "tsx", "jsx", "swift",
        "mq5", "mqh", "yaml", "yml", "toml", "ini",
        "cfg", "conf", "sh",
    ]

    /// 转码结局：unchanged＝非文本类或已是合法 UTF-8
    /// （原样）；transcoded＝GB18030 族旧编码已转成
    /// UTF-8；undecodable＝文本类但 GB18030 也解不开
    /// （原样上传、调用方提示可能读不了）
    public enum TranscodeOutcome: Equatable, Sendable {
        case unchanged
        case transcoded
        case undecodable
    }

    public struct TranscodeResult: Equatable, Sendable {
        public let data: Data
        public let outcome: TranscodeOutcome

        public init(data: Data, outcome: TranscodeOutcome) {
            self.data = data
            self.outcome = outcome
        }
    }

    /// 发送前编码归一（纯函数）：网关对文本文件按
    /// UTF-8 硬读（read_text(utf-8-sig)），GBK 族编
    /// 码的 .txt/.md/.csv 在服务端直接解码失败、只
    /// 剩一条警告、智能体读不到全文（静默断点）。
    /// 入口先转：文本扩展名＋字节非合法 UTF-8 →
    /// GB18030 解码后重编码 UTF-8（GB18030 覆盖
    /// GBK/GB2312 全部码位）；解出的文本含 NUL 视
    /// 为二进制垃圾、按解不开处理。手机上的原文件
    /// 不动，只改上传的这份字节
    public static func transcodedForUpload(
        fileName: String, data: Data
    ) -> TranscodeResult {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard textExtensions.contains(ext), !data.isEmpty else {
            return TranscodeResult(data: data, outcome: .unchanged)
        }
        if String(data: data, encoding: .utf8) != nil {
            return TranscodeResult(data: data, outcome: .unchanged)
        }
        // kCFStringEncodingGB_18030_2000 的常量名在
        // Swift 桥接里不可见（CI 实证），用其文档原
        // 始值 0x0630 直接构造 CFStringEncoding
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(0x0630)
            )
        )
        guard let decoded = String(data: data, encoding: gb18030),
              !decoded.contains("\0"),
              let reencoded = decoded.data(using: .utf8)
        else {
            return TranscodeResult(data: data, outcome: .undecodable)
        }
        return TranscodeResult(data: reencoded, outcome: .transcoded)
    }

    /// 转码提示汇总（与 rejectionNotice 同风格：点名
    /// ＋人话；两类皆空返回 nil）。文案走三语目录
    /// （宪法 §8），源串即键、经 L10n 取词
    public static func transcodeNotice(
        transcoded: [String], undecodable: [String]
    ) -> String? {
        var sentences: [String] = []
        if !transcoded.isEmpty {
            sentences.append(
                L10n.format(
                    "%@原本是 GBK 等旧编码，已转成 UTF-8 再发送。",
                    namedList(transcoded)
                )
            )
        }
        if !undecodable.isEmpty {
            sentences.append(
                L10n.format(
                    "%@不是 UTF-8 编码、转换失败，仍按原样加入待发列表，服务器可能读不了。",
                    namedList(undecodable)
                )
            )
        }
        guard !sentences.isEmpty else { return nil }
        return sentences.joined()
    }

    /// 被拒文件汇总点名：超限与读失败各成一句、都有
    /// 才并列；名单 1 个直名、2 个并列、3 个以上取
    /// 前两名＋「等 N 个文件」，不让用户对着一个名
    /// 子猜其余下落（对图片路计数汇总口径的补全：
    /// 文件路逐个点名更有用、但必须全员有账）。
    /// 两类皆空返回 nil（调用方不写 notice）
    public static func rejectionNotice(
        oversized: [String], unreadable: [String]
    ) -> String? {
        var sentences: [String] = []
        if !oversized.isEmpty {
            sentences.append(
                "\(namedList(oversized))超过 100MB，未加入待发列表。"
            )
        }
        if unreadable.count == 1 {
            sentences.append(
                "读取「\(unreadable[0])」失败，未加入待发列表。"
            )
        } else if !unreadable.isEmpty {
            sentences.append(
                "\(namedList(unreadable))没能读取，未加入待发列表。"
            )
        }
        guard !sentences.isEmpty else { return nil }
        return sentences.joined()
    }

    /// 名单拼装（「」逐名）：1 个直名、2 个并列、
    /// 3+ 取前两名＋总数收尾
    private static func namedList(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return ""
        case 1:
            return "「\(names[0])」"
        case 2:
            return "「\(names[0])」、「\(names[1])」"
        default:
            return "「\(names[0])」、「\(names[1])」等 \(names.count) 个文件"
        }
    }
}
