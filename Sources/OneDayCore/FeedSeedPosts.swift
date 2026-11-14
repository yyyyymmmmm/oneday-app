import Foundation

/// FA-2 首次种子帖（治 F-6，规格 three-pages-muse-parity
/// §4.1 FA-2）：App 内置的一组固定介绍帖，讲清动态的五件
/// 事——简报、点子、目标、文件、旁聊。呈现口径（规格写死）：
/// ①只在「从未产出且无任何真帖」时垫底呈现；②与真帖同形
/// 态同动作（讨论/删除可用）；③真帖出现即退场；④删了不
/// 复活（本地标记，账在 FeedStore）；⑤不进桥数据、不冒充
/// 生成帖——kind=.seed，动作行的类别位明示「上手指南」；
/// ⑥不读任何用户数据（内容全是固定文案）。
public enum FeedSeedPosts {
    /// 种子帖 id 前缀（桥 id 空间永不以此前缀开头，App 侧
    /// 据此把种子帖的一切桥回写短路）
    public static let idPrefix = "oneday-seed-"

    public static func isSeed(_ id: String) -> Bool {
        id.hasPrefix(idPrefix)
    }

    /// 五件介绍帖（顺序即呈现序）。createdAt 恒 0：种子帖
    /// 不是某个时刻的产出，行面与详情头对它们不显相对时间
    public static let all: [BridgeFeedPost] = [
        BridgeFeedPost(
            id: idPrefix + "brief", kind: .seed,
            title: "动态替你盯着感兴趣的事",
            body: "在这一页右上角的滑杆里，用你自己的话写下你感兴趣什么——比如某个行业的新动作、某个项目的进展。之后我每天替你去看，有值得一提的新发现就发到这里；你点开简报改一句，我马上再去抓一轮。",
            createdAt: 0, emoji: "📰"
        ),
        BridgeFeedPost(
            id: idPrefix + "ideas", kind: .seed,
            title: "点子页是替你想下一步的管家",
            body: "点子页的卡片都是「我可以替你做这件事」：它结合你的目标、任务和日程来想，觉得值得做就点采纳，我去办；觉得太泛就标一下，我下次绕开这类。第一张卡要等你的素材攒起来后的早上出现。",
            createdAt: 0, emoji: "💡"
        ),
        BridgeFeedPost(
            id: idPrefix + "goals", kind: .seed,
            title: "目标页盯着你要去哪",
            body: "在目标页选一个方面，我先陪你聊定这个目标，再持续替你盯着：关联的任务在跑、卡住还是办完，都会记在目标下面。你随时能看它走到哪一步了。",
            createdAt: 0, emoji: "🎯"
        ),
        BridgeFeedPost(
            id: idPrefix + "files", kind: .seed,
            title: "文件页收着给你的交付物",
            body: "我做好的文档、表格、图片都会落到文件页，按来源会话归好类，不用回聊天里翻。点开就能看，要改就在原会话里接着说。",
            createdAt: 0, emoji: "📁"
        ),
        BridgeFeedPost(
            id: idPrefix + "chat", kind: .seed,
            title: "旁聊是派活和深聊的地方",
            body: "主线之外，每件正经事可以开一条旁聊慢慢聊：从动态、点子点「讨论」就会带着原文开一条。聊完不用管，会话都收在抽屉里，随时回来接着说。",
            createdAt: 0, emoji: "💬"
        ),
    ]

    /// 可见性判定（纯函数，规格口径逐条对应）：有真帖 →
    /// 全退场；产过（不再是 neverProduced）→ 不垫底；
    /// 本地删过的 → 不再回来
    public static func visible(
        realPostCount: Int, neverProduced: Bool,
        deletedIDs: Set<String>
    ) -> [BridgeFeedPost] {
        guard realPostCount == 0, neverProduced else { return [] }
        return all.filter { !deletedIDs.contains($0.id) }
    }
}
