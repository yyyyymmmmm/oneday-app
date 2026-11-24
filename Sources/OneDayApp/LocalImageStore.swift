import Nuke
import UIKit

/// §418（#23 本地图收口；前身 §199 LocalImageDecode-
/// Cache 退役）：聊天本地图唯一解码口——独立 NSCache
/// 不再留例外，解码产物统一入 Nuke 本地管线内存缓存
/// （合成键 localdata:// 条目/图序/字节数，见 Remote-
/// ImageRequestFactory.localRequest），全仓只剩一套
/// 图缓存。
///
/// 同步契约不变（facet 判定／行高合成／body 建卡三处
/// 同步消费）：命中管线缓存直取；未命中先把字节登记
/// 进注入表（管线异步路可取），再同步解码并播种管线
/// 缓存。解码由旧 `UIImage(data:)` 全尺寸直解改为
/// ImageIO 降采样（长边封顶 1024——只治全尺寸解码，
/// 宽高比不变、ChatImageSizing 只吃宽高比，布局口径
/// 不受影响）。
///
/// 键口径与旧口径逐字同构：条目 id＋图序＋数据字节
/// 数（条目图数据落盘后不可变，字节数入键防同条目
/// 重发图时串图）。解码失败不入缓存（坏图逐遍重试、
/// 不出卡，行为不变）。
///
/// 并发口径（@unchecked Sendable 的依据）：可变状态
/// 只有解码计数（NSLock 守卫）；缓存与注入表为各自
/// 的线程安全件；decode 是 init 后不变的 let。
final class LocalImageStore: @unchecked Sendable {
    static let shared = LocalImageStore()

    private let decode: (Data) -> UIImage?
    private let counterLock = NSLock()
    private var missDecodes = 0

    init(
        decode: @escaping (Data) -> UIImage? = {
            RemoteImagePipeline.downsampled(
                data: $0,
                pixelSize: CGFloat(
                    RemoteImageRequestFactory.localDecodeCap))
        }
    ) {
        self.decode = decode
    }

    /// 实际解码次数（验收/单测读面）：同键第二遍起
    /// 不增长，即「零重解码」的代理指标（口径与旧
    /// LocalImageDecodeCache.decodeCount 不变）
    var decodeCount: Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return missDecodes
    }

    func image(entryID: UUID, index: Int, data: Data) -> UIImage? {
        let request = RemoteImageRequestFactory.localRequest(
            entryID: entryID, index: index,
            byteCount: data.count)
        let cache = OneDayImagePipelines.local.cache
        if let cached = cache.cachedImage(
            for: request, caches: .memory)?.image {
            return cached
        }
        LocalImageDataRegistry.shared.register(
            key: RemoteImageRequestFactory.localKey(
                entryID: entryID, index: index,
                byteCount: data.count),
            data: data)
        counterLock.lock()
        missDecodes += 1
        counterLock.unlock()
        guard let image = decode(data) else { return nil }
        cache.storeCachedImage(
            ImageContainer(image: image),
            for: request, caches: .memory)
        return image
    }

    func removeAll() {
        OneDayImagePipelines.local.cache.removeAll(
            caches: .memory)
    }
}
