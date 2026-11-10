import Foundation

/// 模型显示名映射（0.3.8，fixlist 第 6 条）：原始 model id
/// 只许出现在详情页（对话模型页），其余一切界面（设置页
/// 身份卡/副题、顶栏小胶囊、列表值）一律走本表翻译。
/// 0.3.7 前的事故：设置页副题直出「deepseek-flash」而聊
/// 天页写「DeepSeek Flash」，同屏两副面孔。本表是唯一
/// 事实源：先查聊天清单（ChatModels，含 Qwen 全名 id），
/// 再查服务端常见别名；查不到返回 nil，调用方按语境兜
/// 底（身份位写「服务端默认」，不许把原始 id 顶上去）。
/// 0.32.1：已下线模型（ChatModels.retiredItems）的历
/// 史会话同样经 ChatModels 显示名翻译，不许掉进「服务
/// 端默认」兜底冒充。
public enum ModelDisplayNames {
    /// 网关别名：不是真模型名，界面上一律称「服务端默认」
    public static let gatewayAlias = "hermes-agent"

    /// 服务端别名 → 显示名（DeepSeek 官方别名映射到
    /// 规范名的显示名，与服务器实查口径一致）
    private static let aliases: [String: String] = [
        "deepseek-chat": "DeepSeek Flash",
        "deepseek-reasoner": "DeepSeek Flash",
    ]

    /// id → 界面显示名；未知/网关别名返回 nil
    public static func displayName(for id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        if id == gatewayAlias { return nil }
        if ChatModels.contains(id) || ChatModels.isRetired(id) {
            return ChatModels.displayName(for: id)
        }
        return aliases[id]
    }

    /// 身份位口径：拿不到显示名时说「服务端默认」
    /// （服务端按自己的默认在跑，不编模型名）
    public static func identityLabel(for id: String?) -> String {
        displayName(for: id) ?? "服务端默认"
    }
}
