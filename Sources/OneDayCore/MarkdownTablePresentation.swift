import Foundation

/// 表格呈现口径（§271，第 72 条）：聊天表格旧形态
/// 是「列宽按内容理想宽＋整表横滑」——长文本单元
/// 格不折行，3 列长文表也要横着拖才看得全（格式
/// 显示诊断 §四实证）。本口径两条：
/// - 列宽封顶＋单元格折行：列宽不再由最长单元格
///   的理想宽决定，封顶后单元格在列内折行呈现；
/// - 列数超限降级列表：>4 列的表在气泡宽内横滑
///   读不全，降级为逐行「表头标签＋值」的列表呈
///   现（信息不丢、不用横拖）。
public enum MarkdownTablePresentation {
    public enum Mode: Equatable {
        case grid
        case list
    }

    /// Grid 呈现的列数上限（超过即降级列表）
    public static let gridColumnLimit = 4

    /// 列宽封顶（pt）：与气泡文本宽同量级——两列
    /// 封顶表加列距约等于文本宽、单列长文先折行
    /// 而非先横滑
    public static let maxColumnWidth: Double = 168

    public static func mode(columnCount: Int) -> Mode {
        columnCount > gridColumnLimit ? .list : .grid
    }

    /// 列表降级的一行一条：表头作标签、行值作值
    public struct ListEntry: Equatable {
        public var label: String
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    /// 表格 → 列表条目（逐行×逐列）：行短于表头时
    /// 缺位补空串、长于表头时多余值不呈现（与块解
    /// 析的列数对齐口径一致，不造数据）
    public static func listEntries(
        header: [String], rows: [[String]]
    ) -> [[ListEntry]] {
        rows.map { row in
            header.enumerated().map { index, label in
                ListEntry(
                    label: label,
                    value: index < row.count ? row[index] : ""
                )
            }
        }
    }
}
