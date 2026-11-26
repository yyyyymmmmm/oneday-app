import Foundation

/// 凭据请求标记的拆分产出：正文（摘除标记行后）＋请求号（出现序、去重）
public struct VaultRequestMarkerSplit: Equatable, Sendable {
    public let text: String
    public let requestIDs: [String]

    public init(text: String, requestIDs: [String]) {
        self.text = text
        self.requestIDs = requestIDs
    }
}

/// 助手正文里的凭据请求标记（聊天内凭据批准卡，补件 C 客户端半边）：
/// 智能体请求凭据时，服务端工具回执带标记 `[[vreq:vreq_<24 位 URL-safe>]]`
/// 独立成行放进回复；App 只认标记、按号向 /v1/vault/requests 取元数据渲染
/// VaultRequestCard。本解析是呈现层的收口（与 DeliveryMarker / MediaMarker
/// 同层、同纪律）：
/// - 形态：整行（允许行首尾空白）恰好是一个标记、号形态合 `vreq_` + 24 位
///   [A-Za-z0-9_-]（token_urlsafe(18) 产物）；
///   号形态不对（位数错/非法字符/缺括号）的行一律不是标记、按原文保留——
///   查无此号与形态不对都在 App 层落纯文本（解析权在端点，不在语法）；
/// - 行内嵌着写的标记（前后有字）不算交付，须独占一行；代码围栏内的行是
///   字面量，不摘；
/// - 同号重复出现只取一次（呈现位取首现），与 DeliveryMarker 去重口径一致；
/// - 摘行后的正文收拾与 DeliveryMarker 同法（三连换行压一空行、首尾修剪）；
///   无标记时原文逐字返回，不动存量消息分毫。
public enum VaultRequestMarker {
    private static let prefix = "[[vreq:"
    private static let suffix = "]]"

    /// 请求号形态判定：`vreq_` + 24 位 URL-safe 字符 [A-Za-z0-9_-]
    public static func isValidID(_ id: String) -> Bool {
        guard id.hasPrefix("vreq_") else { return false }
        let token = id.dropFirst(5)
        guard token.count == 24 else { return false }
        let allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
        return token.allSatisfy { allowed.contains($0) }
    }

    /// 标记原文（App 层查无此号时按纯文本原样显示用）
    public static func markerText(for id: String) -> String {
        "\(prefix)\(id)\(suffix)"
    }

    public static func split(in text: String) -> VaultRequestMarkerSplit {
        guard text.contains(prefix) else {
            return VaultRequestMarkerSplit(text: text, requestIDs: [])
        }
        var kept: [String] = []
        var ids: [String] = []
        var seen: Set<String> = []
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                kept.append(line)
                continue
            }
            if !inFence, let id = markerID(in: trimmed) {
                if seen.insert(id).inserted {
                    ids.append(id)
                }
                continue
            }
            if !inFence, line.contains(prefix) {
                let (cleaned, inlineIDs) = extractInlineMarkers(in: line)
                for id in inlineIDs where seen.insert(id).inserted {
                    ids.append(id)
                }
                if !cleaned.isEmpty {
                    kept.append(cleaned)
                }
                continue
            }
            kept.append(line)
        }
        guard !ids.isEmpty else {
            return VaultRequestMarkerSplit(text: text, requestIDs: [])
        }
        return VaultRequestMarkerSplit(
            text: collapseBlankRuns(kept.joined(separator: "\n")),
            requestIDs: ids
        )
    }

    /// 提取行内嵌入的 `[[vreq:vreq_...]]` 标记，并返回摘除标记后的文本
    private static func extractInlineMarkers(
        in line: String
    ) -> (String, [String]) {
        var result = ""
        var ids: [String] = []
        var cursor = line.startIndex
        while cursor < line.endIndex {
            guard let start = line.range(
                of: prefix, range: cursor..<line.endIndex
            ),
            let end = line.range(
                of: suffix, range: start.upperBound..<line.endIndex
            ) else {
                result.append(contentsOf: line[cursor...])
                break
            }
            let candidate = String(line[start.upperBound..<end.lowerBound])
            if isValidID(candidate) {
                result.append(contentsOf: line[cursor..<start.lowerBound])
                ids.append(candidate)
                cursor = end.upperBound
            } else {
                result.append(contentsOf: line[cursor..<start.upperBound])
                cursor = start.upperBound
            }
        }
        let cleaned = result.trimmingCharacters(in: .whitespaces)
        return (cleaned, ids)
    }

    /// 一行（已修剪）是否为可摘的凭据请求标记行：整行恰好是 `[[vreq:` +
    /// 合形态请求号 + `]]`；任一不过回 nil（整行按原文保留）
    private static func markerID(in trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix(prefix),
              trimmedLine.hasSuffix(suffix)
        else { return nil }
        let id = String(
            trimmedLine.dropFirst(prefix.count).dropLast(suffix.count)
        )
        return isValidID(id) ? id : nil
    }

    /// 摘行后的空行收拾（与 DeliveryMarker 同法）：三连以上换行压成一个空行，
    /// 首尾空白与换行修剪——正文段落结构不因摘行变样
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
