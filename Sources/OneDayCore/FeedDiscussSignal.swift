import Foundation

/// 动态「讨论」信号的 note 提取（FA-1，契约 rev2
/// §1.9 冻结）：讨论建聊后用户在该旁聊发出的首句里，
/// 只取「用户自述偏好」的那一句作 note 随 signal 上
/// 报——口味笔记只收用户亲口的偏好表述（Muse 纪
/// 律：口味摘要学自用户在讨论里说的话，聊天正文不
/// 整段外送）。判定口径：
/// - 按句切分（。！？；与换行），逐句找偏好标记；
/// - 命中第一句即取整句（去首尾空白），超长句截到
///   note 上限（桥侧只作一句提示，宁截不编）；
/// - 一句都没命中＝nil，调用方发无 note 的弱信号。
/// 标记表只收明确的偏好动词/短语，不收话题词——
/// 「这篇讲得好」不是偏好自述、不命中；「以后这种
/// 多给我推」才是。
public enum FeedDiscussSignal {
    /// note 长度上限（字符）：一句自述足够，超此截断
    public static let noteLimit = 120

    /// 偏好标记（子串命中即算）：喜欢类、兴趣类、
    /// 增减推送类、意愿类，中英各一份（英文按小写
    /// 归一后匹配）
    static let preferenceMarkers: [String] = [
        "喜欢", "不喜欢", "感兴趣", "没兴趣", "不感兴趣",
        "多看", "少看", "多推", "少推", "别推", "不要推",
        "多给我", "少给我", "想看", "不想看", "想多看",
        "希望多", "希望少", "以后多", "以后少", "请多",
        "i like", "i love", "i prefer", "don't like",
        "do not like", "interested in", "more of",
        "less of", "show me more", "show me less",
    ]

    /// 从用户首句全文中提取自述偏好句；无命中返回 nil
    public static func preferenceNote(in message: String) -> String? {
        let trimmed = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return nil }
        for sentence in sentences(in: trimmed) {
            let candidate = sentence.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !candidate.isEmpty else { continue }
            let lowered = candidate.lowercased()
            if preferenceMarkers.contains(where: {
                lowered.contains($0)
            }) {
                if candidate.count <= noteLimit {
                    return candidate
                }
                return String(candidate.prefix(noteLimit))
            }
        }
        return nil
    }

    /// 句切分：句末标点与换行作界，标点留在前句尾
    /// （自述句原样上报，含标点更像原话）
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if "。！？；.!?;\n".contains(ch) {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
