import Foundation

/// 锚点点达的本地解析（§165，规格 §4.4）：枢纽记录行与
/// 通知回执点按时，先在本机找这条记录的锚——找的顺序
/// 是证据强度序，任一环缺失即如实降级，**不许拿标题/
/// 时间等弱信号猜**：
/// 1. 已物化的锚定条目（ChatEntry.approvalKey 命中）：
///    落锚在物化时已冻结，这是最硬的证据；
/// 2. 记录自带的 anchor.sessionId 恰有本地线程绑定：
///    还没物化（如刚拉到、物化未跑）也能直达该对话，
///    但**不定位到卡**——条目尚不存在，只跳对话；
/// 3. 都没有 → 无锚点落点，调用方走现行降级（枢纽段
///    聚焦/只达段）。
public enum ApprovalAnchorNavigation {
    public enum Target: Equatable, Sendable {
        /// 切到该线程并滚动定位到锚定行（行底色点亮）
        case entry(threadID: UUID, approvalKey: String)
        /// 只切到该线程，不定位（条目未物化）
        case threadOnly(threadID: UUID)
        case none
    }

    /// 已物化条目索引：线程 id × 其内全部锚定键
    public struct MaterializedIndex: Equatable, Sendable {
        public let threadIDByKey: [String: UUID]
        /// 锚定条目 id（滚动定位与点亮用）：键 → 条目 id
        public let entryIDByKey: [String: UUID]

        public init(
            threadIDByKey: [String: UUID],
            entryIDByKey: [String: UUID]
        ) {
            self.threadIDByKey = threadIDByKey
            self.entryIDByKey = entryIDByKey
        }
    }

    public static func target(
        subsystem: WriteGateSubsystem, recordID: String,
        anchorSessionID: String?,
        threadIDByServerSessionID: [String: UUID],
        materialized: MaterializedIndex
    ) -> Target {
        let key = ApprovalAnchor.key(
            subsystem: subsystem, id: recordID
        )
        if let threadID = materialized.threadIDByKey[key] {
            return .entry(threadID: threadID, approvalKey: key)
        }
        if let sessionID = anchorSessionID, !sessionID.isEmpty,
           let threadID = threadIDByServerSessionID[sessionID] {
            return .threadOnly(threadID: threadID)
        }
        return .none
    }
}

/// 通知落点的锚点扩展解析（§165，规格 §4.4）：审批回执
/// 通知带 refId 时先查本机锚——命中已物化条目 → 新落点
/// approvalAnchor（切线程＋定位）；只命中线程 → 只切线
/// 程不定位；未命中 → 现行 approvalDecision/approval-
/// Home 不变（枢纽段聚焦）。非审批通知不走本解析。
public enum ApprovalNotificationRouting {
    public static func destination(
        notification: OverviewNotification,
        anchorTarget: ApprovalAnchorNavigation.Target
    ) -> NotificationDestination {
        guard notification.isDecisionReceipt else {
            return NotificationDestination.resolve(notification)
        }
        switch anchorTarget {
        case .entry(let threadID, let approvalKey):
            return .approvalAnchor(
                threadID: threadID, approvalKey: approvalKey
            )
        case .threadOnly(let threadID):
            return .approvalThread(threadID: threadID)
        case .none:
            return NotificationDestination.resolve(notification)
        }
    }
}
