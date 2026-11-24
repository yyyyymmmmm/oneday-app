import Foundation
import Observation
import UIKit

/// 量测工单（§331）：主线程组装（facet＋条目快
/// 照＋环境，全部值），后台队列执行 measure 得
/// 行高、按 memoKey 回填整行备忘缓存。@unchecked
/// Sendable 的依据：载荷是组装后不可变的值快照
/// （与 §251 LayoutAttributedBox 同口径），
/// measure 只读快照、只写线程安全缓存（NSCache/
/// ParseMemoBox 家族）与 §251 量测池的每线栈；
/// 执行者唯一由量测台认领盒保证（§430 包 3：
/// 队列与 measureNow 任一时刻只一执行者持单），
/// 闭包本体不被并发重入——背书自此完整
struct ChatNativeRowMeasureJob: @unchecked Sendable {
    let memoKey: String
    let rowKey: String
    let measure: () -> CGFloat
}

/// 后台量测台（§331，0.50.70 热修题 3 根治）
///
/// 大厂聊天列表量测的全件形态在本仓的落点（微
/// 信预排版/Signal 静态量测管线同构）：行高不
/// 在主线程 body 求值里现算——ChatView 构建行
/// 时先查整行备忘缓存（§330 缓存层、命中直用
/// 确定高）；未命中则组装工单投本台，后台串行
/// 队列以 facet 快照整行量测（文本量测走 §251
/// 量测池的每线 TextKit 栈），结果回填缓存并
/// 发发布信号，ChatView 随之以新高重喂列表
/// （控制器高度-only 落写、不重配 cell、不扰
/// 手势）。打开会话即全表投单＝预排版：用户滚
/// 到某行前，该行高多半已就绪。
///
/// 纪律：
/// - 同一 memoKey 同时只许一单在飞（resolve 的
///   needsJob 判定＋collect 双重去重）；修订一
///   变 memoKey 即变、新单另投，旧单结果只回填
///   自己键的缓存格，不会串到新行；
/// - 未就绪行的当趟高＝该行上次用高（lastKnown，
///   跨修订沿用）或合成器兜底高——估计→确定的
///   修正恒走高度-only 路径，与题 1 在途保护正
///   交（重配才伤手势、改高不伤）；
/// - 发布信号合并（40ms 窗）：冷开长会话几百
///   单陆续完成不逐单触发重渲；
/// - 单执行者（§430 包 3）：同一工单任一时刻
///   只许一个执行者——队列块与 measureNow 执
///   行前各经认领盒认领，认领失败不许碰闭包；
///   已量完的事实以行高缓存为凭据，后到执行者
///   查缓存复用、不二次执行；
/// - 队列串行：量测次序＝投单次序的逆序（趟末
///   flushCollected 按行序逆序投递——最新行靠
///   底、用户视线所在，先量先就绪）
/// - 台账 190（上滑根治）：投单次序改方向感知
///   ——resolve 调用序即行序（ChatView 每趟按行
///   序逐行 resolve），本台据此自建行序账；顶可
///   见行锚（noteTopVisible）向上移＝上滑趋势
///   时，flush 改按「锚上方最近行优先」投单，
///   不再让上滑方向排在队尾。另设 measureNow
///   就地量测口：将入视口而未就绪的行在布局提
///   供者问高时同步量出确定高（学 Telegram 无
///   估算高——120 兜底只留给永不入视口的行）；
///   积压计数入静态账盒供诊断面回读
/// 工单执行认领盒（§430 包 3）：同一 memoKey 任
/// 一时刻只许一个执行者持有——量测台队列块与
/// measureNow 在跑工单闭包前都须先认领，认领失
/// 败即不许碰该闭包。认领是执行期瞬时互斥（存
/// 缓存后即释放）：「已量完」的事实由行高缓存
/// 本身作凭据——持认领者先查缓存再执行，后到
/// 的认领成功时缓存必已落、查缓存即复用，不会
/// 二次执行。盒本体锁护、与 BacklogBox 同式
private final class RowMeasureExecutionClaims:
    @unchecked Sendable {
    private let lock = NSLock()
    private var claimed: Set<String> = []

    /// 认领成功＝调用方是当前唯一执行者
    func tryClaim(_ memoKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed.contains(memoKey)
        else { return false }
        claimed.insert(memoKey)
        return true
    }

    func release(_ memoKey: String) {
        lock.lock()
        claimed.remove(memoKey)
        lock.unlock()
    }
}

@MainActor
@Observable
final class ChatNativeRowMeasureDesk {
    /// 发布代次：任一工单完成且其行高与当趟用高
    /// 不同即合并 bump 一次——ChatView 读此值入
    /// body 依赖、bump 即重喂行高
    private(set) var publishedRevision = 0

    @ObservationIgnored
    private let queue = DispatchQueue(
        label: "site.didichou.oneday.rowmeasure",
        qos: .userInitiated
    )
    @ObservationIgnored
    /// §430 单执行者认领盒：队列块（后台线程）
    /// 与 measureNow（主线程）执行工单前各认领，
    /// 盒本体线程安全（与 BacklogBox 同式）
    @ObservationIgnored
    private let executionClaims =
        RowMeasureExecutionClaims()
    @ObservationIgnored
    private var inFlight: Set<String> = []
    @ObservationIgnored
    private var collected: [ChatNativeRowMeasureJob] = []
    @ObservationIgnored
    private var collectedKeys: Set<String> = []
    @ObservationIgnored
    private var lastKnownByRow: [String: CGFloat] = [:]
    @ObservationIgnored
    private var publishTask: Task<Void, Never>?

    /// §422 待落写登记：resolve 命中时登记的清
    /// 账与 lastKnown 回写，flushCollected 开头
    /// 在求值期外统一执行
    @ObservationIgnored
    private var pendingSettlements:
        [PendingSettlement] = []

    private struct PendingSettlement {
        let rowKey: String
        let memoKey: String
        let height: CGFloat
    }

    /// 同步读口（body 求值内）：缓存命中回确定
    /// 高（清账与 lastKnown 回写只登记待落写、
    /// 趟末 flushCollected 开头执行——§422 纯读
    /// 化，求值期零字典写入、零工单析构）；未命
    /// 中回 lastKnown/兜底高，needsJob 报是否该
    /// 为本行组装工单（在飞/已收集的不重复组装
    /// ——组装要快照 facet、不许白费）
    func resolve(
        memoKey: String, rowKey: String,
        fallback: CGFloat
    ) -> (
        height: CGFloat, needsJob: Bool, isExact: Bool
    ) {
        noteResolveOrder(rowKey)
        if let hit = ChatNativeRowHeightComposer
            .cachedRowHeight(forKey: memoKey) {
            // §422（包 2，resolve 纯读化）：命中即
            // 该行工单使命完成，但清账（双留账置
            // nil）与 lastKnown 回写不在求值期当
            // 场执行——旧形态在此写 jobsByRowKey
            // 置 nil、Dictionary.subscript.setter
            // 内同步析构工单，闭包析构链 swift_
            // release 撞已释放内存（204455.ips
            // 崩②）。改为只登记待落写，由 flush-
            // Collected 开头在求值期外统一执行
            pendingSettlements.append(
                PendingSettlement(
                    rowKey: rowKey, memoKey: memoKey,
                    height: hit
                )
            )
            return (hit, false, true)
        }
        let needsJob = !inFlight.contains(memoKey)
            && !collectedKeys.contains(memoKey)
        return (
            lastKnownByRow[rowKey] ?? fallback, needsJob,
            false
        )
    }

    /// 收集本趟工单（趟末 flushCollected 统一投
    /// 递；同键重复收集只留一单）
    func collect(_ job: ChatNativeRowMeasureJob) {
        guard !inFlight.contains(job.memoKey),
              !collectedKeys.contains(job.memoKey)
        else { return }
        collected.append(job)
        collectedKeys.insert(job.memoKey)
        jobsByRowKey[job.rowKey] = job
        memoKeyByRowKey[job.rowKey] = job.memoKey
        noteBacklog()
    }

    /// 趟末落写（§422）：执行 resolve 登记的待
    /// 落写——lastKnown 回写无条件（与旧形态命
    /// 中即写同值、只移时机）；双留账清账按命
    /// 中键守卫：同行其后已收集新修订工单（键
    /// 不同）不误清。工单析构自此只发生在求值
    /// 期之外（此处与 finish/measureNow 入口）
    private func applyPendingSettlements() {
        guard !pendingSettlements.isEmpty
        else { return }
        let settlements = pendingSettlements
        pendingSettlements = []
        for item in settlements {
            lastKnownByRow[item.rowKey] = item.height
            if jobsByRowKey[item.rowKey]?.memoKey
                == item.memoKey {
                jobsByRowKey[item.rowKey] = nil
            }
            if memoKeyByRowKey[item.rowKey]
                == item.memoKey {
                memoKeyByRowKey[item.rowKey] = nil
            }
        }
    }

    /// 趟末投递：默认逆序投单（最新行先量）；上
    /// 滑趋势在场时按锚距投单（锚上方最近行先
    /// 量、锚下方次之），清空收集箱。投递前先以
    /// 本趟 resolve 序重建行序账；开头先执行
    /// §422 待落写（趟末收尾段、求值期外）
    func flushCollected() {
        applyPendingSettlements()
        rebuildRowIndex()
        let jobs = orderedForDispatch(collected)
        collected = []
        collectedKeys = []
        for job in jobs {
            guard !inFlight.contains(job.memoKey)
            else { continue }
            inFlight.insert(job.memoKey)
            let claims = executionClaims
            queue.async { [weak self] in
                // §430 单执行者：先认领再碰闭包。
                // 认领失败＝measureNow 正在主线程
                // 直执同一工单——不许并发同跑，等
                // 其结果落缓存后复用对账（见
                // reuseClaimBusyResult）
                guard claims.tryClaim(job.memoKey)
                else {
                    self?.reuseClaimBusyResult(job)
                    return
                }
                // 持认领先查缓存：measureNow 已先
                // 行量完并释放认领时缓存必已落，
                // 复用其值、不二次执行
                let height: CGFloat
                if let cached = ChatNativeRowHeightComposer
                    .cachedRowHeight(forKey: job.memoKey) {
                    height = cached
                } else {
                    let measured = job.measure()
                    ChatNativeRowHeightComposer
                        .storeRowHeight(
                            measured, forKey: job.memoKey
                        )
                    height = measured
                }
                claims.release(job.memoKey)
                let memoKey = job.memoKey
                let rowKey = job.rowKey
                Task { @MainActor [weak self] in
                    self?.finish(
                        memoKey: memoKey, rowKey: rowKey,
                        height: height
                    )
                }
            }
        }
    }

    /// §430 队列侧复用路（认领失败时）：measureNow
    /// 正在主线程直执同一工单，其结果毫秒级落缓存
    /// ——后台轮询缓存，落了即复用其值走 finish 对
    /// 账；超时仍无值（认领者异常未落缓存的理论兜
    /// 底）放弃本趟、清在飞账，该行经下一趟 resolve
    /// 重新投单，不许把在飞账烂尾在账上
    nonisolated private func reuseClaimBusyResult(
        _ job: ChatNativeRowMeasureJob
    ) {
        var reused: CGFloat?
        for _ in 0..<400 {
            if let cached = ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: job.memoKey) {
                reused = cached
                break
            }
            usleep(5_000)
        }
        let memoKey = job.memoKey
        let rowKey = job.rowKey
        Task { @MainActor [weak self] in
            if let reused {
                self?.finish(
                    memoKey: memoKey, rowKey: rowKey,
                    height: reused
                )
            } else {
                self?.abandonInFlight(memoKey: memoKey)
            }
        }
    }

    /// §430 理论兜底：认领者未落缓存时清在飞账
    /// （jobsByRowKey 留账保留——后续 measureNow
    /// 仍可认领直执，resolve 也会重新报 needsJob）
    private func abandonInFlight(memoKey: String) {
        inFlight.remove(memoKey)
        noteBacklog()
    }

    private func finish(
        memoKey: String, rowKey: String,
        height: CGFloat
    ) {
        inFlight.remove(memoKey)
        // 工单本体留账清（已完成、不必再就地重
        // 跑）；memoKey 留账保留——重喂到达前布
        // 局侧 measureNow 仍可经它回缓存确定值，
        // 待 resolve 命中时一并清
        jobsByRowKey[rowKey] = nil
        ChatMeasureDeskBacklog.noteFinished()
        noteBacklog()
        guard lastKnownByRow[rowKey] != height
        else { return }
        lastKnownByRow[rowKey] = height
        schedulePublish()
    }

    // MARK: - 台账 190：方向感知／就地量测／积压账

    /// 就地量测留账：已收集/在飞工单按行键留存，
    /// measureNow 据此同步执行；resolve 命中或
    /// 工单完成后清
    @ObservationIgnored
    private var jobsByRowKey:
        [String: ChatNativeRowMeasureJob] = [:]
    @ObservationIgnored
    private var memoKeyByRowKey: [String: String] = [:]
    /// 行序账：resolve 调用序（＝喂入行序）逐趟
    /// 累积、flush 时折成行键→序映射
    @ObservationIgnored
    private var resolveOrderSeen: [String] = []
    @ObservationIgnored
    private var resolveOrderSet: Set<String> = []
    @ObservationIgnored
    private var rowIndexByKey: [String: Int] = [:]
    /// 顶可见锚与上滑趋势（noteTopVisible 维护）
    @ObservationIgnored
    private var anchorRowKey: String?
    @ObservationIgnored
    private var lastAnchorIndex: Int?
    @ObservationIgnored
    private var trendUp = false

    private func noteResolveOrder(_ rowKey: String) {
        guard !resolveOrderSet.contains(rowKey)
        else { return }
        resolveOrderSet.insert(rowKey)
        resolveOrderSeen.append(rowKey)
    }

    private func rebuildRowIndex() {
        guard !resolveOrderSeen.isEmpty else { return }
        for (index, key) in resolveOrderSeen
            .enumerated() {
            rowIndexByKey[key] = index
        }
        resolveOrderSeen = []
        resolveOrderSet = []
    }

    /// 顶可见行上报（ChatView 原生面回调）：锚序
    /// 下移（顶可见行变旧）＝上滑趋势；上滑期间
    /// flush 按锚距投单。锚行不在行序账内（直播
    /// 行等不经 resolve 的行）时不更新趋势
    func noteTopVisible(rowKey: String) {
        anchorRowKey = rowKey
        guard let index = rowIndexByKey[rowKey]
        else { return }
        if let last = lastAnchorIndex, index != last {
            trendUp = index < last
        }
        lastAnchorIndex = index
    }

    /// 投单次序：无上滑趋势＝逆序（最新先量，现
    /// 行口径）；上滑趋势＋锚在账＝锚上方行按距
    /// 锚近者先、锚下方行按序次之、无序行垫底
    private func orderedForDispatch(
        _ jobs: [ChatNativeRowMeasureJob]
    ) -> [ChatNativeRowMeasureJob] {
        guard trendUp,
              let anchor = anchorRowKey,
              let anchorIndex = rowIndexByKey[anchor]
        else { return Array(jobs.reversed()) }
        func index(of job: ChatNativeRowMeasureJob)
            -> Int? {
            rowIndexByKey[job.rowKey]
        }
        let above = jobs
            .filter { (index(of: $0) ?? .max) <= anchorIndex }
            .sorted {
                (index(of: $0) ?? .max)
                    > (index(of: $1) ?? .max)
            }
        let below = jobs
            .filter { (index(of: $0) ?? .max) > anchorIndex }
            .sorted {
                (index(of: $0) ?? .max)
                    < (index(of: $1) ?? .max)
            }
        return above + below
    }

    /// 就地量测（台账 190②）：行将入视口而当趟
    /// 高仍非确定值时，布局侧经 ChatView 闭包调
    /// 本口同步执行该行工单——单行量测毫秒级、
    /// 入屏前付清，不让估算高在屏上跳。单执行
    /// 者纪律（§430 包 3）：直执前经认领盒认领，
    /// 工单正在量测台队列执行时认领失败——回
    /// nil（布局侧保留当趟喂入高），不许在主线
    /// 程并发重跑同一闭包，队列完成自有 finish
    /// 的高度-only 修正把确定高送到；工单已完
    /// 成则回缓存确定值；无工单无缓存回 nil
    func measureNow(rowKey: String) -> CGFloat? {
        guard let job = jobsByRowKey[rowKey] else {
            guard let memoKey = memoKeyByRowKey[rowKey]
            else { return nil }
            return ChatNativeRowHeightComposer
                .cachedRowHeight(forKey: memoKey)
        }
        // 工单已在后台完成（缓存已落、留账未清）
        // 时直回缓存值，不重跑量测
        if let cached = ChatNativeRowHeightComposer
            .cachedRowHeight(forKey: job.memoKey) {
            jobsByRowKey[rowKey] = nil
            return cached
        }
        // §430 单执行者：认领失败＝队列正在执行
        // 同一工单，回 nil 等 finish 修正（见头注）
        guard executionClaims.tryClaim(job.memoKey)
        else { return nil }
        let height = job.measure()
        ChatNativeRowHeightComposer.storeRowHeight(
            height, forKey: job.memoKey
        )
        executionClaims.release(job.memoKey)
        if let position = collected.firstIndex(
            where: { $0.memoKey == job.memoKey }
        ) {
            collected.remove(at: position)
            collectedKeys.remove(job.memoKey)
        }
        jobsByRowKey[rowKey] = nil
        ChatMeasureDeskBacklog.noteSyncMeasured()
        noteBacklog()
        if lastKnownByRow[rowKey] != height {
            lastKnownByRow[rowKey] = height
            schedulePublish()
        }
        return height
    }

    /// 积压账回写（静态账盒：诊断面无实例可读，
    /// 与 ChatLagProbe 计数盒同式）
    private func noteBacklog() {
        ChatMeasureDeskBacklog.notePending(
            collected: collected.count,
            inFlight: inFlight.count
        )
    }

    /// 诊断面读口（台账 190⑤）：量测台积压一行
    static func backlogLine() -> String {
        ChatMeasureDeskBacklog.line()
    }

    /// 发布合并：40ms 窗内多次完成只 bump 一次
    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: 40_000_000
            )
            guard let self else { return }
            self.publishTask = nil
            self.publishedRevision += 1
        }
    }
}

/// 量测台积压账盒（台账 190⑤）：静态计数——收
/// 集/在飞积压（最近一台量测台的回写，多台并存
/// 时后写者为准）、完成总数、就地量测次数。诊
/// 断面（ChatDiagnosticsView）经量测台的静态读
/// 口回读，生产路径只记账、无行为影响（与
/// ChatLagProbe 计数盒同式）
enum ChatMeasureDeskBacklog {
    private static let box = BacklogBox()

    static func notePending(
        collected: Int, inFlight: Int
    ) {
        box.notePending(
            collected: collected, inFlight: inFlight
        )
    }

    static func noteFinished() { box.noteFinished() }
    static func noteSyncMeasured() {
        box.noteSyncMeasured()
    }

    static func line() -> String { box.line() }

    /// 测试读口：清账
    static func reset() { box.reset() }
}

private final class BacklogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingCollected = 0
    private var pendingInFlight = 0
    private var finishedTotal = 0
    private var syncMeasuredTotal = 0

    func notePending(collected: Int, inFlight: Int) {
        lock.lock()
        pendingCollected = collected
        pendingInFlight = inFlight
        lock.unlock()
    }

    func noteFinished() {
        lock.lock()
        finishedTotal += 1
        lock.unlock()
    }

    func noteSyncMeasured() {
        lock.lock()
        syncMeasuredTotal += 1
        lock.unlock()
    }

    func line() -> String {
        lock.lock()
        defer { lock.unlock() }
        return "积压 \(pendingCollected + pendingInFlight)"
            + "（排队 \(pendingCollected)／在飞 \(pendingInFlight)）"
            + "·已量 \(finishedTotal)·就地量测 \(syncMeasuredTotal)"
    }

    func reset() {
        lock.lock()
        pendingCollected = 0
        pendingInFlight = 0
        finishedTotal = 0
        syncMeasuredTotal = 0
        lock.unlock()
    }
}
