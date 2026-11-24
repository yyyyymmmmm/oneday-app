import Foundation
import OneDayCore
import SwiftUI

/// 线程待发引用持有者（§305，横扫 A-03 附带收口）：
/// 两张按线程寻址的待发引用表原挂 AppState 顶层、混
/// 在导航信箱群里——它们是草稿数据、不是导航（横扫
/// A-03 处置明示不随路由走），自此独立持有：写入方
/// （动态/点子/文件面）在落点决定的同一动作内直写，
/// ChatView 按 currentThreadID 派生呈现。不经草稿账
/// （setDraft 只许亲笔，见 SideChatStore 隔离铁律）。
/// 只活在内存：进程死亡即亡，与引用本身的生命周期
/// 一致（引用不落盘恢复，规格 §3.3）
@MainActor
@Observable
final class PendingThreadQuotes {
    /// 动态讨论待发引用（§208 立制、§210 改挂）：与
    /// Telegram 草稿按 peer 存、Stream composer 长在
    /// channel 上的主流形态同构（§210 定因，见
    /// discuss-quote-attach-report-20261113）
    var feedQuotesByThread: [UUID: FeedPostQuote] = [:]
    /// 点子／文件待发引用（§219）：与上表同型。载荷
    /// 是 SourceQuote 统一枚举，本表只承载 .idea／
    /// .file 两族（.feed 族沿上表 §210 既有通道，不
    /// 在此重复存放）；槽位单一在场、后入覆盖的互
    /// 斥由 ChatView 呈现侧收口函数对两表交叉清理
    /// 兑现
    var sourceQuotesByThread: [UUID: SourceQuote] = [:]
}
