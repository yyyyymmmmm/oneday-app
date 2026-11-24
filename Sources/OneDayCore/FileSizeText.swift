import Foundation

/// 紧凑大小文案（§452）：微信文件卡口径——无空格、
/// 单位贴数（321KB／1.2MB／178B），只给文件卡与兜
/// 底页这类紧凑呈现用；信息密集面仍走 ByteCount-
/// Formatter，不混口径。纯函数、钉测把守。
public enum FileSizeText {
    public static func compact(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0B" }
        let kb = 1024.0
        let mb = kb * 1024
        let gb = mb * 1024
        let value = Double(bytes)
        if bytes < 1024 {
            return "\(bytes)B"
        }
        if value < mb {
            return "\(Int((value / kb).rounded()))KB"
        }
        if value < gb {
            return trimmed(value / mb) + "MB"
        }
        return trimmed(value / gb) + "GB"
    }

    /// 一位小数、整数时去尾（1.0→「1」、1.25→「1.3」四舍五入到一位）
    private static func trimmed(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        if r == r.rounded() {
            return "\(Int(r))"
        }
        return String(format: "%.1f", r)
    }
}
