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
final class DeliveryStore {
    static let shared = DeliveryStore()

    enum MetaResult: Equatable {
        case loaded(BridgeDelivery)
        case notFound
    }

    private(set) var metaResults: [String: MetaResult] = [:]
    @ObservationIgnored private var metaInFlight: Set<String> = []
    @ObservationIgnored private var imageBytes: [String: Data] = [:]
    @ObservationIgnored private var imageMisses: Set<String> = []
    @ObservationIgnored private var imageInFlight: Set<String> = []

    func metaResult(for id: String) -> MetaResult? {
        metaResults[id]
    }

    func loadMeta(
        id: String, client: OneDayBridgeClient, appState: AppState
    ) async {
        guard metaResults[id] == nil,
              !metaInFlight.contains(id),
              let config = appState.config
        else { return }
        metaInFlight.insert(id)
        defer { metaInFlight.remove(id) }
        do {
            let meta = try await client.delivery(config: config, id: id)
            metaResults[id] = .loaded(meta)
        } catch let error as OneDayBridgeError where error == .recordGone {
            metaResults[id] = .notFound
        } catch {
            // 网络/未连接类失败不落账：下次渲染重查
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
