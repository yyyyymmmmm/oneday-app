import Foundation

/// 渲染计划缓存键（§132，发送空屏诊断 B 案）：Chat-
/// View 旧形态每次 body 重算都要对全线程重算渲染计
/// 划——sortedEntries 全量排序至少两遍（分隔走查＋
/// 成组走查各一遍）、每条工具条目的 JSON 每次访问
/// 现解码；任一 @State 写入（流式增量、滚动回调回
/// 写、notice……）都全量重付。本键给渲染计划一个数
/// 据版本：键不变即计划不变，视图层按键命中缓存、
/// 跳过排序与走查。
///
/// 失效条件（钉测覆盖，任一变化即键变）：
/// - 条目集合变化：条目增删（计数＋id 集指纹）；
/// - 工具卡形态翻转：任一条目的 toolCardData 有无
///   变化（成组规则随之变）；
/// - 条目时刻变化：createdAt 参与排序与分隔落点；
/// - 线程切换：threadID；
/// - 跨日：dayStamp（分隔文案含今天/昨天相对口径，
///   跨零点须失效）。
public struct ChatRenderPlanKey: Equatable {
    /// 条目的最小投影：判定只需要 id、工具卡数据
    /// 有无与创建时刻——投影本身不触发 JSON 解码
    public struct EntryStub: Equatable {
        public let id: UUID
        public let hasToolCardData: Bool
        public let createdAt: Date

        public init(
            id: UUID, hasToolCardData: Bool, createdAt: Date
        ) {
            self.id = id
            self.hasToolCardData = hasToolCardData
            self.createdAt = createdAt
        }
    }

    public let threadID: UUID
    /// 条目集指纹（计数与逐条投影的哈希）
    public let fingerprint: Int
    public let entryCount: Int
    /// 当日零点（跨日失效用）
    public let dayStamp: Date

    /// 由条目投影集造键：投影先按 id 排序再逐条入
    /// 哈希——入参顺序（关系数组的未定序）不影响键
    public static func make(
        threadID: UUID,
        entries: [EntryStub],
        dayStamp: Date
    ) -> ChatRenderPlanKey {
        var hasher = Hasher()
        hasher.combine(entries.count)
        let ordered = entries.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        for stub in ordered {
            hasher.combine(stub.id)
            hasher.combine(stub.hasToolCardData)
            hasher.combine(stub.createdAt)
        }
        return ChatRenderPlanKey(
            threadID: threadID,
            fingerprint: hasher.finalize(),
            entryCount: entries.count,
            dayStamp: dayStamp
        )
    }
}
