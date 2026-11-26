import Foundation

/// 凭据请求卡覆盖层（0.51.2／服务端 2.17.2）：与
/// 选择框覆盖层（OptionsCardOverlay）同构的本机
/// 瞬态层，但一张线程可挂多张卡——按挂载行
/// serverRowID 索引。真源在消息行 display_
/// metadata 的 vault_request 块（终态 attach），
/// 本层只负责让已拉到/已落定的块在行管线里有
/// 同步可读的落点：渲染凭块直出、不发二次请求；
/// 正文 [[vreq:]] 标记只作块不在场时的兜底路径。
/// 播种两路：落定回读（RunTranscriptSettle 提
/// 取）与历史回填（导入消息全量按行播种）。
@MainActor
public final class VaultRequestOverlay {
    private var blocks: [UUID: [Int: MessageVaultRequest]] = [:]

    public init() {}

    public func block(
        threadID: UUID, serverRowID: Int
    ) -> MessageVaultRequest? {
        blocks[threadID]?[serverRowID]
    }

    /// 播种单块：同行重复播种以新块覆旧（状态推
    /// 进如 pending→submitted 靠服务端新投影，
    /// 旧块不许压新块）
    public func seed(
        threadID: UUID, serverRowID: Int,
        block: MessageVaultRequest
    ) {
        blocks[threadID, default: [:]][serverRowID] = block
    }

    /// 历史回填批量播种：拉到的消息里全部块按行
    /// 落位（与选择框「只尾位一张」不同——凭据卡
    /// 是行内历史构件，过期/已处理态照样呈现）
    public func seedAll(
        threadID: UUID,
        entries: [(serverRowID: Int, block: MessageVaultRequest)]
    ) {
        for entry in entries {
            seed(
                threadID: threadID,
                serverRowID: entry.serverRowID,
                block: entry.block
            )
        }
    }

    /// 本线程已被块覆盖的 request_id 集（渲染侧
    /// 据此把同 id 的正文标记排除出兜底路径，防
    /// 一卡双出）
    public func coveredRequestIDs(threadID: UUID) -> Set<String> {
        Set((blocks[threadID] ?? [:]).values.map(\.requestID))
    }

    /// 修订摘要（行管线 baseRevision 折入用）：行
    /// 号＋状态＋字段数——块到达/状态推进即变，
    /// 行随之重建
    public func revisionDigest(threadID: UUID) -> String {
        guard let threadBlocks = blocks[threadID],
              !threadBlocks.isEmpty
        else { return "" }
        return threadBlocks.keys.sorted().map { rowID in
            let block = threadBlocks[rowID]!
            return "vreqb:\(rowID):\(block.status):\(block.fields.count)"
        }.joined(separator: ",")
    }

    public func clear(threadID: UUID) {
        blocks[threadID] = nil
    }
}

/// 凭据卡行高输入（App 行高合成器消费的值形）：
/// 字段数＋状态——卡高只由版式件数定（字段行恒
/// 高、文案限行），不量文本
public struct VaultCardHeightInput: Equatable, Sendable {
    public let fieldCount: Int
    public let status: String

    public init(fieldCount: Int, status: String) {
        self.fieldCount = fieldCount
        self.status = status
    }

    /// 估高（与 VaultRequestCard 版式逐件同账：
    /// 外 padding 上下 spacingM×2＝32、头行（圆形
    /// 徽章 36＋标题/服务两行栈内间距）37、段间
    /// spacingM（16）；详情段：域名行 22＋spacingS
    /// （12）＋reason 段落（非空时 3 行×16≈54）；
    /// pending 态加 spacingM、每字段「标签＋输入
    /// 框」49（标签 12 + spacingMicro 2 + 输入框
    /// 文本 15 + 输入框纵边距 20）＋字段间 spacingM、
    /// 按钮行 39（文本 15 + padding 20 + 系统样式
    /// 额外边距 4）；终态加一行状态注记 33；status
    /// ＝"missing" 是标记兜底的「已处理或已过期」
    /// 灰行（非卡本体）、只一行 20）
    public var estimatedHeight: Double {
        if status == "missing" {
            return 20
        }
        // 外 padding 32 + 头行 37 + 段间 16
        let base = 32.0 + 37 + 16
        // 域名行 22
        let detailSection = 22.0

        if status != "pending" {
            // 终态：base + 详情段（域名行）+ 段间 16 + 状态注记 33
            return base + detailSection + 16 + 33
        }

        // pending 态：base + 详情段（域名行 + spacingS + reason 3 行）
        // + 段间 + 字段区 + 按钮行
        let reasonHeight = 54.0  // 3 行限行段落约 54
        let detailWithReason = detailSection + 12 + reasonHeight
        let fields = Double(max(fieldCount, 0))
        return base + detailWithReason + 16 + 39 + fields * 49
            + max(fields - 1, 0) * 16
    }
}
