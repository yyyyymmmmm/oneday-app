import Foundation
import OneDayCore

/// 登记交付的元数据与快照缓存（§146，规格 §7.2）：
/// 登记 meta 是登记时签发的快照、按 id 不可变，
/// 进程内永久缓存——同一 id 只取一次数；查无此
/// 号（404）同理落账（随机号不可能事后被签发）。
/// 网络/未连接类失败不落账，下次渲染重查，不把
/// 一次抖动钉成「查无」。status 的桥侧读时复核
/// 语义在本进程生命周期内以首次取数为准（进程
/// 重启即全量复核），属规格 §7.2 允许 App 决定
/// 的刷新口径。
/// 快照字节（thumb/cover）：命中直回；404（无
/// 此档）/410（文件已删）记 miss 不再重试（快照
/// 不可变、重试无新结果）；其余失败回 nil 不记
/// miss，下次可再试。
@MainActor
@Observable
/// §416 新鲜度普查豁免：按文件逐项懒取元数据，非名单全量拉取（判定表见 DESIGN §416）
final class DeliveryStore {
    static let shared = DeliveryStore()

    enum MetaResult: Equatable {
        case loaded(BridgeDelivery)
        case notFound
        case failed(String)
    }

    private(set) var metaResults: [String: MetaResult] = [:]
    private(set) var metaRevision: Int = 0
    private(set) var metaFailureCounts: [String: Int] = [:]
    @ObservationIgnored private var metaInFlight: Set<String> = []
    @ObservationIgnored private var imageBytes: [String: Data] = [:]
    @ObservationIgnored private var imageMisses: Set<String> = []
    @ObservationIgnored private var imageInFlight: Set<String> = []

    func metaResult(for id: String) -> MetaResult? {
        metaResults[id]
    }

    func metaFailureCount(for id: String) -> Int {
        metaFailureCounts[id] ?? 0
    }

    /// 预灌服务端消息投影内联下发的交付元数据，避免回补后二次查询
    func ingest(_ deliveries: [BridgeDelivery]) {
        guard !deliveries.isEmpty else { return }
        for delivery in deliveries {
            metaResults[delivery.id] = .loaded(delivery)
            metaFailureCounts.removeValue(forKey: delivery.id)
        }
        metaRevision &+= 1
    }

    /// 同步 peek（§329 行高合成用）：某档快照字节
    /// 是否已在进程缓存——只读不取数、不触发网络；
    /// 合成器据此判交付文件卡的封面形态（字节在
    /// 缓存＝视图 .task 同步命中、封面必达）
    func hasCachedImage(
        id: String, variant: DeliveryImageVariant
    ) -> Bool {
        imageBytes["\(id)/\(variant.rawValue)"] != nil
    }

    func loadMeta(
        id: String, client: OneDayBridgeClientProtocol, appState: AppState
    ) async {
        if case .loaded = metaResults[id] { return }
        if case .notFound = metaResults[id] { return }

        // 预算闸：失败计数 ≥5 停止重试
        if metaFailureCounts[id, default: 0] >= 5 { return }

        guard !metaInFlight.contains(id) else { return }
        guard let config = appState.config else {
            recordFailure(id: id, message: L10n.string("服务器未连接"))
            return
        }
        metaInFlight.insert(id)
        defer { metaInFlight.remove(id) }
        do {
            let meta = try await client.delivery(config: config, id: id)
            metaResults[id] = .loaded(meta)
            metaFailureCounts.removeValue(forKey: id)
            metaRevision &+= 1
        } catch let error as OneDayBridgeError where error == .recordGone {
            metaResults[id] = .notFound
            metaFailureCounts.removeValue(forKey: id)
            metaRevision &+= 1
        } catch let error as OneDayBridgeError {
            recordFailure(id: id, message: Self.failureMessage(for: error))
        } catch {
            recordFailure(id: id, message: L10n.string("网络请求失败"))
        }
    }

    private func recordFailure(id: String, message: String) {
        metaFailureCounts[id, default: 0] += 1
        metaResults[id] = .failed(message)
        metaRevision &+= 1
    }

    func retryMeta(
        id: String, client: OneDayBridgeClientProtocol, appState: AppState
    ) async {
        metaResults.removeValue(forKey: id)
        metaFailureCounts.removeValue(forKey: id)
        metaRevision &+= 1
        await loadMeta(id: id, client: client, appState: appState)
    }

    private static func failureMessage(for error: OneDayBridgeError) -> String {
        switch error {
        case .noKey:
            return L10n.string("缺少登录密钥")
        case .unauthorized:
            return L10n.string("登录密钥已失效")
        case .bridgeMissing:
            return L10n.string("服务端未开通交付接口")
        case .recordGone:
            return L10n.string("登记号不存在")
        case .failed(let message):
            return message
        }
    }

    /// 快照字节：key＝登记号＋档位；并发同键只发
    /// 一趟，在飞期间后到者回 nil（视图 task 会随
    /// 状态变化重入，完成方落账后自然补上）
    func image(
        id: String, variant: DeliveryImageVariant,
        client: OneDayBridgeClient, appState: AppState
    ) async -> Data? {
        let key = "\(id)/\(variant.rawValue)"
        if let hit = imageBytes[key] { return hit }
        if imageMisses.contains(key) { return nil }
        guard !imageInFlight.contains(key),
              let config = appState.config
        else { return nil }
        imageInFlight.insert(key)
        defer { imageInFlight.remove(key) }
        do {
            let data = try await client.deliveryImage(
                config: config, id: id, variant: variant
            )
            imageBytes[key] = data
            return data
        } catch let error as HermesError
            where error.isMissingSnapshot {
            imageMisses.insert(key)
            return nil
        } catch {
            return nil
        }
    }

    /// 原文件/原图字节（GET /deliveries/{id}/content）：
    /// 快照缺失或需要原文件时优先走桥鉴权通道获取
    func content(
        id: String, client: OneDayBridgeClient, appState: AppState
    ) async -> Data? {
        let key = "\(id)/content"
        if let hit = imageBytes[key] { return hit }
        if imageMisses.contains(key) { return nil }
        guard !imageInFlight.contains(key),
              let config = appState.config
        else { return nil }
        imageInFlight.insert(key)
        defer { imageInFlight.remove(key) }
        do {
            let data = try await client.deliveryContent(
                config: config, id: id
            )
            imageBytes[key] = data
            return data
        } catch let error as HermesError
            where error.isMissingSnapshot {
            imageMisses.insert(key)
            return nil
        } catch {
            return nil
        }
    }
}

private extension HermesError {
    /// 登记快照分型：404＝无此档快照、410＝文件
    /// 已删——都是「这档没有、别再试」的终局信号
    var isMissingSnapshot: Bool {
        guard case .unexpectedStatus(_, let status) = self
        else { return false }
        return status == 404 || status == 410
    }
}
