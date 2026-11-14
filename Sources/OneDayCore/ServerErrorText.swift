import Foundation

/// 服务端回传文案的用户安全门（§232，轻动作乐观化
/// 统一包件八）：桥/伴生的 error、detail 字段按契约
/// 应是人话，但客户端不许无条件透传——服务端任何
/// 一处把英文报错、堆栈、地址或长串标识塞进这些字
/// 段，都会直达用户面。本门只做呈现前的 sanity 裁
/// 决：过门原样呈现；不过门由调用方落通用人话、原
/// 文只进诊断留痕（ChatDiagTrace），不许上屏。
public enum ServerErrorText {
    /// 长度上限（字符数）：真人话原因都短，超长多为
    /// 日志/堆栈/转储
    public static let maxLength = 80

    /// 过门判定（入参先修剪）：非空、单行、无控制字
    /// 符、长度不超上限、至少含一个汉字（本产品服务
    /// 端用户文案恒为中文；纯 ASCII 串多为技术报错），
    /// 且不含技术标记（地址/堆栈/异常词/括号转储），
    /// 且无超长纯 ASCII token（哈希/长 id/技术串）
    public static func isUserSafe(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty, text.count <= maxLength else {
            return false
        }
        guard !text.contains("\n"), !text.contains("\r")
        else { return false }
        guard text.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0)
        }) else { return false }
        guard text.unicodeScalars.contains(where: isHan)
        else { return false }
        let lowered = text.lowercased()
        for marker in technicalMarkers
        where lowered.contains(marker) {
            return false
        }
        for token in text.split(whereSeparator: {
            $0.isWhitespace
        }) where token.count > 24
            && token.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return false
        }
        return true
    }

    /// 过门返回修剪后的原文，不过门返回 nil（调用方
    /// 落通用人话＋原文进诊断留痕）
    public static func userSafe(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return isUserSafe(text) ? text : nil
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
    }

    private static let technicalMarkers: [String] = [
        "http://", "https://", "://", "traceback",
        "exception", "stack trace", "errno", "econn",
        "undefined", "<html", "{", "}", "0x",
    ]
}
