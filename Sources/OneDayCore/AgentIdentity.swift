import Foundation

/// 智能体屏上名（0.6.1，用户真机点名）：全 App 标题
/// 位（抽屉名/聊天胶囊/活动页大标题）只认一个来源
/// ——soul/identity 里取得到的身份名，取不到回落
/// 「Hermes」。旧口径拿档案（profile）名翻译当标题
/// （default→「默认档案」）：档案是配置实体、不是
/// 智能体身份，「默认档案」自此退出一切标题位
/// （档案管理页内的实体名不在此列）。
public enum AgentName {
    /// 回落名：与 Hermes 部署的身份名一致，抽屉与
    /// 胶囊的既有字面同此值
    public static let fallback = "Hermes"

    /// 结构词黑名单：soul 的一级标题多为文档名而非
    /// 身份名（如「# SOUL.md」），命中即不取
    private static let structuralHeadings: Set<String> = [
        "soul", "soul.md", "灵魂", "人设", "身份",
        "identity", "persona", "about", "profile",
    ]

    /// 从 soul 全文提取身份名：只认首个一级标题
    /// （`# …`），且须像名字——非空、≤20 字、无句
    /// 读标点、非结构词；其余一律回落，不猜。
    public static func resolve(soulContent: String?) -> String {
        guard let soulContent else { return fallback }
        for line in soulContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("# ") else { return fallback }
            let candidate = trimmed.dropFirst(2)
                .trimmingCharacters(in: .whitespaces)
            guard !candidate.isEmpty,
                  candidate.count <= 20,
                  !candidate.contains(where: {
                      "。．.：:、，,；;！!？?".contains($0)
                  }),
                  !structuralHeadings.contains(candidate.lowercased())
            else { return fallback }
            return candidate
        }
        return fallback
    }
}
