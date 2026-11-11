import Foundation

/// MEDIA: 图片标记的拆分产出（§133）：正文（摘除
/// 标记行后）＋图片路径（出现序、去重）
public struct MediaMarkerSplit: Equatable, Sendable {
    public let text: String
    public let imagePaths: [String]

    public init(text: String, imagePaths: [String]) {
        self.text = text
        self.imagePaths = imagePaths
    }
}

/// 助手正文里的 `MEDIA:<路径>` 标记（§133，用户
/// 2026-11-11 16:18 真机报障）：Hermes 的媒体投递
/// 协议——智能体把产出图片以独立一行 `MEDIA:/…`
/// 写进回复，渠道层本应转成附件下发；OneDay 的
/// API 通道无人转，标记原文漏进气泡，用户只看到
/// 一行路径、图没出来（实证：云电脑截图
/// /opt/data/cache/images/img_….webp）。
/// 本解析是呈现层的收口（与 §129 成牌口同层）：
/// 独立成行的图片标记从正文摘除、路径交 App 层
/// 走既有助手侧图片管线出图（存在性门＋§130 定
/// 高卡）。口径逐项对齐既有纪律，不另立一套：
/// - 扩展名认 FileRefDetector.imageExtensions
///   （webp/png/jpg/jpeg/gif/heic），非图片扩展
///   名的 MEDIA: 行维持纯文本不动——那是文件投
///   递语义，归文件牌链管，不在本包；
/// - 路径须过 FileRefDetector.isInDownloadRoot
///   （下载根 /opt/data）：根外路径天然取不回来，
///   与 §129 一样整行维持纯文本，不摘不藏；
/// - 行内嵌着写的 MEDIA:（一句话中间）不算标记，
///   须独占一行（允许行首尾空白）；代码围栏内的
///   行是字面量，不摘；
/// - 存在性不在 Core 判：摘行无条件（形态＋根＋
///   扩展名全过即摘），出不出图由 App 层按 §129
///   三分判定（exists 出图／missing 与 unverified
///   都先不出图、整行不露原文）。
public enum MediaMarker {
    private static let prefix = "MEDIA:"

    public static func split(in text: String) -> MediaMarkerSplit {
        guard text.contains(prefix) else {
            return MediaMarkerSplit(text: text, imagePaths: [])
        }
        var kept: [String] = []
        var paths: [String] = []
        var seen: Set<String> = []
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                kept.append(line)
                continue
            }
            if !inFence, let path = markerPath(in: trimmed) {
                if seen.insert(path).inserted {
                    paths.append(path)
                }
                continue
            }
            kept.append(line)
        }
        guard !paths.isEmpty else {
            return MediaMarkerSplit(text: text, imagePaths: [])
        }
        return MediaMarkerSplit(
            text: collapseBlankRuns(kept.joined(separator: "\n")),
            imagePaths: paths
        )
    }

    /// 一行（已修剪）是否为可摘的图片标记行：整行
    /// 恰好是 `MEDIA:` ＋一条无空白的绝对路径，扩
    /// 展名是图片、且在下载根内；任一不过回 nil
    /// （整行按原文保留）
    private static func markerPath(in trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix(prefix) else { return nil }
        let path = String(trimmedLine.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty,
              !path.contains(where: { $0.isWhitespace }),
              path.hasPrefix("/"),
              FileRefDetector.isImagePath(path),
              FileRefDetector.isInDownloadRoot(path)
        else { return nil }
        return path
    }

    /// 摘行后的空行收拾：三连以上换行压成一个空行
    /// （段落间距不变），首尾空白与换行修剪——正文
    /// 段落结构不因摘行变样
    private static func collapseBlankRuns(_ text: String) -> String {
        var result = text
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(
                of: "\n\n\n", with: "\n\n"
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
