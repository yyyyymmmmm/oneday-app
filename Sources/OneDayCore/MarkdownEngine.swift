import Foundation

/// §417（#13 Markdown 换底，施工图 swap-md-image-
/// prep-20261123.md 第一部）：解析引擎开关——默认
/// swift-markdown 新核（MarkdownTreeParsing），置
/// true 回滚旧状态机核。保留一个发布周期作回滚：
/// 回滚＝defaults 写入本键后重启（或进程内改本属
/// 性），不需要代码回退、不涉及任何落盘数据（纯
/// 计算层）。
///
/// 切换即清解析备忘：两核产物口径不同（差分签收
/// 表登记的差异），不许在同一备忘盒里混存——进程
/// 内切换走本属性 setter（清盒）；外部 defaults
/// 写入在下次冷启生效（备忘盒进程内新建、天然
/// 干净）。
///
/// 删除条件（与旧核同批）：流式孤岛 parseWith-
/// Ranges 的消费方 StreamingBlockProduct 随 S2
/// 退役后，本开关、MarkdownParser.parseUncached
/// 与 InlineRunBuilder 的旧行内路一并删除。
public enum MarkdownEngine {
    public static let legacyDefaultsKey = "markdown.engine.legacy"

    public static var usesLegacyParser: Bool {
        get {
            UserDefaults.standard.bool(forKey: legacyDefaultsKey)
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: legacyDefaultsKey
            )
            MarkdownParseMemos.blocks.removeAll()
            MarkdownParseMemos.runs.removeAll()
        }
    }
}
