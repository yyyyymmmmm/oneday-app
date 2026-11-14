import OneDayCore
import Foundation
import Observation

/// 对话内授权流协调器（DESIGN §244，规格 permission-
/// system-redesign-20261113 §七）：授权卡的唯一持有者。
///
/// 两条进卡通道：
/// ①permission_ask（桥 P-2）——未决定态的调用被桥拦
///   下先问用户：本协调器出 primer 卡、等用户点按，
///   点「允许」才发那一次系统请求（铁律），现读结论
///   先回桥（granted/denied/parked）、后由宿主刷新；
/// ②permission_notice（桥 P-3）——已拒绝/开关层的调
///   用桥已停好车（park），捎信来让 App 出卡续办。
///
/// 卡持久化在本机（UserDefaults JSON），App 重启后
/// 未终态卡按 24h 口径翻过期或继续可续办——续办凭
/// 的是桥侧 park，同 token、同原参数。续办前若是同
/// 步副本类查询，先经 syncProvider 补一次同步
/// （P-5：授权与同步是同一件事的两面）。
///
/// §261 收敛：卡真相在桥侧——过期以桥 park 的
/// expiresAt 为单源（落卡即随载荷带入、回前台再经
/// park-state 读面对账），本地账本只是展示缓存；
/// ask 超时「未答」由桥显性记账、对账时翻卡标记，
/// 不与用户主动「先不」混同。
/// 同步补课执行口（§261 ④）：授权卡续办前补同步的
/// 唯一执行面。实现＝DeviceSyncController（见
/// DeviceSyncStore.swift 的遵循声明），来源恒 .chat
protocol PermissionSyncPerforming: AnyObject {
    func performPermissionSync(
        dataset: DeviceSyncDataset, config: ServerConfig
    ) async
}

@MainActor
@Observable
final class DevicePermissionCoordinator {
    /// 当前留着的卡（新卡在前）；视图层只读
    private(set) var cards: [PermissionCard] = []

    /// ask 的答复等待者：card id → 续体。桥在等答，
    /// 用户的点按经这里回桥；超时桥自会作罢（park 已
    /// 在桥侧），卡留本地走通道二续办
    @ObservationIgnored
    private var waiters: [String: CheckedContinuation<String, Never>] = [:]

    /// 续办在途集合（防重入：回前台扫描与手动点按并发）
    @ObservationIgnored
    private var resuming: Set<String> = []

    /// 同步补课执行口（§261 ④收编）：由此前 AppState
    /// 注入的无名闭包改为具名协议——协调器只认这一
    /// 口，AppState 启动时把 DeviceSyncController 挂
    /// 上即完，接线点与实现同名可查
    @ObservationIgnored
    weak var syncProvider: (any PermissionSyncPerforming)?

    private static let storageKey = "device.permissionCards.v1"

    init() {
        loadPersisted()
        sweepExpired()
    }

    // MARK: - 通道一：ask

    /// 桥问过来的授权请求：出卡＋等用户决定。返回给
    /// 轮询环的回执（result 是 decision 体；解析失败
    /// 回错误，桥按未答应处理、调用照样 park）
    func handleAsk(
        call: DeviceIncomingCall,
        host: DeviceSessionController
    ) async -> (JSONValue?, DeviceToolError?) {
        guard let ask = PermissionAskRequest.parse(
            arguments: call.arguments
        ) else {
            return (nil, .failed("这条授权请求看不懂，先放一放。"))
        }
        let dates = ask.cardDates(
            now: Date().timeIntervalSince1970
        )
        upsert(PermissionCard(
            id: ask.resumeToken, source: ask.source, tool: ask.tool,
            layer: .permission, isSyncQuery: false, phase: .primer,
            createdAt: dates.createdAt, expiresAt: dates.expiresAt
        ))
        let decision = await withCheckedContinuation { continuation in
            waiters[ask.resumeToken] = continuation
        }
        // 点按方已经把相位推到位（parked/declined 在点
        // 按时即定）；这里只补 granted/denied 的收尾，
        // 不覆盖用户已定的终态
        if decision == "granted" {
            transition(ask.resumeToken, from: [.asking, .primer]) { card in
                card.phase = .done
                card.resultSummary = "已授权，正在继续刚才的事。"
            }
        } else if decision == "denied" {
            transition(ask.resumeToken, from: [.asking, .primer]) { card in
                card.phase = .blocked
            }
        }
        return (.object(["decision": .string(decision)]), nil)
    }

    // MARK: - 通道二：notice

    /// 桥捎信：一条调用已 park，据卡点层出卡
    func ingestNotice(call: DeviceIncomingCall) {
        guard let notice = PermissionNotice.parse(
            arguments: call.arguments
        ) else { return }
        // 同 token 已有卡（如 ask 后又收到 notice）只
        // 更新相位层，不重复出卡
        let dates = notice.cardDates(
            now: Date().timeIntervalSince1970
        )
        upsert(PermissionCard(
            id: notice.resumeToken, source: notice.source,
            tool: notice.tool, layer: notice.layer,
            isSyncQuery: notice.isSyncQuery,
            phase: notice.initialPhase,
            createdAt: dates.createdAt, expiresAt: dates.expiresAt
        ))
    }

    // MARK: - 卡面动作

    /// 「允许」（primer）：未决定才发那一次系统请求
    /// （铁律——已决定态绝不重走请求回调），现读定
    /// 结论。有桥在等（ask）先回桥；没有（notice 卡/
    /// ask 已超时）本地定论后直接 resume
    func allow(cardID: String, host: DeviceSessionController) async {
        guard let card = card(cardID), card.phase == .primer else { return }
        setPhase(cardID, .asking)
        let before = DevicePermissions.currentStates()[card.source]
            ?? .notDetermined
        if before == .notDetermined {
            await host.performAccessRequest(for: card.source)
        }
        let fresh = DevicePermissions.currentStates()[card.source]
            ?? .notDetermined
        if let waiter = waiters.removeValue(forKey: cardID) {
            waiter.resume(
                returning: fresh.isUsable ? "granted" : "denied"
            )
            return
        }
        if fresh.isUsable {
            await resume(cardID: cardID, host: host)
        } else if fresh == .notDetermined {
            // 系统窗被划走没作决定：回 primer 再试
            setPhase(cardID, .primer)
        } else {
            setPhase(cardID, .blocked)
        }
    }

    /// 「先不」（primer）：回桥 parked，卡留着待续办
    func park(cardID: String) {
        guard card(cardID)?.phase == .primer else { return }
        setPhase(cardID, .parked)
        waiters.removeValue(forKey: cardID)?.resume(returning: "parked")
    }

    /// 「算了」（primer/blocked/switchOff/parked/failed）：
    /// 本地终态；桥侧 park 随 24h 过期自清，不必回桥
    func decline(cardID: String) {
        guard let card = card(cardID), !card.phase.isTerminal else { return }
        setPhase(cardID, .declined)
        waiters.removeValue(forKey: cardID)?.resume(returning: "parked")
    }

    /// parked 卡「继续」：回 primer 走本地授权路
    func reopen(cardID: String) {
        guard card(cardID)?.phase == .parked else { return }
        setPhase(cardID, .primer)
    }

    /// 「打开并继续」（switchOff）：开调用开关后直接
    /// 续办（开开关会触发重注册，桥 resume 自带等工具
    /// 重新 offered 的宽限）
    func enableSwitchAndResume(
        cardID: String, host: DeviceSessionController
    ) async {
        guard let card = card(cardID), card.phase == .switchOff else {
            return
        }
        host.setAgentCallEnabled(card.source, true)
        await resume(cardID: cardID, host: host)
    }

    /// 续办本体：同步副本类先补同步，再 POST resume；
    /// 会话刚回前台未稳时 offline 有限重试（3 次）
    func resume(cardID: String, host: DeviceSessionController) async {
        guard let card = card(cardID), !card.phase.isTerminal,
              !resuming.contains(cardID) else { return }
        resuming.insert(cardID)
        defer { resuming.remove(cardID) }
        setPhase(cardID, .resuming) { $0.failureNote = nil }
        if card.isSyncQuery,
           let dataset = DeviceSyncDataset.fromSource(card.source),
           let config = host.activeConfig,
           let syncProvider {
            await syncProvider.performPermissionSync(
                dataset: dataset, config: config
            )
        }
        for attempt in 0..<3 {
            do {
                let outcome = try await host.resumeParkedCall(
                    token: cardID
                )
                switch outcome {
                case .succeeded(let result):
                    setPhase(cardID, .done) {
                        $0.resultSummary = PermissionResultSummary.line(
                            for: result
                        )
                    }
                    return
                case .tokenGone:
                    setPhase(cardID, .expired)
                    return
                case .offline:
                    if attempt < 2 {
                        try? await Task.sleep(
                            for: .milliseconds(2000)
                        )
                        continue
                    }
                    setPhase(cardID, .failed) {
                        $0.failureNote = "手机和服务器刚没接上，等一会儿点「再试一次」。"
                    }
                    return
                case .failed(let code, let message):
                    setPhase(cardID, .failed) {
                        $0.failureNote = code == "sync_copy_empty"
                            ? "数据还没同步好，等一会儿点「再试一次」。"
                            : (message ?? "这次没办成，点「再试一次」再试试。")
                    }
                    return
                }
            } catch {
                setPhase(cardID, .failed) {
                    $0.failureNote = "续办没送出去，检查连接后点「再试一次」。"
                }
                return
            }
        }
    }

    /// 桥侧对账（§261 ①③）：逐张未终态卡问桥 park
    /// 还在不在——桥说没了翻 expired、桥的过期时刻
    /// 覆盖本地推算、桥记了「未答」的卡翻 parked 并
    /// 打标记（与用户主动「先不」在卡面上分开说）。
    /// 读面不可达（旧桥无端点/离线/回执不可信）时
    /// host 回 nil、整轮跳过该卡，本地缓存兜底，不
    /// 拿不确定当真相
    func reconcileParks(host: DeviceSessionController) async {
        for card in cards where !card.phase.isTerminal {
            guard let park = await host.parkState(token: card.id)
            else { continue }
            switch PermissionParkReconciler.decision(
                card: card, park: park,
                now: Date().timeIntervalSince1970
            ) {
            case .keep:
                continue
            case .expire:
                waiters.removeValue(forKey: card.id)?.resume(
                    returning: "parked"
                )
                setPhase(card.id, .expired)
            case .adopt(let park):
                adoptPark(cardID: card.id, park: park)
            }
        }
    }

    private func adoptPark(
        cardID: String, park: PermissionParkState
    ) {
        guard let index = cards.firstIndex(where: { $0.id == cardID })
        else { return }
        var changed = false
        if let expiresAt = park.expiresAt,
           cards[index].expiresAt != expiresAt {
            cards[index].expiresAt = expiresAt
            changed = true
        }
        // 桥记了「未答」而卡还停在 primer：那一轮 ask
        // 桥侧已收场，本地等答续体一并收（回 parked，
        // 与桥侧口径一致），卡翻 parked＋显性标记
        if park.askOutcome == .unanswered,
           cards[index].phase == .primer {
            cards[index].phase = .parked
            cards[index].askUnanswered = true
            changed = true
            waiters.removeValue(forKey: cardID)?.resume(
                returning: "parked"
            )
        }
        if changed { persist() }
    }

    /// 回前台扫描：blocked/switchOff 卡的卡点若已清
    ///（用户在设置里改完回来），自动续办——不让人再
    /// 点一遍（规格车道二「回来能续上」）
    func checkResumes(host: DeviceSessionController) async {
        sweepExpired()
        await reconcileParks(host: host)
        for card in cards {
            switch card.phase {
            case .blocked:
                let state = DevicePermissions.currentStates()[card.source]
                    ?? .notDetermined
                if state.isUsable {
                    await resume(cardID: card.id, host: host)
                }
            case .switchOff:
                if host.agentCallEnabled[card.source] == true {
                    await resume(cardID: card.id, host: host)
                }
            default:
                break
            }
        }
    }

    /// 收起终态卡
    func dismiss(cardID: String) {
        cards.removeAll { $0.id == cardID }
        persist()
    }

    /// 有没有未终态的卡（聊天区挂载判定用）
    var hasVisibleCards: Bool {
        cards.contains { !$0.phase.isTerminal }
            || cards.contains { $0.phase == .done }
    }

    // MARK: - 账本

    func card(_ id: String) -> PermissionCard? {
        cards.first { $0.id == id }
    }

    private func upsert(_ card: PermissionCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            // 已有卡只在非终态时接受新相位（迟到 notice
            // 不许把已办完的卡打回 blocked）；过期时刻
            // 随新载荷对齐桥侧（§261 ②单源）
            if !cards[index].phase.isTerminal {
                cards[index].phase = card.phase
                cards[index].layer = card.layer
                cards[index].expiresAt = card.expiresAt
            }
        } else {
            cards.insert(card, at: 0)
        }
        persist()
    }

    private func setPhase(
        _ id: String, _ phase: PermissionCardPhase,
        mutate: (inout PermissionCard) -> Void = { _ in }
    ) {
        guard let index = cards.firstIndex(where: { $0.id == id })
        else { return }
        cards[index].phase = phase
        mutate(&cards[index])
        persist()
    }

    private func transition(
        _ id: String, from phases: [PermissionCardPhase],
        mutate: (inout PermissionCard) -> Void
    ) {
        guard let index = cards.firstIndex(where: { $0.id == id }),
              phases.contains(cards[index].phase) else { return }
        mutate(&cards[index])
        persist()
    }

    private func sweepExpired() {
        let now = Date().timeIntervalSince1970
        var changed = false
        for index in cards.indices where cards[index].isExpired(at: now) {
            cards[index].phase = .expired
            changed = true
        }
        if changed { persist() }
    }

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(
            forKey: Self.storageKey
        ),
        let decoded = try? JSONDecoder().decode(
            [PermissionCard].self, from: data
        ) else { return }
        cards = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
