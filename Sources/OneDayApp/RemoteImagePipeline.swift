import ImageIO
import Nuke
import OneDayCore
import UIKit

/// 远程图统一管线门面（§144；§418 换底 Nuke）：全仓远
/// 端图只许走这一条路的口径不变——三级缓存（内存已解
/// 码图／磁盘变体字节／网络变体端点）、同键请求合并、
/// 解码一律降采样（禁远端图全尺寸直解）。原图只在查
/// 看器放大越界或显式动作时才下。
/// §418 起内脏由 Nuke 管线承担（OneDayImagePipelines
/// .remote：DataCache 512MB／ImageCache 256MB、请求合
/// 并与解码队列为库内建），本类只保留既有门面 API 与
/// 契约：取数通道仍由调用方注入（变体走桥 rendition、
/// 原图走宿主 performAdmin），经 HermesImageRouting
/// 登记后由 HermesImageDataLoader 按构造器标记分发；
/// 请求与缓存键只经 RemoteImageRequestFactory 构造
/// （键与旧 RemoteImageKey 划分逐字同构）。
/// 消费面：聊天图卡（ServerRemoteImage）、查看器
/// （ImageViewerPage）、文件/影音缩略（FileThumbnail-
/// Store 生成后经 storeMemory 播种同键——影音格点开
/// 查看器时种子即在此，首帧有图）。
/// 旧磁盘缓存目录 Caches/RemoteImages 自换底起不再
/// 读写、留待系统回收（§418 登记的一次性代价：远端
/// 图首次打开需重取一轮变体）。
@MainActor
final class RemoteImagePipeline {
    static let shared = RemoteImagePipeline()

    /// 已登记预取（旧键 → 请求）：cancelPrefetches 的
    /// 批量撤按此表执行；完成项留在表内（stop 已完成
    /// 请求为无害空转），表随不同 path 数增长、量级与
    /// 用户图量同阶
    private var prefetchRequests: [String: ImageRequest] = [:]

    private init() {}

    private var pipeline: ImagePipeline {
        OneDayImagePipelines.remote
    }

    // MARK: - 内存层

    func memoryImage(
        path: String, mtime: Double, tier: ImageRenditionTier
    ) -> UIImage? {
        pipeline.cache.cachedImage(
            for: RemoteImageRequestFactory.tierRequest(
                path: path, mtime: mtime, tier: tier),
            caches: .memory)?.image
    }

    /// 只入内存层（与旧口径同：播种不写磁盘层）
    func storeMemory(
        _ image: UIImage, path: String, mtime: Double,
        tier: ImageRenditionTier
    ) {
        pipeline.cache.storeCachedImage(
            ImageContainer(image: image),
            for: RemoteImageRequestFactory.tierRequest(
                path: path, mtime: mtime, tier: tier),
            caches: .memory)
    }

    /// 查看器种子：已到手的图里从高到低找（影音格 360、
    /// 气泡已显图都在内存层）；内存没有再探磁盘 360 档
    /// （只读缓存不发网络，解码在管线队列、不在主线
    /// 程）。种子命中＝查看器第一帧有图
    func seedImage(path: String, mtime: Double) async -> UIImage? {
        for tier in [ImageRenditionTier.detail, .viewer, .thumb] {
            if let image = memoryImage(
                path: path, mtime: mtime, tier: tier) {
                return image
            }
        }
        var request = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: mtime, tier: .thumb)
        request.options = [.returnCacheDataDontLoad]
        return try? await pipeline.image(for: request)
    }

    // MARK: - 取图主口

    /// 取某档图：内存→磁盘→网络（变体优先、回落原图降
    /// 采样，路由在 loader 内）。同键并发请求由管线合
    /// 并。共享请求不随单个视图消失而取消——取图走非
    /// 结构化任务护盾，结果落缓存供后来者（§144 记账）
    func image(
        path: String, mtime: Double, tier: ImageRenditionTier,
        config: ServerConfig?,
        originalLoader: @escaping () async -> Data?
    ) async -> UIImage? {
        if let cached = memoryImage(
            path: path, mtime: mtime, tier: tier) {
            return cached
        }
        HermesImageRouting.shared.register(
            key: RemoteImageKey.make(
                path: path, mtime: mtime, tier: tier),
            config: config,
            originalLoader: originalLoader)
        let request = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: mtime, tier: tier)
        let task = Task {
            try? await OneDayImagePipelines.remote.image(
                for: request)
        }
        return await task.value
    }

    /// 预取：低优先、只填缓存不回图；已在内存/磁盘的跳
    /// 过。与锚点无关的预取可经 cancelPrefetches 批量撤
    /// （快滑时未发出的预取不许继续抢带宽）
    func prefetch(
        path: String, mtime: Double, tier: ImageRenditionTier,
        config: ServerConfig?,
        originalLoader: @escaping () async -> Data?
    ) {
        let key = RemoteImageKey.make(
            path: path, mtime: mtime, tier: tier)
        let request = RemoteImageRequestFactory.tierRequest(
            path: path, mtime: mtime, tier: tier)
        guard prefetchRequests[key] == nil,
              memoryImage(path: path, mtime: mtime, tier: tier)
                  == nil,
              !pipeline.cache.containsData(for: request)
        else { return }
        HermesImageRouting.shared.register(
            key: key, config: config,
            originalLoader: originalLoader)
        prefetchRequests[key] = request
        OneDayImagePipelines.remotePrefetcher.startPrefetching(
            with: [request])
    }

    func cancelPrefetches(except keepKeys: Set<String> = []) {
        let stopping = prefetchRequests.filter {
            !keepKeys.contains($0.key)
        }
        if !stopping.isEmpty {
            OneDayImagePipelines.remotePrefetcher
                .stopPrefetching(
                    with: Array(stopping.values))
        }
        prefetchRequests = prefetchRequests.filter {
            keepKeys.contains($0.key)
        }
    }

    // MARK: - 降采样解码（本地图门面共用）

    /// ImageIO 降采样：只解到目标像素量级，不整图入内存
    /// （与 FileThumbnailStore 同法）。nonisolated：本体
    /// 无状态、只吃入参。§418 后远端路解码归 Nuke 管
    /// 线，本口只剩本地图同步门面（LocalImageStore）在
    /// 缓存未命中时调用
    nonisolated static func downsampled(
        data: Data, pixelSize: CGFloat
    ) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(
            data as CFData, sourceOptions as CFDictionary
        ) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
