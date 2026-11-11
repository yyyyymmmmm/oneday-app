import Foundation

/// 智能体屏上名（0.6.1，用户真机点名）：全 App 标题
/// 位（抽屉名/聊天胶囊/活动页大标题）只认一个来源
/// ——soul/identity 里取得到的身份名，取不到回落
/// 「Hermes」。旧口径拿档案（profile）名翻译当标题
/// （default→「默认档案」）：档案是配置实体、不是
/// 智能体身份，「默认档案」自此退出一切标题位
/// （档案管理页内的实体名不在此列）。
public enum AgentName {
    /// 回落名（§155，三层命名定案，2026-11-11 用户
    /// 拍板）：全 App 名字分三层、各司其职——OneDay
    /// ＝客户端产品名（只指本 App）；智能体名＝本解
    /// 析链（服务器 soul 身份名→本机覆盖→此回落）；
    /// Hermes＝服务端（用户自部署的开源服务）。本
    /// 回落值 "Hermes" 的语义是「服务端未给身份名
    /// 时的默认身份」——服务端软件自带的名，不是客
    /// 户端产品名，更不是双名并存：后人勿再以「双
    /// 名问题」为由改此值或改产品名（全改名与回落
    /// 改 OneDay 两案均已被用户否决，定案见
    /// DESIGN-V4 §155）。与 Hermes 部署的默认身份名
    /// 一致，抽屉与胶囊的既有字面同此值
    public static let fallback = "Hermes"

    /// 结构词黑名单：soul 的一级标题多为文档名而非
    /// 身份名（如「# SOUL.md」），命中即不取
    private static let structuralHeadings: Set<String> = [
        "soul", "soul.md", "灵魂", "人设", "身份",
        "identity", "persona", "about", "profile",
    ]

    /// 从 soul 全文提取身份名：只认文档头部（前 3 个
    /// 非空行内）出现的首个一级标题（`# …`）——允许
    /// 标题前有一两行引言，但不深扫全文（后面的章节
    /// 标题不是身份名）；标题须像名字——非空、≤20
    /// 字、无句读标点、非结构词；其余一律回落，不猜
    public static func resolve(soulContent: String?) -> String {
        guard let soulContent else { return fallback }
        var contentLines = 0
        for line in soulContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            contentLines += 1
            if contentLines > 3 { return fallback }
            guard trimmed.hasPrefix("# ") else { continue }
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
