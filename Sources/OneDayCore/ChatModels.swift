import Foundation

/// 聊天模型清单与接线口径（0.3.0，DESIGN-V4 §15）。
///
/// 依据（2026-11-09 旁聊研究线服务器实测）：Hermes 网关
/// /v1/models 只暴露 hermes-agent（网关别名）；裸 model
/// 字段网关不认，但请求带 {"model": 名, "provider":
/// "custom"} 可逐请求切上游（实测 Qwen 落 New API 渠道
/// 13、deepseek-v4-pro 落渠道 14）；严禁在会话里发
/// 「/model xxx」文本切模型（API 不分发斜杠命令）。
/// 故清单在 App 内写死三项、选择本地持久化、逐请求生
/// 效——不再走 0.2.2 的服务端目录拼装＋改服务端默认
/// （那条路会把全站默认一起改掉，且候选拼装曾混入网
/// 关别名出过事故，见 ModelCatalog 文件头）。
public enum ChatModels {
    public struct Item: Equatable, Sendable {
        public let id: String
        public let displayName: String
        /// 选择器行内说明（速度/成本/冷启提示）
        public let note: String
    }

    /// 写死三项（顺序即选择器顺序）
    public static let items: [Item] = [
        Item(
            id: "deepseek-flash",
            displayName: "DeepSeek Flash",
            note: "快 · 日常默认"
        ),
        Item(
            id: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            note: "强 · 复杂任务"
        ),
        Item(
            id: "Qwen/Qwen3-30B-A3B-Instruct-2507-FP8",
            displayName: "Qwen3-30B",
            note: "自部署 · 冷启需唤醒（约 1–3 分钟）"
        ),
    ]

    /// 未选过时的默认项
    public static var fallbackID: String { items[0].id }

    /// 自部署 Qwen：冷启竞速模型（客户端唤醒重试口径的
    /// 判定键，见 ChatView.runStream）
    public static let coldStartID = "Qwen/Qwen3-30B-A3B-Instruct-2507-FP8"

    public static func contains(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    public static func displayName(for id: String) -> String {
        items.first { $0.id == id }?.displayName ?? id
    }

    /// 请求体接线口径：清单内模型逐请求切上游须带
    /// provider=custom；清单外（网关别名等）不带、维持
    /// 旧行为
    public static func providerField(for model: String) -> String? {
        contains(model) ? "custom" : nil
    }

    /// 初始选择口径：已存选择优先；否则服务端默认若在
    /// 清单内则用之；再否则 fallback
    public static func initialSelection(
        stored: String?, serverDefault: String?
    ) -> String {
        if let stored, contains(stored) { return stored }
        if let serverDefault, contains(serverDefault) {
            return serverDefault
        }
        return fallbackID
    }
}
