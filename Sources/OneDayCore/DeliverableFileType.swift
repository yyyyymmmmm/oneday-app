import Foundation

/// 交付物行的类型小字（0.20.0，用户给的 Muse 资源
/// 库 Files 图口径）：副题只给类型词——取文件扩展名
/// 大写（Space/DOCX/PPTX 即此形态）；无扩展名给
/// 「文件」。大小/日期/来源是管理信息、不进本行副
/// 题（来源仍在数据层 Deliverable.source 里可查）。
public enum DeliverableFileType {
    public static func label(forFileName name: String) -> String {
        let ext = (name as NSString).pathExtension
            .trimmingCharacters(in: .whitespaces)
        guard !ext.isEmpty else { return "文件" }
        return ext.uppercased()
    }
}
