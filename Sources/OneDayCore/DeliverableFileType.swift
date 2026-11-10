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

    /// 展示标题（0.36.31，文件页 v2 规格 §4.3）：去扩展
    /// 名——扩展名进类型签（label），标题不再带「.docx」
    /// 尾巴（现行行口径露全名带后缀，随本版修正）；无
    /// 扩展名、点文件（.env 一类 NSString 口径无扩展
    /// 名）、去尾后为空的都原样返回。双扩展只去末段
    /// （a.tar.gz → a.tar，与行类型签 GZ 对位）。
    public static func displayTitle(forFileName name: String) -> String {
        let nsName = name as NSString
        guard !nsName.pathExtension.isEmpty else { return name }
        let stem = nsName.deletingPathExtension
        return stem.isEmpty ? name : stem
    }
}
