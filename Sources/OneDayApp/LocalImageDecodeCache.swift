import UIKit

/// §199（2026-11-13）本地图解码缓存
///
/// 出处与定因：一层审计 §2.3——气泡 body 求值路径
/// 里逐张 `UIImage(data:)` 同步解码、无任何缓存，
/// 含图会话滚动/流式时每遍 body 全额重解码。本缓
/// 存是本地图的唯一解码口：同（条目，图序，数据）
/// 只解一次，其后命中直取已解码图。
///
/// 键口径：条目 id＋图序＋数据字节数。条目的图数
/// 据落盘后不可变（ChatEntry.imageDatasData 写入
/// 即定型，无原地换图路径），三因子足够定址；字
/// 节数入键防同条目重发图时的长度变异串图。成本
/// 按数据字节计、总量封顶 64MB，内存压力下由
/// NSCache 自行淘汰（淘汰只伤性能不伤正确性）。
/// 解码失败不入缓存（与旧口径同：坏图每遍重试、
/// 不出卡，行为不变）。
///
/// 并发口径（@unchecked Sendable 的依据）：可变状
/// 态只有 NSCache（系统件、自带线程安全）与解码计
/// 数（NSLock 守卫）；decode 是 init 后不变的 let。
/// 气泡 body 在主线程调用，滚动/流式下亦可能被预
/// 取路径触碰——上述守卫使任意线程调用都安全
final class LocalImageDecodeCache: @unchecked Sendable {
    static let shared = LocalImageDecodeCache()

    private let cache = NSCache<NSString, UIImage>()
    private let decode: (Data) -> UIImage?
    private let counterLock = NSLock()
    private var missDecodes = 0

    init(decode: @escaping (Data) -> UIImage? = { UIImage(data: $0) }) {
        self.decode = decode
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// 实际解码次数（验收/单测读面）：同键第二遍起
    /// 不增长，即「零重解码」的代理指标
    var decodeCount: Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return missDecodes
    }

    func image(entryID: UUID, index: Int, data: Data) -> UIImage? {
        let key = "\(entryID.uuidString)|\(index)|\(data.count)"
            as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        counterLock.lock()
        missDecodes += 1
        counterLock.unlock()
        guard let image = decode(data) else { return nil }
        cache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
