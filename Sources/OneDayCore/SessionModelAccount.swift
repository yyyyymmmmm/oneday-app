import Foundation

/// 会话模型账的取键派生（§216 模型账合一，诊断题三）：
/// 同一会话的模型选择只许一本账——取键入参（server-
/// SessionID＋threadID）只许经本处派生，不许各面各算
/// 一份。病根（2026-11-14 真机实报）：胶囊按当前线
/// 程记录的 serverSessionID 取键、枢纽按 SideChat-
/// Store 持久化的 mainServerSessionID 取键，两份 id
/// 副本分叉即两账分叉（枢纽显 DeepSeek Flash、胶囊
/// 显 claude-sonnet-4-6）。
///
/// 派生口径（单一事实源＝线程实际绑定）：
/// - 线程已绑定服务端会话 → 以线程绑定为准；
/// - 钦定主线线程尚未绑定 → 回落 SideChatStore 的钦
///   定 id 副本（它只作派生缓存：链接落定时由链接层
///   强制与线程绑定对齐同值，不再是独立事实源）；
/// - 非主线线程、无线程 → 不回落（与 §153 既有口径
///   逐字同义，本函数只是把散在 ChatView 两处与枢纽
///   一处的表达式收成一个口）。
public enum SessionModelAccount {

    /// 通用派生（胶囊面）：入参为当前线程的绑定与钦
    /// 定判定；返回 AppState.sessionModelKey 的入参对。
    public static func accountIDs(
        threadServerSessionID: String?,
        threadID: UUID?,
        isMainThread: Bool,
        mainServerSessionID: String?
    ) -> (serverSessionID: String?, threadID: UUID?) {
        let serverID = threadServerSessionID
            ?? (isMainThread ? mainServerSessionID : nil)
        return (serverID, threadID)
    }

    /// 主线派生（枢纽面）：以钦定主线线程的实际绑定
    /// 为准——与胶囊在主线时经 accountIDs 得到的入参
    /// 对恒等（同键定理，SessionModelAccountTests 钉
    /// 死）；钦定线程不存在（尚未落位）时回落钦定 id
    /// 副本、threadID 为 nil（与胶囊无线程时落固定键
    /// 的旧口径有别：枢纽语境恒是主线，认钦定 id 键
    /// 才是它要读的那本账）。
    public static func mainlineAccountIDs(
        mainThreadServerSessionID: String?,
        mainThreadID: UUID?,
        mainServerSessionID: String?
    ) -> (serverSessionID: String?, threadID: UUID?) {
        guard let mainThreadID else {
            return (mainServerSessionID, nil)
        }
        return accountIDs(
            threadServerSessionID: mainThreadServerSessionID,
            threadID: mainThreadID,
            isMainThread: true,
            mainServerSessionID: mainServerSessionID
        )
    }
}

/// 服务端会话行 model 字段的定性与读数（§216 裁决）：
/// 该字段是服务端回执/化石值（会话创建时落下、或服
/// 务端侧最近一次改模的残留），**不是用户选择记
/// 录**——被收养的休眠老会话可冻结在已下线时代的
/// 值上（实查：收养旧主线冻结在 deepseek-flash，
/// 2026-11-10 DeepSeek 时代）。执行值只由本地账解
/// 析链决定（存量选择＞配置默认＞分组首项，Session-
/// ModelResolution 既有口径）；报告值只许进本读数做
/// 只读比对，产出「不一致」标记供留痕/呈现，**任
/// 何调用方不许据报告值改账**：主线 run 逐请求带出
/// 解析值、从不回写会话行字段，该字段对主线无执行
/// 效力；把它写成存量选择等于让化石真实改变后续
/// run 的执行模型（可把已欠费下线的通道重新设为
/// 执行模型）。
public enum SessionModelTruth {

    public struct Reading: Equatable, Sendable {
        /// 下一次 run 实际执行的解析值（与 Session-
        /// ModelResolution.resolve 同物）；分组未就
        /// 绪时为 nil（调用方走既有回落口径）
        public let execution: ChatModelChoice?
        /// 服务端报告值（归一后）与执行值不一致——
        /// 只读标记：供留痕与呈现说明，永不触发改账
        public let serverReportDisagrees: Bool

        public init(
            execution: ChatModelChoice?,
            serverReportDisagrees: Bool
        ) {
            self.execution = execution
            self.serverReportDisagrees = serverReportDisagrees
        }
    }

    public static func reading(
        stored: ChatModelChoice?,
        groups: [ChatModelGroup],
        serverDefault: ChatModelChoice?,
        serverReportedModel: String?
    ) -> Reading {
        let execution = SessionModelResolution.resolve(
            stored: stored, groups: groups,
            serverDefault: serverDefault
        )
        guard let reported = serverReportedModel,
              !reported.isEmpty,
              let execution else {
            return Reading(execution: execution, serverReportDisagrees: false)
        }
        let disagrees = ModelDisplayNames.canonicalID(for: reported)
            != ModelDisplayNames.canonicalID(for: execution.model)
        return Reading(
            execution: execution, serverReportDisagrees: disagrees
        )
    }
}
