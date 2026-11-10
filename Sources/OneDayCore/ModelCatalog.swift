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

/// 模型菜单「哪行带勾」的语义真源（0.36.13）：菜单
/// 本体自本版改系统 Picker 承载、勾由系统绘制（诊
/// 断 model-menu-checkmark-diagnosis：0.36.4 的等宽
/// 对号槽＋.opacity 藏勾形态在 Menu→UIKit 转换时透
/// 明度被剥掉、每行图标原样提取，双勾同显；苹果反
/// 馈 FB16679936 与社区核查一致——菜单带勾正道只
/// 有 Toggle/Picker）。本函数是勾的判定口径：选中
/// 值在清单内才有勾且恒一勾；已下线/未知 id、空串、
/// nil 一律零勾。视图层只消费它喂 Picker 的
/// selection，渲染通道本身（系统画勾）单测钉不住、
/// 验收靠真机展开菜单看一勾（见 DESIGN-V4 §78）。
/// 0.36.4 的 ModelMenuSpec（对号槽宽/间距常数）随
/// opacity 形态一并退役——槽已无消费者。
public enum ModelMenuSelection {
    /// 当前应带勾的模型 id：selected 命中清单才返
    /// 回它本身，否则 nil（零勾）
    public static func checkedID(
        itemIDs: [String], selected: String?
    ) -> String? {
        guard let selected, !selected.isEmpty,
              itemIDs.contains(selected)
        else { return nil }
        return selected
    }
}
