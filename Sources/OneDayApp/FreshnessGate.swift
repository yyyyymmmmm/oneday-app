import Foundation

/// 共用新鲜度门（§367，缓存 C1 地基）：把 CronStore
/// .loadIfNeeded 的范式抽成可复用值件——CronStore 只
/// 记「已载＋配置键」，本件再加一维「载了多久」：已
/// 成功载过、配置键（服务器标识）没变、距上次成功
/// 载入未满 TTL，三者齐备才算新鲜，读触发可直接用
/// 已载数据、零请求；缺一即不新鲜，照常走全量 load。
///
/// 落账纪律（写死）：只许成功路径 stamp——未连接/
/// 拉取失败不落账，不许拿旧时刻冒充新时刻；写后回
/// 读主名单成功同样 stamp（回读即全量现值、按构造
/// 新鲜），但回读本身不经本门判定（正确性口径，
/// §367.4）。
struct FreshnessGate: Equatable {
    /// 名单类标准新鲜期（§367.3 定档）：慢变名单＋
    /// 多口整表的高代价型，对齐伴生探测 60s 先例取
    /// 上档；身份 30s 是单口小数据口径、不适用名单面
    static let standardListTTL: TimeInterval = 60

    /// 本面的新鲜期（秒）
    let ttl: TimeInterval
    /// 上次成功载入时刻（从未成功载过为 nil）
    private(set) var lastLoadedAt: Date?
    /// 上次成功载入时的配置键（服务器 baseString）
    private(set) var loadedConfigKey: String?

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    /// 读触发前的判定：仍新鲜则整轮拉取可跳过
    func isFresh(configKey: String?, now: Date) -> Bool {
        guard let lastLoadedAt, let loadedConfigKey,
              let configKey, loadedConfigKey == configKey
        else { return false }
        return now.timeIntervalSince(lastLoadedAt) < ttl
    }

    /// 成功载入后落账（时刻与配置键成对回写）
    mutating func stamp(configKey: String?, now: Date) {
        lastLoadedAt = now
        loadedConfigKey = configKey
    }
}
