import Foundation

/// 登记交付标记的拆分产出（§146）：正文（摘除
/// 标记行后）＋登记号（出现序、去重）
public struct DeliveryMarkerSplit: Equatable, Sendable {
    public let text: String
    public let deliveryIDs: [String]

    public init(text: String, deliveryIDs: [String]) {
        self.text = text
        self.deliveryIDs = deliveryIDs
    }
}

/// 助手正文里的登记交付标记（§146，登记制 App
/// 半边；规格 delivery-registry-spec-20261111.md
/// §4 消息面契约＋§7 消费契约，用户 2026-11-11
/// 17:14 定调「不要位置，要的是真实的文件」）：
/// 智能体交付文件先经伴生登记端点登记，回执里
/// 的标记 `[[deliver:dlv_<20 位小写十六进制>]]`
/// 独立成行放进回复；App 只认标记、按号向登记
/// 端点取元数据渲染——正文里的裸路径从此只是
/// 文字、永不升格（§129/§136 兜底只管没有标记
/// 的历史消息，与本层不打架：有标记走登记）。
/// 本解析是呈现层的收口（与 §136 MediaMarker
/// 同层、同纪律）：
/// - 形态：整行（允许行首尾空白）恰好是一个标
///   记、号形态合 §4.1 定版正则
///   `\[\[deliver:(dlv_[0-9a-f]{20})\]\]`；
///   号形态不对（位数错/大写/非十六进制/缺括
///   号）的行一律不是标记、按原文保留——查无此
///   号与形态不对都在 App 层落纯文本（规格
///   §4.2：解析权在端点，不在语法）；
/// - 行内嵌着写的标记（前后有字）不算交付，
///   须独占一行；代码围栏内的行是字面量，不摘；
/// - 同号重复出现只取一次（呈现位取首现），与
///   §136 去重口径一致；
/// - 摘行后的正文收拾与 MediaMarker 同法（三连
///   换行压一空行、首尾修剪）；无标记时原文逐
///   字返回，不动存量消息分毫。
public enum DeliveryMarker {
    private static let prefix = "[[deliver:"
    private static let suffix = "]]"

    /// 登记号形态判定（规格 §4.1）：`dlv_`＋20
    /// 位小写十六进制；端点签发的号只此一形
    public static func isValidID(_ id: String) -> Bool {
        guard id.hasPrefix("dlv_") else { return false }
        let hex = id.dropFirst(4)
        guard hex.count == 20 else { return false }
        return hex.allSatisfy { "0123456789abcdef".contains($0) }
    }

    /// 标记原文（App 层查无此号时按纯文本原样
    /// 显示用，规格 §7.3——不拼路径、不加工）
    public static func markerText(for id: String) -> String {
        "\(prefix)\(id)\(suffix)"
    }

    public static func split(in text: String) -> DeliveryMarkerSplit {
        guard text.contains(prefix) else {
            return DeliveryMarkerSplit(text: text, deliveryIDs: [])
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
            kept.append(line)
        }
        guard !ids.isEmpty else {
            return DeliveryMarkerSplit(text: text, deliveryIDs: [])
        }
        return DeliveryMarkerSplit(
            text: collapseBlankRuns(kept.joined(separator: "\n")),
            deliveryIDs: ids
        )
    }

    /// 一行（已修剪）是否为可摘的登记标记行：整
    /// 行恰好是 `[[deliver:`＋合形态登记号＋`]]`；
    /// 任一不过回 nil（整行按原文保留）
    private static func markerID(in trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix(prefix),
              trimmedLine.hasSuffix(suffix)
        else { return nil }
        let id = String(
            trimmedLine.dropFirst(prefix.count).dropLast(suffix.count)
        )
        return isValidID(id) ? id : nil
    }

    /// 摘行后的空行收拾（与 MediaMarker 同法）：
    /// 三连以上换行压成一个空行，首尾空白与换行
    /// 修剪——正文段落结构不因摘行变样
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
