import Foundation

/// 聊天模型清单与接线口径（0.3.0，DESIGN-V4 §15）。
///
/// 依据（2026-11-09 旁聊研究线服务器实测）：Hermes 网关
/// /v1/models 只暴露 hermes-agent（网关别名）；裸 model
/// 字段网关不认，但请求带 {"model": 名, "provider":
/// "custom"} 可逐请求切上游（实测 Qwen 落 New API 渠道
/// 13、deepseek-v4-pro 落渠道 14）；严禁在会话里发
/// 「/model xxx」文本切模型（API 不分发斜杠命令）。
/// 故清单在 App 内写死、选择本地持久化、逐请求生效
/// ——不再走 0.2.2 的服务端目录拼装＋改服务端默认
/// （那条路会把全站默认一起改掉，且候选拼装曾混入网
/// 关别名出过事故，见 ModelCatalog 文件头）。
///
/// 0.32.1（审计 F05/R2 止血，DESIGN-V4 §60）：Qwen 条
/// 目下线——上游 Modal 应用已拆除、New API 渠道 13 已
/// 禁用，Hermes 现只走 DeepSeek 官方；原条目把已停用
/// 渠道包装成「冷启需唤醒」是假可用承诺，故从可选清
/// 单隐藏、冷启/唤醒态整路拆除。已下线 id 只保留显示
/// 名映射（历史消息的名字牌）与落回提示判定，不再可
/// 选。正道＝模型目录改服务端下发（含状态位），见 §60
/// 待办指针，本轮不做。
public enum ChatModels {
    public struct Item: Equatable, Sendable {
        public let id: String
        public let displayName: String
        /// 短名（0.4.1）：身份胶囊窄宽档位用——只许整词
        /// 缩短、不许截断词中间（用户 10:07 点名）；全名
        /// 仍是选择器/设置页口径
        public let shortDisplayName: String
        /// 选择器行内说明（速度/成本/冷启提示）
        public let note: String
    }

    /// 可选清单（顺序即选择器顺序）。0.32.1 起只剩
    /// DeepSeek 两项：Qwen 已下线（见文件头），不在此列
    public static let items: [Item] = [
        Item(
            id: "deepseek-flash",
            displayName: "DeepSeek Flash",
            shortDisplayName: "Flash",
            note: "快 · 日常默认"
        ),
        Item(
            id: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            shortDisplayName: "V4 Pro",
            note: "强 · 复杂任务"
        ),
    ]

    /// 已下线模型（0.32.1，F05 止血）：不可选、不进
    /// 选择器；只保留显示名映射供历史消息渲染，以及
    /// 「已存选择命中下线模型」的落回判定
    public static let retiredItems: [Item] = [
        Item(
            id: "Qwen/Qwen3-30B-A3B-Instruct-2507-FP8",
            displayName: "Qwen3-30B",
            shortDisplayName: "Qwen3",
            note: "已停用"
        ),
    ]

    /// 未选过时的默认项
    public static var fallbackID: String { items[0].id }

    public static func contains(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    /// 是否已下线模型（可选清单之外、退役名单之内）
    public static func isRetired(_ id: String) -> Bool {
        retiredItems.contains { $0.id == id }
    }

    public static func displayName(for id: String) -> String {
        items.first { $0.id == id }?.displayName
            ?? retiredItems.first { $0.id == id }?.displayName
            ?? id
    }

    /// 短名（0.4.1）：清单内取写死短名；清单外无短名
    /// 口径、回全名（不许对未知 id 做字符串截断）。
    /// 已下线模型同样保留短名映射（历史消息名牌）
    public static func shortDisplayName(for id: String) -> String {
        items.first { $0.id == id }?.shortDisplayName
            ?? retiredItems.first { $0.id == id }?.shortDisplayName
            ?? displayName(for: id)
    }

    /// 已存选择命中已下线模型时的一次性落回提示文案
    /// （0.32.1）：选择实际经 initialSelection 落回
    /// fallback，本函数只负责「如实告知」；未命中下线
    /// 模型（或从未选过）返回 nil、不打扰
    public static func retiredFallbackNotice(stored: String?) -> String? {
        guard let stored, isRetired(stored) else { return nil }
        return "原选模型 \(displayName(for: stored)) 已停用，"
            + "已自动切回 \(displayName(for: fallbackID))。"
    }

    /// 请求体接线口径：清单内模型逐请求切上游须带
    /// provider=custom；清单外（网关别名等）不带、维持
    /// 旧行为
    public static func providerField(for model: String) -> String? {
        contains(model) ? "custom" : nil
    }

    /// 退役判定（§153 顶栏包 B2）：顶栏全量分组清单
    /// （ChatModelGroups）接管可选集后，本写死清单不
    /// 再是可选集真源——发送层逐请求 provider 只认会
    /// 话选择自带的 providerField（ChatModelChoice）。
    /// 本枚举保留三职：①显示名/短名单源（ModelDisplay-
    /// Names 消费）；②退役名映射与落回提示（历史消息
    /// 名牌）；③演示模式的分组种子（DemoHermesClient
    /// 演示回执由 items 派生）。providerField(for:) 与
    /// initialSelection 随私有 chatModel 层退场停用，
    /// 仅存量测试锚点保留（§153.3 记账）。

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
