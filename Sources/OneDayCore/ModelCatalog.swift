import Foundation

/// 模型目录的拼装与校验（0.2.4 修复，纯逻辑、可单测）。
///
/// 背景（2026-11-09 服务器实测，证据确凿）：Hermes 网关 8642
/// 的 GET /v1/models 只返回 `hermes-agent`——那是**网关别名**
/// （客户端调网关时填的模型名），不是上游模型；把它写进
/// /api/config 当默认模型，上游立刻 400。上游 DeepSeek 官方
/// /v1/models 只返回 deepseek-flash、deepseek-v4-pro。
/// 0.2.2 的选择器把「config 当前值 ∪ 网关 /v1/models ∪ 用量」
/// 并集，误把网关别名列成可选项，本文件是根治口径：
/// 候选只许来自上游，并对一切来源硬排除网关别名。
public enum ModelCatalog {
    /// 老模型名 → 实际运行的上游模型（别名映射）。
    /// 依据同为上述实测：以 deepseek-chat / deepseek-reasoner
    /// 发上游均 HTTP 200 且返回体 model 字段为 deepseek-flash
    /// ——老名字是别名、不是独立模型。这些名字仍可作默认
    /// （能跑），但 UI 必须标注将按哪个模型运行。
    public static let aliasRuntime: [String: String] = [
        "deepseek-chat": "deepseek-flash",
        "deepseek-reasoner": "deepseek-flash",
    ]

    /// 从 GET /api/model/options 的回执里宽容提取上游模型 id。
    /// 该端点在 OpenAPI 里响应未定型（描述称与官方
    /// ModelPickerDialog 同形：已认证提供商＋精选模型列表），
    /// 故不按单一结构强解：递归遍历任意层级的 "models" 数组，
    /// 元素接受字符串或含 id/model/name 的对象；保序去重。
    public static func extractModelIDs(from root: JSONValue) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func add(_ id: String?) {
            guard let id, !id.isEmpty, seen.insert(id).inserted else { return }
            ordered.append(id)
        }
        func collectModelsArray(_ value: JSONValue) {
            guard case .array(let items) = value else { return }
            for item in items {
                switch item {
                case .string(let id):
                    add(id)
                case .object(let fields):
                    add(fields["id"]?.stringValue
                        ?? fields["model"]?.stringValue
                        ?? fields["name"]?.stringValue)
                default:
                    break
                }
            }
        }
        func walk(_ value: JSONValue) {
            switch value {
            case .object(let fields):
                if let models = fields["models"] {
                    collectModelsArray(models)
                }
                for child in fields.values { walk(child) }
            case .array(let items):
                for item in items { walk(item) }
            default:
                break
            }
        }
        walk(root)
        return ordered
    }

    /// 候选拼装（选择器的唯一数据源口径）：
    /// 1. 正规端点 /api/model/options 的上游列表非空即用它；
    /// 2. 为空才回落「用量历史 ∪ config 当前值」（当前值在前）；
    /// 3. 两种来源都**硬排除网关别名**（凡出现在网关
    ///    /v1/models 返回里的 id 一律不进候选）。
    public static func candidates(
        options: [String],
        usage: [String],
        current: String?,
        gatewayAliases: Set<String>
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        func add(_ model: String?) {
            guard let model, !model.isEmpty,
                  !gatewayAliases.contains(model),
                  seen.insert(model).inserted else { return }
            ordered.append(model)
        }
        if !options.isEmpty {
            options.forEach { add($0) }
        } else {
            add(current)
            usage.forEach { add($0) }
        }
        return ordered
    }

    /// 写入校验：待写进 /api/config 的默认模型必须在候选集内，
    /// 不在则拦截（网关别名、拼写错误、已下线模型都走这里）。
    public static func isWritable(_ model: String, candidates: [String]) -> Bool {
        candidates.contains(model)
    }
}

/// 身份胶囊模型菜单的行布局真源（0.36.4，用户 18:48
/// 点名）：每行预留等宽对号槽——选中行槽内显 ✓、未
/// 选行槽留空，模型名由此同列对齐。旧形态只有选中
/// 行带 Label(checkmark)、未选行是裸 Text，名字起
/// 点随有无对号漂移一列宽、两行不对齐。数值由
/// ModelCatalogTests 钉死防回潮。
public enum ModelMenuSpec {
    /// 对号槽宽（每行恒占位，与有无对号无关）
    public static let checkmarkSlotWidth: CGFloat = 18
    /// 对号槽与模型名之间的间距
    public static let checkmarkSlotSpacing: CGFloat = 6
}
